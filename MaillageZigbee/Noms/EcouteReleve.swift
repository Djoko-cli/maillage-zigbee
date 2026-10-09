import Foundation
import MaillageCoeur
import Network

/// Ecoute TCP d'un releve du passeur, sur 127.0.0.1 seulement et sur un port choisi par le
/// systeme (Network.framework, comme le reste de l'app). La premiere connexion est la seule
/// acceptee : l'ecoute se ferme aussitot. Sa trame est lue au fil de l'eau
/// (`EnvoiPasseur.Lecture`, au plus 8 Mo de JSON), puis la connexion est fermee : le passeur,
/// qui attend cette fermeture, sait alors que tout a ete lu. Une connexion coupee par une erreur
/// avant la fin de la trame finit par `.interrompu`. Tout se passe sur la file principale.
/// Le bac a sable de l'app exige `com.apple.security.network.server` pour ecouter, meme sur
/// la boucle locale.
@MainActor
final class EcouteReleve {
    enum Evenement: Equatable {
        /// L'ecoute est prete sur ce port : lancer le passeur.
        case prete(UInt16)
        /// Le releve est fini, recu ou non ; l'ecoute et la connexion sont fermees.
        case fin(NomsPasseur.Fin)
    }

    /// Jeton attendu du passeur, a usage unique.
    let jeton: String
    private var lecture: EnvoiPasseur.Lecture
    private var ecouteur: NWListener?
    private var connexion: NWConnection?
    private var suite: ((Evenement) -> Void)?
    private var pret = false

    init(jeton: String) {
        self.jeton = jeton
        lecture = EnvoiPasseur.Lecture(jeton: jeton)
    }

    /// Ouvre l'ecoute ; `suite` recoit `.prete`, puis `.fin`, sauf apres `fermer()`.
    func ouvrir(_ suite: @escaping (Evenement) -> Void) {
        self.suite = suite
        let parametres = NWParameters.tcp
        parametres.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let ecouteur: NWListener
        do {
            ecouteur = try NWListener(using: parametres)
        } catch {
            terminer(.ecoute(error.localizedDescription))
            return
        }
        self.ecouteur = ecouteur
        ecouteur.stateUpdateHandler = { [weak self] etat in
            MainActor.assumeIsolated { self?.changement(etat) }
        }
        ecouteur.newConnectionHandler = { [weak self] c in
            MainActor.assumeIsolated { self?.accepter(c) }
        }
        ecouteur.start(queue: .main)
    }

    /// Ferme l'ecoute et la connexion ; plus aucun evenement.
    func fermer() {
        suite = nil
        ecouteur?.cancel()
        ecouteur = nil
        connexion?.cancel()
        connexion = nil
    }

    private func changement(_ etat: NWListener.State) {
        switch etat {
        case .ready:
            guard !pret else { return }
            guard let port = ecouteur?.port?.rawValue else {
                terminer(.ecoute(String(localized: "port inconnu")))
                return
            }
            pret = true
            suite?(.prete(port))
        case .waiting(let e), .failed(let e):
            terminer(.ecoute(e.localizedDescription))
        default:
            break
        }
    }

    /// Une seule connexion par releve : l'ecoute se ferme des la premiere.
    private func accepter(_ c: NWConnection) {
        guard connexion == nil, suite != nil else {
            c.cancel()
            return
        }
        ecouteur?.cancel()
        ecouteur = nil
        connexion = c
        c.start(queue: .main)
        recevoir(c)
    }

    private func recevoir(_ c: NWConnection) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] donnees, _, finie, erreur in
            MainActor.assumeIsolated {
                guard let self, self.connexion === c else { return }
                var issue = EnvoiPasseur.Lecture.Issue.incomplete
                if let donnees, !donnees.isEmpty { issue = self.lecture.ajouter(donnees) }
                // Une erreur avant la fin de la trame : la connexion a ete coupee, la trame n'est
                // pas en cause. Une fin propre sans trame complete, elle, est une trame fausse.
                if issue == .incomplete, erreur != nil {
                    self.terminer(.interrompu)
                    return
                }
                if issue == .incomplete, finie { issue = self.lecture.fin() }
                switch issue {
                case .incomplete: self.recevoir(c)
                case .json(let json): self.terminer(.recu(json))
                case .jetonFaux: self.terminer(.jetonFaux)
                case .longueurFausse: self.terminer(.longueurFausse)
                }
            }
        }
    }

    private func terminer(_ fin: NomsPasseur.Fin) {
        guard let suite else { return }
        fermer()
        suite(.fin(fin))
    }
}
