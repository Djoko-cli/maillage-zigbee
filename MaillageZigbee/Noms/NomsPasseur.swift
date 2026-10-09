import AppKit
import Foundation
import MaillageCoeur
import Observation

/// Les noms de Maison, releves par le Passeur (Passeur Noms : l'app iOS « concue pour iPad » que Maillage Thread
/// installe sur le Mac ; generique, elle sert toute app qui l'ouvre) et gardes dans le conteneur de l'app
/// (`releve-maison.json`). Un releve : une ecoute TCP sur 127.0.0.1 (`EcouteReleve`) et un jeton a usage unique ; le
/// Passeur, ouvert sans activation avec l'URL `maillage-passeur://releve?port=<port>&jeton=<jeton>`, lit Maison, envoie
/// le releve (`EnvoiPasseur`) et se ferme. Repris de `NomsInternes` de Maillage Thread 1.1.0.
/// Le dernier releve reussi est garde : un echec ne l'efface jamais, il se dit dans `probleme`. Sans Passeur, l'app
/// marche avec les seuls noms du pont Hue.
@MainActor
@Observable
final class NomsPasseur {
    /// Ouvre le Passeur avec cette cible (son URL) ; nil s'il est ouvert, sinon pourquoi il ne l'est pas.
    typealias Lanceur = @MainActor (_ cible: EnvoiPasseur.Cible) async -> EchecLancement?

    /// Le Passeur n'a pas ete ouvert.
    enum EchecLancement: Equatable {
        /// Il n'est pas installe sur ce Mac.
        case introuvable
        /// macOS ne l'a pas ouvert : la cause.
        case refuse(String)
    }

    /// Fin d'un releve.
    enum Fin: Equatable {
        /// Le JSON du Passeur, de la longueur annoncee, a decoder.
        case recu(Data)
        case jetonFaux
        case longueurFausse
        /// Connexion coupee par une erreur avant la fin de la trame : la trame n'est pas en cause.
        case interrompu
        /// Aucun releve dans le delai.
        case delai
        /// Passeur introuvable ou lancement refuse.
        case lancement(EchecLancement)
        /// Ecoute impossible : la cause.
        case ecoute(String)
    }

    nonisolated static let fichier = "releve-maison.json"
    /// Identifiant du Passeur (celui de Maillage Thread).
    nonisolated static let idPasseur = "fr.djoko.maillage.passeur"
    /// Profil gratuit du Passeur : 7 jours ; au-dela, il faut le recompiler.
    nonisolated static let validite: TimeInterval = 7 * 24 * 3600
    /// Au lancement, un releve de moins d'un jour suffit : le Passeur n'est pas relance.
    nonisolated static let fraicheur: TimeInterval = 24 * 3600
    /// Attente d'un releve : le premier lancement attend la reponse a la demande d'acces a Maison.
    /// Le texte du delai (`finir`, cas `.delai`) dit "2 minutes" en dur : a changer avec cette valeur.
    nonisolated static let delaiParDefaut: Duration = .seconds(120)

    /// Dernier releve reussi.
    private(set) var releve: ReleveMaison?
    /// Dernier probleme : releve refuse, illisible ou interrompu, rien dans le delai, Passeur introuvable ou qui ne se
    /// lance pas, acces a Maison refuse, ecriture impossible.
    private(set) var probleme: String?
    /// Le dernier lancement n'a pas trouve le Passeur : les Reglages disent comment l'installer.
    private(set) var passeurAbsent = false
    /// Une ecoute est ouverte : le Passeur est lance, ou va l'etre.
    private(set) var releveEnCours = false
    /// Mode demo, ou tests : aucun releve demande, lu ni ecrit.
    let inerte: Bool
    /// Appele a chaque changement du releve retenu.
    @ObservationIgnored var surReleve: ((ReleveMaison?) -> Void)?
    /// Derniere demande de releve.
    @ObservationIgnored private(set) var derniereDemande: Date?

    @ObservationIgnored private let cache: URL?
    @ObservationIgnored private let delai: Duration
    @ObservationIgnored private let lanceur: Lanceur
    @ObservationIgnored private var ecoute: EcouteReleve?
    @ObservationIgnored private var minuterie: Task<Void, Never>?

    /// `cache` : le `releve-maison.json` de l'app. `lanceur` : `lancerPasseurDuMac` pour l'app, un faux dans les
    /// tests. Il n'a pas de valeur par defaut : un test qui l'oublierait lancerait le vrai Passeur.
    init(cache: URL, delai: Duration = NomsPasseur.delaiParDefaut, lanceur: @escaping Lanceur) {
        self.cache = cache
        self.delai = delai
        self.lanceur = lanceur
        inerte = false
        releve = try? ReleveMaison.lire(Data(contentsOf: cache))
    }

    /// Inerte (demo, tests) : le releve donne, aucun releve demande, lu ni ecrit ; jamais de Passeur lance.
    init(demo releve: ReleveMaison? = nil) {
        cache = nil
        delai = Self.delaiParDefaut
        lanceur = { _ in .introuvable }
        inerte = true
        self.releve = releve
    }

