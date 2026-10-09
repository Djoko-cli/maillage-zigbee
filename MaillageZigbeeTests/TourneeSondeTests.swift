import Foundation
import MaillageCoeur
import Synchronization
import Testing
@testable import MaillageZigbee

/// Une sonde Zigbee rejouee ligne a ligne (valeurs inventees) : un petit reseau, le pont (`0000`) et un routeur (`1A2B`)
/// dont la table arrive sur deux lignes (`suite`), la sonde sous ce routeur.
enum SondeRejouee {
    static let pont = "A000000000000003"
    static let routeur = "A000000000000002"
    static let sonde = "A000000000000001"
    static let detecteur = "A000000000000007"

    static let bonjour = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":"SONDE-Z1","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false}"#
    static let etat = #"{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":{"court":"1A2B","ieee":"A000000000000002","lqi":180,"rssi":-71},"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":false,"refus_cadence":0,"rattachements_echoues":0,"pile":"1.6.8"}"#
    static let voisins = #"{"v":1,"t":"voisins","liste":[{"court":"1A2B","ieee":"A000000000000002","type":"routeur","relation":"parent","lqi":180,"rssi":-71,"cout_sortant":1,"age":0}],"suite":false}"#

    static func entete(_ genre: String, _ id: String, _ cible: String, total: Int) -> String {
        #""v":1,"t":"\#(genre)","id":\#(id),"cible":"\#(cible)","ok":true,"ms":840,"pages":2,"total":\#(total),"partielle":false"#
    }

    static let entreePont = #"{"court":"0000","ieee":"A000000000000003","type":"coordinateur","relation":"aucune","ecoute":true,"profondeur":0,"admission":false,"lqi":210}"#
    static let entreeRouteur = #"{"court":"1A2B","ieee":"A000000000000002","type":"routeur","relation":"frere","ecoute":true,"profondeur":15,"admission":false,"lqi":200}"#
    static let entreeDetecteur = #"{"court":"0A11","ieee":"A000000000000007","type":"final","relation":"enfant","ecoute":false,"profondeur":2,"admission":false,"lqi":120}"#
    static let entreeSonde = #"{"court":"5E6F","ieee":"A000000000000001","type":"final","relation":"enfant","ecoute":true,"profondeur":2,"admission":false,"lqi":188}"#
    static let route = #"{"destination":"1A2B","etat":"active","prochain":"1A2B","memoire_limitee":false,"plusieurs_vers_un":false,"enregistrement":false}"#
    /// La route « plusieurs vers un » du routeur vers le pont.
    static let routeVersPont = #"{"destination":"0000","etat":"active","prochain":"0000","memoire_limitee":false,"plusieurs_vers_un":true,"enregistrement":false}"#

    /// Les lignes de la sonde pour une commande ; `table` et `routes` reprennent l'id recu.
    static func repondre(_ ligne: String) -> [String] {
        let mots = ligne.trimmingCharacters(in: .newlines).split(separator: " ").map(String.init)
        switch mots.first {
        case "bonjour": return [bonjour]
        case "etat": return [etat]
        case "voisins": return [voisins]
        case "table" where mots.count >= 3 && mots[1] == "0000":
            return ["{\(entete("table", mots[2], "0000", total: 2)),\"liste\":[\(entreeRouteur),\(entreeDetecteur)],\"suite\":false}"]
        case "table" where mots.count >= 3 && mots[1] == "1A2B":
            return ["{\(entete("table", mots[2], "1A2B", total: 2)),\"liste\":[\(entreePont)],\"suite\":true}",
                    "{\(entete("table", mots[2], "1A2B", total: 2)),\"liste\":[\(entreeSonde)],\"suite\":false}"]
        case "routes" where mots.count >= 3 && mots[1] == "1A2B":
            return ["{\(entete("routes", mots[2], mots[1], total: 1)),\"liste\":[\(routeVersPont)],\"suite\":false}"]
        case "routes" where mots.count >= 3:
            return ["{\(entete("routes", mots[2], mots[1], total: 1)),\"liste\":[\(route)],\"suite\":false}"]
        default: return [#"{"v":1,"t":"erreur","erreur":"inconnue"}"#]
        }
    }

    /// Commandes que l'app ne doit jamais envoyer d'elle-meme.
    static let interdites = ["oubli", "suspendre", "reprendre", "echecs", "nom"]

    static func interdite(_ ligne: String) -> Bool {
        interdites.contains { ligne.hasPrefix($0) }
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@Suite("Sonde USB : requetes reseau appariees par id et cible", .timeLimit(.minutes(1)))
struct SondeUSBReseauTests {
    /// Une table sur deux lignes `suite`, reunies ; une ligne d'un autre id ou d'une autre cible est ignoree ; les id
    /// partent de 1 et suivent.
    @Test func tableAppariee() async throws {
        let canal = CanalRejoue { l in
            guard l.hasPrefix("table 1A2B") else { return SondeRejouee.repondre(l) }
            let id = l.split(separator: " ")[2].trimmingCharacters(in: .newlines)
            let autreId = #"{"v":1,"t":"table","id":99,"cible":"1A2B","ok":false,"erreur":"delai"}"#
            let autreCible = #"{"v":1,"t":"table","id":\#(id),"cible":"2B3C","ok":false,"erreur":"delai"}"#
            return [autreId, autreCible] + SondeRejouee.repondre(l)
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let r = try #require(try await s.table(0x1A2B))
        #expect(r.ok && r.id == 1 && r.cible == "1A2B" && r.liste.count == 2 && r.complete)
        #expect(r.liste.map(\.court) == ["0000", "5E6F"])
        let p = try #require(try await s.table(0x0000))
        #expect(p.id == 2 && p.liste.count == 2)
        let routes = try #require(try await s.routes(0x0000))
        #expect(routes.ok && routes.id == 3 && routes.liste.first?.prochain == "1A2B")
        #expect(canal.envoyes == ["table 1A2B 1\n", "table 0000 2\n", "routes 0000 3\n"])
    }

    /// Une seule requete reseau a la fois : la seconde est refusee tout de suite (`occupee`), sans rien envoyer ; la
    /// premiere est servie ensuite.
    @Test func uneSeuleRequeteReseau() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let premiere = Task { try await s.table(0x1A2B) }
        try await Task.sleep(for: .milliseconds(50))
        await #expect(throws: SondeUSB.Erreur.occupee("routes")) { _ = try await s.routes(0x0000) }
        #expect(canal.envoyes == ["table 1A2B 1\n"])
        canal.emettre(SondeRejouee.repondre("table 1A2B 1"))
        #expect(try await premiere.value?.ok == true)
    }

    /// Sans reponse dans l'echeance : nil, et la requete suivante peut partir.
    @Test func echeanceDUneTable() async throws {
        let canal = CanalRejoue { l in l.hasPrefix("table 0000") ? SondeRejouee.repondre(l) : [] }
        let s = SondeUSB(canal: canal, delaiTable: .milliseconds(100))
        try await s.demarrer {}
        #expect(try await s.table(0x1A2B) == nil)
        #expect(try await s.table(0x0000)?.ok == true)
        #expect(SondeUSB(canal: canal).delaiTable == .seconds(125), "125 s par defaut : la sonde borne une table a 120 s")
    }

    /// Echec de la sonde (`non_membre`), erreur generale (`syntaxe`) : un echec de la requete, tout de suite.
    @Test func echecs() async throws {
        let canal = CanalRejoue { l in
            l.hasPrefix("table") ? [#"{"v":1,"t":"table","id":1,"cible":"1A2B","ok":false,"erreur":"non_membre"}"#]
                : [#"{"v":1,"t":"erreur","erreur":"syntaxe"}"#]
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let r = try #require(try await s.table(0x1A2B))
        #expect(!r.ok && r.erreur == "non_membre")
        let g = try #require(try await s.routes(0x1A2B))
        #expect(!g.ok && g.erreur == "syntaxe" && g.id == 2 && g.cible == "1A2B")
    }

    /// `voisins` : la table de la sonde ; `occupee` tout de suite.
    @Test func voisins() async throws {
        let s = SondeUSB(canal: CanalRejoue(repondre: SondeRejouee.repondre))
        try await s.demarrer {}
        #expect(try await s.voisins().map(\.court) == ["1A2B"])
        let occupee = SondeUSB(canal: CanalRejoue { _ in [#"{"v":1,"t":"voisins","erreur":"occupee"}"#] })
        try await occupee.demarrer {}
        await #expect(throws: SondeUSB.Erreur.occupee("voisins")) { _ = try await occupee.voisins() }
    }

    /// Relecture finale, M4 : une reponse `voisins` dont la derniere ligne manque expire ; ses lignes recues ne
    /// s'ajoutent pas a la reponse suivante (pas de doublon).
    @Test func voisinsPartielsOublies() async throws {
        let partielle = SondeRejouee.voisins.replacingOccurrences(of: #""suite":false"#, with: #""suite":true"#)
        let premiere = Mutex(true)
        let canal = CanalRejoue { l in
            guard l == "voisins\n" else { return SondeRejouee.repondre(l) }
            return premiere.withLock { p in
                defer { p = false }
                return p ? [partielle] : [SondeRejouee.voisins]
            }
        }
        let s = SondeUSB(canal: canal, delaiCommande: .milliseconds(100))
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.sansReponse("voisins")) { _ = try await s.voisins() }
        #expect(try await s.voisins().map(\.court) == ["1A2B"])
    }

    /// Les lignes `signal` ne font qu'avancer un compteur (le parent perdu a part) ; elles ne servent aucune attente.
    @Test func signaux() async throws {
        let canal = CanalRejoue { l in
            l == "etat\n" ? [#"{"v":1,"t":"signal","signal":"0x32","nom":"NLME_STATUS_INDICATION","ok":true,"detail":9}"#,
                             SondeRejouee.etat] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        #expect(try await s.etat().membre)
        canal.emettre([#"{"v":1,"t":"signal","signal":"0x01","nom":"ZDO_SIGNAL_DEFAULT_START","ok":true,"detail":0}"#])
        try await Task.sleep(for: .milliseconds(50))
        let signaux = await s.signaux, pertes = await s.pertesParent
        #expect(signaux == 2 && pertes == 1)
    }

    /// La sonde redemarre (un bonjour non demande) pendant une table : la table echoue (`redemarree`) sans attendre
    /// l'echeance ; la liaison fermee pendant une table : `fermee`.
    @Test func redemarrageEtFermeture() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let t = Task { try await s.table(0x1A2B) }
        try await Task.sleep(for: .milliseconds(50))
        canal.emettre([SondeRejouee.bonjour])
        #expect(try await t.value?.erreur == "redemarree")
        let u = Task { try await s.table(0x1A2B) }
        try await Task.sleep(for: .milliseconds(50))
        canal.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await u.value }
    }
}

/// Horloge simulee de l'app : elle n'avance que quand le test l'avance.
final class HorlogeApp: Sendable {
    private let t: Mutex<Date>

    init(_ debut: Date) {
        t = Mutex(debut)
    }

    var maintenant: Date { t.withLock { $0 } }

    func avancer(_ secondes: TimeInterval) {
        t.withLock { $0 += secondes }
    }
}

/// Les attentes de la boucle des tournees, simulees : chaque attente note sa duree et dure jusqu'a ce que le test la
/// libere (dans l'ordre) ; une attente annulee (la tournee a ete remplacee) est comptee et se termine.
final class Sommeil: Sendable {
    private struct Etat {
        var delais: [Duration] = []
        var liberees = 0
        var annulees = 0
    }

    private let etat = Mutex(Etat())

    /// Durees demandees, dans l'ordre.
    var delais: [Duration] { etat.withLock { $0.delais } }
    var annulees: Int { etat.withLock { $0.annulees } }

    /// Libere l'attente suivante.
    func liberer() { etat.withLock { $0.liberees += 1 } }

    @Sendable func dormir(_ duree: Duration) async throws {
        let rang = etat.withLock { e in
            e.delais.append(duree)
            return e.delais.count
        }
        while etat.withLock({ $0.liberees < rang }) {
            if Task.isCancelled {
                etat.withLock { $0.annulees += 1 }
                throw CancellationError()
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@MainActor
@Suite("Tournees de la sonde dans l'app : boucle, Rafraichir, securite des ports", .timeLimit(.minutes(1)))
struct TourneeSondeTests {
    static let port = SondeMaillageTests.port

    static func sonde(_ p: UserDefaults, canal: CanalRejoue, premiere: Duration = .seconds(3600),
                      periode: Duration = .seconds(3600)) -> SondeMaillage {
        SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, delaiPremiereTournee: premiere,
                      periodeTournees: periode, delaiTable: .seconds(2), attendre: { _ in })
    }

    /// Rafraichir : une tournee tout de suite ; son maillage part a la surveillance, entre les signaux de debut et de
    /// fin ; le bilan, l'etat de la sonde et la date de la tournee sont gardes. Rien d'autre que `bonjour`, `etat`,
    /// `voisins`, `table` et `routes` n'est envoye.
    @Test func tourneeAuRafraichir() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue(repondre: SondeRejouee.repondre)
        let s = Self.sonde(p, canal: canal)
        var suite: [String] = []
        var maillages: [MaillageZigbee] = []
        s.surTournee = { suite.append($0 ? "debut" : "fin") }
        s.surMaillage = { m, _ in
            suite.append("maillage")
            maillages.append(m)
        }
        await s.connecter(Self.port, choisi: true)
        #expect(s.tourneeAuRafraichir)
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { s.derniereTournee != nil })
        #expect(suite == ["debut", "maillage", "fin"])
        #expect(canal.envoyes == ["bonjour\n", "etat\n", "etat\n", "voisins\n", "table 0000 1\n", "table 1A2B 2\n",
                                  "routes 0000 3\n", "routes 1A2B 4\n"])
        #expect(!canal.envoyes.contains(where: SondeRejouee.interdite))
        let m = try #require(maillages.first)
        #expect(m.complet && m.coordinateur?.ieee == SondeRejouee.pont && m.parentSonde == SondeRejouee.routeur)
        #expect(m.parent(de: SondeRejouee.sonde)?.lqi == 188 && m.noeud(SondeRejouee.detecteur)?.endormi == true)
        #expect(m.viaPont(vers: SondeRejouee.routeur)?.ieee == SondeRejouee.routeur)
        #expect(m.chemin(de: SondeRejouee.routeur)?.prochain == SondeRejouee.pont)
        #expect(m.chemin(de: SondeRejouee.routeur)?.suppose == false && m.dateTables == m.date)
        #expect(s.bilan?.tablesLues == 2 && s.bilan?.tablesDemandees == 2 && s.bilan?.routesLues == true)
        #expect(s.bilan?.routesRouteursLues == 1 && s.bilan?.avecTables == true)
        #expect(s.dureeTournee != nil && s.erreurTournee == nil && s.etatSonde?.canal == 25)
        #expect(!s.tourneeEnCours && s.avancement == nil && s.tourneeAuRafraichir)
        // La tournee suivante ne lit pas les tables de voisins : les routes seulement, les liens de la memoire.
        let premiere = s.derniereTournee
        let envoyes = canal.envoyes.count
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { s.derniereTournee != premiere })
        #expect(Array(canal.envoyes.dropFirst(envoyes)) == ["etat\n", "voisins\n", "routes 0000 5\n", "routes 1A2B 6\n"])
        let m2 = try #require(maillages.last)
        #expect(maillages.count == 2 && m2.complet && m2.dateTables == m.date && m2.liens == m.liens)
        #expect(m2.chemin(de: SondeRejouee.routeur)?.prochain == SondeRejouee.pont && s.bilan?.avecTables == false)
        await s.oublier()
    }

    /// La premiere tournee part seule, peu apres la connexion ; puis une a chaque periode ; l'oubli arrete la boucle.
    @Test func boucleDesTournees() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue(repondre: SondeRejouee.repondre)
        let s = Self.sonde(p, canal: canal, premiere: .milliseconds(20), periode: .milliseconds(150))
        var recus = 0
        s.surMaillage = { _, _ in recus += 1 }
        await s.connecter(Self.port, choisi: true)
        #expect(recus == 0, "pas tout de suite")
        #expect(await SondeMaillageTests.sonder { recus >= 2 })
        await s.oublier()
        let apres = recus
        try await Task.sleep(for: .milliseconds(400))
        #expect(recus == apres, "plus de tournee apres l'oubli")
        #expect(SondeMaillage.delaiPremiereTournee == .seconds(10) && SondeMaillage.periodeTournees == .seconds(900))
    }

    /// Sonde hors du reseau : pas de tournee (ni table ni routes), la raison dans les Reglages ; pas de maillage.
    @Test func sondeHorsDuReseau() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue { l in l == "etat\n" ? [CanalRejoue.etatDetache] : SondeRejouee.repondre(l) }
        let s = Self.sonde(p, canal: canal)
        var recus = 0
        s.surMaillage = { _, _ in recus += 1 }
        await s.connecter(Self.port, choisi: true)
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { s.bilan != nil })
        #expect(recus == 0 && s.erreurTournee == SondeMaillage.texteEmpechement(.horsReseau))
        #expect(!canal.envoyes.contains { $0.hasPrefix("table") || $0.hasPrefix("routes") })
        await s.oublier()
    }

    /// Un port qui ne repond pas en sonde Zigbee : `bonjour`, et rien d'autre, meme apres le delai de la premiere
    /// tournee.
    @Test func portRefuseRienQueBonjour() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let halo = #"{"v":1,"t":"bonjour","produit":"pont-halo","version":"0.4.0"}"#
        let canal = CanalRejoue { _ in [halo] }
        let s = Self.sonde(p, canal: canal, premiere: .milliseconds(10))
        await s.connecter(Self.port, choisi: true)
        try await Task.sleep(for: .milliseconds(100))
        s.rafraichir()
        #expect(canal.envoyes == ["bonjour\n"])
        guard case .refusee = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
    }

    /// La sonde debranchee pendant une tournee : la tournee finit sans maillage, l'etat passe a « absente ».
    @Test func debrancheePendantUneTournee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = CanalRejoue(fermetureDifferee: .milliseconds(10)) { l in
            l.hasPrefix("table 1A2B") ? [] : SondeRejouee.repondre(l)
        }
        let s = Self.sonde(p, canal: canal)
        var suite: [String] = []
        s.surTournee = { suite.append($0 ? "debut" : "fin") }
        s.surMaillage = { _, _ in suite.append("maillage") }
        await s.connecter(Self.port, choisi: true)
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { canal.envoyes.contains("table 1A2B 2\n") })
        #expect(s.tourneeEnCours)
        s.portsChanges([])
        #expect(s.etat == .absente && !s.tourneeEnCours && suite == ["debut", "fin"])
        try await Task.sleep(for: .milliseconds(100))
        #expect(suite == ["debut", "fin"], "aucun maillage plus tard")
    }

    /// Textes des Reglages : le role, le reseau (parent sous son nom), le bilan d'une tournee, les raisons.
    @Test func textesDesReglages() {
        let e = EtatSonde(membre: true, role: "final", parent: ParentSonde(court: "1A2B", ieee: SondeRejouee.routeur,
                                                                            lqi: 180, rssi: -71), canal: 25)
        #expect(FenetreReglages.texteRole(e)
                == [String(localized: "membre"), String(localized: "appareil final")].joined(separator: ", "))
        #expect(FenetreReglages.texteRole(EtatSonde(membre: false, recherche: true, suspendue: true))
                == [String(localized: "hors réseau"), String(localized: "cherche un réseau"),
                    String(localized: "suspendue")].joined(separator: ", "))
        #expect(FenetreReglages.texteReseau(e) { $0 == SondeRejouee.routeur ? "Plafonnier" : nil }
                == [String(localized: "canal \(25)"), String(localized: "parent \("Plafonnier") (LQI \(180))")]
                    .joined(separator: " · "))
        var b = BilanTournee()
        b.avecTables = true
        b.tablesDemandees = 36
        b.tablesLues = 35
        b.routesRouteursDemandees = 35
        b.routesRouteursLues = 34
        b.sansReponse = 1
        b.muets = 1
        #expect(FenetreReglages.texteBilan(b, duree: nil)
                == [String(localized: "\(35)/\(36) tables"), String(localized: "\(34)/\(35) routes"),
                    String(localized: "\(1) muets")].joined(separator: " · "))
        b.avecTables = false
        b.pausesCadence = 2
        #expect(FenetreReglages.texteBilan(b, duree: nil)
                == [String(localized: "\(34)/\(35) routes"), String(localized: "\(2) pauses de cadence"),
                    String(localized: "\(1) muets")].joined(separator: " · "), "sans tables : les routes seules")
        // Des routes remises a la tournee suivante faute de budget, et les pages envoyees.
        b.routesReportees = 20
        b.pages = 547
        #expect(FenetreReglages.texteBilan(b, duree: nil)
                == [String(localized: "\(34)/\(35) routes"), String(localized: "\(20) routes reportées"),
                    String(localized: "\(547) pages"), String(localized: "\(2) pauses de cadence"),
                    String(localized: "\(1) muets")].joined(separator: " · "))
        b.lacune = "non_membre"
        #expect(FenetreReglages.texteBilan(b, duree: 72).hasSuffix(String(localized: "incomplète")))
        #expect(SondeMaillage.texteLacune("non_membre") == String(localized: "Tournée incomplète : la sonde a quitté le réseau."))
        #expect(SondeMaillage.texteEmpechement(nil) == nil)
    }
}

