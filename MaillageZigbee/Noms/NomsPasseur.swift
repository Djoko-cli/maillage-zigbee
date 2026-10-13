import AppKit
import Foundation
import MaillageCoeur
import Observation

/// Les noms de Maison, servis en continu par le demon Passeur Noms (installe par Maillage Thread ; generique, il sert
/// toute app qui l'abonne) et gardes dans le conteneur de l'app (`releve-maison.json`). Au lancement, l'app s'abonne :
/// une ecoute sur 127.0.0.1 (`AbonnementPasseur`), un jeton a usage unique et l'URL
/// `maillage-passeur://abonner?port=<port>&jeton=<jeton>`, ouverte sans activation. Le demon envoie `etat` et `releve`
/// a la connexion, puis a chaque changement dans Maison ; l'app lui envoie `relire`, `identifier` et
/// `ouvertureSession`. Connexion perdue, ou aucun demon dans le delai : nouvel abonnement apres 5 s, 10 s, 30 s, puis
/// toutes les minutes. Repris de `NomsInternes` de Maillage Thread 1.3.0 (spec du demon, 12/10/2026, section 4.2).
/// Le dernier releve reussi est garde : un echec ne l'efface jamais, il se dit dans `probleme`. Sans demon, l'app
/// marche avec les seuls noms du pont Hue.
@MainActor
@Observable
final class NomsPasseur {
    /// Ouvre le demon avec cette cible (son URL) ; nil s'il est ouvert, sinon pourquoi il ne l'est pas.
    typealias Lanceur = @MainActor (_ cible: EnvoiPasseur.Cible) async -> EchecLancement?

    /// Le demon n'a pas ete ouvert.
    enum EchecLancement: Equatable {
        /// Aucune app n'ouvre le schema du protocole : pas de demon sur ce Mac ; `ancien` : une app porte pourtant
        /// l'identifiant du passeur (l'ancienne app iOS « concue pour iPad », qui ne connait pas `abonner`).
        case introuvable(ancien: Bool)
        /// Le demon ne tourne toujours pas 10 s apres son lancement.
        case neDemarrePas
        /// macOS ne l'a pas ouvert : la cause.
        case refuse(String)
    }

    /// Resultat d'une identification, montre quelques secondes dans la fiche de l'appareil.
    struct Identification: Equatable {
        /// L'`id` de l'accessoire de Maison.
        var accessoire: String
        var texte: String
    }

    /// Ce que fait le lanceur selon que le demon tourne deja ou non.
    enum PlanLancement: Equatable {
        /// Il tourne : l'URL est envoyee directement.
        case urlSeule
        /// Il ne tourne pas : le lancer SANS URL, attendre qu'il tourne, puis envoyer l'URL.
        case lancerPuisURL
    }

    nonisolated static let fichier = "releve-maison.json"
    /// Identifiant du demon (celui de l'ancien Passeur aussi).
    nonisolated static let idPasseur = "fr.djoko.maillage.passeur"
    /// Premiere attente d'un demon, et garde de `relire` : le temps d'une demande d'acces a Maison. Les textes
    /// (`texte(delai:)`) disent "2 minutes" en dur : a changer avec cette valeur (le catalogue aussi).
    nonisolated static let delaiParDefaut: Duration = .seconds(120)
    /// Attentes avant de se reabonner ; la derniere se repete.
    nonisolated static let reabonnements: [Duration] = [.seconds(5), .seconds(10), .seconds(30), .seconds(60)]
    /// Avertissement avant l'expiration du profil du demon.
    nonisolated static let preavisProfil: TimeInterval = 30 * 24 * 3600
    /// Duree d'affichage du resultat d'une identification.
    nonisolated static let dureeIdentification: Duration = .seconds(4)
    /// Pause apres le lancement sans URL du demon : le temps que HomeKit se stabilise (banc de Maillage Thread du
    /// 13/10 : maisons livrees en 0,2 s).
    nonisolated static let attenteDemarrage: Duration = .milliseconds(1500)
    /// Attente du demarrage du demon, lance sans URL : 100 essais de 100 ms.
    nonisolated static let essaisDemarrage = 100

