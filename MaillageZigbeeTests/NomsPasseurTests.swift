import AppKit
import Foundation
import MaillageCoeur
import Network
import Synchronization
import SwiftUI
import Testing
@testable import MaillageZigbee

/// Faux Passeur des tests (repris de Maillage Thread) : un client TCP sur 127.0.0.1. Les tests ne lancent jamais le vrai
/// Passeur. Il envoie des octets et ferme son
/// cote, puis attend que l'app ferme la connexion, comme le vrai passeur ; vrai si elle l'a
/// fermee, faux si la connexion a echoue (rien n'ecoute sur ce port).
enum FauxPasseur {
    static func envoyer(_ octets: Data, port: UInt16) async -> Bool {
        guard let p = NWEndpoint.Port(rawValue: port) else { return false }
        let c = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
        let fermee = await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
            let reprise = Reprise(suite)
            c.stateUpdateHandler = { etat in
                switch etat {
                case .ready:
                    c.send(content: octets, contentContext: .finalMessage, isComplete: true,
                           completion: .contentProcessed { erreur in
                        guard erreur == nil else { return reprise.reprendre(false) }
                        c.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, fin, e in
                            reprise.reprendre(fin || e != nil)
                        }
                    })
                case .waiting, .failed: reprise.reprendre(false)
                default: break
                }
            }
            c.start(queue: .global())
        }
        c.cancel()
        return fermee
    }

    /// Reprend la continuation une seule fois, depuis n'importe quel fil.
    final class Reprise: Sendable {
        private let suite: Mutex<CheckedContinuation<Bool, Never>?>

        init(_ suite: CheckedContinuation<Bool, Never>) {
            self.suite = Mutex(suite)
        }

        func reprendre(_ fermee: Bool) {
            suite.withLock { $0.take() }?.resume(returning: fermee)
        }
    }

    /// Client de la boucle locale qui reste connecte : il envoie les octets qu'on lui donne sans
    /// fermer son cote, puis se ferme proprement (`terminer`, comme le passeur) ou est coupe net
    /// (`couper`, la connexion est reinitialisee). Il se connecte des sa creation, sans attendre.
    final class Client: Sendable {
        private let connexion: NWConnection
        private let etat = Mutex<NWConnection.State>(.setup)

        init?(port: UInt16) {
            guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
            connexion = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
            connexion.stateUpdateHandler = { [weak self] nouvel in self?.etat.withLock { $0 = nouvel } }
            connexion.start(queue: .global())
        }

        deinit {
            connexion.cancel()
        }

        /// La connexion est etablie.
        var pret: Bool { etat.withLock { $0 == .ready } }

        /// Attend que la connexion soit etablie, au plus `delai` ; faux si elle echoue (rien
        /// n'ecoute sur ce port).
        func attendre(delai: Duration = .seconds(5)) async -> Bool {
            let fin = ContinuousClock.now + delai
            while ContinuousClock.now < fin {
                switch etat.withLock({ $0 }) {
                case .ready: return true
                case .waiting, .failed, .cancelled: return false
                default: try? await Task.sleep(for: .milliseconds(2))
                }
            }
            return false
        }

        /// Envoie ces octets sans fermer son cote ; vrai s'ils sont partis.
        func envoyer(_ octets: Data) async -> Bool {
            await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
                connexion.send(content: octets, completion: .contentProcessed { erreur in
                    suite.resume(returning: erreur == nil)
                })
            }
        }

        /// Envoie ces octets (s'il y en a) et ferme son cote, puis attend que l'app ferme la
        /// connexion, au plus 5 s ; vrai si elle l'a fermee.
        func terminer(_ octets: Data = Data()) async -> Bool {
            await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
                let reprise = Reprise(suite)
                DispatchQueue.global().asyncAfter(deadline: .now() + 5) { reprise.reprendre(false) }
                connexion.send(content: octets.isEmpty ? nil : octets, contentContext: .finalMessage,
                               isComplete: true, completion: .contentProcessed { [connexion] erreur in
                    guard erreur == nil else { return reprise.reprendre(false) }
                    connexion.receive(minimumIncompleteLength: 1, maximumLength: 1) { _, _, fin, e in
                        reprise.reprendre(fin || e != nil)
                    }
                })
            }
        }

        /// Coupe net, sans fermeture propre : l'app recoit une erreur de connexion.
        func couper() {
            connexion.forceCancel()
        }
    }
}

