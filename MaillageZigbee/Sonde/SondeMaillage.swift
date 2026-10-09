import Foundation
import MaillageCoeur
import Observation

/// La sonde vue par l'app : port retenu (par son numero de serie USB), connexion, verification (`bonjour` doit dire
/// `"produit":"sonde-zigbee"`), reprise quand elle est rebranchee, et la boucle des tournees (spec de l'app,
/// section 6) : la premiere ~10 s apres la connexion, puis toutes les 15 minutes, et au bouton Rafraichir. Chaque
/// tournee (`Tournee`) rend un `MaillageZigbee` a la surveillance (`surMaillage`). Quand une tournee a reporte des
/// routes faute de budget de pages, la passe complementaire (les routes reportees seulement) est lancee des que le
/// budget le permet (`MemoireTournee.instantPasseComplementaire`), sans attendre la tournee suivante ; le rythme de
/// 15 minutes reprend a sa fin.
/// Budget de pages : le journal des pages envoyees (10 dernieres minutes) est garde dans les preferences, donc d'un
/// lancement de l'app a l'autre ; une tournee dont les tables de voisins et les routes du pont ne tiennent pas dans la
/// marge restante (550 pages par 10 minutes, `MemoireTournee.instantProchaineTournee`) attend l'instant ou elles
/// tiennent (`tourneeDifferee`). Rafraichir n'outrepasse pas cette attente.
/// Securite des ports : l'app n'ouvre jamais un port qu'on ne lui a pas designe (spec de la sonde, section 2) ; sur un
/// port ouvert, `bonjour` d'abord, et rien d'autre tant qu'il ne dit pas `"produit":"sonde-zigbee"`. Elle n'envoie
/// jamais `oubli`, `suspendre`, `reprendre`, `nom` ni `echecs`.
@MainActor
@Observable
final class SondeMaillage {
    enum Etat: Equatable {
        /// Aucune sonde choisie dans les Reglages.
        case sansSonde
        /// La sonde retenue n'est pas branchee.
        case absente
        case connexion
        case connectee(Bonjour)
        /// Le port choisi n'est pas une sonde, ou ne repond pas.
        case refusee(String)
        case erreur(String)
    }

    /// Numero de serie USB de la sonde retenue (l'adresse MAC du C6).
    static let cleSerie = "sondeSerieUSB"
    /// Nom de la sonde retenue, donne par la carte (`bonjour`).
    static let cleNom = "sondeNom"
    /// Journal des pages envoyees a la sonde dans les 10 dernieres minutes : `[instant, pages, instant, pages...]`
    /// (`BudgetPages.enregistrable`).
    static let cleJournalPages = "sondeJournalPages"
    /// Pages de la derniere lecture complete des tables de voisins (estime la suivante apres un relancement).
    static let clePagesTables = "sondePagesTables"
    /// Nouvel essai d'une connexion automatique en echec : une sonde qui demarre en plus de 3 s (bonjour sans reponse)
    /// n'attend pas l'evenement USB suivant.
    static let delaiNouvelEssai: Duration = .seconds(5)
    /// Premiere tournee apres la connexion : le temps que la sonde se rattache si elle vient de demarrer.
    static let delaiPremiereTournee: Duration = .seconds(10)
    /// Une tournee toutes les 15 minutes (spec de l'app, section 6).
    static let periodeTournees: Duration = .seconds(15 * 60)

    private(set) var etat: Etat = .sansSonde
    /// Ports Espressif branches (la sonde, ou un autre C6 comme le pont Halo).
    private(set) var ports: [PortUSB] = []
    private(set) var serie: String?
    /// Nom de la sonde (« SONDE-Z1 »), mis a jour a chaque `bonjour` ; nil sans sonde retenue.
    private(set) var nom: String?
    /// Numero de serie USB du port que l'etat concerne (connexion, connexion etablie, refus, erreur) ; nil sans sonde
    /// ou la sonde retenue absente.
    private(set) var serieEtat: String?
    /// Dernier `etat` de la sonde, lu a la connexion et a chaque tournee.
    private(set) var etatSonde: EtatSonde?
    /// Reception du dernier maillage (fin de sa tournee).
    private(set) var derniereTournee: Date?
    private(set) var tourneeEnCours = false
    /// Avancement de la tournee en cours ; nil hors tournee.
    private(set) var avancement: AvancementTournee?
    /// Debut de la tournee en cours ; nil hors tournee.
    private(set) var debutTournee: Date?
    /// Bilan et duree de la derniere tournee faite (Reglages › Sonde) ; nil avant la premiere.
    private(set) var bilan: BilanTournee?
    /// Heure de la passe complementaire programmee ; nil sans passe programmee (une seule a la fois).
    private(set) var passeComplementaire: Date?