    /// Dernier releve reussi.
    private(set) var releve: ReleveMaison?
    /// Dernier probleme : demon introuvable ou ancien, lancement refuse, aucun demon dans le delai, connexion perdue,
    /// releve refuse ou illisible, acces a Maison refuse, ecriture impossible.
    private(set) var probleme: String?
    /// Le dernier lancement n'a pas trouve le demon (ou seulement l'ancien Passeur) : les Reglages disent comment
    /// l'installer.
    private(set) var passeurAbsent = false
    /// Le demon est connecte (jeton accepte).
    private(set) var connecte = false
    /// Dernier `etat` du demon ; garde apres une deconnexion, mais les Reglages ne le lisent que connecte.
    private(set) var etat: EtatPasseur?
    /// `relire` envoye, releve pas encore recu.
    private(set) var releveEnCours = false
    /// Derniere reponse a « Identifier », effacee apres `dureeIdentification`.
    private(set) var identification: Identification?
    /// Echecs d'abonnement depuis la derniere connexion : choisit l'attente suivante.
    private(set) var tentative = 0
    /// Mode demo, ou tests : aucun abonnement, releve ni fichier lu ou ecrit.
    let inerte: Bool
    /// Appele a chaque changement du releve retenu.
    @ObservationIgnored var surReleve: ((ReleveMaison?) -> Void)?

    @ObservationIgnored private let cache: URL?
    @ObservationIgnored private let delai: Duration
    @ObservationIgnored private let attentes: [Duration]
    @ObservationIgnored private let lanceur: Lanceur
    @ObservationIgnored private var abonnement: AbonnementPasseur?
    @ObservationIgnored private var minuterie: Task<Void, Never>?
    @ObservationIgnored private var reprise: Task<Void, Never>?
    @ObservationIgnored private var effacement: Task<Void, Never>?
    /// Garde de `relire` : libere `releveEnCours` si le demon ne repond pas dans le delai.
    @ObservationIgnored private var gardeReleve: Task<Void, Never>?
    /// Numero de la derniere demande d'identification, et son accessoire.
    @ObservationIgnored private var demande = 0
    @ObservationIgnored private var enIdentification: String?

    /// `cache` : le `releve-maison.json` de l'app. `lanceur` : `lancerPasseurDuMac` pour l'app, un faux dans les
    /// tests. Il n'a pas de valeur par defaut : un test qui l'oublierait lancerait le vrai demon.
    init(cache: URL, delai: Duration = NomsPasseur.delaiParDefaut, attentes: [Duration] = NomsPasseur.reabonnements,
         lanceur: @escaping Lanceur) {
        self.cache = cache
        self.delai = delai
        self.attentes = attentes.isEmpty ? NomsPasseur.reabonnements : attentes
        self.lanceur = lanceur
        inerte = false
        releve = try? ReleveMaison.lire(Data(contentsOf: cache))
    }

    /// Inerte (demo, tests) : le releve donne, aucun abonnement, rien de lu ni d'ecrit ; jamais de demon lance.
    init(demo releve: ReleveMaison? = nil) {
        cache = nil
        delai = Self.delaiParDefaut
        attentes = Self.reabonnements
        lanceur = { _ in .introuvable(ancien: false) }
        inerte = true
        self.releve = releve
    }

    /// `releve-maison.json` dans le dossier de l'app, a cote de `noms-pont.json`.
    static func fichierCache(dossier: URL) -> URL {
        dossier.appendingPathComponent(fichier)
    }

    /// Donne le releve garde et s'abonne au demon.
    func demarrer() {
        surReleve?(releve)
        abonner()
    }

