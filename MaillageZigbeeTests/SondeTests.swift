import Foundation
import MaillageCoeur
import Observation
import Synchronization
import Testing
@testable import MaillageZigbee

/// Canal rejoue : chaque commande envoyee produit les lignes que `repondre` donne.
final class CanalRejoue: CanalSonde {
    private struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var envoyes: [String] = []
    }

    private let etat = Mutex(Etat())
    let repondre: @Sendable (String) -> [String]
    /// Fin du flux differee apres `fermer`, comme la liaison serie qui ferme le port sur sa file :
    /// d'ici la, les commandes ont encore leurs reponses.
    let fermetureDifferee: Duration?

    init(fermetureDifferee: Duration? = nil, repondre: @escaping @Sendable (String) -> [String]) {
        self.fermetureDifferee = fermetureDifferee
        self.repondre = repondre
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        return flux
    }

    func envoyer(_ ligne: String) {
        let reponses = repondre(ligne)
        etat.withLock { e in
            e.envoyes.append(ligne)
            for r in reponses { e.suite?.yield(Data(r.utf8)) }
        }
    }

    /// Lignes spontanees de la sonde.
    func emettre(_ lignes: [String]) {
        etat.withLock { e in
            for r in lignes { e.suite?.yield(Data(r.utf8)) }
        }
    }

    func fermer() {
        guard let d = fermetureDifferee else {
            etat.withLock { $0.suite?.finish() }
            return
        }
        Task { [self] in
            try? await Task.sleep(for: d)
            etat.withLock { $0.suite?.finish() }
        }
    }

    var envoyes: [String] { etat.withLock { $0.envoyes } }

    static let bonjour = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":null,"ieee":"A000000000000001","membre":false,"role":null,"suspendue":false}"#
    /// bonjour d'une sonde nommee (valeurs inventees).
    static let bonjourNomme = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.1","nom":"SONDE-01","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false}"#
    /// Sonde hors adhesion : elle cherche un reseau.
    static let etatDetache = #"{"v":1,"t":"etat","membre":false,"recherche":true,"court":null,"ieee":"A000000000000001","role":null,"parent":null,"pan":null,"epid":null,"canal":null,"suspendue":false,"pile":"1.6.8"}"#
    /// Sonde membre (valeurs inventees) : sous le routeur 1A2B, canal 25.
    static let etatAttache = #"{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":{"court":"1A2B","ieee":"A000000000000002","lqi":180,"rssi":-71},"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":false,"pile":"1.6.8"}"#

    /// La sonde minimale : `bonjour` et `etat` (membre) ; rien d'autre a l'etape 1 du prototype.
    static func sondeMinimale(_ ligne: String) -> [String] {
        switch ligne {
        case "bonjour\n": [bonjour]
        case "etat\n": [etatAttache]
        default: []
        }
    }
}

/// Preferences des tests de la sonde et de la fenetre, en memoire : chaque lecture et chaque ecriture passent par un dictionnaire, sans
/// jamais toucher le domaine sur le disque. Avec `UserDefaults(suiteName:)`, `removePersistentDomain` laissait un
/// fichier vide par test dans `Library/Preferences` du conteneur de l'app (des centaines).
final class PreferencesMemoire: UserDefaults, @unchecked Sendable {
    /// Sous `verrou` (des valeurs `Any`, que `Mutex` refuse de partager).
    private var valeurs: [String: Any] = [:]
    private let verrou = NSLock()
    let domaine: String

    init?(domaine: String) {
        self.domaine = domaine
        super.init(suiteName: domaine)
    }

    override func object(forKey cle: String) -> Any? { verrou.withLock { valeurs[cle] } }
    /// Chaque changement est annonce par KVO, comme le fait `UserDefaults` : `@AppStorage` (les tests de la fenetre)
    /// le suit ainsi.
    override func set(_ valeur: Any?, forKey cle: String) {
        willChangeValue(forKey: cle)
        verrou.withLock { valeurs[cle] = valeur }
        didChangeValue(forKey: cle)
    }