    /// Une tournee qui attend que le budget de pages de la sonde le permette.
    struct TourneeDifferee: Equatable {
        /// L'instant ou elle partira.
        var instant: Date
        /// Elle lira les tables de voisins : une tournee complete.
        var complete: Bool
    }

    /// La tournee differee faute de budget de pages (la sonde a deja beaucoup servi) ; nil sans attente de ce genre.
    private(set) var tourneeDifferee: TourneeDifferee?
    private(set) var dureeTournee: TimeInterval?
    /// Derniere erreur de la sonde connectee (la liaison reste ouverte), ou pourquoi la tournee n'a pas eu lieu.
    private(set) var erreurTournee: String?
    /// Appele a chaque nouveau maillage, avec l'heure de sa reception (fin de la tournee).
    @ObservationIgnored var surMaillage: ((MaillageZigbee, Date) -> Void)?
    /// Appele au debut (vrai) et a la fin (faux) de chaque tournee.
    @ObservationIgnored var surTournee: ((Bool) -> Void)?
    /// Appele quand la sonde est oubliee : son maillage part du graphe.
    @ObservationIgnored var surOubli: (() -> Void)?

    @ObservationIgnored private let preferences: UserDefaults
    @ObservationIgnored private let actif: Bool
    @ObservationIgnored private let ouvrirCanal: (String) -> any CanalSonde
    @ObservationIgnored private let delaiNouvelEssai: Duration
    /// Nouvel essai planifie d'une connexion automatique en echec.
    @ObservationIgnored private var nouvelEssai: Task<Void, Never>?
    /// Heure des releves (injectee par les tests).
    @ObservationIgnored private let horloge: @Sendable () -> Date
    /// Pauses de la tournee (attente du retour de la sonde dans le reseau), injectees par les tests.
    @ObservationIgnored private let attendre: @Sendable (Duration) async throws -> Void
    /// Attente avant la prochaine tournee ou passe (injectee par les tests, avec `horloge`).
    @ObservationIgnored private let dormir: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private let delaiPremiereTournee: Duration
    @ObservationIgnored private let periodeTournees: Duration
    /// Echeance d'une table ou des routes (125 s ; les tests la raccourcissent).
    @ObservationIgnored private let delaiTable: Duration
    /// Ce que la tournee retient d'une fois sur l'autre (routeurs muets, tables, routes lues, budget de pages) ; remise a
    /// zero avec une autre sonde.
    @ObservationIgnored private var memoire = MemoireTournee()
    /// La prochaine tournee (attente comprise), et la tournee en cours.
    @ObservationIgnored private var boucle: Task<Void, Never>?
    @ObservationIgnored private var sonde: SondeUSB?
    /// Chemin du port de `sonde` (nil sans sonde connectee).
    @ObservationIgnored private var cheminConnecte: String?
    /// Liaison d'une connexion en cours, avant sa verification : `deconnecter` la ferme aussi.
    @ObservationIgnored private var enConnexion: SondeUSB?
    /// Numero d'essai, incremente par `deconnecter` : une connexion dont le numero a change est perimee et ne touche
    /// plus a rien.
    @ObservationIgnored private var essai = 0
    /// Fermetures lancees par `deconnecter`, chainees : une connexion attend qu'elles soient finies (ports vraiment
    /// fermes) avant d'ouvrir un port.
    @ObservationIgnored private var fermetures: Task<Void, Never>?
    @ObservationIgnored private var surveillantPorts: PortsUSB?