    /// Ouvre l'ecoute, puis l'URL `abonner` avec son port et un jeton neuf. Un abonnement a la fois ; jamais inerte.
    func abonner() {
        guard !inerte, cache != nil, abonnement == nil else { return }
        reprise?.cancel()
        reprise = nil
        let a = AbonnementPasseur(jeton: EnvoiPasseur.nouveauJeton())
        abonnement = a
        minuterie = Task { [weak self, delai] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            // Sans NomsPasseur, personne ne finira cet abonnement : on ferme l'ecoute.
            guard let self else {
                a.fermer()
                return
            }
            // "2 minutes" : `delaiParDefaut` (120 s), en dur dans le texte.
            self.finir(a, probleme: String(localized: "Passeur Noms ne s'est pas connecté en 2 minutes."))
        }
        a.ouvrir { [weak self] e in self?.surAbonnement(a, e) }
    }

    /// « Rafraichir depuis Maison » : `relire` au demon connecte (releve et batteries) ; sans demon, un nouvel
    /// abonnement tout de suite.
    func relire() {
        guard !inerte, cache != nil else { return }
        if connecte, let a = abonnement {
            releveEnCours = true
            a.envoyer(.relire)
            // Un demon connecte qui ne repond jamais ne laisse pas le bouton grise pour toujours.
            gardeReleve?.cancel()
            gardeReleve = Task { [weak self, delai] in
                try? await Task.sleep(for: delai)
                guard !Task.isCancelled, let self, self.releveEnCours else { return }
                self.releveEnCours = false
                self.probleme = String(localized: "Passeur Noms n'a pas répondu à la demande de relevé.")
            }
        } else if abonnement == nil {
            tentative = 0
            abonner()
        }
    }

    /// « Identifier » par Maison : le demon appelle `identify()` sur cet accessoire de Maison (son `id`).
    func identifier(accessoire id: String) {
        guard connecte, let a = abonnement else { return }
        demande += 1
        enIdentification = id
        a.envoyer(.identifier(demande: demande, accessoire: id))
    }

    /// L'interrupteur des Reglages : inscrit ou desinscrit le demon a l'ouverture de session.
    func reglerOuvertureSession(_ actif: Bool) {
        guard connecte, let a = abonnement else { return }
        a.envoyer(.ouvertureSession(actif: actif))
    }

    private func surAbonnement(_ a: AbonnementPasseur, _ e: AbonnementPasseur.Evenement) {
        guard abonnement === a else { return }
        switch e {
        case .prete(let port):
            let cible = EnvoiPasseur.Cible(port: port, jeton: a.jeton, demande: .abonner)
            Task { [weak self] in
                guard let self, let echec = await self.lanceur(cible) else { return }
                self.finir(a, probleme: Self.texte(echec), absent: echec.estAbsent)
            }
        case .connecte:
            minuterie?.cancel()
            minuterie = nil
            connecte = true
            tentative = 0
            probleme = nil
            passeurAbsent = false
        case .message(let m):
            recevoir(m)
        case .fin(let f):
            finir(a, probleme: Self.texte(f))
        }
    }

    private func recevoir(_ m: MessagePasseur) {
        switch m {
        case .etat(let e):
            etat = e
        case .releve(let json):
            releveEnCours = false
            gardeReleve?.cancel()
            gardeReleve = nil
            do {
                integrer(try ReleveMaison.lire(json))
            } catch {
                probleme = String(localized: "Relevé de Maison illisible : \(error.localizedDescription)")
            }
        case .identifie(let r):
            guard r.demande == demande, let id = enIdentification else { return }
            montrer(Identification(accessoire: id, texte: Self.texte(r)))
        case .relire, .identifier, .ouvertureSession:
            // Messages de l'app vers le demon : ignores dans l'autre sens.
            break
        }
    }

    /// Ferme l'abonnement, retient le probleme et planifie le suivant.
    private func finir(_ a: AbonnementPasseur, probleme p: String, absent: Bool = false) {
        guard abonnement === a else { return }
        abonnement = nil
        a.fermer()
        minuterie?.cancel()
        minuterie = nil
        gardeReleve?.cancel()
        gardeReleve = nil
        connecte = false
        releveEnCours = false
        probleme = p
        passeurAbsent = absent
        let attente = Self.attente(apres: tentative, dans: attentes)
        tentative += 1
        reprise = Task { [weak self] in
            try? await Task.sleep(for: attente)
            guard !Task.isCancelled else { return }
            self?.abonner()
        }
    }