    override func removeObject(forKey cle: String) { set(nil as Any?, forKey: cle) }
    override func string(forKey cle: String) -> String? { object(forKey: cle) as? String }
    override func bool(forKey cle: String) -> Bool { object(forKey: cle) as? Bool ?? false }
    override func integer(forKey cle: String) -> Int { object(forKey: cle) as? Int ?? 0 }
    override func double(forKey cle: String) -> Double { object(forKey: cle) as? Double ?? 0 }
    override func data(forKey cle: String) -> Data? { object(forKey: cle) as? Data }
    override func set(_ valeur: Bool, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func set(_ valeur: Int, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func set(_ valeur: Double, forKey cle: String) { set(valeur as Any, forKey: cle) }
    override func dictionaryRepresentation() -> [String: Any] { verrou.withLock { valeurs } }
    override func persistentDomain(forName nom: String) -> [String: Any]? {
        nom == domaine ? dictionaryRepresentation() : nil
    }
    override func removePersistentDomain(forName nom: String) {
        guard nom == domaine else { return }
        verrou.withLock { valeurs = [:] }
    }
}

/// Canal d'un port qui ne s'ouvre pas (tenu par une autre app, retire entre-temps).
struct CanalEnPanne: CanalSonde {
    struct Panne: Error {}

    func ouvrir() throws -> AsyncStream<Data> { throw Panne() }
    func envoyer(_ ligne: String) {}
    func fermer() {}
}

/// Horloge des tests, avancee a la main (ou par un canal, pendant une tournee).
final class HorlogeFactice: Sendable {
    private let t: Mutex<Date>

    init(_ debut: Date) {
        t = Mutex(debut)
    }

    var maintenant: Date { t.withLock { $0 } }

    func avancer(_ secondes: TimeInterval) {
        t.withLock { $0 += secondes }
    }
}

/// Journal commun a des canaux de test ; on peut y attendre une ligne.
final class JournalCanaux: Sendable {
    private struct Etat {
        var lignes: [String] = []
        var attentes: [(ligne: String, suite: CheckedContinuation<Void, Never>)] = []
    }

    private let etat = Mutex(Etat())

    func noter(_ ligne: String) {
        let prets = etat.withLock { e in
            e.lignes.append(ligne)
            let prets = e.attentes.filter { $0.ligne == ligne }.map(\.suite)
            e.attentes.removeAll { $0.ligne == ligne }
            return prets
        }
        for p in prets { p.resume() }
    }

    /// Rend la main une fois `ligne` notee (tout de suite si elle l'est deja).
    func attendre(_ ligne: String) async {
        await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
            let deja = etat.withLock { e in
                guard !e.lignes.contains(ligne) else { return true }
                e.attentes.append((ligne, suite))
                return false
            }
            if deja { suite.resume() }
        }
    }

    var lignes: [String] { etat.withLock { $0.lignes } }

    /// Ouvertures, fermetures et fins de flux, sans les commandes.
    var cycle: [String] {
        lignes.filter { l in ["ouvrir", "fermer", "fin"].contains(l.split(separator: " ").first.map(String.init)) }
    }
}

/// Canal de test de la connexion : note au journal ses ouvertures, sa fermeture,
/// la fin de son flux (le port vraiment ferme) et les commandes recues. Il peut
/// retenir la reponse a `bonjour`, et finir son flux en differe, comme la liaison
/// serie qui ferme le port sur sa file.
final class CanalTemoin: CanalSonde {
    let nom: String
    let journal: JournalCanaux
    let retenirBonjour: Bool
    let fermetureDifferee: Duration?
    private let suite = Mutex<AsyncStream<Data>.Continuation?>(nil)

    init(_ nom: String, journal: JournalCanaux, retenirBonjour: Bool = false, fermetureDifferee: Duration? = nil) {
        self.nom = nom
        self.journal = journal
        self.retenirBonjour = retenirBonjour
        self.fermetureDifferee = fermetureDifferee
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (flux, s) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        suite.withLock { $0 = s }
        journal.noter("ouvrir \(nom)")
        return flux
    }

    func envoyer(_ ligne: String) {
        let commande = ligne.trimmingCharacters(in: .newlines)
        journal.noter("\(commande) \(nom)")
        switch commande {
        case "bonjour" where !retenirBonjour: repondre(CanalRejoue.bonjour)
        case "etat": repondre(CanalRejoue.etatDetache)
        default: break
        }
    }

    /// La reponse retenue a `bonjour` arrive enfin.
    func libererBonjour() {
        repondre(CanalRejoue.bonjour)
    }

    private func repondre(_ l: String) {
        suite.withLock { _ = $0?.yield(Data(l.utf8)) }
    }

