import Foundation
import MaillageCoeur
import Network

/// Abonnement de l'app au demon Passeur Noms (spec du 12/10, sections 2 et 4.1) : une ecoute TCP sur 127.0.0.1
/// seulement, sur un port choisi par le systeme ; la premiere connexion est la seule acceptee (l'ecoute se ferme
/// aussitot). Le demon y ecrit le jeton (compare a temps constant), puis les deux cotes echangent des trames
/// (`EnvoiPasseur.LectureFlux`, `MessagePasseur`) ; un type inconnu est ignore, une trame mal formee ferme tout. Tout
/// sur la file principale. Le bac a sable de l'app exige `com.apple.security.network.server` pour ecouter.
@MainActor
final class AbonnementPasseur {
    enum Evenement: Equatable {
        /// L'ecoute est prete sur ce port : ouvrir l'URL `abonner`.
        case prete(UInt16)
        /// Le demon est connecte, son jeton accepte.
        case connecte
        case message(MessagePasseur)
        /// L'abonnement est fini ; l'ecoute et la connexion sont fermees.
        case fin(Fin)
    }

    enum Fin: Equatable {
        /// Premiere ligne autre que le jeton, ou connexion fermee avant sa fin.
        case jetonFaux
        /// Longueur illisible ou trop grande, ou JSON illisible.
        case trameFausse
        /// Le demon a ferme la connexion.
        case fermee
        /// Connexion coupee par une erreur.
        case interrompue
        /// Ecoute impossible : la cause.
        case ecoute(String)
    }

    /// Jeton attendu du demon, a usage unique.
    let jeton: String
    private var lecture: EnvoiPasseur.LectureFlux
    private var ecouteur: NWListener?
    private var connexion: NWConnection?
    private var suite: ((Evenement) -> Void)?
    private var pret = false
    private var connecte = false

    init(jeton: String) {
        self.jeton = jeton
        lecture = EnvoiPasseur.LectureFlux(jeton: jeton)
    }

    /// Ouvre l'ecoute ; `suite` recoit `.prete`, puis `.connecte`, les messages et `.fin`, sauf apres `fermer()`.
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

    /// Envoie un message au demon connecte ; ignore avant la connexion.
    func envoyer(_ m: MessagePasseur) {
        guard connecte, let c = connexion else { return }
        c.send(content: EnvoiPasseur.trame(m), completion: .contentProcessed { [weak self] erreur in
            guard erreur != nil else { return }
            MainActor.assumeIsolated { self?.terminer(.interrompue) }
        })
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

    /// Une seule connexion : l'ecoute se ferme des la premiere.
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
                if let donnees, !donnees.isEmpty {
                    let issue = self.lecture.ajouter(donnees)
                    if !self.connecte, self.lecture.jetonAccepte {
                        self.connecte = true
                        self.suite?(.connecte)
                    }
                    for json in issue.trames {
                        // Un message a pu fermer l'abonnement.
                        guard self.connexion === c else { return }
                        switch MessagePasseur.lire(json) {
                        case .message(let m): self.suite?(.message(m))
                        case .ignore: break
                        case .illisible:
                            self.terminer(.trameFausse)
                            return
                        }
                    }
                    switch issue.erreur {
                    case .jetonFaux?:
                        self.terminer(.jetonFaux)
                        return
                    case .trameFausse?:
                        self.terminer(.trameFausse)
                        return
                    case nil:
                        break
                    }
                }
                if erreur != nil {
                    self.terminer(.interrompue)
                    return
                }
                if finie {
                    self.terminer(self.connecte ? .fermee : .jetonFaux)
                    return
                }
                self.recevoir(c)
            }
        }
    }

    private func terminer(_ fin: Fin) {
        guard let suite else { return }
        fermer()
        suite(.fin(fin))
    }
}