    private func montrer(_ i: Identification) {
        identification = i
        effacement?.cancel()
        effacement = Task { [weak self] in
            try? await Task.sleep(for: Self.dureeIdentification)
            guard !Task.isCancelled else { return }
            self?.identification = nil
        }
    }

    /// Retient un releve recu : le releve s'il est reussi, sinon le probleme ; le releve retenu est ecrit dans le
    /// conteneur, d'un coup (ecriture atomique). Inerte : garde et transmis, jamais ecrit.
    func integrer(_ r: ReleveMaison) {
        let (garde, p) = Self.retenir(r, ancien: releve)
        probleme = p
        guard garde != releve else { return }
        releve = garde
        if let garde, let cache {
            do {
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try garde.donnees().write(to: cache, options: .atomic)
            } catch {
                probleme = error.localizedDescription
            }
        }
        surReleve?(garde)
    }

    // MARK: - Lancement du demon

    /// Lanceur reel : Passeur Noms, installe par Maillage Thread (outils/passeur.sh), ouvert sans activation, d'abord
    /// sans URL puis avec l'URL de la cible. Pas d'arguments de lancement : macOS retire ceux que passe une app du bac a
    /// sable.
    static func lancerPasseurDuMac(_ cible: EnvoiPasseur.Cible) async -> EchecLancement? {
        // Le demon se trouve par son schema `schemaProtocole`, jamais en lisant son paquet (le bac a sable l'interdit)
        // ni par son identifiant seul (LaunchServices garde des copies perimees) : banc de Maillage Thread du 13/10.
        let marque = URL(string: "\(EnvoiPasseur.schemaProtocole):")
        guard let url = marque.flatMap({ NSWorkspace.shared.urlForApplication(toOpen: $0) }) else {
            return .introuvable(ancien: NSWorkspace.shared.urlForApplication(withBundleIdentifier: idPasseur) != nil)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            // homed refuse un demon lance a froid PAR une URL : il coupe sa connexion XPC au premier sync (4097) et ne
            // livre jamais les maisons (banc du 13/10). On le lance donc d'abord SANS URL, on attend qu'il tourne et
            // que HomeKit se stabilise, puis on envoie l'URL. Seule compte la copie trouvee par le schema.
            let enMarche = {
                tourne(NSRunningApplication.runningApplications(withBundleIdentifier: idPasseur).map(\.bundleURL), copie: url)
            }
            if plan(demonTourne: enMarche()) == .lancerPuisURL {
                _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
                var essais = 0
                while !enMarche(), essais < essaisDemarrage {
                    try? await Task.sleep(for: .milliseconds(100))
                    essais += 1
                }
                // Toujours pas lance apres 10 s : envoyer l'URL a froid serait refuse par HomeKit.
                guard enMarche() else { return .neDemarrePas }
                try? await Task.sleep(for: attenteDemarrage)
            }
            _ = try await NSWorkspace.shared.open([cible.url], withApplicationAt: url, configuration: configuration)
            return nil
        } catch {
            return .refuse(error.localizedDescription)
        }
    }

    /// Une instance de CETTE copie du demon tourne (`bundleURL` des instances de l'identifiant du passeur) : une copie
    /// perimee qui tourne (ancien passeur iOS, autre chemin) ne fait pas de `copie` un demon deja lance.
    nonisolated static func tourne(_ instances: [URL?], copie: URL) -> Bool {
        instances.contains { $0?.standardizedFileURL == copie.standardizedFileURL }
    }

    nonisolated static func plan(demonTourne: Bool) -> PlanLancement {
        demonTourne ? .urlSeule : .lancerPuisURL
    }

    /// L'attente avant le prochain abonnement, apres `tentative` echecs.
    nonisolated static func attente(apres tentative: Int, dans attentes: [Duration]) -> Duration {
        attentes[min(max(tentative, 0), attentes.count - 1)]
    }

    // MARK: - Textes