    /// `actif` faux (mode demo, tests) : ni port, ni preferences lues.
    init(preferences: UserDefaults = .standard, actif: Bool,
         ouvrirCanal: @escaping (String) -> any CanalSonde = { CanalSerie(liaison: LiaisonSerie(chemin: $0)) },
         delaiNouvelEssai: Duration = SondeMaillage.delaiNouvelEssai,
         delaiPremiereTournee: Duration = SondeMaillage.delaiPremiereTournee,
         periodeTournees: Duration = SondeMaillage.periodeTournees,
         delaiTable: Duration = ProtocoleSonde.echeanceTable,
         horloge: @escaping @Sendable () -> Date = { Date() },
         attendre: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         dormir: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.preferences = preferences
        self.actif = actif
        self.ouvrirCanal = ouvrirCanal
        self.delaiNouvelEssai = delaiNouvelEssai
        self.delaiPremiereTournee = delaiPremiereTournee
        self.periodeTournees = periodeTournees
        self.delaiTable = delaiTable
        self.horloge = horloge
        self.attendre = attendre
        self.dormir = dormir
        serie = actif ? preferences.string(forKey: Self.cleSerie) : nil
        nom = actif ? preferences.string(forKey: Self.cleNom) : nil
        memoire = nouvelleMemoire()
    }

    /// La memoire d'une tournee qui commence : vide, sauf le journal des pages envoyees dans les 10 dernieres minutes
    /// (et les pages des dernieres tables), relu des preferences. Ni preferences lues ni ecrites hors `actif`.
    private func nouvelleMemoire() -> MemoireTournee {
        guard actif else { return MemoireTournee() }
        var m = MemoireTournee()
        if let valeurs = preferences.object(forKey: Self.cleJournalPages) as? [Double] {
            m.budget = BudgetPages(enregistre: valeurs, a: horloge())
        }
        if let pages = preferences.object(forKey: Self.clePagesTables) as? Int, pages > 0 { m.pagesTables = pages }
        return m
    }

    /// Une requete de plus est revenue : le budget a jour va dans la memoire et dans les preferences, tout de suite (une
    /// app quittee en pleine tournee n'oublie pas ses pages).
    private func garderBudget(_ b: BudgetPages) {
        memoire.budget = b
        guard actif else { return }
        preferences.set(b.enregistrable(a: horloge()), forKey: Self.cleJournalPages)
    }

    /// Nom de la sonde retenue pour l'etat qui la concerne : absente, ou connexion, connexion etablie, refus ou erreur
    /// de son port ; nil pour un autre port choisi, ou sans sonde.
    var nomEtat: String? {
        switch etat {
        case .sansSonde: nil
        case .absente: nom
        case .connexion, .connectee, .refusee, .erreur: serie != nil && serieEtat == serie ? nom : nil
        }
    }

    /// `rafraichir` lancerait une tournee : sonde connectee, pas de tournee en cours.
    var tourneeAuRafraichir: Bool {
        if case .connectee = etat { !tourneeEnCours } else { false }
    }

    /// Nom montre pour la sonde : le sien, sinon « Sonde ».
    static func nomAffiche(_ nom: String?) -> String {
        nom ?? String(localized: "Sonde")
    }

    /// Suit les ports ; reprend la sonde retenue des qu'elle est branchee.
    func demarrer() {
        guard actif, surveillantPorts == nil else { return }
        let p = PortsUSB()
        p.changement = { [weak self] l in self?.portsChanges(l) }
        p.demarrer()
        surveillantPorts = p
        portsChanges(PortsUSB.lister())
    }

    /// Choix d'un port dans les Reglages : retenu seulement s'il repond en sonde. Le port de la sonde deja connectee
    /// n'est pas rouvert.
    func choisir(_ port: PortUSB) {
        guard actif, port.chemin != cheminConnecte else { return }
        lancerConnexion(port, choisi: true)
    }

    /// Oublie la sonde retenue (numero de serie, nom), son releve et son maillage dans le graphe (`surOubli`), et ferme
    /// la liaison.
    func oublier() async {
        preferences.removeObject(forKey: Self.cleSerie)
        serie = nil
        retenirNom(nil)
        oublierReleve()
        surOubli?()
        deconnecter(.sansSonde)
    }

    /// Nom donne par le dernier `bonjour` : retenu a cote du numero de serie, efface si le firmware n'en donne pas.
    private func retenirNom(_ n: String?) {
        if let n {
            preferences.set(n, forKey: Self.cleNom)
        } else {
            preferences.removeObject(forKey: Self.cleNom)
        }
        nom = n
    }

    /// Le releve de la sonde (etat, derniere tournee, bilan, memoire des muets) : il est a une autre sonde, ou a
    /// aucune.
    private func oublierReleve() {
        etatSonde = nil
        derniereTournee = nil
        erreurTournee = nil
        bilan = nil
        dureeTournee = nil
        passeComplementaire = nil
        tourneeDifferee = nil
        // Le journal des pages reste : c'est la sonde physique qui plafonne, pas le reseau lu.
        if actif { preferences.removeObject(forKey: Self.clePagesTables) }
        memoire = nouvelleMemoire()
    }

