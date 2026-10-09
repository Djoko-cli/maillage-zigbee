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

/// Lancements du passeur demandes par l'app, dans l'ordre (leurs cibles : port et jeton).
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
    /// Lanceur des tests qui ne doivent jamais lancer le Passeur : s'il est appele, le test echoue.
    /// `NomsPasseur` n'a pas de lanceur par defaut (l'oublier lancerait le vrai Passeur) : tout test
    /// qui ne prevoit pas de lancement donne celui-ci.
    static let lanceurInterdit: Lanceur = { _ in
        Issue.record("le Passeur ne doit pas etre lance par ce test")
        return .refuse("lanceur interdit")
    }
}


@MainActor
@Suite("Noms de Maison : releve du Passeur par la boucle locale", .timeLimit(.minutes(1)))
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

    /// Faux lanceur : note chaque lancement ; puis, comme le Passeur, envoie a l'ecoute les octets que `trame` tire du
    /// jeton recu (nil : il ne se connecte pas). `echec` : le lancement echoue, rien n'est envoye.
    static func lanceur(_ lancements: LancementsPasseur, echec: NomsPasseur.EchecLancement? = nil,
                        trame: (@Sendable (String) -> Data)? = nil) -> NomsPasseur.Lanceur {
        { cible in
            lancements.noter(cible)
            if let echec { return echec }
            if let trame {
                Task.detached { _ = await FauxPasseur.envoyer(trame(cible.jeton), port: cible.port) }
            }
            return nil
        }
    }

    /// Trame du vrai Passeur, avec le jeton recu.
    static func bonneTrame(_ r: ReleveMaison) throws -> @Sendable (String) -> Data {
        let json = try r.donnees()
        return { EnvoiPasseur.trame(jeton: $0, json: json) }
    }

    /// Demande un releve et attend sa fin, au plus `delai`.
    static func demander(_ n: NomsPasseur, delai: Duration = .seconds(10)) async {
        n.rafraichir()
        await attendre(n, delai: delai)
    }

    /// Attend que le faux lanceur ait ete appele `fois` fois, au plus 10 s ; rend la cible du dernier lancement.
    static func cible(_ lancements: LancementsPasseur, fois: Int = 1) async -> EnvoiPasseur.Cible? {
        let fin = ContinuousClock.now + .seconds(10)
        while lancements.tous.count < fois, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        return lancements.cible
    }

    /// Attend la fin du releve en cours, au plus `delai`.
    static func attendre(_ n: NomsPasseur, delai: Duration = .seconds(10)) async {
        let fin = ContinuousClock.now + delai
        while n.releveEnCours, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        #expect(!n.releveEnCours, "releve fini")
    }

    /// Attend que plus rien n'ecoute sur ce port, au plus 5 s : l'app a alors accepte une connexion. Chaque essai est
    /// un client de plus, que l'app ferme aussitot si l'ecoute n'est pas encore fermee.
    static func ecouteFermee(port: UInt16) async -> Bool {
        let fin = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < fin {
            if await !FauxPasseur.envoyer(Data("essai".utf8), port: port) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    /// Occupe le fil principal, sans rendre la main a sa file, jusqu'a `condition` (au plus 5 s) : l'ecoute, qui livre
    /// ses connexions sur cette file, n'en traite aucune pendant ce temps.
    static func occuper(jusqua condition: () -> Bool) {
        let fin = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < fin { usleep(1000) }
    }

    /// Textes de l'app, dans la langue de l'hote des tests.
    static let refus = String(localized: "Accès à Maison refusé à Passeur Noms : Réglages Système › Confidentialité et sécurité › Maison.")
    static let jetonFaux = String(localized: "Relevé de Maison refusé : jeton faux.")
    static let longueurFausse = String(localized: "Relevé de Maison illisible : longueur fausse.")
    static let interrompu = String(localized: "Relevé de Maison interrompu : la connexion avec Passeur Noms a été coupée.")
    static let absent = String(localized: "Passeur Noms n'est pas installé sur ce Mac : les noms viennent de l'app Hue.")

    /// Un releve reussi remplace l'ancien ; un echec du Passeur le garde et dit pourquoi, avec les textes de l'app : le
    /// message du Passeur (en francais seulement) n'est que le detail d'une erreur.
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

    /// Au-dela de 7 jours, le profil gratuit du Passeur a pu expirer.
    @Test func ancien() {
        #expect(!NomsPasseur.estAncien(Self.releve(), maintenant: Self.date + 6 * 86_400))
        #expect(NomsPasseur.estAncien(Self.releve(), maintenant: Self.date + 8 * 86_400))
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
        relu.surReleve = { recus.append($0) }
        relu.demarrer()
        #expect(recus == [Self.releve(), Self.releve()], "donne au demarrage")
    }

    /// Au lancement : releve absent ou de plus d'un jour, et pas de demande dans le dernier jour (pas de relance en
    /// boucle).
    @Test func aRafraichir() {
        let t = Self.date
        #expect(NomsPasseur.aRafraichir(releve: nil, demande: nil, maintenant: t))
        #expect(!NomsPasseur.aRafraichir(releve: t.addingTimeInterval(-23 * 3600), demande: nil, maintenant: t))
        #expect(NomsPasseur.aRafraichir(releve: t.addingTimeInterval(-25 * 3600), demande: nil, maintenant: t))
        #expect(!NomsPasseur.aRafraichir(releve: t.addingTimeInterval(-48 * 3600), demande: t.addingTimeInterval(-60),
                                         maintenant: t), "demande recente : le Passeur ne s'est peut-etre pas lance")
    }

    /// Un releve garde de moins d'un jour : rien au lancement. Plus ancien : le Passeur est lance (faux lanceur).
    @Test func rafraichiAuLancementSiAncien() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let n = NomsPasseur(cache: cache, lanceur: NomsPasseur.lanceurInterdit)
        n.integrer(Self.releve())
        n.rafraichirSiAncien(maintenant: Self.date.addingTimeInterval(3600))
        #expect(!n.releveEnCours, "releve d'une heure : rien")
        let lancements = LancementsPasseur()
        let vieux = NomsPasseur(cache: cache, delai: .milliseconds(300), lanceur: Self.lanceur(lancements))
        vieux.rafraichirSiAncien(maintenant: Self.date.addingTimeInterval(2 * 86_400))
        #expect(vieux.releveEnCours)
        #expect(await Self.cible(lancements) != nil, "Passeur lance")
        await Self.attendre(vieux)
    }

    /// Inerte (demo, tests) : jamais de Passeur lance, ni au lancement ni au bouton ; le releve donne est garde.
    @Test func inerte() {
        let n = NomsPasseur(demo: NomsDemo.releveMaison)
        n.rafraichirSiAncien(maintenant: .distantFuture)
        n.rafraichir()
        #expect(n.inerte && !n.releveEnCours && n.releve == NomsDemo.releveMaison)
        #expect(NomsPasseur().releve == nil && NomsPasseur().inerte)
    }

    /// Un bon jeton : le Passeur est lance avec le port de l'ecoute et un jeton de 64 chiffres ; le releve est retenu,
    /// ecrit dans le conteneur et relu au lancement ; l'ecoute est fermee.
    @Test func bonJeton() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements, trame: try Self.bonneTrame(Self.releve())))
        var recus: [ReleveMaison?] = []
        n.surReleve = { recus.append($0) }
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        #expect(n.probleme == nil && !n.passeurAbsent)
        #expect(recus == [Self.releve()])
        #expect(try ReleveMaison.lire(Data(contentsOf: cache)) == Self.releve(), "ecrit dans le conteneur")
        #expect(NomsPasseur(cache: cache, lanceur: NomsPasseur.lanceurInterdit).releve == Self.releve(), "relu au lancement")
        let cible = try #require(lancements.cible)
        #expect(lancements.tous.count == 1)
        #expect(cible.jeton.count == 64)
        #expect(await !FauxPasseur.envoyer(Data("encore".utf8), port: cible.port), "ecoute fermee")
    }

    /// Le Passeur a pu s'ouvrir, mais l'acces a Maison lui est refuse : le releve garde reste.
    @Test func refusDeMaison() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(LancementsPasseur(),
                                                               trame: try Self.bonneTrame(Self.releve(.refuse, message: "Accès refusé"))))
        n.integrer(Self.releve())
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        #expect(n.probleme == Self.refus)
    }

    /// Un mauvais jeton : rien n'est retenu ni ecrit, le dernier releve valide reste.
    @Test func mauvaisJeton() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let json = try Self.releve(nom: "Intrus").donnees()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(LancementsPasseur(), trame: { jeton in
            EnvoiPasseur.trame(jeton: String(jeton.reversed()), json: json)
        }))
        n.integrer(Self.releve())
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        #expect(n.probleme == Self.jetonFaux)
        #expect(try ReleveMaison.lire(Data(contentsOf: cache)) == Self.releve(), "fichier inchange")
    }

    /// Une longueur fausse (illisible, au-dela de 8 Mo, ou plus longue que la trame) : le dernier releve valide reste.
    @Test func longueurFausse() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let json = try Self.releve(nom: "Intrus").donnees()
        for longueur in ["abc", String(EnvoiPasseur.tailleMax + 1), String(json.count + 10)] {
            let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(LancementsPasseur(), trame: { jeton in
                Data("\(jeton)\n\(longueur)\n".utf8) + json
            }))
            n.integrer(Self.releve())
            await Self.demander(n)
            #expect(n.releve == Self.releve(), "longueur \(longueur)")
            #expect(n.probleme == Self.longueurFausse, "longueur \(longueur)")
        }
    }

    /// Une connexion coupee par une erreur avant la fin de la trame se dit interrompue, et non « jeton faux » ni
    /// « longueur fausse » : la trame n'est pas en cause. Une fin propre (le Passeur ferme son cote) sans trame complete
    /// garde son message. Dans tous les cas, le dernier releve valide reste.
    @Test func connexionCoupee() async throws {
        let jeton = 2 * EnvoiPasseur.octetsJeton
        let json = try Self.releve(nom: "Intrus").donnees()
        let arrets: [(String, (Data) -> Data, String)] = [
            ("dans le jeton", { $0.prefix(jeton / 2) }, Self.jetonFaux),
            ("apres le jeton", { $0.prefix(jeton + 1) }, Self.longueurFausse),
            ("dans le json", { $0.dropLast(3) }, Self.longueurFausse),
        ]
        for (ou, tronquer, propre) in arrets {
            for coupee in [false, true] {
                let cache = Self.cache()
                defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
                let lancements = LancementsPasseur()
                let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements))
                n.integrer(Self.releve())
                n.rafraichir()
                let cible = try #require(await Self.cible(lancements))
                let debut = tronquer(EnvoiPasseur.trame(jeton: cible.jeton, json: json))
                if coupee {
                    let client = try #require(FauxPasseur.Client(port: cible.port))
                    #expect(await client.attendre())
                    #expect(await client.envoyer(debut))
                    // Plus rien n'ecoute : l'app a accepte la connexion, la coupure vient ensuite.
                    #expect(await Self.ecouteFermee(port: cible.port))
                    client.couper()
                } else {
                    #expect(await FauxPasseur.envoyer(debut, port: cible.port))
                }
                await Self.attendre(n)
                #expect(n.releve == Self.releve(), "\(ou), coupee \(coupee) : le dernier releve valide reste")
                #expect(n.probleme == (coupee ? Self.interrompu : propre), "\(ou), coupee \(coupee)")
            }
        }
    }

    /// Un JSON illisible : le dernier releve valide reste, et le detail est dit.
    @Test func jsonIllisible() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(LancementsPasseur(), trame: { jeton in
            EnvoiPasseur.trame(jeton: jeton, json: Data("pas du json".utf8))
        }))
        n.integrer(Self.releve())
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        let debut = String(localized: "Relevé de Maison illisible : \("")")
        #expect(n.probleme?.hasPrefix(debut) == true && n.probleme != Self.longueurFausse, "\(n.probleme ?? "")")
    }

    /// Rien dans le delai (le Passeur ne se connecte pas) : le dernier releve valide reste, et l'ecoute est fermee.
    @Test func delaiDepasse() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, delai: .seconds(1), lanceur: Self.lanceur(lancements))
        n.integrer(Self.releve())
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        #expect(n.probleme == String(localized: "Passeur Noms n'a rien envoyé en 2 minutes."))
        let cible = try #require(lancements.cible)
        #expect(await !FauxPasseur.envoyer(try Self.bonneTrame(Self.releve(nom: "Tard"))(cible.jeton), port: cible.port),
                "ecoute fermee")
        #expect(n.releve == Self.releve())
    }

    /// Passeur absent : un message clair, l'aide des Reglages, l'ecoute fermee, le releve garde (et sans releve, les
    /// noms du pont seuls). Lancement refuse par macOS : la cause.
    @Test func passeurAbsentOuRefuse() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements, echec: .introuvable))
        n.integrer(Self.releve())
        await Self.demander(n)
        #expect(n.releve == Self.releve())
        #expect(n.probleme == Self.absent && n.passeurAbsent)
        let cible = try #require(lancements.cible)
        #expect(await !FauxPasseur.envoyer(Data("x".utf8), port: cible.port), "ecoute fermee")
        let refuse = NomsPasseur(cache: cache, lanceur: Self.lanceur(LancementsPasseur(), echec: .refuse("cause inventée")))
        await Self.demander(refuse)
        #expect(refuse.probleme == String(localized: "Passeur Noms ne s'est pas ouvert : \("cause inventée") (profil de 7 jours expiré ?)"))
        #expect(!refuse.passeurAbsent)
    }

    /// Une seule ecoute a la fois : une demande pendant un releve est ignoree ; une fois le releve fini, une autre
    /// demande lance de nouveau le Passeur, avec un autre jeton.
    @Test func uneSeuleEcoute() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements))
        n.rafraichir()
        let premiere = n.derniereDemande
        let fin = ContinuousClock.now + .seconds(10)
        while lancements.tous.isEmpty, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        n.rafraichir()
        n.rafraichirSiAncien(maintenant: .now + 3 * 86_400)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(lancements.tous.count == 1, "demandes ignorees pendant le releve")
        #expect(n.derniereDemande == premiere)
        let cible = try #require(lancements.cible)
        #expect(await FauxPasseur.envoyer(try Self.bonneTrame(Self.releve())(cible.jeton), port: cible.port))
        #expect(!n.releveEnCours)
        #expect(n.releve == Self.releve())
        n.rafraichir()
        #expect(n.releveEnCours)
        while lancements.tous.count < 2, ContinuousClock.now < fin { try? await Task.sleep(for: .milliseconds(5)) }
        let seconde = try #require(lancements.cible)
        #expect(seconde.jeton != cible.jeton, "jeton a usage unique")
        #expect(await FauxPasseur.envoyer(try Self.bonneTrame(Self.releve(nom: "Pont"))(seconde.jeton), port: seconde.port))
        #expect(n.releve == Self.releve(nom: "Pont"))
    }

    /// Un NomsPasseur qui disparait pendant un releve ne laisse pas d'ecoute ouverte : a la fin du delai, la minuterie
    /// la ferme.
    @Test func ecouteFermeeSiNomsPasseurDisparait() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        var n: NomsPasseur? = NomsPasseur(cache: cache, delai: .milliseconds(100), lanceur: Self.lanceur(lancements))
        n?.rafraichir()
        let cible = try #require(await Self.cible(lancements))
        n = nil
        try? await Task.sleep(for: .seconds(1))
        #expect(await !FauxPasseur.envoyer(Data("x".utf8), port: cible.port), "ecoute fermee par la minuterie")
    }

    /// Une seule connexion par releve : des que la premiere est acceptee, meme sans sa trame finie, l'ecoute est fermee.
    /// Un second client ne trouve plus personne, et le releve reste celui du premier.
    @Test func uneSeuleConnexion() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements))
        n.rafraichir()
        let cible = try #require(await Self.cible(lancements))
        let trame = EnvoiPasseur.trame(jeton: cible.jeton, json: try Self.releve().donnees())
        let moitie = trame.count / 2
        let premier = try #require(FauxPasseur.Client(port: cible.port))
        #expect(await premier.attendre(), "premier client connecte")
        #expect(await premier.envoyer(trame.prefix(moitie)))
        #expect(await Self.ecouteFermee(port: cible.port), "ecoute fermee des la premiere connexion")
        #expect(n.releveEnCours, "le premier client n'a pas fini : le releve continue")
        #expect(n.releve == nil && n.probleme == nil)
        #expect(await premier.terminer(trame.dropFirst(moitie)))
        await Self.attendre(n)
        #expect(n.releve == Self.releve(), "le releve est celui du premier client")
        #expect(n.probleme == nil)
    }

    /// Deux connexions arrivees avant que l'app ait traite la premiere : la seconde, meme avec un jeton et un releve
    /// complets, est refusee. Le releve est celui du premier client.
    @Test func deuxConnexionsEnSimultane() async throws {
        let cache = Self.cache()
        defer { try? FileManager.default.removeItem(at: cache.deletingLastPathComponent()) }
        let lancements = LancementsPasseur()
        let n = NomsPasseur(cache: cache, lanceur: Self.lanceur(lancements))
        n.rafraichir()
        let cible = try #require(await Self.cible(lancements))
        let trame = EnvoiPasseur.trame(jeton: cible.jeton, json: try Self.releve().donnees())
        let intrus = EnvoiPasseur.trame(jeton: cible.jeton, json: try Self.releve(nom: "Intrus").donnees())
        let moitie = trame.count / 2
        let premier = try #require(FauxPasseur.Client(port: cible.port))
        Self.occuper { premier.pret }
        let second = try #require(FauxPasseur.Client(port: cible.port))
        Self.occuper { second.pret }
        // Le temps que l'ecoute mette les deux connexions dans la file du fil principal.
        usleep(100_000)
        #expect(premier.pret && second.pret, "deux connexions etablies avant que l'app en traite une")
        #expect(await premier.envoyer(trame.prefix(moitie)))
        _ = await second.terminer(intrus)
        #expect(n.releveEnCours, "le second client n'a pas pris la place du premier")
        #expect(n.releve == nil && n.probleme == nil)
        #expect(await premier.terminer(trame.dropFirst(moitie)))
        await Self.attendre(n)
        #expect(n.releve == Self.releve(), "le releve est celui du premier client")
        #expect(n.probleme == nil)
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