    nonisolated static func texte(_ e: EchecLancement) -> String {
        switch e {
        case .introuvable(ancien: false):
            String(localized: "Passeur Noms n'est pas installé sur ce Mac : les noms viennent de l'app Hue.")
        case .introuvable(ancien: true):
            String(localized: "Passeur Noms est l'ancienne version : relance outils/passeur.sh de Maillage Thread.")
        case .neDemarrePas: String(localized: "Passeur Noms ne démarre pas : relance outils/passeur.sh.")
        // Cause la plus probable : le profil de developpement du demon a expire (un an).
        case .refuse(let cause): String(localized: "\(cause) (profil du passeur expiré ? relance outils/passeur.sh)")
        }
    }

    nonisolated static func texte(_ f: AbonnementPasseur.Fin) -> String {
        switch f {
        case .jetonFaux: String(localized: "Connexion de Passeur Noms refusée : jeton faux.")
        case .trameFausse: String(localized: "Message illisible de Passeur Noms : connexion fermée.")
        case .fermee: String(localized: "Passeur Noms s'est déconnecté.")
        case .interrompue: String(localized: "Connexion avec Passeur Noms coupée.")
        case .ecoute(let cause): String(localized: "Écoute de Passeur Noms impossible : \(cause)")
        }
    }

    nonisolated static func texte(_ r: ReponseIdentifier) -> String {
        if r.ok { return String(localized: "Identification demandée") }
        switch r.erreur {
        case ReponseIdentifier.inconnu?: return String(localized: "Accessoire introuvable dans Maison")
        case ReponseIdentifier.nonIdentifiable?: return String(localized: "Cet accessoire ne sait pas s'identifier")
        case let e?: return String(localized: "Identification impossible : \(e)")
        case nil: return String(localized: "Identification impossible")
        }
    }

    /// Reglages › Maison : l'etat du demon.
    nonisolated static func texteDemon(connecte: Bool, etat: EtatPasseur?) -> String {
        guard connecte, let e = etat else { return String(localized: "non connecté") }
        let acces = switch e.acces {
        case .autorise: String(localized: "accès à Maison autorisé")
        case .refuse: String(localized: "accès à Maison refusé")
        case .attente: String(localized: "accès à Maison en attente")
        }
        return String(localized: "connecté · version \(e.version) · \(acces)")
    }

    /// Le profil du demon expire dans 30 jours ou moins, ou a expire.
    nonisolated static func profilBientotExpire(_ e: EtatPasseur?, maintenant: Date) -> Bool {
        guard let fin = e?.profilExpire else { return false }
        return fin.timeIntervalSince(maintenant) <= preavisProfil
    }

    /// L'interrupteur d'ouverture de session : actif avec un demon connecte qui a donne son etat. (`indisponible`,
    /// `notFound` de SMAppService, est l'etat d'un demon jamais inscrit : l'inscription reste possible.)
    nonisolated static func interrupteurActif(connecte: Bool, etat: EtatPasseur?) -> Bool {
        connecte && etat != nil
    }

    /// Un releve reussi remplace l'ancien ; un echec le garde et dit pourquoi, avec les textes de l'app : le message du
    /// demon (en francais seulement) n'est que le detail d'une erreur.
    nonisolated static func retenir(_ nouveau: ReleveMaison, ancien: ReleveMaison?) -> (ReleveMaison?, String?) {
        switch nouveau.statut {
        case .ok: (nouveau, nil)
        case .refuse:
            (ancien, String(localized: "Accès à Maison refusé à Passeur Noms : Réglages Système › Confidentialité et sécurité › Maison."))
        case .indisponible: (ancien, String(localized: "Maison indisponible pour Passeur Noms."))
        case .erreur:
            (ancien, nouveau.message.map { String(localized: "Passeur Noms a échoué : \($0)") }
                ?? String(localized: "Passeur Noms a échoué."))
        }
    }
}

extension NomsPasseur.EchecLancement {
    /// Pas de demon utilisable sur ce Mac : les Reglages disent comment l'installer.
    var estAbsent: Bool {
        if case .introuvable = self { true } else { false }
    }
}