    /// Bouton Rafraichir : une tournee tout de suite (sonde connectee, pas de tournee en cours), qui s'y substitue la
    /// passe complementaire programmee (elle lit d'abord les routes reportees) ; la suivante 15 min apres sa fin, ou une
    /// nouvelle passe complementaire si elle a encore reporte des routes.
    func rafraichir() {
        guard tourneeAuRafraichir, sonde != nil else { return }
        planifierTournee(dans: .zero)
    }

    // MARK: - Tournee

    /// Planifie la prochaine tournee de la sonde connectee dans `delai` (la boucle : chaque tournee planifie la
    /// suivante), ou, avec `passeA`, la passe complementaire a cette heure (`delai` en est l'attente). Un seul plan a la
    /// fois : le nouveau remplace l'ancien, passe programmee comprise. Un `deconnecter` l'annule, tournee en cours
    /// comprise.
    private func planifierTournee(dans delai: Duration, passeA: Date? = nil) {
        boucle?.cancel()
        passeComplementaire = nil
        tourneeDifferee = nil
        guard let s = sonde else { return }
        let n = essai
        let complementaire = passeA != nil
        passeComplementaire = passeA
        boucle = Task { [weak self] in
            if delai > .zero { try? await self?.dormir(delai) }
            guard !Task.isCancelled, let self, n == self.essai, self.sonde === s else { return }
            self.passeComplementaire = nil
            // Une passe complementaire a son propre instant ; toute autre tournee attend que le budget le permette.
            if !complementaire, !(await self.attendreBudget(s, essai: n)) { return }
            let suite = await self.tourner(s, complementaire: complementaire)
            guard !Task.isCancelled, n == self.essai, self.sonde === s else { return }
            self.planifierSuite(passeSurReports: suite)
        }
    }

    /// Attend, si besoin, que le budget de pages couvre les tables de voisins (quand elles sont dues) et les routes du pont
    /// de la tournee qui va partir (`MemoireTournee.instantProchaineTournee`), en le montrant (`tourneeDifferee`).
    /// L'instant est recalcule apres chaque attente. Rend faux si le plan a ete annule ou remplace entre-temps.
    private func attendreBudget(_ s: SondeUSB, essai n: Int) async -> Bool {
        while let instant = memoire.instantProchaineTournee(a: horloge()) {
            let maintenant = horloge()
            tourneeDifferee = TourneeDifferee(instant: instant, complete: memoire.tablesDues)
            try? await dormir(.seconds(max(0, instant.timeIntervalSince(maintenant))))
            guard !Task.isCancelled, n == essai, sonde === s else { return false }
        }
        tourneeDifferee = nil
        return true
    }

    /// Ce qui suit une tournee finie : la passe complementaire si elle a reporte des routes (des que le budget le permet,
    /// au moins 30 s apres), sinon la tournee suivante 15 minutes apres sa fin. `passeSurReports` faux : la tournee n'a
    /// pas eu lieu, ou une passe complementaire n'a lu aucune route (rien ne dit qu'une autre y arriverait : pas
    /// d'emballement), donc le rythme normal.
    private func planifierSuite(passeSurReports: Bool) {
        let fin = horloge()
        guard passeSurReports, let instant = memoire.instantPasseComplementaire(apres: fin) else {
            planifierTournee(dans: periodeTournees)
            return
        }
        planifierTournee(dans: .seconds(max(0, instant.timeIntervalSince(fin))), passeA: instant)
    }