/// Passe complementaire (decision de Majid du 08/10) : horloge et attentes simulees, sonde rejouee.
@MainActor
@Suite("Passe complementaire des routes reportees dans l'app", .timeLimit(.minutes(1)))
struct PasseComplementaireTests {
    static let t0 = Date(timeIntervalSince1970: 1_791_450_000)

    /// Une sonde dont la table du pont epuise le budget (548 pages) : les routes de 1A2B sont reportees (5 pages
    /// estimees, 0 restante). Les autres reponses donnent 2 pages. Valeurs inventees.
    static func canalCharge() -> CanalRejoue {
        CanalRejoue { l in
            let lignes = SondeRejouee.repondre(l)
            guard l.hasPrefix("table 0000") else { return lignes }
            return lignes.map { $0.replacingOccurrences(of: "\"pages\":2", with: "\"pages\":548") }
        }
    }

    static func sonde(_ p: UserDefaults, canal: CanalRejoue, horloge: HorlogeApp, sommeil: Sommeil) -> SondeMaillage {
        SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, delaiPremiereTournee: .seconds(10),
                      periodeTournees: .seconds(900), delaiTable: .seconds(2), horloge: { horloge.maintenant },
                      attendre: { _ in }, dormir: sommeil.dormir)
    }

    /// La premiere tournee (10 s apres la connexion) : `canal` apres ses requetes.
    static func premiereTournee(_ s: SondeMaillage, sommeil: Sommeil) async -> Bool {
        guard await SondeMaillageTests.sonder({ sommeil.delais.count == 1 }) else { return false }
        sommeil.liberer()
        return await SondeMaillageTests.sonder { s.derniereTournee != nil && sommeil.delais.count == 2 }
    }

    /// Une tournee qui reporte des routes programme la passe complementaire a l'instant ou le budget le permet : les 548
    /// pages de la table du pont (a t0) sortent de la fenetre a t0 + 600, et 7 pages (routes du pont et de 1A2B) y
    /// tiennent. A cet instant, la passe lit les routes reportees, sans table de voisins ; puis le rythme de 15 minutes
    /// reprend a sa fin.
    @Test func passeAProgrammer() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = Self.canalCharge()
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = Self.sonde(p, canal: canal, horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await SondeMaillageTests.sonder { sommeil.delais == [.seconds(10)] } && s.passeComplementaire == nil)
        #expect(await Self.premiereTournee(s, sommeil: sommeil))
        #expect(s.bilan?.routesReportees == 1 && s.bilan?.routesRouteursDemandees == 0 && s.bilan?.complementaire == false)
        let instant = Self.t0.addingTimeInterval(600)
        #expect(s.passeComplementaire == instant && sommeil.delais == [.seconds(10), .seconds(600)])
        #expect(TexteTournee.passeComplementaire(instant)
                == String(localized: "passe complémentaire à \(instant.formatted(date: .omitted, time: .shortened))"))
        let avant = canal.envoyes.count
        // Pas encore l'heure : rien ne part tant que l'attente dure.
        try await Task.sleep(for: .milliseconds(60))
        #expect(canal.envoyes.count == avant && s.passeComplementaire == instant)

        h.avancer(600)
        sommeil.liberer()
        #expect(await SondeMaillageTests.sonder { sommeil.delais.count == 3 })
        #expect(Array(canal.envoyes.dropFirst(avant)) == ["etat\n", "voisins\n", "routes 0000 4\n", "routes 1A2B 5\n"],
                "pas de table de voisins ; les routes du pont, puis celles reportees")
        let b = try #require(s.bilan)
        #expect(b.complementaire && !b.avecTables && b.routesRouteursLues == 1 && b.routesReportees == 0)
        #expect(s.passeComplementaire == nil && sommeil.delais.last == .seconds(900), "le rythme de 15 minutes reprend")
        #expect(!canal.envoyes.contains(where: SondeRejouee.interdite))
        await s.oublier()
    }

    /// Rien de reporte : pas de passe, la tournee suivante 15 minutes apres.
    @Test func pasDePasseSansReport() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = Self.sonde(p, canal: CanalRejoue(repondre: SondeRejouee.repondre), horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.premiereTournee(s, sommeil: sommeil))
        #expect(s.bilan?.routesReportees == 0 && s.passeComplementaire == nil)
        #expect(sommeil.delais == [.seconds(10), .seconds(900)])
        await s.oublier()
    }

    /// Une seule passe programmee a la fois, et Rafraichir s'y substitue : la tournee manuelle (qui lit d'abord les
    /// routes reportees) annule la passe, dont l'attente finit sans rien lancer ; le rythme de 15 minutes reprend a sa
    /// fin.
    @Test func rafraichirSubstitueLaPasse() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let canal = Self.canalCharge()
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = Self.sonde(p, canal: canal, horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.premiereTournee(s, sommeil: sommeil))
        #expect(s.passeComplementaire != nil && sommeil.delais.count == 2 && sommeil.annulees == 0)
        // Le budget est libre (10 minutes plus tard) : la tournee manuelle lit les routes reportees elle-meme.
        h.avancer(601)
        let avant = canal.envoyes.count
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { s.bilan?.routesRouteursLues == 1 && sommeil.delais.count == 3 })
        #expect(await SondeMaillageTests.sonder { sommeil.annulees == 1 }, "l'attente de la passe est annulee")
        #expect(Array(canal.envoyes.dropFirst(avant)) == ["etat\n", "voisins\n", "routes 0000 4\n", "routes 1A2B 5\n"])
        #expect(s.bilan?.complementaire == false && s.bilan?.routesReportees == 0)
        #expect(s.passeComplementaire == nil && sommeil.delais.last == .seconds(900))
        // L'ancienne attente est morte : la liberer ne lance rien.
        sommeil.liberer()
        try await Task.sleep(for: .milliseconds(80))
        #expect(canal.envoyes.count == avant + 4 && sommeil.delais.count == 3)
        await s.oublier()
    }

    /// Rafraichir quand le budget ne permet toujours pas de lire les routes reportees : la tournee manuelle n'outrepasse
    /// pas le budget, elle attend l'instant ou les routes du pont tiennent (la passe programmee est remplacee, son
    /// attente annulee) ; une seule attente vivante.
    @Test func uneSeulePasseProgrammee() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = Self.sonde(p, canal: Self.canalCharge(), horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.premiereTournee(s, sommeil: sommeil))
        let instant = Self.t0.addingTimeInterval(600)
        #expect(s.passeComplementaire == instant)
        h.avancer(100)
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder { sommeil.delais.count == 3 })
        #expect(s.bilan?.routesReportees == 1 && s.passeComplementaire == nil, "la passe laisse place a la tournee")
        #expect(s.tourneeDifferee == SondeMaillage.TourneeDifferee(instant: instant, complete: false))
        #expect(sommeil.delais.last == .seconds(500), "la nouvelle attente : 500 s")
        #expect(await SondeMaillageTests.sonder { sommeil.annulees == 1 }, "une seule attente vivante")
        await s.oublier()
    }

    /// Pas d'emballement : une passe qui ne lit aucune route (lancee avant que le budget le permette) n'en programme
    /// pas d'autre ; la tournee suivante est 15 minutes apres.
    @Test func pasDEmballement() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = Self.sonde(p, canal: Self.canalCharge(), horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.premiereTournee(s, sommeil: sommeil))
        // L'attente est liberee sans que l'horloge ait avance : le budget est encore epuise.
        sommeil.liberer()
        #expect(await SondeMaillageTests.sonder { sommeil.delais.count == 3 })
        #expect(s.bilan?.complementaire == true && s.bilan?.routesRouteursDemandees == 0 && s.bilan?.routesReportees == 1)
        #expect(s.passeComplementaire == nil && sommeil.delais.last == .seconds(900))
        await s.oublier()
    }

    /// Textes : la ligne du menu, le bilan d'une passe.
    @Test func textes() {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let passe = t + 600
        let heure = passe.formatted(date: .omitted, time: .shortened)
        #expect(TexteTournee.heure(passe) == heure)
        #expect(TexteTournee.menuPasse(passe, nom: "SONDE-01") == String(localized: "\("SONDE-01") : passe complémentaire à \(heure)"))
        guard case .bonjour(let b)? = MessageSonde.lire(Data(CanalRejoue.bonjourNomme.utf8)) else {
            Issue.record("bonjour illisible")
            return
        }
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t, avancement: nil, maintenant: t, passe: passe)
                == TexteTournee.menuPasse(passe, nom: "SONDE-01"))
        let tables = AvancementTournee(etape: .tables, fait: 1, total: 2)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t, avancement: tables, maintenant: t, passe: passe)
                == TexteTournee.menu(tables, nom: "SONDE-01"), "la tournee en cours d'abord")
        var bilan = BilanTournee()
        bilan.complementaire = true
        bilan.routesRouteursDemandees = 20
        bilan.routesRouteursLues = 20
        bilan.pages = 100
        #expect(FenetreReglages.texteBilan(bilan, duree: nil)
                == [String(localized: "passe complémentaire"), String(localized: "\(20)/\(20) routes"),
                    String(localized: "\(100) pages")].joined(separator: " · "))
    }
}

