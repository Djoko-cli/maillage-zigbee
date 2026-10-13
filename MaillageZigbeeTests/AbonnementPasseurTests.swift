import Foundation
import MaillageCoeur
import Network
import Synchronization
import Testing
@testable import MaillageZigbee

/// Attend une condition, au plus `delai` ; rend la condition.
nonisolated(nonsending) func attendreQue(_ delai: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
    let fin = ContinuousClock.now + delai
    while ContinuousClock.now < fin {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

/// Faux demon des tests : se connecte a l'ecoute de l'app, envoie des octets sans fermer son cote, et lit les trames
/// de l'app (`LectureTrames`).
final class FauxDemon: Sendable {
    private let connexion: NWConnection
    private let lecture = Mutex(EnvoiPasseur.LectureTrames())
    private let recus = Mutex<[MessagePasseur]>([])

    init?(port: UInt16) {
        guard let p = NWEndpoint.Port(rawValue: port) else { return nil }
        connexion = NWConnection(host: "127.0.0.1", port: p, using: .tcp)
        connexion.start(queue: .global())
        lire()
    }

    deinit {
        connexion.cancel()
    }

    /// Messages recus de l'app, dans l'ordre.
    var messages: [MessagePasseur] { recus.withLock { $0 } }

    private func lire() {
        connexion.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] d, _, fin, e in
            guard let self else { return }
            if let d, !d.isEmpty {
                let trames = self.lecture.withLock { $0.ajouter(d) }.trames
                for j in trames {
                    if case .message(let m) = MessagePasseur.lire(j) { self.recus.withLock { $0.append(m) } }
                }
            }
            if fin || e != nil { return }
            self.lire()
        }
    }

    /// Envoie ces octets sans fermer son cote ; vrai s'ils sont partis.
    func envoyer(_ octets: Data) async -> Bool {
        await withCheckedContinuation { (suite: CheckedContinuation<Bool, Never>) in
            connexion.send(content: octets, completion: .contentProcessed { erreur in
                suite.resume(returning: erreur == nil)
            })
        }
    }

    func jeton(_ j: String) async -> Bool { await envoyer(EnvoiPasseur.ligneJeton(j)) }
    func message(_ m: MessagePasseur) async -> Bool { await envoyer(EnvoiPasseur.trame(m)) }

    /// Fermeture propre (le demon quitte).
    func fermer() {
        connexion.cancel()
    }

    /// Coupure nette.
    func couper() {
        connexion.forceCancel()
    }
}

@MainActor
@Suite("Abonnement au demon Passeur Noms", .timeLimit(.minutes(1)))
struct AbonnementPasseurTests {
    static let jeton = String(repeating: "7e", count: 32)
    static let etat = EtatPasseur(version: "2.0", acces: .autorise, ouvertureSession: .inactive, profilExpire: nil)

    /// Les evenements d'un abonnement, dans l'ordre.
    final class Evenements {
        var liste: [AbonnementPasseur.Evenement] = []
        var port: UInt16? {
            if case .prete(let p) = liste.first { return p }
            return nil
        }
    }

    static func ouvrir() async throws -> (AbonnementPasseur, Evenements, FauxDemon) {
        let a = AbonnementPasseur(jeton: jeton)
        let e = Evenements()
        a.ouvrir { e.liste.append($0) }
        #expect(await attendreQue { e.port != nil })
        let port = try #require(e.port)
        let d = try #require(FauxDemon(port: port))
        return (a, e, d)
    }

    /// Jeton, `etat` et `releve` ecrits d'un coup : tout est lu, dans l'ordre.
    @Test func jetonEtatEtReleveDUnCoup() async throws {
        let (a, e, d) = try await Self.ouvrir()
        let releve = Data(#"{"version":2}"#.utf8)
        #expect(await d.envoyer(EnvoiPasseur.ligneJeton(Self.jeton) + EnvoiPasseur.trame(.etat(Self.etat))
                                + EnvoiPasseur.trame(.releve(releve))))
        #expect(await attendreQue { e.liste.count == 4 })
        #expect(e.liste.dropFirst().first == .connecte)
        #expect(e.liste.dropFirst(2).first == .message(.etat(Self.etat)))
        guard case .message(.releve) = e.liste.last else {
            Issue.record("releve attendu")
            return
        }
        a.fermer()
    }

    /// Les messages de l'app partent vers le demon, une fois connecte ; avant, ils sont ignores.
    @Test func envoi() async throws {
        let (a, e, d) = try await Self.ouvrir()
        a.envoyer(.relire)
        #expect(await d.jeton(Self.jeton))
        #expect(await attendreQue { e.liste.contains(.connecte) })
        a.envoyer(.identifier(demande: 1, accessoire: "X"))
        a.envoyer(.ouvertureSession(actif: true))
        #expect(await attendreQue { d.messages.count == 2 })
        #expect(d.messages == [.identifier(demande: 1, accessoire: "X"), .ouvertureSession(actif: true)])
        a.fermer()
    }

    /// Un type inconnu est ignore, la connexion reste.
    @Test func typeInconnuIgnore() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.jeton(Self.jeton))
        let inconnu = Data(#"{"t":"allumer","v":1}"#.utf8)
        #expect(await d.envoyer(Data("\(inconnu.count)\n".utf8) + inconnu + EnvoiPasseur.trame(.etat(Self.etat))))
        #expect(await attendreQue { e.liste.contains(.message(.etat(Self.etat))) })
        #expect(!e.liste.contains { if case .fin = $0 { true } else { false } })
        a.fermer()
    }

    @Test func jetonFaux() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.jeton(String(repeating: "00", count: 32)))
        #expect(await attendreQue { e.liste.last == .fin(.jetonFaux) })
        a.fermer()
    }

    @Test func trameFausse() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.envoyer(EnvoiPasseur.ligneJeton(Self.jeton) + Data("x\n".utf8)))
        #expect(await attendreQue { e.liste.last == .fin(.trameFausse) })
        a.fermer()
    }

    @Test func jsonIllisible() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.envoyer(EnvoiPasseur.ligneJeton(Self.jeton) + Data("2\n[]".utf8)))
        #expect(await attendreQue { e.liste.last == .fin(.trameFausse) })
        a.fermer()
    }

    @Test func demonFerme() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.jeton(Self.jeton))
        #expect(await attendreQue { e.liste.contains(.connecte) })
        d.fermer()
        #expect(await attendreQue { e.liste.last == .fin(.fermee) })
        a.fermer()
    }

    @Test func fermeAvantLeJeton() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.envoyer(Data("7e7e".utf8)))
        d.fermer()
        #expect(await attendreQue { e.liste.last == .fin(.jetonFaux) })
        a.fermer()
    }

    @Test func coupure() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.jeton(Self.jeton))
        #expect(await attendreQue { e.liste.contains(.connecte) })
        d.couper()
        #expect(await attendreQue {
            if case .fin(let f) = e.liste.last { f == .interrompue || f == .fermee } else { false }
        })
        a.fermer()
    }

    /// Une seule connexion : l'ecoute se ferme des la premiere.
    @Test func uneSeuleConnexion() async throws {
        let (a, e, d) = try await Self.ouvrir()
        #expect(await d.jeton(Self.jeton))
        #expect(await attendreQue { e.liste.contains(.connecte) })
        let port = try #require(e.port)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await !FauxPasseur.envoyer(Data("x".utf8), port: port), "plus personne n'ecoute")
        a.fermer()
    }
}