    /// Une tournee de la sonde `s` : son avancement, puis son maillage (s'il y en a un) a la surveillance, son bilan et
    /// l'etat lu de la sonde. Perimee (sonde deconnectee entre-temps), elle ne touche plus a rien.
    /// Rend vrai si une passe complementaire peut la suivre : la tournee a eu lieu, et, pour une passe, elle a lu des
    /// routes.
    private func tourner(_ s: SondeUSB, complementaire: Bool) async -> Bool {
        debuterTournee()
        guard tourneeEnCours else { return false }
        let debut = horloge()
        do {
            let r = try await Tournee.executer(s, memoire: memoire, complementaire: complementaire, horloge: horloge,
                                               attendre: attendre, avancement: { [weak self] a in self?.avancer(a) },
                                               surBudget: { [weak self] b in self?.garderBudget(b) })
            guard s === sonde else { return false }
            guard !Task.isCancelled else {
                finirTournee(nil)
                return false
            }
            memoire = r.memoire
            if actif {
                if let pages = r.memoire.pagesTables {
                    preferences.set(pages, forKey: Self.clePagesTables)
                }
                preferences.set(r.memoire.budget.enregistrable(a: horloge()), forKey: Self.cleJournalPages)
            }
            etatSonde = r.etat
            bilan = r.bilan
            dureeTournee = horloge().timeIntervalSince(debut)
            erreurTournee = Self.texteEmpechement(r.empechement) ?? r.bilan.lacune.map(Self.texteLacune)
            finirTournee(r.maillage)
            return r.empechement == nil && (!complementaire || r.bilan.routesRouteursDemandees > 0)
        } catch {
            guard s === sonde else { return false }
            if !(error is CancellationError) { erreurTournee = error.localizedDescription }
            finirTournee(nil)
            return false
        }
    }

    /// Pourquoi une tournee n'a pas eu lieu ; nil si elle a eu lieu.
    static func texteEmpechement(_ e: EmpechementTournee?) -> String? {
        switch e {
        case .horsReseau?: String(localized: "La sonde n'est pas dans le réseau : pas de tournée.")
        case .suspendue?: String(localized: "La sonde est suspendue : pas de tournée.")
        case nil: nil
        }
    }

    /// Tournee incomplete, d'apres la derniere raison de la sonde.
    static func texteLacune(_ raison: String) -> String {
        switch raison {
        case "non_membre": String(localized: "Tournée incomplète : la sonde a quitté le réseau.")
        case "cadence": String(localized: "Tournée incomplète : la sonde a atteint sa limite de requêtes.")
        case "sans_reponse": String(localized: "Tournée incomplète : la sonde n'a pas répondu.")
        case Tournee.lacuneSansTables: String(localized: "Tournée incomplète : tables de voisins pas encore lues.")
        default: String(localized: "Tournée incomplète : \(raison).")
        }
    }

    /// Debut d'une tournee : son heure, et `surTournee`. Sans sonde connectee, ou pendant une tournee, rien.
    func debuterTournee() {
        guard case .connectee = etat, !tourneeEnCours else { return }
        tourneeEnCours = true
        debutTournee = horloge()
        surTournee?(true)
    }

    /// Avancement de la tournee en cours ; rien hors tournee.
    func avancer(_ a: AvancementTournee) {
        guard tourneeEnCours else { return }
        avancement = a
    }

    /// Fin de la tournee en cours : son maillage, s'il y en a un, part a la surveillance avec l'heure de sa reception ;
    /// l'avancement et l'heure du debut sont remis a nil, puis `surTournee`. Hors tournee, rien.
    func finirTournee(_ m: MaillageZigbee?) {
        guard tourneeEnCours else { return }
        if let m {
            let recu = horloge()
            derniereTournee = recu
            surMaillage?(m, recu)
        }
        avancement = nil
        debutTournee = nil
        tourneeEnCours = false
        surTournee?(false)
    }

    /// Ports branches : la sonde retenue revient, ou s'en va.
    func portsChanges(_ liste: [PortUSB]) {
        ports = liste.filter(\.estEspressif)
        guard let serie else { return }
        if let p = ports.first(where: { $0.serie == serie }) {
            // `lancerConnexion` passe tout de suite a `.connexion` : un second appel n'en lance pas d'autre.
            if sonde == nil && etat != .connexion { lancerConnexion(p, choisi: false) }
        } else if (sonde != nil || etat != .absente) && !versUnAutrePort {
            deconnecter(.absente)
        }
    }

    /// Une connexion, en cours ou etablie, vise un autre port que celui de la sonde retenue (un choix des Reglages) :
    /// l'absence de la sonde retenue ne l'annule pas.
    private var versUnAutrePort: Bool {
        (etat == .connexion || sonde != nil) && serieEtat != serie
    }