    /// `releve-maison.json` dans le dossier de l'app, a cote de `noms-pont.json`.
    static func fichierCache(dossier: URL) -> URL {
        dossier.appendingPathComponent(fichier)
    }

    /// Donne le releve garde.
    func demarrer() {
        surReleve?(releve)
    }

    /// « Rafraichir depuis Maison » : ouvre l'ecoute, puis lance le Passeur avec son port et un jeton neuf. Une seule
    /// ecoute a la fois : une demande pendant un releve est ignoree. Jamais inerte.
    func rafraichir() {
        guard !inerte, cache != nil, ecoute == nil else { return }
        derniereDemande = .now
        let e = EcouteReleve(jeton: EnvoiPasseur.nouveauJeton())
        ecoute = e
        releveEnCours = true
        minuterie = Task { [weak self, delai] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled else { return }
            // Sans NomsPasseur, personne ne finira ce releve : on ferme l'ecoute, que seul `fermer()` libere (la
            // fermeture donnee a `ouvrir` la retient, et elle la garde).
            guard let self else { e.fermer(); return }
            self.finir(e, .delai)
        }
        e.ouvrir { [weak self] evenement in
            self?.surEcoute(e, evenement)
        }
    }

    /// Au lancement : relance le Passeur si le releve garde a plus d'un jour (ou s'il n'y en a pas). Jamais inerte.
    func rafraichirSiAncien(maintenant: Date = .now) {
        guard !inerte, Self.aRafraichir(releve: releve?.date, demande: derniereDemande, maintenant: maintenant) else {
            return
        }
        rafraichir()
    }

    private func surEcoute(_ e: EcouteReleve, _ evenement: EcouteReleve.Evenement) {
        guard ecoute === e else { return }
        switch evenement {
        case .prete(let port):
            let cible = EnvoiPasseur.Cible(port: port, jeton: e.jeton)
            Task { [weak self] in
                guard let self, let echec = await self.lanceur(cible) else { return }
                self.finir(e, .lancement(echec))
            }
        case .fin(let fin):
            finir(e, fin)
        }
    }

    /// Ferme l'ecoute et retient l'issue du releve (sauf s'il est deja fini).
    private func finir(_ e: EcouteReleve, _ fin: Fin) {
        guard ecoute === e else { return }
        ecoute = nil
        e.fermer()
        minuterie?.cancel()
        minuterie = nil
        releveEnCours = false
        if case .lancement(.introuvable) = fin { passeurAbsent = true } else { passeurAbsent = false }
        switch fin {
        case .recu(let json):
            do {
                integrer(try ReleveMaison.lire(json))
            } catch {
                probleme = String(localized: "Relevé de Maison illisible : \(error.localizedDescription)")
            }
        case .jetonFaux: probleme = String(localized: "Relevé de Maison refusé : jeton faux.")
        case .longueurFausse: probleme = String(localized: "Relevé de Maison illisible : longueur fausse.")
        case .interrompu:
            probleme = String(localized: "Relevé de Maison interrompu : la connexion avec Passeur Noms a été coupée.")
        // "2 minutes" : `delaiParDefaut` (120 s). Le texte est en dur, meme si `delai` se regle : les deux changent
        // ensemble (le catalogue aussi).
        case .delai: probleme = String(localized: "Passeur Noms n'a rien envoyé en 2 minutes.")
        case .lancement(.introuvable):
            probleme = String(localized: "Passeur Noms n'est pas installé sur ce Mac : les noms viennent de l'app Hue.")
        case .lancement(.refuse(let cause)):
            probleme = String(localized: "Passeur Noms ne s'est pas ouvert : \(cause) (profil de 7 jours expiré ?)")
        case .ecoute(let cause): probleme = String(localized: "Écoute du relevé impossible : \(cause)")
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

    /// Lanceur reel : Passeur Noms, installe par Maillage Thread, ouvert sans activation avec l'URL de la cible (port et
    /// jeton). Pas d'arguments de lancement : macOS retire ceux que passe une app du bac a sable.
    static func lancerPasseurDuMac(_ cible: EnvoiPasseur.Cible) async -> EchecLancement? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: idPasseur) else {
            return .introuvable
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        do {
            _ = try await NSWorkspace.shared.open([cible.url], withApplicationAt: url, configuration: configuration)
            return nil
        } catch {
            return .refuse(error.localizedDescription)
        }
    }

    /// Releve absent ou de plus d'un jour, et pas de demande dans le dernier jour : un Passeur qui ne se lance pas n'est
    /// pas relance en boucle.
    nonisolated static func aRafraichir(releve: Date?, demande: Date?, maintenant: Date) -> Bool {
        func ancien(_ d: Date?) -> Bool { d.map { maintenant.timeIntervalSince($0) > fraicheur } ?? true }
        return ancien(releve) && ancien(demande)
    }

    /// Un releve reussi remplace l'ancien ; un echec le garde et dit pourquoi, avec les textes de l'app : le message du
    /// Passeur (en francais seulement) n'est que le detail d'une erreur.
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

    /// Releve de plus de 7 jours : le profil gratuit du Passeur a pu expirer.
    nonisolated static func estAncien(_ r: ReleveMaison, maintenant: Date) -> Bool {
        maintenant.timeIntervalSince(r.date) > validite
    }
}
