import Foundation
import Network
import dnssd

/// Ecoute Bonjour d'un type de service (NWBrowser, avec les TXT) : garde la
/// liste des instances vues et le TXT brut de chacune.
@MainActor
final class NavigateurBonjour {
    enum Etat: Equatable, Sendable {
        case demarrage, pret, refuse
        case erreur(String)
    }

    let type: String
    /// Instance -> TXT brut (vide si le navigateur n'en a pas donne).
    private(set) var instances: [String: Data] = [:]
    private(set) var etat: Etat = .demarrage
    /// Appele sur le fil principal a chaque changement d'instances ou d'etat.
    var surChangement: (() -> Void)?
    private var navigateur: NWBrowser?

    init(type: String) {
        self.type = type
    }

    func demarrer() {
        let n = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: "local."), using: NWParameters())
        n.stateUpdateHandler = { [weak self] etat in
            MainActor.assumeIsolated { self?.changerEtat(etat) }
        }
        n.browseResultsChangedHandler = { [weak self] resultats, _ in
            MainActor.assumeIsolated { self?.noter(resultats) }
        }
        navigateur = n
        n.start(queue: .main)
    }

    func arreter() {
        navigateur?.cancel()
        navigateur = nil
    }

    private func noter(_ resultats: Set<NWBrowser.Result>) {
        var vus: [String: Data] = [:]
        for r in resultats {
            // Un meme service est vu une fois par interface (en0, en18...) : une seule entree.
            guard case let .service(nom, _, _, _) = r.endpoint else { continue }
            var txt = Data()
            if case let .bonjour(enregistrement) = r.metadata { txt = enregistrement.data }
            if vus[nom]?.isEmpty ?? true { vus[nom] = txt }
        }
        guard vus != instances else { return }
        instances = vus
        surChangement?()
    }

    private func changerEtat(_ e: NWBrowser.State) {
        let nouveau: Etat
        switch e {
        case .setup, .cancelled: nouveau = .demarrage
        case .ready: nouveau = .pret
        case .waiting(let erreur), .failed(let erreur): nouveau = Self.etat(erreur)
        @unknown default: nouveau = .demarrage
        }
        if case .failed = e {
            // Relance dans 10 s (le reseau revient souvent seul).
            arreter()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(10))
                self?.demarrer()
            }
        }
        guard nouveau != etat else { return }
        etat = nouveau
        surChangement?()
    }

    /// Refus du reseau local : le navigateur attend avec l'erreur DNS PolicyDenied.
    static func etat(_ erreur: NWError) -> Etat {
        if case .dns(let code) = erreur, code == DNSServiceErrorType(kDNSServiceErr_PolicyDenied) { return .refuse }
        return .erreur(erreur.debugDescription)
    }
}