/// Budget de pages : journal gardé dans les preferences d'un lancement de l'app à l'autre, tournee differee quand la
/// fenetre est pleine (etape 3 quinquies). Horloge et attentes simulees, sonde rejouee, preferences en memoire.
@MainActor
@Suite("Journal des pages et tournees differees dans l'app", .timeLimit(.minutes(1)))
struct BudgetPagesAppTests {
    static let t0 = PasseComplementaireTests.t0

    static func t1970(_ secondes: TimeInterval) -> Double { t0.addingTimeInterval(secondes).timeIntervalSince1970 }

    /// La premiere tournee (10 s apres la connexion) de `s`, dont l'attente est liberee.
    static func lancer(_ s: SondeMaillage, sommeil: Sommeil) async -> Bool {
        guard await SondeMaillageTests.sonder({ sommeil.delais.first == .seconds(10) }) else { return false }
        sommeil.liberer()
        return true
    }

    static func tables(_ canal: CanalRejoue) -> [String] { canal.envoyes.filter { $0.hasPrefix("table") } }

    /// Le journal des pages va dans les preferences a chaque requete (instants et pages, compacts) avec les pages des
    /// tables ; une app relancee 2 minutes plus tard (preferences gardees, memoire neuve) le relit : sa premiere tournee,
    /// complete, attend que les pages sortent de la fenetre, sans rien envoyer. Rafraichir n'outrepasse pas l'attente
    /// (il la refait, sans table non plus) ; a l'instant calcule, la tournee part.
    @Test func journalRelu() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let s = PasseComplementaireTests.sonde(p, canal: PasseComplementaireTests.canalCharge(), horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await PasseComplementaireTests.premiereTournee(s, sommeil: sommeil))
        // table 0000 (548 pages), table 1A2B (2), routes 0000 (2) : tout date de t0.
        let t = Self.t1970(0)
        #expect(p.object(forKey: SondeMaillage.cleJournalPages) as? [Double] == [t, 548, t, 2, t, 2])
        #expect(p.object(forKey: SondeMaillage.clePagesTables) as? Int == 550)
        await s.oublier()
        #expect(p.object(forKey: SondeMaillage.cleJournalPages) as? [Double] == [t, 548, t, 2, t, 2],
                "le journal est celui de la sonde physique : il reste")
        #expect(p.object(forKey: SondeMaillage.clePagesTables) == nil)

        // Relancement 2 minutes plus tard.
        let h2 = HorlogeApp(Self.t0.addingTimeInterval(120))
        let sommeil2 = Sommeil()
        let canal2 = PasseComplementaireTests.canalCharge()
        let s2 = PasseComplementaireTests.sonde(p, canal: canal2, horloge: h2, sommeil: sommeil2)
        await s2.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.lancer(s2, sommeil: sommeil2))
        let instant = Self.t0.addingTimeInterval(600)
        let differee = SondeMaillage.TourneeDifferee(instant: instant, complete: true)
        #expect(await SondeMaillageTests.sonder { s2.tourneeDifferee == differee && sommeil2.delais == [.seconds(10), .seconds(480)] })
        let heure = instant.formatted(date: .omitted, time: .shortened)
        #expect(TexteTournee.tourneeDifferee(differee)
                == String(localized: "Tournée complète à \(heure) : la sonde a déjà beaucoup servi"))
        #expect(TexteTournee.menuDifferee(differee, nom: "SONDE-Z1") == String(localized: "\("SONDE-Z1") : tournée complète à \(heure)"))
        #expect(Self.tables(canal2).isEmpty && s2.derniereTournee == nil && !s2.tourneeEnCours)

        // Rafraichir ne passe pas devant : la meme attente, l'ancienne annulee.
        s2.rafraichir()
        #expect(await SondeMaillageTests.sonder { sommeil2.delais.count == 3 && sommeil2.annulees == 1 })
        #expect(sommeil2.delais.last == .seconds(480) && s2.tourneeDifferee == differee && Self.tables(canal2).isEmpty)

        // A l'instant calcule, la tournee part.
        h2.avancer(480)
        sommeil2.liberer()
        sommeil2.liberer()
        #expect(await SondeMaillageTests.sonder { s2.derniereTournee != nil && !s2.tourneeEnCours })
        #expect(s2.tourneeDifferee == nil && s2.bilan?.avecTables == true && s2.bilan?.lacune == nil)
        #expect(Self.tables(canal2).first == "table 0000 1\n")
        #expect(!canal2.envoyes.contains(where: SondeRejouee.interdite))
        await s2.oublier()
    }

    /// Le journal relu et les pages des dernieres tables estiment la tournee : 500 pages encore dans la fenetre (200 a
    /// t0+200, 300 a t0+100) et 450 pages de tables au dernier lancement : 472 pages de plus ne tiennent qu'une fois la
    /// fenetre videe (t0+800). Sans le total des tables, les 35 pages d'une table et du pont tiennent : elle part tout de
    /// suite.
    @Test func estimationDesTablesApresRelancement() async throws {
        // Avec le total des dernieres tables : on attend.
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set([Self.t1970(100), 300, Self.t1970(200), 200] as [Double], forKey: SondeMaillage.cleJournalPages)
        p.set(450, forKey: SondeMaillage.clePagesTables)
        // La sonde est deja retenue (comme apres un relancement) : la connexion n'oublie pas son releve.
        p.set(SondeMaillageTests.port.serie, forKey: SondeMaillage.cleSerie)
        let h = HorlogeApp(Self.t0.addingTimeInterval(250))
        let sommeil = Sommeil()
        let canal = PasseComplementaireTests.canalCharge()
        let s = PasseComplementaireTests.sonde(p, canal: canal, horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.lancer(s, sommeil: sommeil))
        let instant = Self.t0.addingTimeInterval(800)
        #expect(await SondeMaillageTests.sonder {
            s.tourneeDifferee == SondeMaillage.TourneeDifferee(instant: instant, complete: true)
                && sommeil.delais.last == .seconds(550)
        })
        #expect(Self.tables(canal).isEmpty)
        await s.oublier()

        // Sans ce total : une table et le pont (13 + 22 pages) tiennent dans les 50 pages restantes.
        let (q, domaineQ) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(q, domaineQ) }
        q.set([Self.t1970(100), 300, Self.t1970(200), 200] as [Double], forKey: SondeMaillage.cleJournalPages)
        let sommeil2 = Sommeil()
        let canal2 = PasseComplementaireTests.canalCharge()
        let s2 = PasseComplementaireTests.sonde(q, canal: canal2, horloge: h, sommeil: sommeil2)
        await s2.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await Self.lancer(s2, sommeil: sommeil2))
        #expect(await SondeMaillageTests.sonder { s2.derniereTournee != nil && !s2.tourneeEnCours })
        #expect(s2.tourneeDifferee == nil && !Self.tables(canal2).isEmpty)
        await s2.oublier()
    }

    /// Sans tables a lire, le budget n'exige que les routes du pont : Rafraichir juste apres une tournee complete (304
    /// pages) part tout de suite, alors qu'une tournee complete (302 pages de tables de plus) ne tiendrait pas.
    @Test func rafraichirSansTables() async throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        let h = HorlogeApp(Self.t0)
        let sommeil = Sommeil()
        let canal = CanalRejoue { l in
            let lignes = SondeRejouee.repondre(l)
            guard l.hasPrefix("table 0000") else { return lignes }
            return lignes.map { $0.replacingOccurrences(of: "\"pages\":2", with: "\"pages\":300") }
        }
        let s = PasseComplementaireTests.sonde(p, canal: canal, horloge: h, sommeil: sommeil)
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(await PasseComplementaireTests.premiereTournee(s, sommeil: sommeil))
        #expect(s.bilan?.avecTables == true && s.bilan?.routesReportees == 0 && sommeil.delais == [.seconds(10), .seconds(900)])
        s.rafraichir()
        #expect(await SondeMaillageTests.sonder {
            canal.envoyes.filter { $0.hasPrefix("routes 0000") }.count == 2 && !s.tourneeEnCours
        })
        #expect(s.tourneeDifferee == nil && s.bilan?.avecTables == false && Self.tables(canal).count == 2)
        await s.oublier()
    }

    /// Textes de la tournee differee : complete ou non, dans les Reglages et dans le menu (apres la tournee en cours et
    /// la passe programmee).
    @Test func textesDifferee() throws {
        let t = Date(timeIntervalSince1970: 1_790_000_000)
        let instant = t + 600
        let heure = instant.formatted(date: .omitted, time: .shortened)
        let complete = SondeMaillage.TourneeDifferee(instant: instant, complete: true)
        let simple = SondeMaillage.TourneeDifferee(instant: instant, complete: false)
        #expect(TexteTournee.tourneeDifferee(simple) == String(localized: "Tournée à \(heure) : la sonde a déjà beaucoup servi"))
        #expect(TexteTournee.menuDifferee(simple, nom: "SONDE-01") == String(localized: "\("SONDE-01") : tournée à \(heure)"))
        guard case .bonjour(let b)? = MessageSonde.lire(Data(CanalRejoue.bonjourNomme.utf8)) else {
            Issue.record("bonjour illisible")
            return
        }
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t, avancement: nil, maintenant: t,
                                     differee: complete) == TexteTournee.menuDifferee(complete, nom: "SONDE-01"))
        let tables = AvancementTournee(etape: .tables, fait: 1, total: 2)
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t, avancement: tables, maintenant: t,
                                     differee: complete) == TexteTournee.menu(tables, nom: "SONDE-01"))
        #expect(MenuBarre.ligneSonde(.connectee(b), nom: "SONDE-01", derniere: t, avancement: nil, maintenant: t,
                                     passe: instant, differee: complete) == TexteTournee.menuPasse(instant, nom: "SONDE-01"))
    }

    /// Sans sonde active (mode demo, tests sans preferences) : ni lecture ni ecriture des preferences.
    @Test func sansSondeActiveRienDeLuNiEcrit() throws {
        let (p, domaine) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, domaine) }
        p.set([Self.t1970(100), 300] as [Double], forKey: SondeMaillage.cleJournalPages)
        let avant = p.dictionaryRepresentation().keys.sorted()
        let s = SondeMaillage(preferences: p, actif: false)
        s.portsChanges([])
        #expect(p.dictionaryRepresentation().keys.sorted() == avant && s.tourneeDifferee == nil)
    }
}
