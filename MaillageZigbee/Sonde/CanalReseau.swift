import Foundation
import MaillageCoeur
import Network
import Synchronization

/// Lignes d'une connexion TCP (LF), le reseau dans l'app, un faux dans les tests.
protocol TransportLignes: Sendable {
    /// Lignes recues, sans LF ; le flux finit quand la connexion se ferme ou echoue.
    func ouvrir() -> AsyncStream<Data>
    /// Une ligne, sans LF (le transport l'ajoute).
    func envoyer(_ ligne: Data)
    func fermer()
}

/// Decoupe un flux TCP en lignes (LF ; un CR final est retire). Au-dela de `longueurMax` octets sans LF : `tropLongue`
/// (spec sonde Wi-Fi, 3.3), et l'appelant ferme la connexion.
struct DecoupeurLF: Sendable {
    static let longueurMax = 4200
    private var tampon = Data()

    mutating func ajouter(_ d: Data) -> (lignes: [Data], tropLongue: Bool) {
        var lignes: [Data] = []
        for o in d {
            if o == 0x0A {
                var l = tampon
                if l.last == 0x0D { l.removeLast() }
                lignes.append(l)
                tampon.removeAll(keepingCapacity: true)
            } else if tampon.count == Self.longueurMax {
                return (lignes, true)
            } else {
                tampon.append(o)
            }
        }
        return (lignes, false)
    }
}

/// La sonde par le reseau (spec sonde Wi-Fi, 4.1) : poignee de main H1 a l'ouverture, puis chaque commande dans un
/// message `H1 <sid> <ctr> <mac> <rid> <commande>` ; les lignes JSON remontent sans leur rid, comme celles de l'USB.
/// Une ligne remonte si son rid est 0 (signal) ou un rid deja envoye sur cette connexion ; sinon elle est ignoree.
final class CanalReseau: CanalSonde {
    private struct Etat {
        var session: SessionH1?
        var enAttente: [String] = []
        var dernierRid: UInt32 = 0
        var suite: AsyncStream<Data>.Continuation?
    }

    private let transport: any TransportLignes
    private let cle: Data
    private let delaiPoigneeDeMain: Duration
    private let etat = Mutex(Etat())

    init(transport: any TransportLignes, cle: Data, delaiPoigneeDeMain: Duration = .seconds(5)) {
        self.transport = transport
        self.cle = cle
        self.delaiPoigneeDeMain = delaiPoigneeDeMain
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (lignes, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        let recues = transport.ouvrir()
        let na = H1.aleatoire(16)
        transport.envoyer(H1.salut(cle: cle, na: na))
        let lecture = Task {
            for await l in recues { self.recevoir(l, na: na, cle: self.cle) }
            suite.finish()
        }
        let delai = delaiPoigneeDeMain
        Task { [transport] in
            try? await Task.sleep(for: delai)
            if self.etat.withLock({ $0.session == nil }) { transport.fermer() }
        }
        suite.onTermination = { [transport] _ in
            lecture.cancel()
            transport.fermer()
        }
        return lignes
    }

    func envoyer(_ ligne: String) {
        var texte = ligne
        if texte.hasSuffix("\n") { texte.removeLast() }
        // Scellement et envoi sous le meme verrou : les commandes partent dans l'ordre de leur rid, meme quand la
        // poignee de main vide la file en parallele.
        etat.withLock { e in
            e.dernierRid += 1
            let charge = "\(e.dernierRid) \(texte)"
            guard var s = e.session else {
                e.enAttente.append(charge)
                return
            }
            let d = s.sceller(Data(charge.utf8))
            e.session = s
            transport.envoyer(d)
        }
    }

    func fermer() { transport.fermer() }

    private func recevoir(_ ligne: Data, na: Data, cle: Data) {
        etat.withLock { e in
            guard var s = e.session else {
                guard let defi = H1.verifierDefi(ligne, cle: cle, na: na) else { return }
                var session = SessionH1(sid: defi.sid,
                                        ks: H1.cleSession(cle: cle, na: na, nc: defi.nc, sid: defi.sid))
                for charge in e.enAttente { transport.envoyer(session.sceller(Data(charge.utf8))) }
                e.enAttente = []
                e.session = session
                return
            }
            let charge = s.ouvrir(ligne)
            e.session = s
            guard let charge, let espace = charge.firstIndex(of: 0x20),
                  let rid = UInt32(String(decoding: charge[charge.startIndex..<espace], as: UTF8.self)),
                  rid == 0 || rid <= e.dernierRid
            else { return }
            e.suite?.yield(Data(charge[charge.index(after: espace)...]))
        }
    }
}

/// TCP vers le service Bonjour de la sonde (Network.framework), en IPv4 : resolution par nom d'instance, sans adresse
/// fixe. Pas pret dans `delaiConnexion` : ferme.
final class TransportTCP: TransportLignes {
    private struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var decoupeur = DecoupeurLF()
    }

    private let connexion: NWConnection
    private let file = DispatchQueue(label: "fr.djoko.maillage.zigbee.sonde.tcp")
    private let delaiConnexion: Duration
    private let etat = Mutex(Etat())

    init(service: String, type: String = "_maillage-zigbee._tcp", delaiConnexion: Duration = .seconds(10)) {
        let parametres = NWParameters.tcp
        (parametres.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        connexion = NWConnection(to: .service(name: service, type: type, domain: "local.", interface: nil),
                                 using: parametres)
        self.delaiConnexion = delaiConnexion
    }

    func ouvrir() -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        connexion.stateUpdateHandler = { [weak self] e in
            switch e {
            case .ready: self?.lire()
            case .failed, .cancelled: self?.finir()
            default: break
            }
        }
        connexion.start(queue: file)
        let delai = delaiConnexion
        Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard let self, self.connexion.state != .ready else { return }
            self.fermer()
        }
        return flux
    }

    func envoyer(_ ligne: Data) {
        connexion.send(content: ligne + Data([0x0A]), completion: .contentProcessed { _ in })
    }

    func fermer() {
        connexion.cancel()
        finir()
    }

    private func lire() {
        connexion.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] d, _, fin, erreur in
            guard let self else { return }
            if let d, !d.isEmpty {
                let (lignes, trop) = self.etat.withLock { $0.decoupeur.ajouter(d) }
                self.etat.withLock { e in
                    for l in lignes { e.suite?.yield(l) }
                }
                if trop { return self.fermer() }
            }
            if fin || erreur != nil { return self.fermer() }
            self.lire()
        }
    }

    private func finir() {
        etat.withLock { e in
            e.suite?.finish()
            e.suite = nil
        }
    }
}