/// Lancements du demon demandes par l'app, dans l'ordre (leurs cibles : port et jeton).
final class LancementsPasseur: Sendable {
    private let liste = Mutex<[EnvoiPasseur.Cible]>([])

    func noter(_ cible: EnvoiPasseur.Cible) {
        liste.withLock { $0.append(cible) }
    }

    var tous: [EnvoiPasseur.Cible] { liste.withLock { $0 } }
    /// Port et jeton du dernier lancement.
    var cible: EnvoiPasseur.Cible? { tous.last }
}

extension NomsPasseur {
    /// Lanceur des tests qui ne doivent jamais lancer le demon : s'il est appele, le test echoue.
    /// `NomsPasseur` n'a pas de lanceur par defaut (l'oublier lancerait le vrai demon) : tout test
    /// qui ne prevoit pas de lancement donne celui-ci.
    static let lanceurInterdit: Lanceur = { _ in
        Issue.record("le demon ne doit pas etre lance par ce test")
        return .refuse("lanceur interdit")
    }
}

@MainActor
@Suite("Noms de Maison : client du demon Passeur Noms", .timeLimit(.minutes(1)))
struct NomsPasseurTests {
    static let date = Date(timeIntervalSince1970: 1_790_000_000)

    static func releve(_ statut: StatutPasseur = .ok, nom: String = "Lampe bureau", message: String? = nil) -> ReleveMaison {
        ReleveMaison(date: date, statut: statut, message: message, domicile: statut == .ok ? "Maison inventée" : nil,
                     accessoires: statut == .ok ? [AccessoireReleve(nom: nom, piece: "Bureau", fabricant: "Signify")] : [],
                     zones: statut == .ok ? [ZoneMaison(nom: "Étage", pieces: ["Bureau"])] : nil)
    }