    /// Connexion au port : ferme la liaison en place et attend qu'elle le soit vraiment, ouvre le port, le garde s'il
    /// repond en sonde Zigbee. Perimee par un `deconnecter` pendant une attente, elle ferme sa liaison (en l'attendant)
    /// et sort sans toucher a l'etat, a la sonde, ni au numero de serie retenu. Automatique (`choisi` faux) et en echec,
    /// elle est refaite une fois apres `delaiNouvelEssai` ; `dernierEssai` : c'est ce nouvel essai.
    func connecter(_ port: PortUSB, choisi: Bool, dernierEssai: Bool = false) async {
        deconnecter(.connexion, port: port)
        let n = essai
        // Tant que l'ancienne liaison tient le port, TIOCEXCL refuse de le rouvrir.
        await fermetures?.value
        guard n == essai else { return }
        let s = SondeUSB(canal: ouvrirCanal(port.chemin), delaiTable: delaiTable)
        enConnexion = s
        do {
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            guard n == essai else {
                await s.fermer()
                return
            }
            let b = try await s.bonjour()
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "\(port.libelle) n'est pas une sonde Zigbee (« \(b.produit) »)"))
                return
            }
            enConnexion = nil
            sonde = s
            cheminConnecte = port.chemin
            etat = .connectee(b)
            if choisi, let serieUSB = port.serie {
                // Le releve etait celui d'une autre sonde.
                if serieUSB != serie { oublierReleve() }
                preferences.set(serieUSB, forKey: Self.cleSerie)
                serie = serieUSB
            }
            // Le nom va avec la sonde retenue (un port sans numero de serie ne l'est pas).
            let retenue = port.serie != nil && port.serie == serie
            retenirNom(retenue ? b.nom : nil)
            await lireEtat(s)
            guard n == essai, s === sonde else { return }
            planifierTournee(dans: delaiPremiereTournee)
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = choisi ? .refusee(error.localizedDescription) : .erreur(error.localizedDescription)
            if !choisi && !dernierEssai { planifierNouvelEssai(port) }
        }
    }

    /// `etat` de la sonde connectee ; rien n'est retenu si la liaison n'est plus la sienne. Une liaison fermee est
    /// laissee a `liaisonFermee`.
    private func lireEtat(_ s: SondeUSB) async {
        do {
            let e = try await s.etat()
            guard s === sonde else { return }
            etatSonde = e
            erreurTournee = nil
        } catch SondeUSB.Erreur.fermee {
            // La liaison est fermee : `liaisonFermee` s'en occupe.
        } catch {
            guard s === sonde else { return }
            erreurTournee = error.localizedDescription
        }
    }

    /// Connexion lancee sans l'attendre (Reglages, ports) : la liaison en place est fermee et `etat` passe a
    /// `.connexion` tout de suite ; un `deconnecter` d'ici au depart de la tache (oublier, autre choix, port retire)
    /// l'annule.
    private func lancerConnexion(_ port: PortUSB, choisi: Bool) {
        deconnecter(.connexion, port: port)
        let n = essai
        Task {
            guard n == essai else { return }
            await connecter(port, choisi: choisi)
        }
    }

    /// Nouvel essai d'une connexion automatique en echec, apres `delaiNouvelEssai`, si rien n'a change depuis (aucun
    /// `deconnecter` : ni evenement USB, ni choix, ni oubli). C'est le seul : en echec a son tour, la sonde attend
    /// l'evenement USB suivant.
    private func planifierNouvelEssai(_ port: PortUSB) {
        let n = essai
        let delai = delaiNouvelEssai
        nouvelEssai?.cancel()
        nouvelEssai = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai else { return }
            await self.connecter(port, choisi: false, dernierEssai: true)
        }
    }

    private func liaisonFermee(_ s: SondeUSB) {
        guard sonde === s else { return }
        deconnecter(.absente)
    }

    /// Ferme sans attendre la liaison connectee et celle d'une connexion en cours, qui devient perimee ; `connecter`
    /// attend ces fermetures. `port` : celui que le nouvel etat concerne (connexion).
    private func deconnecter(_ nouveau: Etat, port: PortUSB? = nil) {
        essai += 1
        boucle?.cancel()
        boucle = nil
        passeComplementaire = nil
        tourneeDifferee = nil
        finirTournee(nil)
        for s in [sonde, enConnexion].compactMap({ $0 }) {
            let precedentes = fermetures
            fermetures = Task {
                await s.fermer()
                await precedentes?.value
            }
        }
        sonde = nil
        enConnexion = nil
        cheminConnecte = nil
        serieEtat = port?.serie
        etat = nouveau
    }
}
