import Foundation
import Synchronization
import Testing
@testable import MaillageCoeur

/// Horloge des tests de la tournee : les pauses de l'attente l'avancent, sans dormir.
final class HorlogeTournee: Sendable {
    private let t: Mutex<Date>

    init(_ debut: Date) {
        t = Mutex(debut)
    }

    var maintenant: Date { t.withLock { $0 } }

    func avancer(_ secondes: TimeInterval) {
        t.withLock { $0 += secondes }
    }
}

/// Sonde simulee : un faux reseau Zigbee (la table de chaque routeur, par adresse courte ; la table de routage du
/// pont), et des pannes par requete. Valeurs inventees.
final class SondeSimulee: InterlocuteurSonde {
    /// Ce qu'une requete rend au lieu de la reponse normale.
    enum Panne: Sendable {
        /// Echec de la sonde : `delai`, `non_membre`, `cadence`...
        case erreur(String)
        /// Rien dans l'echeance.
        case sansReponse
        /// Une ligne perdue : `n` entrees de moins que le total annonce.
        case tronquee(Int)
        /// Une autre table, entiere.
        case autre([EntreeTable])
        /// Une autre table de routage, entiere.
        case autresRoutes([EntreeRoute])
    }

    typealias I = SondeSimulee.Ieee

    enum Ieee {
        static let sonde = "A000000000000001"
        static let r1 = "A000000000000002"
        static let pont = "A000000000000003"
        static let r2 = "A000000000000004"
        static let r3 = "A000000000000005"
        static let r4 = "A000000000000006"
        static let f1 = "A000000000000007"
        static let f2 = "A000000000000008"
    }

    static func routeur(_ court: String, _ ieee: String?, lqi: Int, type: String = "routeur") -> EntreeTable {
        EntreeTable(court: court, ieee: ieee, type: type, relation: "frere", ecoute: true, profondeur: 15,
                    admission: false, lqi: lqi)
    }

    static func enfant(_ court: String, _ ieee: String?, lqi: Int, ecoute: Bool) -> EntreeTable {
        EntreeTable(court: court, ieee: ieee, type: "final", relation: "enfant", ecoute: ecoute, profondeur: 2,
                    admission: false, lqi: lqi)
    }

    /// Le reseau de reference : le pont, quatre routeurs (R4 annonce sans adresse longue par R2), deux appareils
    /// finaux endormis et la sonde, sous R1.
    static let reseau: [UInt16: [EntreeTable]] = [
        0x0000: [routeur("1A2B", I.r1, lqi: 200), routeur("2B3C", I.r2, lqi: 150),
                 enfant("0A11", I.f1, lqi: 120, ecoute: false)],
        0x1A2B: [routeur("0000", I.pont, lqi: 210, type: "coordinateur"), routeur("2B3C", I.r2, lqi: 90),
                 routeur("3C4D", I.r3, lqi: 60), enfant("5E6F", I.sonde, lqi: 188, ecoute: true)],
        0x2B3C: [routeur("0000", I.pont, lqi: 140, type: "coordinateur"), routeur("1A2B", I.r1, lqi: 95),
                 enfant("0A12", I.f2, lqi: 70, ecoute: false), routeur("4D5E", "FFFFFFFFFFFFFFFF", lqi: 40)],
        0x3C4D: [routeur("1A2B", I.r1, lqi: 66), routeur("4D5E", I.r4, lqi: 120)],
        0x4D5E: [routeur("3C4D", I.r3, lqi: 118), routeur("2B3C", I.r2, lqi: 44)],
    ]

    /// La table de routage de chaque routeur : R1 et R2 vont au pont, R3 passe par R1 (routes « plusieurs vers un »
    /// actives) ; R4 n'a qu'une route inactive (son chemin sera suppose).
    static let routesRouteurs: [UInt16: [EntreeRoute]] = [
        0x1A2B: [EntreeRoute(destination: "0000", etat: "active", prochain: "0000", plusieursVersUn: true),
                 EntreeRoute(destination: "4D5E", etat: "active", prochain: "3C4D")],
        0x2B3C: [EntreeRoute(destination: "0000", etat: "active", prochain: "0000", plusieursVersUn: true)],
        0x3C4D: [EntreeRoute(destination: "0000", etat: "inactive", prochain: "0000"),
                 EntreeRoute(destination: "0000", etat: "active", prochain: "1A2B", plusieursVersUn: true)],
        0x4D5E: [EntreeRoute(destination: "0000", etat: "inactive", prochain: "0000")],
    ]

    static let routesPont: [EntreeRoute] = [
        EntreeRoute(destination: "1A2B", etat: "active", prochain: "1A2B"),
        EntreeRoute(destination: "3C4D", etat: "active", prochain: "1A2B"),
        EntreeRoute(destination: "4D5E", etat: "inactive", prochain: "2B3C"),
    ]

    private struct Etat {
        var requetes: [String] = []
        var rangs: [String: Int] = [:]
        var envois: [BudgetPages.Envoi] = []
        var refusCadence = 0
    }

    private let etat = Mutex(Etat())
    let horloge: HorlogeTournee
    let reseau: [UInt16: [EntreeTable]]
    let routesRouteurs: [UInt16: [EntreeRoute]]
    /// Panne d'une requete (« table 1A2B », « routes 0000 », « etat », « voisins ») a son rang (1 : la premiere).
    let panne: @Sendable (String, Int) -> Panne?
    /// La sonde est-elle membre a cette heure ?
    let membre: @Sendable (Date) -> Bool
    let suspendue: Bool
    /// Duree d'une table, ajoutee a l'horloge.
    let dureeTable: TimeInterval
    /// Pages d'une reponse reussie (« table 1A2B », « routes 0000 ») ; nil : la reponse n'en donne pas.
    let pages: @Sendable (String) -> Int?
    /// Garde-fou de la sonde : pages au plus par fenetre glissante de 10 minutes (au-dela, refus `cadence` sans rien
    /// envoyer) ; nil : aucun.
    let plafond: Int?

    init(horloge: HorlogeTournee, reseau: [UInt16: [EntreeTable]] = SondeSimulee.reseau,
         routesRouteurs: [UInt16: [EntreeRoute]] = SondeSimulee.routesRouteurs, suspendue: Bool = false,
         dureeTable: TimeInterval = 2, panne: @escaping @Sendable (String, Int) -> Panne? = { _, _ in nil },
         membre: @escaping @Sendable (Date) -> Bool = { _ in true },
         pages: @escaping @Sendable (String) -> Int? = { $0.hasPrefix("table") ? 2 : nil }, plafond: Int? = nil) {
        self.horloge = horloge
        self.pages = pages
        self.plafond = plafond
        self.reseau = reseau
        self.routesRouteurs = routesRouteurs
        self.suspendue = suspendue
        self.dureeTable = dureeTable
        self.membre = membre
        self.panne = panne
    }

    var requetes: [String] { etat.withLock { $0.requetes } }
    /// Les pages envoyees par la sonde (reponses reussies), a la date de leur reponse.
    var envois: [BudgetPages.Envoi] { etat.withLock { $0.envois } }
    /// Refus `cadence` du garde-fou de la sonde (`plafond`).
    var refusCadence: Int { etat.withLock { $0.refusCadence } }

    /// Les pages au plus envoyees sur une fenetre glissante de 10 minutes.
    var pagesMaxSurDixMinutes: Int { Self.pagesMaxSurDixMinutes(envois) }

    static func pagesMaxSurDixMinutes(_ e: [BudgetPages.Envoi]) -> Int {
        e.map { fin in
            e.filter { $0.date <= fin.date && $0.date > fin.date.addingTimeInterval(-BudgetPages.fenetre) }
                .reduce(0) { $0 + $1.pages }
        }.max() ?? 0
    }

    /// Le garde-fou de la sonde : la reponse part (ses pages comptees), ou elle est refusee en `cadence`.
    private func accepter(_ requete: String) -> Bool {
        let p = pages(requete) ?? 1
        let maintenant = horloge.maintenant
        return etat.withLock { e in
            if let plafond {
                let fenetre = e.envois.filter { $0.date > maintenant.addingTimeInterval(-BudgetPages.fenetre) }
                if fenetre.reduce(0, { $0 + $1.pages }) + p > plafond {
                    e.refusCadence += 1
                    return false
                }
            }
            e.envois.append(BudgetPages.Envoi(date: maintenant, pages: p))
            return true
        }
    }

    private func noter(_ r: String) -> Int {
        etat.withLock { e in
            e.requetes.append(r)
            e.rangs[r, default: 0] += 1
            return e.rangs[r] ?? 0
        }
    }

    func etat() async throws -> EtatSonde {
        _ = noter("etat")
        let m = membre(horloge.maintenant)
        return EtatSonde(membre: m, recherche: !m, court: m ? "5E6F" : nil, ieee: I.sonde, role: m ? "final" : nil,
                         parent: m ? ParentSonde(court: "1A2B", ieee: I.r1, lqi: 180, rssi: -71) : nil,
                         pan: m ? "1234" : nil, epid: m ? "A0000000000000FF" : nil, canal: m ? 25 : nil,
                         suspendue: suspendue, refusCadence: 0, rattachementsEchoues: 0, pile: "1.6.8")
    }