    /// Une seule fermeture effective ; rien a fermer si le canal n'a pas ete ouvert.
    func fermer() {
        guard let s = suite.withLock({ s in
            defer { s = nil }
            return s
        }) else { return }
        journal.noter("fermer \(nom)")
        guard let d = fermetureDifferee else {
            journal.noter("fin \(nom)")
            s.finish()
            return
        }
        let journal = journal, nom = nom
        Task {
            try? await Task.sleep(for: d)
            journal.noter("fin \(nom)")
            s.finish()
        }
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@Suite("Sonde USB : commandes et reponses", .timeLimit(.minutes(1)))
struct SondeUSBTests {
    /// bonjour et etat, dans l'ordre.
    @Test func bonjourEtat() async throws {
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjour] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        let b = try await s.bonjour()
        #expect(b.estSonde && b.version == "1.0.0")
        let e = try await s.etat()
        #expect(!e.membre && e.recherche == true && e.parent == nil)
        #expect(canal.envoyes == ["bonjour\n", "etat\n"])
    }

    /// Sans reponse de la sonde : `delai` apres le delai donne et la marge.
    @Test func delai() async throws {
        let s = SondeUSB(canal: CanalRejoue { _ in [] }, delaiCommande: .milliseconds(50))
        try await s.demarrer {}
        await #expect(throws: SondeUSB.Erreur.sansReponse("bonjour")) { try await s.bonjour() }
        await #expect(throws: SondeUSB.Erreur.sansReponse("etat")) { try await s.etat() }
    }

    /// Liaison fermee : les attentes sont liberees, les commandes suivantes refusees.
    @Test func fermeture() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        let fermee = Mutex(false)
        try await s.demarrer { fermee.withLock { $0 = true } }
        let requete = Task { try await s.bonjour() }
        try await Task.sleep(for: .milliseconds(50))
        canal.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await requete.value }
        await #expect(throws: SondeUSB.Erreur.fermee) { _ = try await s.etat() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(fermee.withLock { $0 })
    }

    /// La sonde n'a pas le verrou de la pile Zigbee (`occupee`) : `etat` echoue tout de suite en `occupee`, sans
    /// attendre le delai, et le message le dit.
    @Test(.timeLimit(.minutes(1)), arguments: ["etat"])
    func commandeOccupee(_ commande: String) async throws {
        let s = SondeUSB(canal: CanalRejoue { l in
            l == commande + "\n" ? [#"{"v":1,"t":"\#(commande)","erreur":"occupee"}"#] : []
        })
        try await s.demarrer {}
        let debut = ContinuousClock.now
        await #expect(throws: SondeUSB.Erreur.occupee(commande)) {
            _ = try await s.etat()
        }
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
        #expect(SondeUSB.Erreur.occupee(commande).localizedDescription
                == String(localized: "la sonde est occupée et n'a pas répondu à « \(commande) »"))
    }

    /// La sonde refuse `etat` pour une autre raison que `occupee` : l'erreur est `refusee`, avec la raison, tout de
    /// suite (et non `occupee`, ni `sansReponse`).
    @Test(.timeLimit(.minutes(1)), arguments: ["etat"])
    func commandeRefusee(_ commande: String) async throws {
        let s = SondeUSB(canal: CanalRejoue { l in
            l == commande + "\n" ? [#"{"v":1,"t":"\#(commande)","erreur":"pas de pile"}"#] : []
        })
        try await s.demarrer {}
        let debut = ContinuousClock.now
        await #expect(throws: SondeUSB.Erreur.refusee("pas de pile")) {
            _ = try await s.etat()
        }
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
    }

    /// Un bonjour non demande : la sonde vient de redemarrer.
    @Test func bonjourSpontane() async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal)
        try await s.demarrer {}
        canal.emettre([CanalRejoue.bonjour])
        try await Task.sleep(for: .milliseconds(50))
        #expect(await s.bonjourSpontane?.version == "1.0.0")
    }

    /// fermer rend la main une fois le flux fini (le port vraiment ferme), meme
    /// quand le canal le finit en differe.
    @Test func fermerAttendLaFinDuFlux() async throws {
        let journal = JournalCanaux()
        let s = SondeUSB(canal: CanalTemoin("1", journal: journal, fermetureDifferee: .milliseconds(50)))
        try await s.demarrer {}
        await s.fermer()
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1"])
        #expect(await s.fermee)
    }

    /// Fermee avant d'avoir demarre (connexion abandonnee) : le canal ne s'ouvre plus.
    @Test func fermeeAvantDeDemarrer() async throws {
        let journal = JournalCanaux()
        let s = SondeUSB(canal: CanalTemoin("1", journal: journal))
        await s.fermer()
        await #expect(throws: SondeUSB.Erreur.fermee) { try await s.demarrer {} }
        #expect(journal.cycle.isEmpty)
    }

    /// L'echeance d'une requete deja servie n'expire pas la suivante : la premiere est servie
    /// tard (a 0,45 s, delai de 0,8 s), la seconde part aussitot et sa reponse arrive a 0,9 s,
    /// apres l'echeance de la premiere (0,8 s) et avant la sienne (1,25 s).
    @Test(.timeLimit(.minutes(1)), arguments: ["bonjour", "etat"])
    func echeanceDUneRequeteServie(_ commande: String) async throws {
        let canal = CanalRejoue { _ in [] }
        let s = SondeUSB(canal: canal, delaiCommande: .milliseconds(800))
        try await s.demarrer {}
        let reponse = commande == "bonjour" ? CanalRejoue.bonjour : CanalRejoue.etatDetache
        @Sendable func requete() async throws {
            if commande == "bonjour" { _ = try await s.bonjour() } else { _ = try await s.etat() }
        }
        let premiere = Task { try await requete() }
        try await Task.sleep(for: .milliseconds(450))
        canal.emettre([reponse])
        try await premiere.value
        let seconde = Task { try await requete() }
        try await Task.sleep(for: .milliseconds(450))
        canal.emettre([reponse])
        try await seconde.value
        #expect(canal.envoyes == [commande + "\n", commande + "\n"])
    }
}