    /// `releve-maison.json` dans un dossier temporaire unique, a effacer apres le test.
    static func cache() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maison-\(UUID().uuidString)")
            .appendingPathComponent(NomsPasseur.fichier)
    }

    /// Faux lanceur : note chaque lancement ; `echec` : le lancement echoue.
    static func lanceur(_ lancements: LancementsPasseur, echec: NomsPasseur.EchecLancement? = nil) -> NomsPasseur.Lanceur {
        { cible in
            lancements.noter(cible)
            return echec
        }
    }

    static func json(_ r: ReleveMaison) throws -> Data { try r.donnees() }

    /// Attend que le faux lanceur ait ete appele `fois` fois, au plus 10 s ; rend la cible du dernier lancement.
    static func cible(_ lancements: LancementsPasseur, fois: Int = 1) async -> EnvoiPasseur.Cible? {
        let fin = ContinuousClock.now + .seconds(10)
        while lancements.tous.count < fois, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        return lancements.cible
    }

    /// Textes de l'app, dans la langue de l'hote des tests.
    static let refus = String(localized: "Accès à Maison refusé à Passeur Noms : Réglages Système › Confidentialité et sécurité › Maison.")

    /// Un client abonne a un faux demon connecte : le client, le demon et le fichier du releve.
    static func connecte(attentes: [Duration] = [.milliseconds(20)])
        async throws -> (NomsPasseur, FauxDemon, LancementsPasseur, URL) {
        let cache = Self.cache()
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, attentes: attentes, lanceur: Self.lanceur(lancements))
        n.demarrer()
        let cible = try #require(await Self.cible(lancements))
        let d = try #require(FauxDemon(port: cible.port))
        #expect(await d.jeton(cible.jeton))
        #expect(await attendreQue { n.connecte })
        return (n, d, lancements, cache)
    }

    /// Un releve reussi remplace l'ancien ; un echec du demon le garde et dit pourquoi, avec les textes de l'app : le
    /// message du demon (en francais seulement) n'est que le detail d'une erreur.
    @Test func echecGardeLeReleve() {
        let ancien = Self.releve(nom: "Lampe")
        let (garde, probleme) = NomsPasseur.retenir(Self.releve(.refuse, message: "Accès refusé"), ancien: ancien)
        #expect(garde == ancien)
        #expect(probleme == Self.refus)
        let (_, indisponible) = NomsPasseur.retenir(Self.releve(.indisponible), ancien: ancien)
        #expect(indisponible == String(localized: "Maison indisponible pour Passeur Noms."))
        let (gardeAussi, erreur) = NomsPasseur.retenir(Self.releve(.erreur, message: "Aucun domicile dans Maison"), ancien: ancien)
        #expect(gardeAussi == ancien)
        #expect(erreur == String(localized: "Passeur Noms a échoué : \("Aucun domicile dans Maison")"))
        let (_, sansDetail) = NomsPasseur.retenir(Self.releve(.erreur), ancien: nil)
        #expect(sansDetail == String(localized: "Passeur Noms a échoué."))
        let (neuf, rien) = NomsPasseur.retenir(Self.releve(nom: "Pont"), ancien: ancien)
        #expect(neuf?.accessoires.first?.nom == "Pont")
        #expect(rien == nil)
    }

    /// Le releve retenu est ecrit dans le conteneur et relu au lancement ; un echec ne l'efface pas.
    @Test func memoireDuReleve() throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let n = NomsPasseur(cache: cache, lanceur: NomsPasseur.lanceurInterdit)
        #expect(n.releve == nil)
        var recus: [ReleveMaison?] = []
        n.surReleve = { recus.append($0) }
        n.integrer(Self.releve())
        n.integrer(Self.releve(.refuse, message: "Accès refusé"))
        #expect(n.releve == Self.releve(), "l'echec n'efface pas le releve")
        #expect(n.probleme == Self.refus)
        #expect(recus == [Self.releve()], "un seul changement")
        let relu = NomsPasseur(cache: cache, lanceur: NomsPasseur.lanceurInterdit)
        #expect(relu.releve == Self.releve(), "relu au lancement")
    }

    /// Un cache d'avant le demon (version 1, sans `id`) se relit.
    @Test func cacheDeVersionUn() throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"accessoires":[{"nom":"Lampe"}],"date":"2026-10-08T07:00:00.000Z","statut":"ok","version":1}"#.utf8)
            .write(to: cache)
        let n = NomsPasseur(cache: cache, lanceur: NomsPasseur.lanceurInterdit)
        #expect(n.releve?.accessoires.first?.nom == "Lampe" && n.releve?.accessoires.first?.id == nil)
    }

    /// Au demarrage : l'URL `abonner` ; puis `etat` et les releves successifs, gardes dans `releve-maison.json`.
    @Test func abonnementEtReleves() async throws {
        let (n, d, lancements, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(lancements.cible?.demande == .abonner)
        #expect(lancements.cible?.jeton.count == 64)
        let e = EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)
        #expect(await d.message(.etat(e)))
        #expect(await attendreQue { n.etat == e })
        #expect(await d.message(.releve(try Self.json(Self.releve()))))
        #expect(await attendreQue { n.releve == Self.releve() })
        #expect(await d.message(.releve(try Self.json(Self.releve(nom: "Pont")))))
        #expect(await attendreQue { n.releve == Self.releve(nom: "Pont") })
        #expect(try ReleveMaison.lire(Data(contentsOf: cache)) == Self.releve(nom: "Pont"), "ecrit dans le conteneur")
        #expect(n.tentative == 0 && n.probleme == nil && !n.passeurAbsent)
    }

    /// `relire`, `identifier` et `ouvertureSession` partent vers le demon ; la reponse a « Identifier » s'affiche pour
    /// son accessoire.
    @Test func commandesEnvoyees() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        n.relire()
        #expect(n.releveEnCours)
        n.identifier(accessoire: "A")
        n.reglerOuvertureSession(true)
        #expect(await attendreQue { d.messages.count == 3 })
        #expect(d.messages == [.relire, .identifier(demande: 1, accessoire: "A"), .ouvertureSession(actif: true)])
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 1, ok: true))))
        #expect(await attendreQue { n.identification != nil })
        #expect(n.identification == NomsPasseur.Identification(accessoire: "A",
                                                               texte: String(localized: "Identification demandée")))
        #expect(await d.message(.releve(try Self.json(Self.releve()))))
        #expect(await attendreQue { !n.releveEnCours })
    }

    /// Une reponse a une demande plus ancienne que la derniere est ignoree.
    @Test func reponseIdentifierEnRetard() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        n.identifier(accessoire: "A")
        n.identifier(accessoire: "B")
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 1, ok: true))))
        #expect(await d.message(.identifie(ReponseIdentifier(demande: 2, ok: false, erreur: ReponseIdentifier.nonIdentifiable))))
        #expect(await attendreQue { n.identification != nil })
        #expect(n.identification?.accessoire == "B")
        #expect(n.identification?.texte == String(localized: "Cet accessoire ne sait pas s'identifier"))
    }

    /// Le demon ferme : deconnecte, le probleme dit, et un nouvel abonnement (nouveau jeton) apres l'attente.
    @Test func reabonnementApresFermeture() async throws {
        let (n, d, lancements, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let premier = try #require(lancements.cible)
        d.fermer()
        #expect(await attendreQue { !n.connecte })
        #expect(n.probleme == String(localized: "Passeur Noms s'est déconnecté."))
        let second = try #require(await Self.cible(lancements, fois: 2))
        #expect(second.jeton != premier.jeton)
        #expect(second.demande == .abonner)
    }

    /// Lancement refuse : le probleme, puis d'autres essais ; `passeurAbsent` seulement si le demon manque.
    @Test func essaisApresUnEchec() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, attentes: [.milliseconds(10)],
                            lanceur: Self.lanceur(lancements, echec: .introuvable(ancien: false)))
        n.demarrer()
        _ = await Self.cible(lancements, fois: 3)
        #expect(lancements.tous.count >= 3)
        #expect(n.probleme == String(localized: "Passeur Noms n'est pas installé sur ce Mac : les noms viennent de l'app Hue."))
        #expect(n.passeurAbsent)
        #expect(n.tentative >= 2)
        let refuse = NomsPasseur(cache: cache, attentes: [.seconds(60)],
                                 lanceur: Self.lanceur(LancementsPasseur(), echec: .refuse("cause inventée")))
        refuse.demarrer()
        #expect(await attendreQue { refuse.probleme != nil })
        #expect(refuse.probleme == NomsPasseur.texte(.refuse("cause inventée")))
        #expect(!refuse.passeurAbsent)
    }

    /// Les attentes avant de se reabonner : 5 s, 10 s, 30 s, puis toutes les minutes.
    @Test func attentesCroissantes() {
        let a = NomsPasseur.reabonnements
        #expect(a == [.seconds(5), .seconds(10), .seconds(30), .seconds(60)])
        #expect(NomsPasseur.attente(apres: 0, dans: a) == .seconds(5))
        #expect(NomsPasseur.attente(apres: 1, dans: a) == .seconds(10))
        #expect(NomsPasseur.attente(apres: 2, dans: a) == .seconds(30))
        #expect(NomsPasseur.attente(apres: 3, dans: a) == .seconds(60))
        #expect(NomsPasseur.attente(apres: 40, dans: a) == .seconds(60))
        #expect(NomsPasseur.delaiParDefaut == .seconds(120), "le texte « 2 minutes » en depend")
    }

    /// Aucun demon dans le delai : le probleme, puis un nouvel essai.
    @Test func delaiSansDemon() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, delai: .milliseconds(100), attentes: [.milliseconds(10)],
                            lanceur: Self.lanceur(lancements))
        n.demarrer()
        _ = await Self.cible(lancements, fois: 2)
        #expect(n.probleme == String(localized: "Passeur Noms ne s'est pas connecté en 2 minutes."))
    }

    /// Un releve illisible garde le releve et le dit.
    @Test func releveIllisible() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(await d.message(.releve(try Self.json(Self.releve()))))
        #expect(await attendreQue { n.releve != nil })
        #expect(await d.message(.releve(Data(#"{"x":1}"#.utf8))))
        #expect(await attendreQue { n.probleme != nil })
        #expect(n.releve == Self.releve())
        // Une version plus recente que celle de l'app est refusee de meme.
        var futur = Self.releve(nom: "Futur")
        futur.version = ReleveMaison.versionActuelle + 1
        #expect(await d.message(.releve(try Self.json(futur))))
        #expect(await attendreQue { n.probleme?.hasPrefix(String(localized: "Relevé de Maison illisible : \("")")) == true })
        #expect(n.releve == Self.releve())
    }

    /// Un releve en erreur du demon (acces refuse) garde le releve et le dit.
    @Test func releveRefuse() async throws {
        let (n, d, _, cache) = try await Self.connecte()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        #expect(await d.message(.releve(try Self.json(Self.releve()))))
        #expect(await attendreQue { n.releve != nil })
        #expect(await d.message(.releve(try Self.json(Self.releve(.refuse, message: "Accès refusé")))))
        #expect(await attendreQue { n.probleme == Self.refus })
        #expect(n.releve == Self.releve())
    }

    /// Un demon connecte qui ne repond pas a `relire` : apres le delai, le bouton est libere, le probleme dit, et la
    /// connexion reste ouverte (garde de 2 minutes, ici 1 s).
    @Test func releveSansReponse() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        // Le delai sert aussi de minuterie de connexion : 1 s laisse la connexion s'etablir sur une machine chargee.
        let n = NomsPasseur(cache: cache, delai: .seconds(1), attentes: [.milliseconds(20)],
                            lanceur: Self.lanceur(lancements))
        n.demarrer()
        let cible = try #require(await Self.cible(lancements))
        let d = try #require(FauxDemon(port: cible.port))
        #expect(await d.jeton(cible.jeton))
        #expect(await attendreQue { n.connecte })
        n.relire()
        #expect(n.releveEnCours)
        #expect(await attendreQue { !n.releveEnCours })
        #expect(n.probleme == String(localized: "Passeur Noms n'a pas répondu à la demande de relevé."))
        #expect(n.connecte)
        #expect(d.messages == [.relire])
    }

    /// Inerte (demo, tests) : rien ne se lance, ni au demarrage ni sur demande ; le releve donne est garde.
    @Test func inerte() {
        let n = NomsPasseur(demo: NomsDemo.releveMaison)
        n.demarrer()
        n.relire()
        n.identifier(accessoire: "A")
        n.reglerOuvertureSession(true)
        #expect(n.inerte && !n.connecte && !n.releveEnCours && n.releve == NomsDemo.releveMaison)
        #expect(NomsPasseur().releve == nil && NomsPasseur().inerte)
    }

    /// Sans demon connecte, « Rafraichir depuis Maison » relance l'abonnement tout de suite, sans attendre.
    @Test func relireSansDemon() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, attentes: [.seconds(60)],
                            lanceur: Self.lanceur(lancements, echec: .refuse("absent")))
        n.demarrer()
        _ = await Self.cible(lancements)
        #expect(await attendreQue { n.probleme != nil })
        n.relire()
        #expect(await Self.cible(lancements, fois: 2) != nil)
        #expect(lancements.tous.count == 2)
    }

    // MARK: Lancement du demon (leçons du banc de Maillage Thread, 13/10)

    /// Le demon est lance SANS URL s'il ne tourne pas (HomeKit refuse un lancement a froid par une URL) ; l'URL seule
    /// s'il tourne deja.
    @Test func planDeLancement() {
        #expect(NomsPasseur.plan(demonTourne: false) == .lancerPuisURL)
        #expect(NomsPasseur.plan(demonTourne: true) == .urlSeule)
        #expect(NomsPasseur.essaisDemarrage == 100, "10 s au plus (100 essais de 100 ms)")
        #expect(NomsPasseur.attenteDemarrage == .milliseconds(1500))
    }

    /// Seule compte la copie trouvee par le schema : une autre instance de l'identifiant du passeur (ancien passeur iOS,
    /// autre chemin) ne fait pas du demon un demon deja lance.
    @Test func quelleCopieTourne() {
        let copie = URL(fileURLWithPath: "/Users/x/Applications/Passeur Noms.app")
        let ancienne = URL(fileURLWithPath: "/Users/x/Documents/Wrapper/Passeur Noms.app")
        #expect(!NomsPasseur.tourne([], copie: copie))
        #expect(!NomsPasseur.tourne([nil, ancienne], copie: copie), "une autre copie tourne")
        #expect(NomsPasseur.tourne([ancienne, copie], copie: copie))
        #expect(NomsPasseur.tourne([URL(fileURLWithPath: "/Users/x/Applications/./Passeur Noms.app")], copie: copie),
                "chemins normalises")
    }

    /// Les echecs de lancement : demon introuvable, ancien passeur (identifiant present, schema absent), demon qui ne
    /// demarre pas, lancement refuse ; seuls les deux premiers disent d'installer le demon.
    @Test func textesDesEchecs() {
        #expect(NomsPasseur.texte(.introuvable(ancien: false))
                == String(localized: "Passeur Noms n'est pas installé sur ce Mac : les noms viennent de l'app Hue."))
        #expect(NomsPasseur.texte(.introuvable(ancien: true))
                == String(localized: "Passeur Noms est l'ancienne version : relance outils/passeur.sh de Maillage Thread."))
        #expect(NomsPasseur.texte(.neDemarrePas) == String(localized: "Passeur Noms ne démarre pas : relance outils/passeur.sh."))
        #expect(NomsPasseur.texte(.refuse("cause")) == String(localized: "\("cause") (profil du passeur expiré ? relance outils/passeur.sh)"))
        #expect(NomsPasseur.EchecLancement.introuvable(ancien: true).estAbsent)
        #expect(!NomsPasseur.EchecLancement.neDemarrePas.estAbsent)
        #expect(!NomsPasseur.EchecLancement.refuse("x").estAbsent)
    }

    /// Les textes des fins d'abonnement.
    @Test func textesDesFins() {
        #expect(NomsPasseur.texte(AbonnementPasseur.Fin.jetonFaux) == String(localized: "Connexion de Passeur Noms refusée : jeton faux."))
        #expect(NomsPasseur.texte(AbonnementPasseur.Fin.trameFausse) == String(localized: "Message illisible de Passeur Noms : connexion fermée."))
        #expect(NomsPasseur.texte(AbonnementPasseur.Fin.fermee) == String(localized: "Passeur Noms s'est déconnecté."))
        #expect(NomsPasseur.texte(AbonnementPasseur.Fin.interrompue) == String(localized: "Connexion avec Passeur Noms coupée."))
        #expect(NomsPasseur.texte(AbonnementPasseur.Fin.ecoute("occupé"))
                == String(localized: "Écoute de Passeur Noms impossible : \("occupé")"))
    }

    // MARK: Reglages

    static let maintenant = Date(timeIntervalSince1970: 1_800_000_000)

    static func etat(_ ouverture: EtatPasseur.Ouverture = .inactive, acces: EtatPasseur.Acces = .autorise,
                     profil: Date? = nil) -> EtatPasseur {
        EtatPasseur(version: "2.0", acces: acces, ouvertureSession: ouverture, profilExpire: profil)
    }

    @Test func texteDuDemon() {
        #expect(NomsPasseur.texteDemon(connecte: false, etat: Self.etat()) == String(localized: "non connecté"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: nil) == String(localized: "non connecté"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: Self.etat())
                == String(localized: "connecté · version \("2.0") · \(String(localized: "accès à Maison autorisé"))"))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: Self.etat(acces: .refuse)).contains(String(localized: "accès à Maison refusé")))
        #expect(NomsPasseur.texteDemon(connecte: true, etat: Self.etat(acces: .attente)).contains(String(localized: "accès à Maison en attente")))
    }

    /// Avertissement 30 jours avant l'expiration du profil, et apres.
    @Test func profil() {
        let jour: TimeInterval = 86_400
        #expect(!NomsPasseur.profilBientotExpire(nil, maintenant: Self.maintenant))
        #expect(!NomsPasseur.profilBientotExpire(Self.etat(), maintenant: Self.maintenant), "profil illisible")
        #expect(!NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant + 31 * jour), maintenant: Self.maintenant))
        #expect(NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant + 30 * jour), maintenant: Self.maintenant))
        #expect(NomsPasseur.profilBientotExpire(Self.etat(profil: Self.maintenant - jour), maintenant: Self.maintenant))
    }

    /// L'interrupteur : grise sans demon connecte ; actif meme `indisponible` (demon jamais inscrit).
    @Test func interrupteur() {
        #expect(!NomsPasseur.interrupteurActif(connecte: false, etat: Self.etat()))
        #expect(!NomsPasseur.interrupteurActif(connecte: true, etat: nil))
        #expect(NomsPasseur.interrupteurActif(connecte: true, etat: Self.etat(.indisponible)))
        #expect(NomsPasseur.interrupteurActif(connecte: true, etat: Self.etat(.aApprouver)))
    }

    @Test func textesDIdentification() {
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: true)) == String(localized: "Identification demandée"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false, erreur: ReponseIdentifier.inconnu))
                == String(localized: "Accessoire introuvable dans Maison"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false, erreur: "hors de portée"))
                == String(localized: "Identification impossible : \("hors de portée")"))
        #expect(NomsPasseur.texte(ReponseIdentifier(demande: 1, ok: false)) == String(localized: "Identification impossible"))
    }

    /// Reglages › Maison : l'etat, le releve, les zones dans l'ordre de Maison, le bilan de la fusion.
    @Test func textesDesReglages() {
        #expect(ReglagesMaison.texteZones([ZoneMaison(nom: "Rez-de-chaussée"), ZoneMaison(nom: "Étage")])
                == "Rez-de-chaussée, Étage")
        #expect(ReglagesMaison.texteZones([]) == String(localized: "aucune zone dans Maison"))
        #expect(ReglagesMaison.texteEtat(releve: nil, enCours: false) == String(localized: "aucun relevé : noms de l'app Hue"))
        #expect(ReglagesMaison.texteEtat(releve: Self.releve(), enCours: true) == String(localized: "relevé en cours…"))
        #expect(ReglagesMaison.texteEtat(releve: Self.releve(), enCours: false) == String(localized: "relevé reçu"))
        #expect(ReglagesMaison.texteBilan(nil) == String(localized: "noms de l'app Hue seulement"))
        #expect(ReglagesMaison.texteBilan(FusionNoms.Bilan(apparies: 20, nonApparies: 1))
                == String(localized: "\(20) nommés par Maison · \(1) avec le nom de l'app Hue"))
        #expect(ReglagesMaison.texteReleve(Self.releve()).hasPrefix(String(localized: "\(1) accessoires · \("")")))
    }

    /// La page Maison des Reglages se construit, en demo et hors demo, avec et sans releve.
    @Test func pageDesReglages() {
        for (s, p) in [(Surveillance(mode: .demo, dossier: nil), NomsPasseur(demo: NomsDemo.releveMaison)),
                       (Surveillance(mode: .direct, dossier: nil), NomsPasseur())] {
            let vue = Form { ReglagesMaison() }.formStyle(.grouped).environment(s).environment(p)
            #expect(NSHostingView(rootView: vue).fittingSize.height > 100)
        }
    }
}