    func voisins() async throws -> [VoisinDeLaSonde] {
        _ = noter("voisins")
        return [VoisinDeLaSonde(court: "1A2B", ieee: I.r1, type: "routeur", relation: "parent", lqi: 180, rssi: -71),
                VoisinDeLaSonde(court: "2B3C", ieee: I.r2, type: "routeur", relation: "aucune", lqi: 97, rssi: -80)]
    }

    func table(_ cible: UInt16) async throws -> ReponseListe<EntreeTable>? {
        let texte = "table \(ProtocoleSonde.texte(court: cible))"
        let rang = noter(texte)
        horloge.avancer(dureeTable)
        let c = ProtocoleSonde.texte(court: cible)
        switch panne(texte, rang) {
        case .erreur(let e)?: return .echec(e, id: rang, cible: c)
        case .sansReponse?: return nil
        case .tronquee(let n)?:
            let l = reseau[cible] ?? []
            return ReponseListe(id: rang, cible: c, ok: true, total: l.count, liste: Array(l.dropLast(n)))
        case .autre(let l)?: return ReponseListe(id: rang, cible: c, ok: true, total: l.count, liste: l)
        case .autresRoutes?, nil:
            guard membre(horloge.maintenant) else { return .echec("non_membre", id: rang, cible: c) }
            guard let l = reseau[cible] else { return .echec("delai", id: rang, cible: c) }
            guard accepter(texte) else { return .echec("cadence", id: rang, cible: c) }
            return ReponseListe(id: rang, cible: c, ok: true, ms: 840, pages: pages(texte), total: l.count, liste: l)
        }
    }

    func routes(_ cible: UInt16) async throws -> ReponseListe<EntreeRoute>? {
        let texte = "routes \(ProtocoleSonde.texte(court: cible))"
        let rang = noter(texte)
        horloge.avancer(dureeTable / 2)
        let c = ProtocoleSonde.texte(court: cible)
        switch panne(texte, rang) {
        case .erreur(let e)?: return .echec(e, id: rang, cible: c)
        case .sansReponse?: return nil
        case .autresRoutes(let l)?: return ReponseListe(id: rang, cible: c, ok: true, total: l.count, liste: l)
        default:
            guard membre(horloge.maintenant) else { return .echec("non_membre", id: rang, cible: c) }
            guard let l = cible == 0 ? Self.routesPont : routesRouteurs[cible] else {
                return .echec("delai", id: rang, cible: c)
            }
            guard accepter(texte) else { return .echec("cadence", id: rang, cible: c) }
            return ReponseListe(id: rang, cible: c, ok: true, pages: pages(texte), total: l.count, liste: l)
        }
    }
}

@Suite("Tournee de la sonde : parcours, attentes, muets, construction du maillage")
struct TourneeTests {
    typealias I = SondeSimulee.Ieee
    static let t0 = Date(timeIntervalSince1970: 1_791_450_000)

    static func executer(_ s: SondeSimulee, memoire: MemoireTournee = MemoireTournee(),
                         avancement: (AvancementTournee) -> Void = { _ in }) async throws -> ResultatTournee {
        let h = s.horloge
        return try await Tournee.executer(s, memoire: memoire, horloge: { h.maintenant },
                                          attendre: { h.avancer(Double($0.components.seconds)) },
                                          avancement: avancement)
    }