/// Chaque test borne a une minute : une attente sans fin echoue au lieu de bloquer la suite.
@MainActor
@Suite("Sonde dans l'app : port retenu, refus, fraicheur du maillage", .timeLimit(.minutes(1)))
struct SondeMaillageTests {
    /// Des preferences de test, en memoire seulement (`PreferencesMemoire`) : aucun fichier dans le conteneur.
    static func preferences() throws -> (UserDefaults, String) {
        let domaine = "fr.djoko.maillage.zigbee.tests.sonde.\(UUID().uuidString)"
        return (try #require(PreferencesMemoire(domaine: domaine)), domaine)
    }

    /// Fin d'un test : son domaine de preferences vide (`removePersistentDomain`).
    static func nettoyer(_ p: UserDefaults, _ domaine: String) {
        p.removePersistentDomain(forName: domaine)
    }

    static let port = PortUSB(chemin: "/dev/cu.usbmodem11301", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                              produit: "USB JTAG/serial debug unit")

    /// Attend, sans delai, que `condition` soit vraie : elle est relue a chaque
    /// changement observe de ce qu'elle lit.
    static func attendre(_ condition: () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { (suite: CheckedContinuation<Void, Never>) in
                withObservationTracking { _ = condition() } onChange: { suite.resume() }
            }
        }
    }

    /// Attend, 5 s au plus, que `condition` soit vraie, en la relisant toutes les 10 ms ; rend sa derniere valeur.
    static func sonder(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<500 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    static func connectee(_ s: SondeMaillage) -> Bool {
        if case .connectee = s.etat { true } else { false }
    }

    /// Un port qui repond en sonde est retenu (numero de serie USB) ; oublier le retire.
    @Test func retenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let canal = CanalRejoue { l in l == "bonjour\n" ? [CanalRejoue.bonjour] : l == "etat\n" ? [CanalRejoue.etatDetache] : [] }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(Self.port, choisi: true)
        guard case .connectee(let b) = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(b.version == "1.0.0")
        #expect(p.string(forKey: SondeMaillage.cleSerie) == "A0:00:00:00:00:01")
        await s.oublier()
        #expect(s.etat == .sansSonde)
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
    }

