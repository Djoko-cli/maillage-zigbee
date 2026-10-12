import CryptoKit
import Foundation
@testable import MaillageCoeur
import Synchronization
import Testing
@testable import MaillageZigbee

/// La sonde cote reseau, faite avec les briques H1 : repond au SALUT par un DEFI (sid et nc fixes), ouvre les messages
/// de l'app, scelle les siens. `repondre` rend les lignes JSON a renvoyer pour une commande.
final class TransportFactice: TransportLignes {
    struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var recus: [String] = []       // charges ouvertes : « <rid> <commande> »
        var ks: Data?
        var ctrC: UInt32 = 0
        var fenetre = FenetreAntiRejeu()
        var ferme = false
    }

    static let sid = "1234ABCD"
    static let nc = "505152535455565758595A5B5C5D5E5F"
    let cle: Data
    let repondre: @Sendable (String) -> [String]
    let muet: Bool
    let etat = Mutex(Etat())

    init(cle: Data, muet: Bool = false, repondre: @escaping @Sendable (String) -> [String] = { _ in [] }) {
        self.cle = cle
        self.muet = muet
        self.repondre = repondre
    }

    func ouvrir() -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        return flux
    }

    func envoyer(_ ligne: Data) {
        let texte = String(decoding: ligne, as: UTF8.self)
        let champs = texte.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        if champs.count == 5, champs[1] == "SALUT" {
            guard !muet, let na = H1.octets(hexa: champs[3]) else { return }
            let mac = H1.mac(SymmetricKey(data: cle),
                             Data("H1|DEFI|\(H1.kid(cle: cle))|\(H1.hexa(na))|\(Self.nc)|\(Self.sid)".utf8))
            let ks = H1.cleSession(cle: cle, na: na, nc: Self.nc, sid: Self.sid).withUnsafeBytes { Data($0) }
            etat.withLock { e in
                e.ks = ks
                e.suite?.yield(Data("H1 DEFI \(Self.sid) \(Self.nc) \(mac)".utf8))
            }
            return
        }
        guard champs.count == 5, champs[0] == "H1", champs[1] == Self.sid, let ctr = UInt32(champs[2]) else { return }
        let reponses: [String]? = etat.withLock { e in
            guard let ks = e.ks else { return nil }
            let attendu = H1.mac(SymmetricKey(data: ks), Data("A|\(Self.sid)|\(ctr)|".utf8) + Data(champs[4].utf8))
            guard attendu == champs[3], e.fenetre.accepter(ctr) else { return nil }
            e.recus.append(champs[4])
            return []
        }
        guard reponses != nil else { return }
        let (rid, _, commande) = Self.couper(champs[4])
        for json in repondre(commande) { emettre(rid: rid, json) }
    }

    /// Une ligne de la sonde : « <rid> <json> », scellee (sens C).
    func emettre(rid: String, _ json: String) {
        etat.withLock { e in
            guard let ks = e.ks else { return }
            e.ctrC += 1
            let charge = "\(rid) \(json)"
            let mac = H1.mac(SymmetricKey(data: ks), Data("C|\(Self.sid)|\(e.ctrC)|\(charge)".utf8))
            e.suite?.yield(Data("H1 \(Self.sid) \(e.ctrC) \(mac) \(charge)".utf8))
        }
    }

    func fermer() {
        etat.withLock { e in
            e.ferme = true
            e.suite?.finish()
        }
    }

    var recus: [String] { etat.withLock { $0.recus } }

    static func couper(_ charge: String) -> (String, Character, String) {
        guard let i = charge.firstIndex(of: " ") else { return (charge, " ", "") }
        return (String(charge[..<i]), " ", String(charge[charge.index(after: i)...]))
    }
}

@Suite("Canal reseau : poignee de main H1, rid, signaux", .timeLimit(.minutes(1)))
struct CanalReseauTests {
    static let cle = Data((0..<32).map { UInt8($0) })

    /// Les n premieres lignes du flux (5 s au plus).
    static func lire(_ flux: AsyncStream<Data>, _ n: Int) async -> [String] {
        var lignes: [String] = []
        for await l in flux {
            lignes.append(String(decoding: l, as: UTF8.self))
            if lignes.count == n { break }
        }
        return lignes
    }

    @Test func commandeEtReponse() async throws {
        let t = TransportFactice(cle: Self.cle) { c in c == "etat" ? [#"{"v":1,"t":"etat","membre":true}"#] : [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"etat","membre":true}"#])
        #expect(t.recus == ["1 etat"])
    }

    @Test func ridsCroissantsEtFileAvantPoigneeDeMain() async throws {
        let t = TransportFactice(cle: Self.cle) { c in [#"{"v":1,"t":"x","c":"\#(c)"}"#] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("bonjour\n")
        canal.envoyer("etat\n")
        _ = await Self.lire(flux, 2)
        #expect(t.recus == ["1 bonjour", "2 etat"])
    }

    @Test func signalRemonte() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        try await Task.sleep(for: .milliseconds(50))
        t.emettre(rid: "0", #"{"v":1,"t":"signal"}"#)
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"signal"}"#])
    }

    @Test func ridInattenduIgnore() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        try await Task.sleep(for: .milliseconds(50))
        t.emettre(rid: "99", #"{"v":1,"t":"etat","intrus":true}"#)
        t.emettre(rid: "1", #"{"v":1,"t":"etat","membre":true}"#)
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"etat","membre":true}"#])
    }

    @Test func mauvaiseCleFermeLeCanal() async throws {
        let t = TransportFactice(cle: Data(repeating: 0x80, count: 32)) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle, delaiPoigneeDeMain: .milliseconds(200))
        let flux = try canal.ouvrir()
        #expect(await Self.lire(flux, 1).isEmpty, "DEFI faux : le flux finit sans ligne")
    }

    @Test func sondeMuetteFermeLeCanal() async throws {
        let t = TransportFactice(cle: Self.cle, muet: true)
        let canal = CanalReseau(transport: t, cle: Self.cle, delaiPoigneeDeMain: .milliseconds(200))
        let flux = try canal.ouvrir()
        #expect(await Self.lire(flux, 1).isEmpty)
        #expect(t.etat.withLock { $0.ferme })
    }

    @Test func coupurePendantRequete() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("table 1A2B 1\n")
        try await Task.sleep(for: .milliseconds(50))
        t.fermer()
        #expect(await Self.lire(flux, 1).isEmpty, "le flux finit : Sonde rend nil a la requete en cours")
    }

    @Test func decoupeurLF() {
        var d = DecoupeurLF()
        var r = d.ajouter(Data("ab\ncd".utf8))
        #expect(r.lignes == [Data("ab".utf8)] && !r.tropLongue)
        r = d.ajouter(Data("e\r\n".utf8))
        #expect(r.lignes == [Data("cde".utf8)])
        r = d.ajouter(Data(repeating: 0x41, count: DecoupeurLF.longueurMax + 1))
        #expect(r.tropLongue)
    }
}
