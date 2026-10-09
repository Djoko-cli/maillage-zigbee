import Foundation

/// Suit le maillage de la sonde de tournee en tournee et en tire les evenements du journal (spec de l'app,
/// section 7). Un noeud se suit par son adresse longue (l'id de son sujet, et `details["ieee"]`).
/// - Le premier maillage est un point de depart : `surveillanceDemarree`, avec le nombre de routeurs et d'appareils,
///   et rien d'autre.
/// - Un routeur (hors coordinateur) qui entre dans le maillage : « apparu » ; qui en sort : « disparu ». Seulement par
///   son adresse longue : un routeur connu par une cle provisoire (vu en route, `~7F80`) n'est ni l'un ni l'autre.
/// - Un appareil final vu pour la premiere fois : « nouveau » ; sous un autre parent : « a change de parent : A → B ».
/// - Un appareil final absent de deux tournees de suite : « n'a plus de parent », une fois ; son retour ensuite :
///   « revenu ». Une absence ne compte pas si son dernier parent est muet a cette tournee (on ne sait pas), ni pour la
///   sonde, jamais « sans parent » (detachee, elle ne rend pas de maillage), ni pour un appareil devenu routeur.
/// - Un appareil final absent des dernieres tables dont le dernier parent connu date de moins de 24 h
///   (`LienParent.dAvant`, voir `ParentsConnus`) n'est ni absent ni sous un autre parent : aucun evenement tant que ce
///   delai tient ; ses absences repartent de zero, donc « sans parent » vient 24 h apres, a la deuxieme absence.
/// - Un maillage incomplet (`MaillageZigbee.complet` faux : la sonde a quitte le reseau, ou refuse en cadence, pendant
///   la tournee) ne donne ni depart de routeur ni absence : ce qu'il n'a pas vu n'est pas parti. Une absence ne compte
///   pas non plus sous un parent dont la table n'a pas ete lue (`tableNonLue`).
/// - Un routeur dont le chemin vers le pont passe par un autre prochain saut : « a change de chemin : A → B ». Un
///   chemin suppose (sans route active) n'en donne pas : on compare le dernier chemin lu au nouveau. Un maillage
///   incomplet n'en donne pas non plus, et ne change pas les chemins retenus.
/// La disparition d'un appareil selon le pont (« disparu ») vient de son etat de connexion (`SuiviConnexions`).
public struct SuiviMaillage: Sendable {
    /// Absences avant « n'a plus de parent ».
    public static let absencesAvantPerte = 2

    private struct EtatAppareil: Sendable {
        var parent: String
        var nomParent: String
        var sujet: Sujet
        var absences = 0
        var perdu = false
    }

    private var demarre = false
    /// Routeurs de la derniere tournee, par adresse longue.
    private var routeurs: [String: Sujet] = [:]
    /// Appareils finaux suivis, par adresse longue.
    private var appareils: [String: EtatAppareil] = [:]
    /// Le dernier prochain saut lu (chemin non suppose) de chaque routeur, et son nom d'alors.
    private var chemins: [String: (prochain: String, nom: String)] = [:]

    public init() {}

    /// Note une veille du Mac et rend son evenement.
    public func noterVeille(_ periode: DateInterval) -> [Evenement] {
        [Evenement(date: periode.end, type: .veille, periode: periode)]
    }