    /// Un autre C6 (le pont Halo) n'est pas une sonde : refuse, rien de retenu.
    @Test func refusee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let halo = #"{"v":1,"t":"bonjour","produit":"pont-halo","version":"0.4.0","mac":null,"appairee":true,"code":null,"qr":null}"#
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { _ in [halo] } })
        await s.connecter(Self.port, choisi: true)
        guard case .refusee(let m) = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(m.contains("pont-halo"))
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
    }

    /// Aucune sonde retenue : un C6 branche est liste pour les Reglages, jamais ouvert
    /// (spec, section 3 : aucun port qu'on ne lui a pas designe).
    @Test func sansSondeRetenueAucunPortOuvert() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalRejoue { _ in [CanalRejoue.bonjour] }
        })
        s.portsChanges([Self.port])
        // Une connexion lancee passerait avant la suite du test (meme acteur, dans l'ordre).
        await Task.yield()
        #expect(s.ports == [Self.port])
        #expect(canaux == 0)
        #expect(s.etat == .sansSonde)
    }

    /// La sonde retenue (serie S) n'est pas branchee, un autre C6 l'est (serie H, le
    /// pont Halo par exemple) : il n'est jamais ouvert, la sonde est absente.
    @Test func autreC6JamaisOuvert() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: "USB JTAG/serial debug unit")
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalRejoue { _ in [CanalRejoue.bonjour] }
        })
        s.portsChanges([autre])
        await Task.yield()
        #expect(s.ports == [autre])
        #expect(canaux == 0)
        #expect(s.etat == .absente)
    }

    /// La sonde retenue absente, un autre port choisi dans les Reglages : un changement de ports
    /// pendant sa connexion (evenement IOKit) ne l'annule pas ; le port choisi est retenu.
    @Test(.timeLimit(.minutes(1))) func choixDUnAutrePortSansLaSondeRetenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let journal = JournalCanaux()
        let canal = CanalTemoin("2", journal: journal, retenirBonjour: true)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        s.portsChanges([autre])
        #expect(s.etat == .absente)
        s.choisir(autre)
        await journal.attendre("bonjour 2")
        s.portsChanges([autre])
        try #require(s.etat == .connexion, "choix annule : \(s.etat)")
        canal.libererBonjour()
        await Self.attendre { Self.connectee(s) }
        #expect(s.serie == "B0:00:00:00:00:02")
        #expect(journal.cycle == ["ouvrir 2"])
        await s.oublier()
    }

    /// La sonde retenue debranchee : absente.
    @Test func debranchee() throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { _ in [] } })
        s.portsChanges([])
        #expect(s.etat == .absente)
    }

    /// « Oublier » pendant la verification du port (bonjour encore sans reponse) :
    /// la connexion en cours est abandonnee et son port ferme ; rien n'est retenu.
    @Test func oublierPendantLaConnexion() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let journal = JournalCanaux()
        let canal = CanalTemoin("1", journal: journal, retenirBonjour: true)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let connexion = Task { await s.connecter(Self.port, choisi: true) }
        await journal.attendre("bonjour 1")
        await s.oublier()
        // La reponse arrive apres coup : elle ne change plus rien.
        canal.libererBonjour()
        await connexion.value
        #expect(s.etat == .sansSonde)
        #expect(s.serie == nil)
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1"])
    }

    /// Deux changements de ports de suite, la sonde retenue branchee : une seule connexion.
    @Test func deuxChangementsDePorts() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalTemoin("\(canaux)", journal: journal)
        })
        s.portsChanges([Self.port])
        s.portsChanges([Self.port])
        await Self.attendre { Self.connectee(s) }
        #expect(canaux == 1)
        #expect(journal.cycle == ["ouvrir 1"])
        await s.oublier()
    }

    /// Choisir le port de la sonde deja connectee : rien n'est ferme ni rouvert.
    @Test func choisirLePortConnecte() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalTemoin("\(canaux)", journal: journal)
        })
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        s.choisir(Self.port)
        // Une connexion lancee par `choisir` passerait avant la suite du test
        // (meme acteur, dans l'ordre) et creerait son canal.
        await Task.yield()
        #expect(canaux == 1)
        #expect(Self.connectee(s))
        #expect(journal.cycle == ["ouvrir 1"])
        await s.oublier()
    }

    /// Reconnexion : l'ancienne liaison est vraiment fermee (fin de son flux)
    /// avant que la nouvelle ne s'ouvre ; sinon le port serait encore tenu.
    @Test func reconnexion() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            // Fin du flux en differe, comme la liaison serie qui ferme le port sur sa file.
            return CanalTemoin("\(canaux)", journal: journal, fermetureDifferee: .milliseconds(50))
        })
        await s.connecter(Self.port, choisi: true)
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        #expect(journal.cycle == ["ouvrir 1", "fermer 1", "fin 1", "ouvrir 2"])
        await s.oublier()
    }

    /// Connexion automatique en echec (sonde qui demarre en plus de 3 s, port pas encore pret) :
    /// un nouvel essai quelques secondes apres, sans attendre l'evenement USB suivant.
    @Test(.timeLimit(.minutes(1))) func nouvelEssaiApresUneConnexionAutomatiqueEnEchec() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ -> any CanalSonde in
            canaux += 1
            return canaux == 1 ? CanalEnPanne() : CanalRejoue { CanalRejoue.sondeMinimale($0) }
        }, delaiNouvelEssai: .milliseconds(50))
        // Un seul evenement USB : le second canal vient du nouvel essai.
        s.portsChanges([Self.port])
        #expect(await Self.sonder { Self.connectee(s) }, "nouvel essai : \(s.etat)")
        #expect(canaux == 2)
        await s.oublier()
    }

    /// Un seul nouvel essai : en echec a son tour, la sonde reste en erreur jusqu'a l'evenement
    /// USB suivant. Un port choisi dans les Reglages, puis refuse, n'est pas essaye de nouveau.
    @Test(.timeLimit(.minutes(1))) func unSeulNouvelEssaiEtAucunPourUnChoix() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalEnPanne()
        }, delaiNouvelEssai: .milliseconds(20))
        s.portsChanges([Self.port])
        #expect(await Self.sonder { canaux == 2 }, "nouvel essai")
        try await Task.sleep(for: .milliseconds(200))
        #expect(canaux == 2, "un seul")
        guard case .erreur = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        await s.connecter(Self.port, choisi: true)
        guard case .refusee = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(canaux == 3, "aucun pour un port choisi")
        await s.oublier()
    }

    /// Le nouvel essai planifie est perime si la sonde est debranchee, oubliee, ou si un autre port
    /// est choisi pendant son attente : il n'ouvre rien (aucun port qu'on ne lui a pas designe).
    @Test(.timeLimit(.minutes(1)), arguments: ["debranchee", "oubliee", "autre port choisi"])
    func nouvelEssaiPerime(_ cas: String) async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        let journal = JournalCanaux()
        var ouverts: [String] = []
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { chemin -> any CanalSonde in
            ouverts.append(chemin)
            return chemin == autre.chemin ? CanalTemoin("autre", journal: journal, retenirBonjour: true) : CanalEnPanne()
        }, delaiNouvelEssai: .milliseconds(50))
        // Connexion automatique en echec : a son retour, le nouvel essai est planifie, et le
        // changement suit dans le meme tour de l'acteur principal, avant qu'il ne parte.
        await s.connecter(Self.port, choisi: false)
        guard case .erreur = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        switch cas {
        case "debranchee": s.portsChanges([])
        case "oubliee": await s.oublier()
        default: s.choisir(autre)
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(ouverts.filter { $0 == Self.port.chemin }.count == 1, "\(cas) : \(ouverts)")
        switch cas {
        case "debranchee": #expect(s.etat == .absente)
        case "oubliee": #expect(s.etat == .sansSonde)
        default: #expect(s.etat == .connexion, "le choix continue")
        }
        await s.oublier()
    }

    /// En demo et sous tests : rien de lu.
    @Test func inactive() throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        let s = SondeMaillage(preferences: p, actif: false)
        #expect(s.serie == nil)
        #expect(s.nom == nil)
    }

    /// Nom donne par la carte (firmware 1.0.1) : retenu a cote du numero de serie, relu au
    /// lancement ; oublier la sonde l'oublie aussi.
    @Test func nomRetenu() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        #expect(s.nom == nil)
        await s.connecter(Self.port, choisi: true)
        #expect(s.nom == "SONDE-01")
        #expect(p.string(forKey: SondeMaillage.cleNom) == "SONDE-01")
        #expect(SondeMaillage(preferences: p, actif: true).nom == "SONDE-01", "relu au lancement")
        await s.oublier()
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
    }

    /// Port sans numero de serie : la sonde n'est pas retenue, son nom non plus (il resterait
    /// affiche sans sonde choisie apres un relancement).
    @Test func nomSansSerieNonRetenu() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let sansSerie = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: nil, produit: nil)
        let canal = CanalRejoue { l in
            l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(sansSerie, choisi: true)
        #expect(Self.connectee(s))
        #expect(s.serie == nil)
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
        await s.oublier()
    }

    /// Le nom de la sonde retenue va a l'etat qui la concerne (connectee, absente) ; pas au
    /// refus d'un autre port choisi, ni a la connexion d'un autre port, ni sans sonde.
    @Test(.timeLimit(.minutes(1))) func nomSeulementPourLaSondeRetenue() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let halo = #"{"v":1,"t":"bonjour","produit":"pont-halo","version":"0.4.0","mac":null,"appairee":true,"code":null,"qr":null}"#
        let pont = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                           produit: nil)
        let troisieme = PortUSB(chemin: "/dev/cu.usbmodemFACTICE03", vid: 0x303A, pid: 0x1001, serie: "C0:00:00:00:00:03",
                                produit: nil)
        let journal = JournalCanaux()
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { chemin in
            if chemin == Self.port.chemin {
                return CanalRejoue { l in
                    l == "bonjour\n" ? [CanalRejoue.bonjourNomme] : l == "etat\n" ? [CanalRejoue.etatDetache] : []
                }
            }
            if chemin == pont.chemin { return CanalRejoue { _ in [halo] } }
            return CanalTemoin("3", journal: journal, retenirBonjour: true)
        })
        #expect(s.nomEtat == nil, "aucune sonde")
        await s.connecter(Self.port, choisi: true)
        #expect(s.nomEtat == "SONDE-01")
        await s.connecter(pont, choisi: true)
        guard case .refusee = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(s.nom == "SONDE-01", "la sonde reste retenue")
        #expect(s.nomEtat == nil, "refus d'un autre port")
        s.portsChanges([pont])
        #expect(s.etat == .absente)
        #expect(s.nomEtat == "SONDE-01", "la sonde retenue est absente")
        s.choisir(troisieme)
        await journal.attendre("bonjour 3")
        #expect(s.etat == .connexion)
        #expect(s.nomEtat == nil, "connexion d'un autre port")
        await s.oublier()
        #expect(s.nomEtat == nil)
    }

    /// La sonde retenue elle-meme, reprise au branchement (sans choix dans les Reglages) : son
    /// nom aussi pendant sa connexion, et apres une erreur de son port.
    @Test(.timeLimit(.minutes(1))) func nomDeLaSondeRetenueEnConnexionEtEnErreur() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        let journal = JournalCanaux()
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ -> any CanalSonde in
            canaux += 1
            // D'abord un bonjour qui tarde (connexion en cours), puis un port qui ne s'ouvre pas.
            return canaux == 1 ? CanalTemoin("1", journal: journal, retenirBonjour: true) : CanalEnPanne()
        })
        s.portsChanges([Self.port])
        await journal.attendre("bonjour 1")
        #expect(s.etat == .connexion)
        #expect(s.nomEtat == "SONDE-01", "connexion de la sonde retenue")
        s.portsChanges([])
        s.portsChanges([Self.port])
        await Self.attendre { if case .erreur = s.etat { true } else { false } }
        #expect(s.nomEtat == "SONDE-01", "erreur de la sonde retenue")
        await s.oublier()
    }

    /// Le nom suit chaque bonjour : un firmware sans nom (1.0.0) l'efface.
    @Test func nomSuitLeBonjour() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            let b = canaux == 1 ? CanalRejoue.bonjourNomme : CanalRejoue.bonjour
            return CanalRejoue { l in l == "bonjour\n" ? [b] : l == "etat\n" ? [CanalRejoue.etatDetache] : [] }
        })
        await s.connecter(Self.port, choisi: true)
        #expect(s.nom == "SONDE-01")
        await s.connecter(Self.port, choisi: true)
        #expect(Self.connectee(s))
        #expect(s.nom == nil)
        #expect(p.string(forKey: SondeMaillage.cleNom) == nil)
        await s.oublier()
    }

    /// Oublier la sonde efface son releve : son etat, et la derniere erreur (`etat` sans reponse au rafraichissement).
    @Test(.timeLimit(.minutes(1))) func oublierEffaceLeReleve() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let muette = Mutex(false)
        let canal = CanalRejoue { l in
            l == "etat\n" && muette.withLock({ $0 }) ? [] : CanalRejoue.sondeMinimale(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        await s.connecter(Self.port, choisi: true)
        #expect(s.etatSonde?.membre == true && s.etatSonde?.canal == 25, "l'etat, lu a la connexion")
        muette.withLock { $0 = true }
        s.rafraichir()
        await Self.attendre { s.erreurTournee != nil }
        #expect(s.etatSonde != nil, "l'etat d'avant reste")
        await s.oublier()
        #expect(s.etatSonde == nil)
        #expect(s.erreurTournee == nil)
    }

    /// Un autre port choisi retient une autre sonde : le releve de la precedente (etat, erreur) ne s'affiche pas pour
    /// elle.
    @Test(.timeLimit(.minutes(1))) func autreSondeSansLeReleveDeLaPrecedente() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let autre = PortUSB(chemin: "/dev/cu.usbmodemFACTICE02", vid: 0x303A, pid: 0x1001, serie: "B0:00:00:00:00:02",
                            produit: nil)
        // Seconde sonde : `bonjour` seulement ; son `etat` reste sans reponse.
        let seconde = CanalRejoue { l in l == "bonjour\n" ? [CanalRejoue.bonjour] : [] }
        let premiere = CanalRejoue { CanalRejoue.sondeMinimale($0) }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { $0 == autre.chemin ? seconde : premiere })
        await s.connecter(Self.port, choisi: true)
        #expect(s.etatSonde != nil)
        let connexion = Task { await s.connecter(autre, choisi: true) }
        await Self.attendre { s.serie == autre.serie }
        #expect(s.etatSonde == nil)
        #expect(s.erreurTournee == nil)
        await connexion.value
        await s.oublier()
    }

    /// « Oublier » pendant que la reponse a `etat` est en route : arrivee apres l'oubli (avant la fin du flux), elle ne
    /// remet pas l'etat de la sonde.
    @Test(.timeLimit(.minutes(1))) func etatRecuApresLOubli() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let journal = JournalCanaux()
        // `etat` ne repond que quand le test le rend.
        let canal = CanalRejoue { l in
            journal.noter(l.trimmingCharacters(in: .newlines))
            return l == "etat\n" ? [] : CanalRejoue.sondeMinimale(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let connexion = Task { await s.connecter(Self.port, choisi: true) }
        await journal.attendre("etat")
        await s.oublier()
        canal.emettre([CanalRejoue.etatAttache])
        await connexion.value
        #expect(s.etatSonde == nil)
    }

    /// `etat` refuse a la connexion (sonde occupee) : l'erreur le dit tout de suite, au lieu de « la sonde ne repond
    /// pas » au bout de l'echeance.
    @Test(.timeLimit(.minutes(1))) func etatOccupee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let canal = CanalRejoue { l in
            l == "etat\n" ? [#"{"v":1,"t":"etat","erreur":"occupee"}"#] : CanalRejoue.sondeMinimale(l)
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal })
        let debut = ContinuousClock.now
        await s.connecter(Self.port, choisi: true)
        #expect(s.erreurTournee == SondeUSB.Erreur.occupee("etat").localizedDescription)
        #expect(ContinuousClock.now - debut < SondeUSB.delaiCommandeUSB)
        await s.oublier()
    }


    /// La sonde de Maillage Thread (`sonde-maillage`) n'est pas une sonde Zigbee : refusee, rien de retenu.
    @Test func sondeThreadRefusee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let thread = #"{"v":1,"t":"bonjour","produit":"sonde-maillage","version":"1.1.0","mac":"A00000000001","appairee":true}"#
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { _ in [thread] } })
        await s.connecter(Self.port, choisi: true)
        guard case .refusee(let m) = s.etat else {
            Issue.record("etat \(s.etat)")
            return
        }
        #expect(m.contains("sonde-maillage"))
        #expect(p.string(forKey: SondeMaillage.cleSerie) == nil)
    }

    /// Sans sonde connectee, « Rafraichir » ne lance rien et n'ouvre rien.
    @Test(.timeLimit(.minutes(1))) func rafraichirSansSonde() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        var canaux = 0
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in
            canaux += 1
            return CanalRejoue { CanalRejoue.sondeMinimale($0) }
        })
        #expect(!s.tourneeAuRafraichir)
        s.rafraichir()
        await Task.yield()
        #expect(canaux == 0 && !s.tourneeEnCours && s.debutTournee == nil)
    }

    /// Les points d'accroche de la tournee : le debut (sonde connectee seulement), l'avancement, la fin avec son
    /// maillage, recu a l'heure de la fin, entre les signaux de debut et de fin ; l'oubli arrete une tournee en cours.
    @Test(.timeLimit(.minutes(1))) func pointsDAccrocheDeLaTournee() async throws {
        let (p, domaine) = try Self.preferences()
        defer { Self.nettoyer(p, domaine) }
        let horloge = HorlogeFactice(MaillageDemo.debut)
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } },
                              horloge: { horloge.maintenant })
        var suite: [String] = []
        var recus: [Date] = []
        s.surTournee = { suite.append($0 ? "debut" : "fin") }
        s.surMaillage = { _, recu in
            suite.append("maillage")
            recus.append(recu)
        }
        s.debuterTournee()
        #expect(!s.tourneeEnCours, "sans sonde connectee : pas de tournee")
        await s.connecter(Self.port, choisi: true)
        s.debuterTournee()
        #expect(s.tourneeEnCours && s.debutTournee == MaillageDemo.debut)
        s.avancer(AvancementTournee(etape: .routes, fait: 1, total: 2))
        #expect(s.avancement == AvancementTournee(etape: .routes, fait: 1, total: 2))
        horloge.avancer(60)
        s.finirTournee(MaillageDemo.maillage)
        #expect(suite == ["debut", "maillage", "fin"])
        #expect(recus == [MaillageDemo.debut + 60] && s.derniereTournee == MaillageDemo.debut + 60)
        #expect(!s.tourneeEnCours && s.avancement == nil && s.debutTournee == nil)
        s.debuterTournee()
        await s.oublier()
        #expect(!s.tourneeEnCours && suite.last == "fin", "l'oubli arrete la tournee")
    }
}