    /// Le parcours de reference : `etat`, `voisins`, une table par routeur en largeur depuis le pont (dedoublonnes par
    /// adresse longue ; R4, vu sans adresse longue par R2, n'est demande qu'une fois), les routes du pont, puis celles
    /// de chaque routeur dans le meme ordre (aucune n'a encore ete lue) ; les pages comptees.
    @Test func parcoursEnLargeur() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0))
        var etapes: [AvancementTournee] = []
        let r = try await Self.executer(s) { etapes.append($0) }
        #expect(s.requetes == ["etat", "voisins", "table 0000", "table 1A2B", "table 2B3C", "table 3C4D",
                               "table 4D5E", "routes 0000", "routes 1A2B", "routes 2B3C", "routes 3C4D", "routes 4D5E"])
        #expect(r.bilan.avecTables && r.bilan.routesRouteursDemandees == 4 && r.bilan.routesRouteursLues == 4)
        #expect(etapes.filter { $0.etape == .routesRouteurs }.map(\.fait) == [0, 1, 2, 3, 4])
        #expect(etapes.filter { $0.etape == .routesRouteurs }.allSatisfy { $0.total == 4 })
        let m = try #require(r.maillage)
        #expect(m.complet && r.empechement == nil)
        #expect(r.bilan.tablesDemandees == 5 && r.bilan.tablesLues == 5 && r.bilan.routesLues && r.bilan.lacune == nil)
        #expect(m.date == Self.t0)
        #expect(m.noeuds.map(\.ieee) == [I.sonde, I.r1, I.pont, I.r2, I.r3, I.r4, I.f1, I.f2], "aucune cle provisoire")
        #expect(m.coordinateur?.ieee == I.pont && m.coordinateur?.court == 0)
        #expect(m.noeud(I.r4)?.court == 0x4D5E && m.noeud(I.r4)?.type == .routeur)
        #expect(m.noeuds.allSatisfy { !$0.muet && !$0.tableNonLue })
        // Etapes : etat (0, 1, 2 sur 2), tables (le total grandit avec le parcours), routes du pont, des routeurs.
        #expect(etapes.first == AvancementTournee(etape: .etatSonde, fait: 0, total: 2))
        #expect(etapes.filter { $0.etape == .tables }.map(\.fait) == [0, 1, 2, 3, 4, 5])
        #expect(etapes.filter { $0.etape == .tables }.last?.total == 5)
        #expect(etapes.map(\.etape).firstIndex(of: .routes)! < etapes.map(\.etape).firstIndex(of: .routesRouteurs)!)
        #expect(etapes.last == AvancementTournee(etape: .routesRouteurs, fait: 4, total: 4))
        // Pages : 2 par table, une par reponse qui n'en donne pas (les routes de la sonde simulee).
        #expect(r.bilan.pages == 5 * 2 + 5 && r.memoire.budget.utilisees(a: s.horloge.maintenant) == 15)
        #expect(r.bilan.routesReportees == 0 && !r.bilan.passeArreteeCadence)
        #expect(r.memoire.routes.keys.sorted() == [I.r1, I.r2, I.r3, I.r4])
    }

    /// Liens radio (mesure du proprietaire de la table, les deux sens), parents (LQI de l'entree « enfant »), endormis
    /// (`ecoute` faux), la sonde sous son parent, son signal, et les routes du pont.
    @Test func construction() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0))
        let m = try #require(try await Self.executer(s).maillage)
        let pontR1 = try #require(m.liens.first { $0.relie(I.pont) && $0.relie(I.r1) })
        // a < b : R1 (…02) avant le pont (…03) ; R1 mesure le pont a 210, le pont mesure R1 a 200.
        #expect(pontR1.a == I.r1 && pontR1.lqiA == 210 && pontR1.lqiB == 200)
        let r2r4 = try #require(m.liens.first { $0.relie(I.r2) && $0.relie(I.r4) })
        #expect(r2r4.lqiA == 40 && r2r4.lqiB == 44, "la mesure de R2 (sans adresse longue) va a R4")
        #expect(m.liens.count == 6)
        #expect(m.parent(de: I.f1) == LienParent(enfant: I.f1, parent: I.pont, lqi: 120, date: m.parent(de: I.f1)?.date))
        #expect(m.parent(de: I.f2)?.parent == I.r2 && m.parent(de: I.f2)?.lqi == 70)
        #expect(m.parent(de: I.sonde)?.parent == I.r1 && m.parent(de: I.sonde)?.lqi == 188, "LQI vu par le parent")
        #expect(m.sonde == I.sonde && m.parentSonde == I.r1)
        #expect(m.noeud(I.f1)?.endormi == true && m.noeud(I.f2)?.endormi == true)
        #expect(m.noeud(I.sonde)?.endormi == false && m.noeud(I.sonde)?.ecoute == true)
        #expect(m.signaux == [SignalSonde(ieee: I.r1, lqi: 180), SignalSonde(ieee: I.r2, lqi: 97)])
        #expect(m.routesPont.count == 3)
        #expect(m.viaPont(vers: I.r3)?.ieee == I.r1, "route active")
        #expect(m.viaPont(vers: I.r4) == nil, "route inactive")
        #expect(m.viaPont(vers: I.r1)?.ieee == I.r1, "voisin direct")
    }

    /// La sonde perd son parent (`non_membre`) : `etat` toutes les 5 s jusqu'a son retour, puis la table est
    /// redemandee ; la tournee reste complete.
    @Test func attenteDuRetourDeLaSonde() async throws {
        let h = HorlogeTournee(Self.t0)
        let retour = Self.t0.addingTimeInterval(30)
        // Membre pour la table du pont (2 s), hors du reseau pour celle de R1 (4 s), de retour a 30 s.
        let s = SondeSimulee(horloge: h, membre: { $0 >= retour || $0 < Self.t0.addingTimeInterval(3) })
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(m.complet && r.bilan.attentes == 1 && r.bilan.tablesLues == 5)
        let tables = s.requetes.filter { $0.hasPrefix("table") }
        #expect(tables.filter { $0 == "table 1A2B" }.count == 2, "redemandee apres le retour")
        #expect(s.requetes.filter { $0 == "etat" }.count >= 3, "etat au debut, puis pendant l'attente")
        #expect(h.maintenant >= retour)
    }

    /// Une attente vaine (120 s) : la table est perdue, les cibles suivantes n'attendent plus ; la tournee est
    /// incomplete, aucun routeur n'a d'echec (la faute est a la sonde).
    @Test func attenteVaine() async throws {
        let h = HorlogeTournee(Self.t0)
        let s = SondeSimulee(horloge: h, membre: { $0 < Self.t0.addingTimeInterval(3) })
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(!m.complet && r.bilan.lacune == "non_membre")
        #expect(r.bilan.attentes == 1, "une seule attente : les suivantes n'attendent plus")
        #expect(h.maintenant.timeIntervalSince(Self.t0) >= 120)
        #expect(s.requetes.filter { $0.hasPrefix("table") } == ["table 0000", "table 1A2B", "table 2B3C"])
        #expect(r.memoire.echecs.isEmpty)
        #expect(m.noeud(I.r1)?.tableNonLue == true && m.noeud(I.r1)?.muet == false)
    }

    /// Deux attentes par table au plus : la sonde repart une troisieme fois, la table est perdue.
    @Test func deuxAttentesParTable() async throws {
        let h = HorlogeTournee(Self.t0)
        let s = SondeSimulee(horloge: h) { requete, rang in
            requete == "table 2B3C" && rang <= 3 ? .erreur("non_membre") : nil
        }
        let r = try await Self.executer(s)
        #expect(r.bilan.attentes == 2)
        #expect(s.requetes.filter { $0 == "table 2B3C" }.count == 3)
        #expect(r.maillage?.complet == false && r.bilan.lacune == "non_membre")
    }

    /// Une table incomplete (une ligne perdue) est redemandee une fois ; incomplete deux fois, elle est gardee telle
    /// quelle.
    @Test func tableIncomplete() async throws {
        let s1 = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, rang in q == "table 1A2B" && rang == 1 ? .tronquee(1) : nil }
        let r1 = try await Self.executer(s1)
        #expect(s1.requetes.filter { $0 == "table 1A2B" }.count == 2)
        #expect(r1.bilan.tablesIncoherentes == 0 && r1.maillage?.parent(de: I.sonde)?.lqi == 188)
        let s2 = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, _ in q == "table 1A2B" ? .tronquee(1) : nil }
        let r2 = try await Self.executer(s2)
        #expect(s2.requetes.filter { $0 == "table 1A2B" }.count == 2)
        #expect(r2.bilan.tablesIncoherentes == 1 && r2.bilan.tablesLues == 5)
        #expect(r2.maillage?.complet == true)
    }

    /// Un routeur sans reponse (`delai`, a sa table comme a ses routes) : sa table n'est pas lue (ses liens viennent de
    /// ses voisins) ; muet a la deuxieme tournee de suite (qui ne lit que les routes) ; sa reponse efface ses echecs.
    /// Une table manquee mais des routes lues : pas d'echec.
    @Test func muetApresDeuxTournees() async throws {
        let h = HorlogeTournee(Self.t0)
        let tableSeule = SondeSimulee(horloge: h) { q, _ in q == "table 3C4D" ? .erreur("delai") : nil }
        let r0 = try await Self.executer(tableSeule)
        #expect(r0.memoire.echecs.isEmpty && r0.bilan.sansReponse == 0 && r0.maillage?.noeud(I.r3)?.tableNonLue == true)
        let enPanne = SondeSimulee(horloge: h) { q, _ in q.hasSuffix("3C4D") ? .erreur("delai") : nil }
        let r1 = try await Self.executer(enPanne)
        let m1 = try #require(r1.maillage)
        #expect(m1.complet && m1.noeud(I.r3)?.tableNonLue == true && m1.noeud(I.r3)?.muet == false)
        #expect(r1.memoire.echecs == [I.r3: 1] && r1.bilan.sansReponse == 1 && r1.bilan.muets == 0)
        #expect(m1.liens.contains { $0.relie(I.r3) && $0.relie(I.r1) }, "vu par R1")
        let r2 = try await Self.executer(enPanne, memoire: r1.memoire)
        #expect(r2.maillage?.noeud(I.r3)?.muet == true && r2.bilan.muets == 1 && r2.memoire.echecs == [I.r3: 2])
        let r3 = try await Self.executer(SondeSimulee(horloge: h), memoire: r2.memoire)
        #expect(r3.maillage?.noeud(I.r3)?.muet == false && r3.memoire.echecs.isEmpty)
    }

    /// Sonde hors du reseau ou suspendue : pas de tournee (un seul `etat`), et la memoire reste celle d'avant.
    @Test func sansTournee() async throws {
        let memoire = MemoireTournee(echecs: [I.r3: 1])
        let hors = SondeSimulee(horloge: HorlogeTournee(Self.t0), membre: { _ in false })
        let r1 = try await Self.executer(hors, memoire: memoire)
        #expect(r1.maillage == nil && r1.empechement == .horsReseau && r1.memoire == memoire && hors.requetes == ["etat"])
        let suspendue = SondeSimulee(horloge: HorlogeTournee(Self.t0), suspendue: true)
        let r2 = try await Self.executer(suspendue, memoire: memoire)
        #expect(r2.maillage == nil && r2.empechement == .suspendue && r2.memoire == memoire)
        #expect(suspendue.requetes == ["etat"])
    }

    /// Suspendue pendant la tournee : pas de maillage, et le routeur sans reponse avant la suspension ne compte pas.
    @Test func suspenduePendantLaTournee() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, _ in
            q == "table 1A2B" ? .erreur("delai") : q == "table 2B3C" ? .erreur("suspendue") : nil
        }
        let r = try await Self.executer(s)
        #expect(r.maillage == nil && r.empechement == .suspendue)
        #expect(r.memoire.echecs.isEmpty && r.memoire.tables == nil && r.memoire.routes.isEmpty)
        #expect(r.memoire.budget.utilisees(a: s.horloge.maintenant) == 2 + 1 + 1, "seules les pages envoyees restent")
        #expect(!s.requetes.contains("routes 0000"))
    }

    /// `cadence` : pause de 20 s, puis la meme requete ; la tournee reste complete, et le routeur n'y est pour rien.
    @Test func cadence() async throws {
        let h = HorlogeTournee(Self.t0)
        let s = SondeSimulee(horloge: h) { q, rang in
            (q == "table 1A2B" && rang <= 2) || (q == "routes 3C4D" && rang == 1) ? .erreur("cadence") : nil
        }
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(s.requetes.filter { $0 == "table 1A2B" }.count == 3 && s.requetes.filter { $0 == "routes 3C4D" }.count == 2)
        #expect(m.complet && r.bilan.lacune == nil && r.bilan.pausesCadence == 3 && r.bilan.tablesLues == 5)
        #expect(r.memoire.echecs.isEmpty && r.bilan.routesLues)
        #expect(h.maintenant.timeIntervalSince(Self.t0) >= 60)
    }

    /// `cadence` au-dela de 10 minutes de tournee : plus de pause ; la tournee s'arrete, incomplete, sans routes ; les
    /// routeurs prevus et jamais demandes ne sont ni lus ni en echec, et la prochaine tournee relit les tables.
    @Test func cadenceAuDelaDeDixMinutes() async throws {
        let h = HorlogeTournee(Self.t0)
        let s = SondeSimulee(horloge: h) { q, _ in q == "table 1A2B" ? .erreur("cadence") : nil }
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(!m.complet && r.bilan.lacune == "cadence" && !r.bilan.routesLues && r.bilan.routesRouteursDemandees == 0)
        #expect(!s.requetes.contains { $0.hasPrefix("routes") } && !s.requetes.contains("table 2B3C"))
        let duree = h.maintenant.timeIntervalSince(Self.t0)
        #expect(duree > Tournee.dureeMax - Tournee.pauseCadence - 5 && duree <= Tournee.dureeMax + 5)
        #expect(m.noeud(I.r2)?.tableNonLue == true, "prevu, jamais demande")
        #expect(r.memoire.echecs.isEmpty && r.memoire.tables == nil && r.memoire.tablesDues)
    }

    /// Sans reponse de la sonde (125 s) : la tournee continue, incomplete, sans echec pour le routeur.
    @Test func sondeSansReponse() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, _ in q == "table 2B3C" ? .sansReponse : nil }
        let r = try await Self.executer(s)
        #expect(r.maillage?.complet == false && r.bilan.lacune == "sans_reponse" && r.memoire.echecs.isEmpty)
        #expect(s.requetes.filter { $0 == "table 2B3C" }.count == 1)
        #expect(s.requetes.contains("table 3C4D"), "le parcours continue")
    }

    /// Le pont ne donne pas sa table : le parcours repart du parent de la sonde et des routeurs qu'elle entend.
    @Test func reprisePourUnPontMuet() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, _ in q == "table 0000" ? .erreur("delai") : nil }
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(s.requetes.filter { $0.hasPrefix("table") } == ["table 0000", "table 1A2B", "table 2B3C", "table 3C4D",
                                                                 "table 4D5E"])
        #expect(m.coordinateur?.ieee == I.pont && m.coordinateur?.tableNonLue == true)
        #expect(m.parent(de: I.f1) == nil, "l'enfant du pont n'est connu que par sa table")
    }

    /// Une adresse courte qui change avant son tour : la plus recente est demandee, et le noeud la garde.
    @Test func adresseCourteLaPlusRecente() async throws {
        var reseau = SondeSimulee.reseau
        reseau[0x1A2B] = [SondeSimulee.routeur("0000", I.pont, lqi: 210, type: "coordinateur"),
                          SondeSimulee.routeur("2C3D", I.r2, lqi: 90)]
        reseau[0x2C3D] = reseau[0x2B3C]
        reseau[0x2B3C] = nil
        reseau[0x4D5E] = [SondeSimulee.routeur("3C4D", I.r3, lqi: 118), SondeSimulee.routeur("2C3D", I.r2, lqi: 44)]
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0), reseau: reseau)
        let m = try #require(try await Self.executer(s).maillage)
        #expect(s.requetes.filter { $0.hasPrefix("table") }.prefix(3) == ["table 0000", "table 1A2B", "table 2C3D"])
        #expect(!s.requetes.contains("table 2B3C"))
        #expect(m.noeud(I.r2)?.court == 0x2C3D)
    }

    /// Adresses longues invalides : un noeud garde par son adresse courte seulement (cle provisoire), jamais dans
    /// l'historique ; fondu dans le noeud de meme adresse courte s'il en a une ailleurs.
    @Test func adressesLonguesInvalides() async throws {
        var reseau = SondeSimulee.reseau
        reseau[0x0000] = (reseau[0x0000] ?? []) + [SondeSimulee.enfant("0A13", "0000000000000000", lqi: 90, ecoute: true)]
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0), reseau: reseau)
        let m = try #require(try await Self.executer(s).maillage)
        let provisoire = NoeudZigbee.cleProvisoire(court: 0x0A13)
        #expect(provisoire == "~0A13")
        let n = try #require(m.noeud(provisoire))
        #expect(!n.ieeeConnue && n.type == .final && m.parent(de: provisoire)?.parent == I.pont)
        #expect(m.noeud("~4D5E") == nil, "R4 retrouve par son adresse courte")
        let releve = ReleveMaillage(m)
        #expect(!releve.noeuds.contains { $0.ieee == provisoire } && !releve.parents.contains { $0.enfant == provisoire })
        #expect(releve.noeuds.count == m.noeuds.count - 1)
        #expect(ProtocoleSonde.ieee("ffffffffffffffff") == nil && ProtocoleSonde.ieee("a000000000000001") == I.sonde)
        #expect(ProtocoleSonde.ieee("A00000000000001") == nil && ProtocoleSonde.ieee(nil) == nil)
    }

    /// Un appareil final que deux tables rangent en enfant (le premier parent ne l'a pas encore oublie) : la mesure la
    /// plus recente l'emporte.
    @Test func parentLePlusRecent() async throws {
        var reseau = SondeSimulee.reseau
        reseau[0x3C4D] = (reseau[0x3C4D] ?? []) + [SondeSimulee.enfant("0A11", I.f1, lqi: 60, ecoute: false)]
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0), reseau: reseau)
        let m = try #require(try await Self.executer(s).maillage)
        #expect(m.parent(de: I.f1)?.parent == I.r3 && m.parent(de: I.f1)?.lqi == 60)
    }

    /// Les chemins vers le pont : R1 et R2 directs, R3 par R1 (la route active l'emporte sur l'inactive), R4 suppose
    /// par son voisin de meilleur LQI deja relie au pont (R3 : 118, contre 40 pour R2) ; les sauts jusqu'au pont, ceux
    /// d'un appareil final par son parent.
    @Test func cheminsVersLePont() async throws {
        let s = SondeSimulee(horloge: HorlogeTournee(Self.t0))
        let m = try #require(try await Self.executer(s).maillage)
        #expect(m.chemins.map(\.routeur) == [I.r1, I.r2, I.r3, I.r4], "les routeurs, pas le pont")
        let r1 = try #require(m.chemin(de: I.r1))
        #expect(r1.prochain == I.pont && r1.actif && r1.plusieursVersUn && !r1.suppose && r1.date != nil)
        #expect(m.chemin(de: I.r2)?.prochain == I.pont && m.chemin(de: I.r3)?.prochain == I.r1)
        let r4 = try #require(m.chemin(de: I.r4))
        #expect(r4.prochain == I.r3 && r4.suppose && !r4.actif)
        #expect(m.sauts(de: I.r1) == 1 && m.sauts(de: I.r3) == 2 && m.sauts(de: I.r4) == 3 && m.sauts(de: I.pont) == 0)
        #expect(m.sauts(de: I.sonde) == 2 && m.sauts(de: I.f1) == 1 && m.prochainSaut(de: I.f2) == I.r2)
    }

    /// Sans route active nulle part, tout est suppose, tour par tour depuis le pont ; une boucle de routes actives ne
    /// relie pas au pont (chemins incomplets, pas de boucle infinie), et un routeur sans voisin relie n'a pas de chemin.
    @Test func cheminsSupposesEtBoucles() {
        let a = "B000000000000001", b = "B000000000000002", c = "B000000000000003", p = "B0000000000000FF"
        let d = "B000000000000004"
        let noeuds = [NoeudZigbee(ieee: p, court: 0, type: .coordinateur), NoeudZigbee(ieee: a, court: 1, type: .routeur),
                      NoeudZigbee(ieee: b, court: 2, type: .routeur), NoeudZigbee(ieee: c, court: 3, type: .routeur),
                      NoeudZigbee(ieee: d, court: 4, type: .routeur)]
        let liens = [LienRadio(a: a, b: p, lqiA: 90, lqiB: 95), LienRadio(a: a, b: b, lqiA: 200, lqiB: 190),
                     LienRadio(a: b, b: p, lqiA: 60, lqiB: nil), LienRadio(a: b, b: c, lqiA: 150, lqiB: 160)]
        let supposes = CheminsPont.calculer(noeuds: noeuds, liens: liens, routes: [:])
        #expect(supposes.map { [$0.routeur, $0.prochain] } == [[a, p], [b, p], [c, b]])
        #expect(supposes.allSatisfy { $0.suppose }, "d n'a aucun voisin : pas de chemin")
        let t = Self.t0
        let boucle: [String: RouteVersPont] = [
            a: RouteVersPont(prochain: 2, actif: true, plusieursVersUn: true, date: t),
            b: RouteVersPont(prochain: 1, actif: true, plusieursVersUn: true, date: t),
        ]
        let m = MaillageZigbee(date: t, noeuds: noeuds, liens: liens,
                               chemins: CheminsPont.calculer(noeuds: noeuds, liens: liens, routes: boucle))
        #expect(m.chemin(de: a)?.prochain == b && m.chemin(de: b)?.prochain == a, "les routes lues restent")
        #expect(m.sauts(de: a) == nil && m.sauts(de: b) == nil && m.chemin(de: c) == nil, "rien n'est relie au pont")
        #expect(RouteVersPont.depuis([EntreeRoute(destination: "1A2B", etat: "active", prochain: "1A2B")], date: t) == nil)
    }

    /// Les tables de voisins une tournee sur quatre : la premiere les lit ; les trois suivantes ne lisent que les routes
    /// (les liens, les parents et leur date viennent de la memoire, la sonde sous son parent du moment) ; la cinquieme
    /// les relit.
    @Test func tablesUneTourneeSurQuatre() async throws {
        let h = HorlogeTournee(Self.t0)
        var memoire = MemoireTournee()
        var maillages: [MaillageZigbee] = []
        var requetes: [[String]] = []
        for _ in 0..<5 {
            let s = SondeSimulee(horloge: h)
            let r = try await Self.executer(s, memoire: memoire)
            memoire = r.memoire
            maillages.append(try #require(r.maillage))
            requetes.append(s.requetes)
            h.avancer(900)
        }
        #expect(requetes.map { $0.contains { $0.hasPrefix("table") } } == [true, false, false, false, true])
        #expect(requetes[1] == ["etat", "voisins", "routes 0000", "routes 1A2B", "routes 2B3C", "routes 3C4D",
                                "routes 4D5E"])
        let premier = maillages[0]
        for m in maillages[1...3] {
            #expect(m.liens == premier.liens && m.parents == premier.parents && m.noeuds == premier.noeuds)
            #expect(m.dateTables == premier.date && m.chemins.map(\.prochain) == premier.chemins.map(\.prochain))
            #expect(m.complet && m.date > premier.date)
        }
        #expect(maillages[4].dateTables == maillages[4].date && memoire.tourneesSansTables == 0)
    }

    /// Un routeur inconnu vu en route (une route active par une adresse courte qu'aucune table connue n'a) : la tournee,
    /// qui ne devait lire que les routes, lit aussi les tables, puis demande ses routes ; un prochain saut que les
    /// tables ne connaissent toujours pas est garde sous son adresse courte.
    @Test func routeurInconnuVuEnRoute() async throws {
        let h = HorlogeTournee(Self.t0)
        let r1 = try await Self.executer(SondeSimulee(horloge: h))
        // R5 (6E7F) apparait a cote de R1 ; R3 passe par lui, et R2 par un 7F80 qu'aucune table ne donne.
        let r5 = "A000000000000009"
        var reseau = SondeSimulee.reseau
        reseau[0x1A2B] = (reseau[0x1A2B] ?? []) + [SondeSimulee.routeur("6E7F", r5, lqi: 170)]
        reseau[0x6E7F] = [SondeSimulee.routeur("1A2B", I.r1, lqi: 175)]
        var routes = SondeSimulee.routesRouteurs
        routes[0x3C4D] = [EntreeRoute(destination: "0000", etat: "active", prochain: "6E7F", plusieursVersUn: true)]
        routes[0x2B3C] = [EntreeRoute(destination: "0000", etat: "active", prochain: "7F80", plusieursVersUn: true)]
        routes[0x6E7F] = [EntreeRoute(destination: "0000", etat: "active", prochain: "1A2B", plusieursVersUn: true)]
        let s = SondeSimulee(horloge: h, reseau: reseau, routesRouteurs: routes)
        let r2 = try await Self.executer(s, memoire: r1.memoire)
        #expect(r2.bilan.avecTables)
        // Apres les tables, les routeurs jamais lus (6E7F, puis 7F80) passent avant R3 et R4.
        #expect(s.requetes == ["etat", "voisins", "routes 0000", "routes 1A2B", "routes 2B3C", "table 0000", "table 1A2B",
                               "table 2B3C", "table 3C4D", "table 6E7F", "table 4D5E", "routes 6E7F", "routes 7F80",
                               "routes 3C4D", "routes 4D5E"])
        let m = try #require(r2.maillage)
        #expect(m.chemin(de: I.r3)?.prochain == r5 && m.chemin(de: r5)?.prochain == I.r1 && m.sauts(de: I.r3) == 3)
        let inconnu = NoeudZigbee.cleProvisoire(court: 0x7F80)
        #expect(m.noeud(inconnu)?.type == .routeur && m.chemin(de: I.r2)?.prochain == inconnu)
        #expect(m.sauts(de: I.r2) == nil, "7F80 ne donne pas ses routes : chemin incomplet")
        #expect(r2.memoire.tables?.lues.count == 6 && r2.memoire.tourneesSansTables == 0)
    }

    // MARK: Budget de pages et routes en plusieurs passes (consigne de l'etape 3 ter)

    /// Le budget de pages : une fenetre glissante de 10 minutes, les envois sortis oublies, jamais negatif.
    @Test func budgetDePages() {
        var b = BudgetPages()
        #expect(b.restant(a: Self.t0) == BudgetPages.plafond && BudgetPages.plafond == 550)
        b.compter(300, a: Self.t0)
        b.compter(200, a: Self.t0.addingTimeInterval(300))
        #expect(b.utilisees(a: Self.t0.addingTimeInterval(300)) == 500 && b.restant(a: Self.t0.addingTimeInterval(300)) == 50)
        #expect(b.utilisees(a: Self.t0.addingTimeInterval(600)) == 200, "les 300 premieres sont sorties de la fenetre")
        b.compter(400, a: Self.t0.addingTimeInterval(310))
        #expect(b.restant(a: Self.t0.addingTimeInterval(310)) == 0, "jamais negatif")
        b.compter(1, a: Self.t0.addingTimeInterval(1000))
        #expect(b.envois == [BudgetPages.Envoi(date: Self.t0.addingTimeInterval(1000), pages: 1)], "les envois sortis oublies")
    }

    /// Un grand reseau invente : le pont et 35 routeurs (le premier, R1, parent de la sonde), chacun relie au pont par
    /// une route « plusieurs vers un » active. Pages : 30 pour la table du pont, 12 par table de routeur (450 en tout),
    /// 22 pour les routes du pont, 5 par table de routage de routeur.
    static let pontGrand = "C0000000000000FF"
    static func routeurGrand(_ i: Int) -> (court: UInt16, ieee: String) {
        i == 0 ? (0x1A2B, I.r1) : (UInt16(0x1000 + i), String(format: "C0000000000000%02X", i))
    }

    static func sondeGrande(_ h: HorlogeTournee,
                            panne: @escaping @Sendable (String, Int) -> SondeSimulee.Panne? = { _, _ in nil })
        -> SondeSimulee {
        let routeurs = (0..<35).map(routeurGrand)
        var reseau: [UInt16: [EntreeTable]] = [
            0x0000: routeurs.map { SondeSimulee.routeur(ProtocoleSonde.texte(court: $0.court), $0.ieee, lqi: 200) },
        ]
        var routes: [UInt16: [EntreeRoute]] = [:]
        for r in routeurs {
            reseau[r.court] = [SondeSimulee.routeur("0000", pontGrand, lqi: 180, type: "coordinateur")]
            routes[r.court] = [EntreeRoute(destination: "0000", etat: "active", prochain: "0000", plusieursVersUn: true)]
        }
        return SondeSimulee(horloge: h, reseau: reseau, routesRouteurs: routes, panne: panne, pages: { q in
            switch q {
            case "table 0000": 30
            case "routes 0000": 22
            default: q.hasPrefix("table") ? 12 : 5
            }
        }, plafond: 600)
    }

    /// Les routes des routeurs demandees, dans l'ordre (sans celles du pont).
    static func routesDemandees(_ s: SondeSimulee) -> [String] {
        s.requetes.filter { $0.hasPrefix("routes") && $0 != "routes 0000" }
    }

    /// Une tournee complete de 35 routeurs (tables 450 pages, routes du pont 22) : les routes des routeurs s'arretent a
    /// 15 (75 pages), sans jamais depasser 550 pages sur 10 minutes ni de refus `cadence` ; les 20 autres sont
    /// reportees, sans tournee incomplete ni routeur en echec. La tournee suivante (15 minutes apres) lit d'abord
    /// celles-la, puis les 15 autres par anciennete.
    @Test func routesEnPlusieursPasses() async throws {
        let h = HorlogeTournee(Self.t0)
        let s1 = Self.sondeGrande(h)
        var etapes: [AvancementTournee] = []
        let r1 = try await Self.executer(s1) { etapes.append($0) }
        let m1 = try #require(r1.maillage)
        let cles = (0..<35).map { Self.routeurGrand($0) }
        #expect(s1.requetes.filter { $0.hasPrefix("table") }.count == 36)
        #expect(Self.routesDemandees(s1) == cles.prefix(15).map { "routes \(ProtocoleSonde.texte(court: $0.court))" })
        #expect(s1.requetes.firstIndex(of: "routes 0000")! < s1.requetes.firstIndex(of: "routes 1A2B")!, "le pont d'abord")
        #expect(r1.bilan.pages == 450 + 22 + 15 * 5 && r1.bilan.pages <= BudgetPages.plafond)
        #expect(s1.pagesMaxSurDixMinutes <= BudgetPages.plafond && s1.refusCadence == 0 && r1.bilan.pausesCadence == 0)
        #expect(r1.bilan.routesRouteursDemandees == 15 && r1.bilan.routesRouteursLues == 15 && r1.bilan.routesReportees == 20)
        #expect(m1.complet && r1.bilan.lacune == nil && r1.memoire.echecs.isEmpty && r1.bilan.muets == 0)
        #expect(!m1.noeuds.contains { $0.muet || $0.tableNonLue })
        // Avancement : « Routes des routeurs · n/15 », 15 etant ce que le budget couvre dans cette passe.
        let passe = etapes.filter { $0.etape == .routesRouteurs }
        #expect(passe.map(\.fait) == Array(0...15) && passe.allSatisfy { $0.total == 15 })
        // Les routeurs lus ont un chemin lu, date ; les autres, un chemin suppose (aucune route connue).
        #expect(m1.chemin(de: cles[0].ieee)?.suppose == false && m1.chemin(de: cles[0].ieee)?.date != nil)
        #expect(m1.chemin(de: cles[20].ieee)?.suppose == true && m1.chemin(de: cles[20].ieee)?.prochain == Self.pontGrand)

        h.avancer(900)
        let s2 = Self.sondeGrande(h)
        let r2 = try await Self.executer(s2, memoire: r1.memoire)
        let m2 = try #require(r2.maillage)
        let ordre = Array(cles[15...]) + Array(cles[..<15])
        #expect(!r2.bilan.avecTables)
        #expect(Self.routesDemandees(s2) == ordre.map { "routes \(ProtocoleSonde.texte(court: $0.court))" },
                "les reportees d'abord, puis par anciennete")
        #expect(r2.bilan.routesReportees == 0 && r2.bilan.pages == 22 + 35 * 5 && s2.refusCadence == 0)
        #expect(m2.complet && m2.chemins.count == 35 && m2.chemins.allSatisfy { !$0.suppose })
        // Les deux tournees ensemble : jamais plus de 550 pages sur 10 minutes.
        #expect(SondeSimulee.pagesMaxSurDixMinutes(s1.envois + s2.envois) <= BudgetPages.plafond)
        #expect(s1.envois.count + s2.envois.count == 36 + 1 + 15 + 1 + 35)
        #expect(r2.memoire.budget.utilisees(a: h.maintenant) == 22 + 35 * 5, "les pages de la premiere sont sorties")
    }

    /// Une tournee relancee peu apres une tournee complete : le budget ne couvre plus aucune route de routeur ; les
    /// routeurs gardent leur chemin d'avant, avec sa date, et la tournee n'est ni incomplete ni en echec.
    @Test func cheminsGardesFauteDeBudget() async throws {
        let h = HorlogeTournee(Self.t0)
        let r1 = try await Self.executer(Self.sondeGrande(h))
        let m1 = try #require(r1.maillage)
        h.avancer(120)
        let s2 = Self.sondeGrande(h)
        var etapes: [AvancementTournee] = []
        let r2 = try await Self.executer(s2, memoire: r1.memoire) { etapes.append($0) }
        let m2 = try #require(r2.maillage)
        #expect(s2.requetes == ["etat", "voisins", "routes 0000"], "les routes du pont, prioritaires ; rien d'autre")
        #expect(r2.bilan.routesRouteursDemandees == 0 && r2.bilan.routesReportees == 35 && r2.bilan.routesLues)
        #expect(m2.complet && r2.bilan.lacune == nil && r2.memoire.echecs.isEmpty && s2.refusCadence == 0)
        #expect(etapes.filter { $0.etape == .routesRouteurs } == [AvancementTournee(etape: .routesRouteurs, fait: 0, total: 0)])
        let lu = Self.routeurGrand(3).ieee
        #expect(m2.chemin(de: lu) == m1.chemin(de: lu) && m2.chemin(de: lu)?.date != nil, "le chemin d'avant, sa date")
        #expect(r2.memoire.routes == r1.memoire.routes)
    }

    /// Les routes des routeurs par anciennete de leur derniere lecture : jamais lu d'abord, puis la plus ancienne ;
    /// l'estimation d'une requete est le nombre de pages de sa derniere lecture : le budget s'arrete au premier routeur
    /// qu'il ne couvre plus, sans passer au suivant.
    @Test func ordreParAnciennete() async throws {
        let h = HorlogeTournee(Self.t0)
        let r0 = try await Self.executer(SondeSimulee(horloge: h))
        h.avancer(900)
        var memoire = r0.memoire
        func lue(_ secondes: TimeInterval, pages: Int? = 5) -> RoutesLues {
            RoutesLues(date: Self.t0.addingTimeInterval(secondes), pages: pages, route: nil)
        }
        memoire.routes = [I.r1: lue(30), I.r2: lue(10), I.r4: lue(20)]
        let s = SondeSimulee(horloge: h)
        _ = try await Self.executer(s, memoire: memoire)
        #expect(Self.routesDemandees(s) == ["routes 3C4D", "routes 2B3C", "routes 4D5E", "routes 1A2B"])
        // R2 (le plus ancien) estime a 600 pages : le budget ne le couvre pas, la passe s'arrete avant lui.
        memoire.routes[I.r2] = lue(10, pages: 600)
        let s2 = SondeSimulee(horloge: h)
        var etapes: [AvancementTournee] = []
        let r2 = try await Self.executer(s2, memoire: memoire) { etapes.append($0) }
        #expect(Self.routesDemandees(s2) == ["routes 3C4D"] && r2.bilan.routesReportees == 3)
        #expect(etapes.filter { $0.etape == .routesRouteurs }.map(\.total) == [1, 1])
        #expect(r2.memoire.routes[I.r2] == memoire.routes[I.r2], "la lecture d'avant reste")
    }

    /// Deux refus `cadence` de suite pendant la passe des routes : la passe s'arrete (les routeurs restants passent a
    /// la tournee suivante, ou ils sont lus d'abord), sans tournee incomplete ni echec. Un refus suivi d'une reponse ne
    /// compte plus : deux refus sur deux routeurs differents, chacun suivi de sa reponse, n'arretent rien.
    @Test func arretApresDeuxRefusCadence() async throws {
        let h = HorlogeTournee(Self.t0)
        let s = SondeSimulee(horloge: h) { q, _ in q == "routes 2B3C" ? .erreur("cadence") : nil }
        let r = try await Self.executer(s)
        let m = try #require(r.maillage)
        #expect(Self.routesDemandees(s) == ["routes 1A2B", "routes 2B3C", "routes 2B3C"])
        #expect(r.bilan.pausesCadence == 1 && r.bilan.passeArreteeCadence && r.bilan.routesReportees == 3)
        #expect(m.complet && r.bilan.lacune == nil && r.memoire.echecs.isEmpty && r.bilan.sansReponse == 0)
        #expect(r.bilan.routesRouteursDemandees == 1 && r.bilan.routesLues)
        h.avancer(900)
        let s2 = SondeSimulee(horloge: h)
        let r2 = try await Self.executer(s2, memoire: r.memoire)
        #expect(Self.routesDemandees(s2) == ["routes 2B3C", "routes 3C4D", "routes 4D5E", "routes 1A2B"])
        #expect(!r2.bilan.passeArreteeCadence && r2.bilan.routesReportees == 0)

        let s3 = SondeSimulee(horloge: HorlogeTournee(Self.t0)) { q, rang in
            (q == "routes 2B3C" || q == "routes 3C4D") && rang == 1 ? .erreur("cadence") : nil
        }
        let r3 = try await Self.executer(s3)
        #expect(Self.routesDemandees(s3) == ["routes 1A2B", "routes 2B3C", "routes 2B3C", "routes 3C4D", "routes 3C4D",
                                             "routes 4D5E"])
        #expect(r3.bilan.pausesCadence == 2 && !r3.bilan.passeArreteeCadence && r3.bilan.routesRouteursLues == 4)
    }

    // MARK: Passe complementaire (decision de Majid du 08/10)

    /// Le premier instant ou `pages` de plus tiennent sous le plafond : `minimum` s'il convient, sinon la sortie de la
    /// fenetre d'un envoi (sa date + 10 minutes) ; au-dela de 550 pages a elles seules, la fenetre vide.
    @Test func premierInstantDuBudget() {
        let minimum = Self.t0.addingTimeInterval(30)
        // Rien d'envoye : tout de suite.
        #expect(BudgetPages().premierInstant(pour: 550, auPlusTot: minimum) == minimum)
        // 300 pages a t0, 200 a t0+100, 40 a t0+200 : 540 utilisees.
        var b = BudgetPages()
        b.compter(300, a: Self.t0)
        b.compter(200, a: Self.t0.addingTimeInterval(100))
        b.compter(40, a: Self.t0.addingTimeInterval(200))
        #expect(b.utilisees(a: minimum) == 540)
        #expect(b.premierInstant(pour: 10, auPlusTot: minimum) == minimum, "540 + 10 = 550 : tient")
        #expect(b.premierInstant(pour: 11, auPlusTot: minimum) == Self.t0.addingTimeInterval(600),
                "les 300 premieres sortent a t0+600 : 240 + 11")
        #expect(b.premierInstant(pour: 310, auPlusTot: minimum) == Self.t0.addingTimeInterval(600), "240 + 310 = 550")
        #expect(b.premierInstant(pour: 311, auPlusTot: minimum) == Self.t0.addingTimeInterval(700),
                "il faut aussi les 200 suivantes : 40 + 311")
        #expect(b.premierInstant(pour: 551, auPlusTot: minimum) == Self.t0.addingTimeInterval(800), "fenetre vide")
        #expect(b.premierInstant(pour: 5000, auPlusTot: minimum) == Self.t0.addingTimeInterval(800), "fenetre vide")
        // Le minimum passe, la fenetre est deja vide.
        #expect(b.premierInstant(pour: 550, auPlusTot: Self.t0.addingTimeInterval(900)) == Self.t0.addingTimeInterval(900))
    }

    /// L'instant de la passe complementaire d'une tournee : au moins 30 s apres sa fin, des que les pages des routeurs
    /// reportes (et des routes du pont, relues) tiennent ; la fenetre vide si elles depassent 550 a elles seules ; nil
    /// si rien n'est reporte, ou sans tables en memoire (relecture finale, I1).
    @Test func instantDeLaPasseComplementaire() {
        let fin = Self.t0.addingTimeInterval(500)
        var m = MemoireTournee(tables: TablesVoisins(date: Self.t0, lues: []))
        #expect(m.instantPasseComplementaire(apres: fin) == nil, "rien de reporte : pas de passe")
        m.reportees = ["a", "b"]
        #expect(m.pagesPasseComplementaire == 5 + 5 + 5, "pont et routeurs jamais lus : 5 pages chacun")
        #expect(m.instantPasseComplementaire(apres: fin) == fin.addingTimeInterval(30), "budget vide : 30 s apres la fin")
        var sansTables = m
        sansTables.tables = nil
        #expect(sansTables.instantPasseComplementaire(apres: fin) == nil, "sans tables en memoire : pas de passe")
        m.pagesRoutesPont = 22
        m.routes["a"] = RoutesLues(date: Self.t0, pages: 8, route: nil)
        #expect(m.pagesPasseComplementaire == 22 + 8 + 5)
        // 520 pages a t0 + 100 ; 30 a t0 + 400 : 550 utilisees a fin + 30, 35 pages a loger : il faut les 520 sorties.
        m.budget.compter(520, a: Self.t0.addingTimeInterval(100))
        m.budget.compter(30, a: Self.t0.addingTimeInterval(400))
        #expect(m.budget.restant(a: fin) == 0)
        #expect(m.instantPasseComplementaire(apres: fin) == Self.t0.addingTimeInterval(700))
        // Plus de 550 pages a elles seules : la fenetre vide (la derniere sortie).
        m.reportees = (0..<6).map { "r\($0)" }
        for k in m.reportees { m.routes[k] = RoutesLues(date: Self.t0, pages: 100, route: nil) }
        #expect(m.pagesPasseComplementaire == 22 + 600)
        #expect(m.instantPasseComplementaire(apres: fin) == Self.t0.addingTimeInterval(1000))
    }

    /// Une tournee qui reporte 20 routes (reseau de 35 routeurs) : la memoire les garde, l'instant de la passe est le
    /// premier ou 122 pages (20 x 5, plus 22 pour les routes du pont) tiennent. A cet instant, la passe complementaire
    /// ne lit que les routes reportees : ni `table`, ni les autres routeurs ; jamais plus de 550 pages sur 10 minutes,
    /// aucun refus de la sonde, la memoire des tables inchangee.
    @Test func passeComplementaire() async throws {
        let h = HorlogeTournee(Self.t0)
        let s1 = Self.sondeGrande(h)
        let r1 = try await Self.executer(s1)
        let m1 = try #require(r1.maillage)
        let cles = (0..<35).map { Self.routeurGrand($0) }
        #expect(r1.bilan.routesReportees == 20 && !r1.bilan.complementaire)
        #expect(r1.memoire.reportees == cles[15...].map(\.ieee), "dans l'ordre de la file")
        #expect(r1.memoire.pagesRoutesPont == 22 && r1.memoire.pagesPasseComplementaire == 22 + 20 * 5)
        let fin = h.maintenant
        let instant = try #require(r1.memoire.instantPasseComplementaire(apres: fin))
        // Le premier instant (a la seconde pres) ou le budget couvre 122 pages, d'apres un balayage independant.
        let attendu = (30...2000).map { fin.addingTimeInterval(Double($0)) }
            .first { r1.memoire.budget.restant(a: $0) >= 122 }
        #expect(attendu != nil && instant <= attendu! && instant > attendu!.addingTimeInterval(-1))
        #expect(instant >= fin.addingTimeInterval(30) && r1.memoire.budget.restant(a: instant) >= 122)
        #expect(r1.memoire.budget.restant(a: instant.addingTimeInterval(-0.5)) < 122 || instant == fin.addingTimeInterval(30),
                "le premier : une demi-seconde plus tot, le budget ne suffit pas")

        h.avancer(instant.timeIntervalSince(fin))
        let s2 = Self.sondeGrande(h)
        var etapes: [AvancementTournee] = []
        let r2 = try await Tournee.executer(s2, memoire: r1.memoire, complementaire: true, horloge: { h.maintenant },
                                            attendre: { h.avancer(Double($0.components.seconds)) }) { etapes.append($0) }
        let m2 = try #require(r2.maillage)
        #expect(s2.requetes == ["etat", "voisins", "routes 0000"] + cles[15...].map { "routes \(ProtocoleSonde.texte(court: $0.court))" },
                "pas de tables ; le pont, puis les routes reportees seulement")
        #expect(r2.bilan.complementaire && !r2.bilan.avecTables && r2.bilan.routesRouteursLues == 20)
        #expect(r2.bilan.routesReportees == 0 && r2.memoire.reportees.isEmpty && r2.memoire.instantPasseComplementaire(apres: h.maintenant) == nil)
        #expect(r2.bilan.pages == 22 + 20 * 5 && s2.refusCadence == 0 && r2.bilan.pausesCadence == 0)
        #expect(SondeSimulee.pagesMaxSurDixMinutes(s1.envois + s2.envois) <= BudgetPages.plafond)
        #expect(m2.complet && r2.bilan.lacune == nil && r2.memoire.echecs.isEmpty && m2.dateTables == m1.dateTables)
        #expect(r2.memoire.tables == r1.memoire.tables && r2.memoire.tourneesSansTables == r1.memoire.tourneesSansTables,
                "la passe ne compte pas dans le rythme des tables")
        #expect(etapes.filter { $0.etape == .routesRouteurs }.map(\.total).allSatisfy { $0 == 20 })
        // Les 20 reportes ont maintenant un chemin lu ; les 15 de la premiere tournee gardent le leur.
        #expect(m2.chemins.count == 35 && m2.chemins.allSatisfy { !$0.suppose })
        #expect(m2.liens == m1.liens, "les liens des tables de la memoire")
    }

    /// Rien de reporte : aucune passe. Une passe qui ne tient pas dans le budget (lancee trop tot) rapporte a son tour
    /// ce qu'elle n'a pas lu.
    @Test func sansReportPasDePasse() async throws {
        let h = HorlogeTournee(Self.t0)
        let r = try await Self.executer(SondeSimulee(horloge: h))
        #expect(r.bilan.routesReportees == 0 && r.memoire.reportees.isEmpty)
        #expect(r.memoire.instantPasseComplementaire(apres: h.maintenant) == nil)
        // Passe lancee alors que le budget est epuise : rien de lu, tout reste reporte.
        let g = HorlogeTournee(Self.t0)
        let r1 = try await Self.executer(Self.sondeGrande(g))
        g.avancer(31)
        let s2 = Self.sondeGrande(g)
        let r2 = try await Tournee.executer(s2, memoire: r1.memoire, complementaire: true, horloge: { g.maintenant },
                                            attendre: { g.avancer(Double($0.components.seconds)) })
        #expect(s2.requetes == ["etat", "voisins", "routes 0000"] && r2.bilan.routesRouteursDemandees == 0)
        #expect(r2.memoire.reportees == r1.memoire.reportees && r2.bilan.routesReportees == 20)
    }

    /// Relecture finale, I1 : apres un lancement (memoire neuve), une tournee aux tables incompletes (une table en
    /// `envoi`) qui reporte des routes ne garde pas de tables ; elle ne programme donc pas de passe complementaire.
    /// Une passe lancee quand meme ne connait que la sonde et son parent : elle est incomplete (`sans_tables`), ne
    /// touche pas a la memoire des routes, et le suivi n'y voit aucun routeur disparu.
    @Test func passeSansTablesNiDisparitions() async throws {
        let h = HorlogeTournee(Self.t0)
        let enPanne = "table \(ProtocoleSonde.texte(court: Self.routeurGrand(5).court))"
        let r1 = try await Self.executer(Self.sondeGrande(h, panne: { q, _ in q == enPanne ? .erreur("envoi") : nil }))
        let m1 = try #require(r1.maillage)
        #expect(!m1.complet && r1.bilan.lacune == "envoi" && r1.memoire.tables == nil)
        #expect(!r1.memoire.reportees.isEmpty && !r1.memoire.routes.isEmpty)
        #expect(r1.memoire.instantPasseComplementaire(apres: h.maintenant) == nil, "pas de passe sans tables en memoire")
        #expect(r1.memoire.tablesDues, "la tournee suivante relit les tables")

        h.avancer(700)
        let r2 = try await Tournee.executer(Self.sondeGrande(h), memoire: r1.memoire, complementaire: true,
                                            horloge: { h.maintenant }, attendre: { h.avancer(Double($0.components.seconds)) })
        let m2 = try #require(r2.maillage)
        #expect(!m2.complet && r2.bilan.lacune == Tournee.lacuneSansTables)
        #expect(Set(r1.memoire.routes.keys).isSubset(of: Set(r2.memoire.routes.keys)), "la memoire des routes reste")
        var suivi = SuiviMaillage()
        _ = suivi.integrer(m1) { $0 }
        let ev = suivi.integrer(m2) { $0 }
        #expect(!ev.contains { $0.type == .routeurDisparu })
    }

    /// Relecture finale, I1 : une tournee aux tables incompletes (seule celle du pont est lue) ne voit ni R3 ni R4 ;
    /// la memoire garde leurs routes (et leur chemin) : ce qu'elle n'a pas vu n'est pas parti.
    @Test func tourneeIncompleteGardeLesRoutes() async throws {
        let h = HorlogeTournee(Self.t0)
        let r1 = try await Self.executer(SondeSimulee(horloge: h))
        #expect(try #require(r1.maillage).complet)
        #expect(Set(r1.memoire.routes.keys) == [I.r1, I.r2, I.r3, I.r4])
        var memoire = r1.memoire
        memoire.tourneesSansTables = Tournee.periodeTables - 1
        h.avancer(900)
        let s2 = SondeSimulee(horloge: h, panne: { q, _ in
            q.hasPrefix("table") && q != "table 0000" ? .erreur("envoi") : nil
        })
        let r2 = try await Self.executer(s2, memoire: memoire)
        let m2 = try #require(r2.maillage)
        #expect(!m2.complet && m2.noeud(I.r3) == nil && m2.noeud(I.r4) == nil)
        #expect(Set(r2.memoire.routes.keys).isSuperset(of: [I.r1, I.r2, I.r3, I.r4]), "les routes de R3 et R4 restent")
        #expect(r2.memoire.routes[I.r3] == r1.memoire.routes[I.r3] && r2.memoire.routes[I.r4] == r1.memoire.routes[I.r4])
        #expect(r2.memoire.tables == r1.memoire.tables, "les tables d'avant restent la source")
    }

    // MARK: Journal des pages gardé d'un lancement à l'autre, tables et pont dans le budget (étape 3 quinquies)

    /// Le journal des pages sous forme compacte : les envois de moins de 10 minutes, relus tels quels ; un envoi date
    /// d'apres `maintenant` compte comme envoye maintenant ; une valeur illisible est ignoree.
    @Test func journalEnregistre() {
        var b = BudgetPages()
        b.compter(300, a: Self.t0)
        b.compter(200, a: Self.t0.addingTimeInterval(300))
        b.compter(1, a: Self.t0.addingTimeInterval(590))
        let maintenant = Self.t0.addingTimeInterval(650)
        let t1970 = { (s: TimeInterval) in Self.t0.addingTimeInterval(s).timeIntervalSince1970 }
        let v = b.enregistrable(a: maintenant)
        #expect(v == [t1970(300), 200, t1970(590), 1], "les 300 pages de t0 sont sorties de la fenetre")
        let lu = BudgetPages(enregistre: v, a: maintenant)
        #expect(lu.envois == [BudgetPages.Envoi(date: Self.t0.addingTimeInterval(300), pages: 200),
                              BudgetPages.Envoi(date: Self.t0.addingTimeInterval(590), pages: 1)])
        #expect(lu.utilisees(a: maintenant) == 201 && lu.restant(a: maintenant) == 349)
        // Un relancement plus tard : les envois sortis entre-temps ne sont pas relus.
        let tard = BudgetPages(enregistre: v, a: Self.t0.addingTimeInterval(900))
        #expect(tard.envois == [BudgetPages.Envoi(date: Self.t0.addingTimeInterval(590), pages: 1)])
        #expect(BudgetPages(enregistre: v, a: Self.t0.addingTimeInterval(1300)).envois.isEmpty)
        // Horloge reculee : un envoi date du futur compte comme envoye maintenant (jamais oublie trop tot).
        let futur = BudgetPages(enregistre: [t1970(5000), 40], a: maintenant)
        #expect(futur.envois == [BudgetPages.Envoi(date: maintenant, pages: 40)])
        // Valeurs illisibles : nombre impair, pas un nombre, pages nulles ou negatives, hors de toute mesure.
        let t = t1970(640)
        let mauvais = BudgetPages(enregistre: [.nan, 5, t, .infinity, t, 0, t, -3, t, 1e12, t], a: maintenant)
        #expect(mauvais.envois.isEmpty)
        #expect(BudgetPages(enregistre: [], a: maintenant).envois.isEmpty)
        #expect(BudgetPages().enregistrable(a: maintenant).isEmpty)
    }

    /// L'estimation de la prochaine tournee : les tables (la somme des pages de leur derniere lecture, 13 pour une table
    /// sans `pages` ou un routeur non lu ; sans tables en memoire, les pages de la derniere lecture, sinon une table)
    /// quand elles sont dues, plus les routes du pont (leur derniere lecture, sinon 22). L'instant : le premier ou le
    /// budget les couvre, la fenetre vide au-dela de 550 ; nil si c'est maintenant.
    @Test func estimationEtInstantDeLaTournee() {
        var m = MemoireTournee()
        #expect(m.tablesDues && m.pagesTablesEstimees == 13 && m.pagesProchaineTournee == 13 + 22)
        #expect(m.instantProchaineTournee(a: Self.t0) == nil, "budget vide : tout de suite")
        m.pagesTables = 450
        #expect(m.pagesTablesEstimees == 450 && m.pagesProchaineTournee == 450 + 22, "apres un relancement")
        m.tables = TablesVoisins(date: Self.t0, lues: [
            TableLue(cle: "a", court: 0, entrees: [], date: Self.t0, pages: 30),
            TableLue(cle: "b", court: 1, entrees: [], date: Self.t0),
        ], nonLues: ["c"])
        #expect(m.pagesTablesEstimees == 30 + 13 + 13, "les tables en memoire priment")
        m.tourneesSansTables = Tournee.periodeTables - 1
        #expect(m.pagesProchaineTournee == 56 + 22 && m.tablesDues)
        m.tourneesSansTables = 1
        #expect(!m.tablesDues && m.pagesProchaineTournee == 22, "sans tables a lire : les routes du pont seules")
        m.pagesRoutesPont = 7
        #expect(m.pagesProchaineTournee == 7)
        // 540 pages a t0 : 7 pages tiennent (547) ; les tables et le pont (56 + 7) attendent la sortie des envois.
        m.budget.compter(300, a: Self.t0)
        m.budget.compter(240, a: Self.t0.addingTimeInterval(100))
        let maintenant = Self.t0.addingTimeInterval(60)
        #expect(m.instantProchaineTournee(a: maintenant) == nil)
        m.tourneesSansTables = Tournee.periodeTables - 1
        #expect(m.tablesDues && m.instantProchaineTournee(a: maintenant) == Self.t0.addingTimeInterval(600),
                "les 300 premieres sortent a t0+600 : 240 + 63")
        // Les tables a elles seules depassent 550 : la fenetre vide.
        m.pagesTables = nil
        m.tables = TablesVoisins(date: Self.t0, lues: [TableLue(cle: "a", court: 0, entrees: [], date: Self.t0, pages: 900)])
        #expect(m.instantProchaineTournee(a: maintenant) == Self.t0.addingTimeInterval(700))
        // Un instant passe : plus d'attente.
        #expect(m.instantProchaineTournee(a: Self.t0.addingTimeInterval(700)) == nil)
    }

    /// Une tournee complete lit ses tables sous leurs pages (`TableLue.pages`) et garde le total (`pagesTables`).
    @Test func pagesDesTablesGardees() async throws {
        let h = HorlogeTournee(Self.t0)
        let r = try await Self.executer(Self.sondeGrande(h))
        #expect(r.memoire.pagesTables == 450 && r.memoire.pagesTablesEstimees == 450)
        #expect(r.memoire.tables?.lues.first?.pages == 30 && r.memoire.tables?.lues.last?.pages == 12)
        // Une tournee sans tables garde ce total.
        h.avancer(900)
        let r2 = try await Self.executer(Self.sondeGrande(h), memoire: r.memoire)
        #expect(!r2.bilan.avecTables && r2.memoire.pagesTables == 450)
    }

    /// Le budget tient d'un lancement de l'app a l'autre : apres chaque tournee, l'app est « relancee » 2 minutes plus
    /// tard avec une memoire neuve, sauf le journal des pages relu de ses preferences (et les pages des tables). Chaque
    /// tournee attend l'instant ou ses tables et ses routes du pont tiennent dans le budget : sur 4 tournees de 450 pages
    /// de tables, jamais plus de 550 pages sur 10 minutes (et aucun refus de la sonde simulee, a 600).
    @Test func tourneesRelanceesDansLeBudget() async throws {
        let h = HorlogeTournee(Self.t0)
        var envois: [BudgetPages.Envoi] = []
        var memoire = MemoireTournee()
        var attentes: [TimeInterval] = []
        for lancement in 0..<4 {
            h.avancer(120)
            if lancement > 0 {
                // Relancement : memoire neuve, journal relu (format des preferences).
                var neuve = MemoireTournee()
                neuve.budget = BudgetPages(enregistre: memoire.budget.enregistrable(a: h.maintenant), a: h.maintenant)
                neuve.pagesTables = memoire.pagesTables
                memoire = neuve
            }
            let avant = h.maintenant
            while let instant = memoire.instantProchaineTournee(a: h.maintenant) { h.avancer(instant.timeIntervalSince(h.maintenant)) }
            attentes.append(h.maintenant.timeIntervalSince(avant))
            let s = Self.sondeGrande(h)
            let r = try await Self.executer(s, memoire: memoire)
            #expect(r.bilan.avecTables && r.maillage?.complet == true && s.refusCadence == 0 && r.bilan.pausesCadence == 0)
            #expect(r.bilan.pages >= 450 + 22)
            memoire = r.memoire
            envois += s.envois
        }
        #expect(attentes[0] == 0, "la premiere : budget vide, tout de suite")
        #expect(attentes[1...].allSatisfy { $0 > 300 && $0 <= 600 }, "les suivantes attendent la sortie des envois d'avant")
        #expect(SondeSimulee.pagesMaxSurDixMinutes(envois) <= BudgetPages.plafond)
        // Sans le journal ni l'attente, la deuxieme tournee aurait depasse : 547 pages d'avant + 472.
        #expect(envois.count > 4 * 36)
    }

    /// Les tables demandees par un routeur inconnu vu en route ne partent que si le budget restant les couvre : sinon
    /// elles attendent la tournee suivante (due, donc differee jusqu'au budget), et le routeur est tout de meme lu.
    @Test func tablesDUnRouteurInconnuFauteDeBudget() async throws {
        let h = HorlogeTournee(Self.t0)
        let r1 = try await Self.executer(SondeSimulee(horloge: h))
        var reseau = SondeSimulee.reseau
        reseau[0x1A2B] = (reseau[0x1A2B] ?? []) + [SondeSimulee.routeur("6E7F", "A000000000000009", lqi: 170)]
        var routes = SondeSimulee.routesRouteurs
        routes[0x2B3C] = [EntreeRoute(destination: "0000", etat: "active", prochain: "7F80", plusieursVersUn: true)]
        // Les tables d'avant ont coute 40 pages chacune : 200 en tout, et il ne reste que 19 pages au budget.
        var memoire = r1.memoire
        let tables = try #require(memoire.tables)
        memoire.tables = TablesVoisins(date: tables.date, lues: tables.lues.map { var t = $0; t.pages = 40; return t })
        h.avancer(900)
        memoire.budget.compter(530, a: h.maintenant)
        let s = SondeSimulee(horloge: h, reseau: reseau, routesRouteurs: routes)
        let r2 = try await Self.executer(s, memoire: memoire)
        #expect(!s.requetes.contains { $0.hasPrefix("table") } && !r2.bilan.avecTables)
        #expect(s.requetes.contains("routes 7F80"), "le routeur inconnu est lu tout de meme")
        #expect(r2.memoire.tablesDues && r2.memoire.tables == memoire.tables, "les tables d'avant restent la source")
        #expect(r2.maillage?.complet == true && r2.bilan.lacune == nil)
    }
}
