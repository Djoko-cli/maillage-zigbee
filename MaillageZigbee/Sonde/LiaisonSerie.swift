import Darwin
import Foundation
import Synchronization

/// Ce qui arrive sur la liaison : des octets, ou la fermeture et sa raison.
enum EvenementLiaison: Sendable {
    case donnees(Data)
    case ferme(String)
}

/// Port serie POSIX lu par une source Dispatch (repris de Halo Compagnon, benq).
/// Lectures et ecritures passent par une meme file serie : l'ordre des lignes
/// envoyees est garanti, et la file principale ne bloque jamais.
final class LiaisonSerie: Sendable {
    let chemin: String

    private struct Etat {
        var fd: Int32 = -1
        var source: (any DispatchSourceRead)?
        var suite: AsyncStream<EvenementLiaison>.Continuation?
        /// Raison de la fermeture, posee par `terminer`, emise apres `close(fd)`.
        var raison: String?
    }

    private let file = DispatchQueue(label: "fr.djoko.maillage.zigbee.sonde", qos: .userInitiated)
    private let etat = Mutex(Etat())

    init(chemin: String) {
        self.chemin = chemin
    }

    /// Le flux finit une fois le descripteur ferme, juste apres `.ferme(raison)` :
    /// a la fin du flux, le port peut etre rouvert (sinon TIOCEXCL le refuse).
    func ouvrir() throws -> AsyncStream<EvenementLiaison> {
        let fd = try PortSerie.ouvrir(chemin)
        let (flux, suite) = AsyncStream.makeStream(of: EvenementLiaison.self, bufferingPolicy: .unbounded)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: file)
        source.setEventHandler { [weak self] in self?.lire() }
        source.setCancelHandler { [weak self] in
            // DTR et RTS sont deja a 0 et HUPCL est retire : fermer ne change rien aux lignes.
            close(fd)
            // Le port est libre : la fermeture et sa raison, puis la fin du flux.
            let raison = self?.etat.withLock { $0.raison } ?? String(localized: "port fermé par l'app")
            suite.yield(.ferme(raison))
            suite.finish()
        }
        etat.withLock { e in
            e.fd = fd
            e.source = source
            e.suite = suite
            e.raison = nil
        }
        suite.onTermination = { [weak self] _ in self?.fermer() }
        source.resume()
        return flux
    }

    /// Sur la file serie : tout ce qui est disponible.
    private func lire() {
        let fd = etat.withLock { $0.fd }
        guard fd >= 0 else { return }
        var tampon = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = tampon.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                let donnees = Data(tampon[0..<n])
                _ = etat.withLock { $0.suite?.yield(.donnees(donnees)) }
                continue
            }
            if n == 0 {
                terminer(String(localized: "port fermé (EOF) : la sonde a peut-être redémarré"))
                return
            }
            let code = errno
            if code == EAGAIN || code == EWOULDBLOCK { return }
            if code == EINTR { continue }
            terminer(String(localized: "lecture impossible : \(String(cString: strerror(code)))"))
            return
        }
    }

    func envoyer(_ donnees: Data) {
        file.async { [weak self] in self?.ecrire(donnees) }
    }

    /// Sur la file serie. Quelques essais si le tampon est plein.
    private func ecrire(_ donnees: Data) {
        let fd = etat.withLock { $0.fd }
        guard fd >= 0 else { return }
        var reste = donnees[...]
        var essais = 0
        while !reste.isEmpty {
            let n = reste.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if n > 0 {
                reste = reste.dropFirst(n)
                continue
            }
            let code = errno
            if n < 0, code == EAGAIN || code == EINTR, essais < 50 {
                essais += 1
                usleep(2000)
                continue
            }
            terminer(String(localized: "écriture impossible : \(String(cString: strerror(code)))"))
            return
        }
    }

    /// Sur la file serie. Sans effet si la liaison n'est pas ouverte ou deja en
    /// train de se fermer (la premiere raison est gardee). Le gestionnaire
    /// d'annulation de la source ferme le descripteur, puis emet `.ferme` et finit le flux.
    private func terminer(_ raison: String) {
        let source = etat.withLock { e -> (any DispatchSourceRead)? in
            guard let s = e.source else { return nil }
            e.source = nil
            e.suite = nil
            e.fd = -1
            e.raison = raison
            return s
        }
        source?.cancel()
    }

    /// Ferme le port sans attendre ; la fin du flux dit quand c'est fait.
    func fermer() {
        file.async { [weak self] in self?.terminer(String(localized: "port fermé par l'app")) }
    }
}