@MainActor
@Suite("Noms de Maison dans l'app : fusion avec le pont, etages, fiche")
struct NomsMaisonAppTests {
    typealias I = NomsDemo.Ieee

    /// La surveillance reunit les noms du pont et le releve de Maison, a chaque nouveau releve de l'un ou de l'autre ;
    /// sans releve de Maison, les noms du pont seuls ; sans pont, rien.
    @Test func fusionDansLaSurveillance() throws {
        let s = Surveillance(mode: .direct, dossier: nil)
        s.releveMaison = NomsDemo.releveMaison
        #expect(s.noms.maison == nil && s.bilanFusion == nil, "Maison seule : aucune adresse longue")
        s.nomsPont = NomsDemo.maison
        #expect(s.noms.maison == NomsDemo.maisonFusionnee)
        #expect(s.bilanFusion == FusionNoms.Bilan(apparies: 20, nonApparies: 1))
        #expect(s.nom(I.suspensionCuisine) == "Suspension de l'îlot")
        s.renommer(I.suspensionCuisine, en: "Mon surnom")
        #expect(s.nom(I.suspensionCuisine) == "Mon surnom", "le surnom l'emporte toujours")
        s.releveMaison = nil
        #expect(s.noms.maison == NomsDemo.maison && s.bilanFusion == nil, "sans Maison : les noms du pont")
        // IEEE, connexion et pile viennent toujours du pont.
        var pont = NomsDemo.maison
        if let i = pont.accessoires.firstIndex(where: { $0.ieee == I.lampeBureau }) {
            pont.accessoires[i].connexion = .deconnecte
        }
        s.releveMaison = NomsDemo.releveMaison
        s.nomsPont = pont
        let a = try #require(s.accessoire(I.lampeBureau))
        #expect(a.connexion == .deconnecte && a.origine == .maison)
        #expect(s.accessoire(I.telecommandeChambre)?.batterie == NomsDemo.maison.accessoire(ieee: I.telecommandeChambre)?.batterie)
    }