    /// Evenements du maillage d'une tournee, dates du debut de la tournee (`MaillageZigbee.date`) ; `nom` : le nom
    /// affiche d'un noeud, par son adresse longue.
    public mutating func integrer(_ m: MaillageZigbee, nom: (String) -> String) -> [Evenement] {
        func sujet(_ ieee: String) -> Sujet { Sujet(id: ieee, nom: nom(ieee)) }
        // Les routeurs suivis : ceux d'adresse longue connue. Un routeur vu seulement en route (cle provisoire) n'est au
        // maillage que les tournees ou ses routes sont relues : ni apparu ni disparu.
        let routeursIci = m.noeuds.filter { $0.type == .routeur && $0.ieeeConnue }.map(\.ieee)
        let routes = Set(m.noeuds.filter(\.route).map(\.ieee))
        var ev: [Evenement] = []
        guard demarre else {
            demarre = true
            ev.append(Evenement(date: m.date, type: .surveillanceDemarree,
                                details: ["routeurs": String(m.noeuds.filter { $0.type == .routeur }.count),
                                          "appareils": String(m.noeuds.filter { !$0.route }.count)]))
            routeurs = Dictionary(routeursIci.map { ($0, sujet($0)) }, uniquingKeysWith: { a, _ in a })
            for p in m.parents {
                appareils[p.enfant] = EtatAppareil(parent: p.parent, nomParent: nom(p.parent), sujet: sujet(p.enfant))
            }
            retenirChemins(m, nom: nom)
            return ev
        }
        for r in routeursIci.sorted() where routeurs[r] == nil {
            ev.append(Evenement(date: m.date, type: .routeurApparu, sujet: sujet(r), details: ["ieee": r]))
        }
        let ici = Set(routeursIci)
        if m.complet {
            for (r, s) in routeurs.sorted(by: { $0.key < $1.key }) where !ici.contains(r) {
                ev.append(Evenement(date: m.date, type: .routeurDisparu, sujet: s, details: ["ieee": r]))
            }
            routeurs = [:]
        }
        for r in routeursIci where routeurs[r] == nil { routeurs[r] = sujet(r) }
        // Un parent d'avant n'est pas un lien lu : l'appareil n'est ni present ni absent.
        let presents = Dictionary(m.parents.filter { !$0.dAvant }.map { ($0.enfant, $0) }, uniquingKeysWith: { a, _ in a })
        let parentsDAvant = Set(m.parents.filter(\.dAvant).map(\.enfant))
        for (e, p) in presents.sorted(by: { $0.key < $1.key }) {
            let s = sujet(e)
            let nomParent = nom(p.parent)
            if let avant = appareils[e] {
                if avant.perdu {
                    ev.append(Evenement(date: m.date, type: .appareilRevenu, sujet: s, apres: nomParent,
                                        details: ["ieee": e]))
                } else if avant.parent != p.parent {
                    ev.append(Evenement(date: m.date, type: .parentChange, sujet: s, avant: avant.nomParent,
                                        apres: nomParent, details: ["ieee": e]))
                }
            } else {
                ev.append(Evenement(date: m.date, type: .appareilNouveau, sujet: s, apres: nomParent, details: ["ieee": e]))
            }
            appareils[e] = EtatAppareil(parent: p.parent, nomParent: nomParent, sujet: s)
        }
        let nonLus = Set(m.noeuds.filter { $0.muet || $0.tableNonLue }.map(\.ieee))
        for (e, var a) in appareils.sorted(by: { $0.key < $1.key }) where presents[e] == nil && !a.perdu {
            if routes.contains(e) {
                // Devenu routeur : il n'a plus de parent a suivre.
                appareils[e] = nil
                continue
            }
            if parentsDAvant.contains(e) {
                a.absences = 0
                appareils[e] = a
                continue
            }
            guard m.complet, e != m.sonde, !nonLus.contains(a.parent) else { continue }
            a.absences += 1
            if a.absences >= Self.absencesAvantPerte {
                a.perdu = true
                ev.append(Evenement(date: m.date, type: .sansParent, sujet: a.sujet, avant: a.nomParent,
                                    details: ["ieee": e]))
            }
            appareils[e] = a
        }
        if m.complet {
            for c in m.chemins where !c.suppose {
                guard let avant = chemins[c.routeur], avant.prochain != c.prochain else { continue }
                ev.append(Evenement(date: m.date, type: .cheminChange, sujet: sujet(c.routeur), avant: avant.nom,
                                    apres: nom(c.prochain), details: ["ieee": c.routeur]))
            }
            retenirChemins(m, nom: nom)
        }
        return ev
    }

    /// Retient le prochain saut de chaque chemin lu (non suppose) de `m`.
    private mutating func retenirChemins(_ m: MaillageZigbee, nom: (String) -> String) {
        for c in m.chemins where !c.suppose { chemins[c.routeur] = (c.prochain, nom(c.prochain)) }
    }
}