    /// La demo de l'app montre la fusion : noms de Maison, quatre etages, le bilan.
    @Test func demo() {
        let s = Surveillance(mode: .demo, dossier: nil)
        #expect(s.noms.maison == NomsDemo.maisonFusionnee)
        #expect(s.bilanFusion == FusionNoms.Bilan(apparies: 20, nonApparies: 1))
    }

    /// Les zones de Maison deviennent les etages de la vue par pieces, dans leur ordre ; l'appareil non apparie va a
    /// l'etage de sa piece ; une piece de l'app Hue sans equivalent dans Maison va dans « Autres pieces ».
    @Test func etagesDeMaison() throws {
        let s = Surveillance(mode: .demo, dossier: nil)
        s.demarrer()
        let e = EntreeScene(surveillance: s, places: PlacesGardees())
        #expect(e.scene.etages.map(\.nom) == NomsDemo.zones.map { .zone($0.nom) })
        #expect(e.domicile == NomsDemo.domicile)
        func etage(_ ieee: String) -> ScenePieces.NomEtage? {
            e.scene.pieces.first { $0.noeuds.contains(ieee) }.map { e.scene.etages[$0.etage].nom }
        }
        #expect(etage(I.fuiteBuanderie) == .zone("Rez-de-chaussée"), "non apparie, dans une piece de Maison")
        #expect(etage(I.suspensionCuisine) == .zone("Rez-de-chaussée"))
        #expect(etage(I.lampeGrenier) == .zone("Combles"))
        #expect(e.libelles[I.suspensionCuisine]?.nom == "Suspension de l'îlot")

        // Une piece de l'app Hue que Maison n'a pas : « Autres pieces ».
        var pont = NomsDemo.maison
        if let i = pont.accessoires.firstIndex(where: { $0.ieee == I.fuiteBuanderie }) { pont.accessoires[i].piece = "Cave" }
        s.nomsPont = pont
        let autre = EntreeScene(surveillance: s, places: PlacesGardees())
        let cave = try #require(autre.scene.pieces.first { $0.nom == .maison("Cave") })
        #expect(autre.scene.etages[cave.etage].nom == .autresPieces)
        #expect(cave.noeuds == [I.fuiteBuanderie])
    }

    /// La fiche signale un nom venu de l'app Hue (appareil pas trouve dans Maison) ; rien pour un appareil nomme par
    /// Maison, ni sans releve de Maison.
    @Test func ficheOrigine() {
        let n = NomsDemo.maisonFusionnee
        #expect(FicheNoeud.ligneOrigine(n.accessoire(ieee: I.fuiteBuanderie))
                == String(localized: "nom de l'app Hue (pas trouvé dans Maison)"))
        #expect(FicheNoeud.ligneOrigine(n.accessoire(ieee: I.lampeBureau)) == nil)
        #expect(FicheNoeud.ligneOrigine(NomsDemo.maison.accessoire(ieee: I.fuiteBuanderie)) == nil)
        #expect(FicheNoeud.ligneOrigine(nil) == nil)
    }
}
