import Foundation

/// Ce que la tournee demande a la sonde : la liaison USB dans l'app, une sonde simulee dans les tests. Une seule
/// requete a la fois : la tournee attend chaque reponse avant la suivante.
public protocol InterlocuteurSonde: Sendable {
    func etat() async throws -> EtatSonde
    /// La table des voisins de la sonde (requete locale, sans trame radio).
    func voisins() async throws -> [VoisinDeLaSonde]
    /// La table des voisins d'un routeur, ses lignes reunies ; nil sans reponse de la sonde dans l'echeance (125 s).
    /// Une erreur generale de la sonde (`syntaxe`...) revient en echec. Leve si la liaison est fermee.
    func table(_ cible: UInt16) async throws -> ReponseListe<EntreeTable>?
    /// La table de routage d'un routeur, memes regles.
    func routes(_ cible: UInt16) async throws -> ReponseListe<EntreeRoute>?
}

/// Une table de voisins lue : celle de quel routeur (sa cle et l'adresse courte demandee), ses entrees, sa date.
public struct TableLue: Hashable, Sendable {
    public var cle: String
    public var court: UInt16
    public var entrees: [EntreeTable]
    public var date: Date
    /// Pages de la reponse ; nil si elle ne les donne pas.
    public var pages: Int?

    public init(cle: String, court: UInt16, entrees: [EntreeTable], date: Date, pages: Int? = nil) {
        self.cle = cle
        self.court = court
        self.entrees = entrees
        self.date = date
        self.pages = pages
    }
}

/// Les tables de voisins d'une tournee qui les a lues sans lacune : la source des liens radio, des parents et des
/// qualites (LQI) jusqu'a la suivante (elles ne sont lues qu'une tournee sur quatre).
public struct TablesVoisins: Hashable, Sendable {
    /// Debut de la tournee qui les a lues.
    public var date: Date
    /// Dans l'ordre du parcours.
    public var lues: [TableLue]
    /// Routeurs prevus dont la table n'a pas ete lue.
    public var nonLues: Set<String>

    public init(date: Date, lues: [TableLue], nonLues: Set<String> = []) {
        self.date = date
        self.lues = lues
        self.nonLues = nonLues
    }
}

/// Le budget de pages de l'app (consigne de l'etape 3 ter) : les pages envoyees a la sonde (`table`, `routes`) sur une
/// fenetre glissante de 10 minutes, tenues sous `plafond` (550), avec une marge sous le garde-fou de la sonde (600 pages
/// par 10 minutes, au-dela : refus `cadence`). Chaque reponse compte ses `pages` ; une reponse qui n'en donne pas (un
/// echec, rien dans l'echeance), une page. Les pages sont datees a la reponse : apres leur envoi, donc gardees un peu
/// plus longtemps que par la sonde.
public struct BudgetPages: Hashable, Sendable {
    /// Pages envoyees au plus sur `fenetre`.
    public static let plafond = 550
    public static let fenetre: TimeInterval = 600

    /// Des pages envoyees, a la date de leur reponse.
    public struct Envoi: Hashable, Sendable {
        public var date: Date
        public var pages: Int

        public init(date: Date, pages: Int) {
            self.date = date
            self.pages = pages
        }
    }

    /// Les envois de la fenetre (et ceux qui en sortiront au prochain compte), dans l'ordre.
    public private(set) var envois: [Envoi]

    public init(envois: [Envoi] = []) {
        self.envois = envois
    }

    /// Le journal sous forme compacte, pour les preferences de l'app : `[instant, pages, instant, pages...]` (secondes
    /// depuis 1970), seulement les envois de la fenetre a `maintenant`.
    public func enregistrable(a maintenant: Date) -> [Double] {
        envois.filter { $0.date > maintenant.addingTimeInterval(-Self.fenetre) && $0.pages > 0 }
            .flatMap { [$0.date.timeIntervalSince1970, Double($0.pages)] }
    }

    /// Le journal relu des preferences a `maintenant` (au lancement de l'app) : les envois de moins de 10 minutes. Un
    /// envoi date d'apres `maintenant` (horloge reculee) compte comme envoye maintenant : jamais oublie trop tot. Une
    /// valeur illisible (nombre impair, pas un nombre) est ignoree.
    public init(enregistre valeurs: [Double], a maintenant: Date) {
        var lus: [Envoi] = []
        var i = 0
        while i + 1 < valeurs.count {
            let (t, p) = (valeurs[i], valeurs[i + 1])
            i += 2
            guard t.isFinite, p.isFinite, p >= 1, p <= 100_000 else { continue }
            let date = min(Date(timeIntervalSince1970: t), maintenant)
            guard date > maintenant.addingTimeInterval(-Self.fenetre) else { continue }
            lus.append(Envoi(date: date, pages: Int(p)))
        }
        envois = lus.sorted { $0.date < $1.date }
    }

    /// Pages envoyees dans les 10 minutes avant `maintenant`.
    public func utilisees(a maintenant: Date) -> Int {
        envois.reduce(0) { $0 + ($1.date > maintenant.addingTimeInterval(-Self.fenetre) ? $1.pages : 0) }
    }

    /// Pages encore permises a `maintenant` (jamais negatif).
    public func restant(a maintenant: Date) -> Int { max(0, Self.plafond - utilisees(a: maintenant)) }

    /// Compte `pages` envoyees, revenues a `maintenant` ; oublie les envois sortis de la fenetre.
    public mutating func compter(_ pages: Int, a maintenant: Date) {
        envois.removeAll { $0.date <= maintenant.addingTimeInterval(-Self.fenetre) }
        envois.append(Envoi(date: maintenant, pages: max(0, pages)))
    }

    /// Le premier instant, au plus tot `minimum`, ou `pages` de plus tiennent sous le plafond : `utilisees + pages <=
    /// plafond`, sans autre envoi d'ici la. Plus de `plafond` pages a elles seules : l'instant ou la fenetre est vide.
    /// Les pages utilisees ne baissent qu'a la sortie d'un envoi de la fenetre (sa date + 10 minutes) : ce sont, avec
    /// `minimum`, les seuls instants a essayer, et le dernier (fenetre vide) convient toujours.
    public func premierInstant(pour pages: Int, auPlusTot minimum: Date) -> Date {
        let besoin = min(max(0, pages), Self.plafond)
        let sorties = envois.map { $0.date.addingTimeInterval(Self.fenetre) }.filter { $0 > minimum }.sorted()
        for instant in [minimum] + sorties where utilisees(a: instant) + besoin <= Self.plafond { return instant }
        return sorties.last ?? minimum
    }
}

/// La derniere lecture reussie de la table de routage d'un routeur : sa date, ses pages, et sa route vers le pont (nil
/// sans entree `0000`).
public struct RoutesLues: Hashable, Sendable {
    public var date: Date
    /// Pages de la reponse ; nil si elle ne les donne pas.
    public var pages: Int?
    public var route: RouteVersPont?

    public init(date: Date, pages: Int?, route: RouteVersPont?) {
        self.date = date
        self.pages = pages
        self.route = route
    }
}

/// Ce que la tournee retient d'une fois sur l'autre : les echecs de suite de chaque routeur, les dernieres tables de
/// voisins, les dernieres routes lues de chaque routeur et le budget de pages.
public struct MemoireTournee: Hashable, Sendable {
    /// Tournees de suite ou un routeur n'a donne ni sa table ni ses routes par sa faute (`delai`, `statut`), par cle du
    /// noeud. Un refus de la sonde (hors du reseau, cadence...) n'en est pas un.
    public var echecs: [String: Int] = [:]
    /// Les tables de voisins de la derniere tournee qui les a lues sans lacune ; nil : aucune.
    public var tables: TablesVoisins?
    /// Tournees passees sans lire les tables depuis.
    public var tourneesSansTables: Int
    /// La derniere lecture reussie des routes de chaque routeur, par cle : un routeur non lu a une tournee (faute de
    /// budget, ou sans reponse) garde son chemin d'avant, avec sa date, et passe en tete a la suivante.
    public var routes: [String: RoutesLues]
    /// Les pages envoyees a la sonde, gardees d'une tournee a l'autre.
    public var budget: BudgetPages
    /// Les routeurs dont la derniere tournee n'a pas lu les routes (faute de budget, ou deux refus `cadence`), par cle,
    /// dans l'ordre de la file : ce que la passe complementaire lit.
    public var reportees: [String]
    /// Pages de la derniere lecture des routes du pont (`routes 0000`) ; nil : jamais lues, ou sans `pages`.
    public var pagesRoutesPont: Int?
    /// Pages envoyees par la derniere lecture complete des tables de voisins ; nil : jamais lues. Gardee par l'app d'un
    /// lancement a l'autre : sans tables en memoire, c'est elle qui estime la prochaine lecture.
    public var pagesTables: Int?

    public init(echecs: [String: Int] = [:], tables: TablesVoisins? = nil, tourneesSansTables: Int = 0,
                routes: [String: RoutesLues] = [:], budget: BudgetPages = BudgetPages(), reportees: [String] = [],
                pagesRoutesPont: Int? = nil, pagesTables: Int? = nil) {
        self.echecs = echecs
        self.tables = tables
        self.tourneesSansTables = tourneesSansTables
        self.routes = routes
        self.budget = budget
        self.reportees = reportees
        self.pagesRoutesPont = pagesRoutesPont
        self.pagesTables = pagesTables
    }

    /// Pages que la prochaine lecture des tables de voisins enverra : la somme des pages de la derniere lecture de
    /// chaque table (`pagesTableEstimees` pour une table sans `pages`, et pour chaque routeur prevu non lu) ; sans
    /// tables en memoire (l'app vient d'etre lancee), les pages de la derniere lecture complete, sinon une table.
    public var pagesTablesEstimees: Int {
        guard let t = tables else { return pagesTables ?? Tournee.pagesTableEstimees }
        return t.lues.reduce(t.nonLues.count * Tournee.pagesTableEstimees) {
            $0 + ($1.pages ?? Tournee.pagesTableEstimees)
        }
    }

    /// Pages que la prochaine tournee (complete ou non) enverra a coup sur : les tables de voisins quand elles sont dues
    /// (`tablesDues`), et les routes du pont (la derniere lecture, sinon `pagesRoutesPontEstimees`).
    public var pagesProchaineTournee: Int {
        (tablesDues ? pagesTablesEstimees : 0) + (pagesRoutesPont ?? Tournee.pagesRoutesPontEstimees)
    }

    /// Le premier instant, au plus tot `maintenant`, ou le budget couvre `pagesProchaineTournee` ; nil si c'est
    /// maintenant. Plus de 550 pages a elles seules : l'instant ou la fenetre est vide (au plus 10 minutes). Les
    /// routes des routeurs ne sont pas dans l'estimation : elles ne partent que dans la marge restante.
    public func instantProchaineTournee(a maintenant: Date) -> Date? {
        let instant = budget.premierInstant(pour: pagesProchaineTournee, auPlusTot: maintenant)
        return instant > maintenant ? instant : nil
    }

    /// Pages que la passe complementaire enverra : les routes du pont (elle les relit, voir `Tournee.executer`) et
    /// l'estimation de chaque routeur reporte (les pages de sa derniere lecture, sinon `pagesRoutesEstimees`).
    public var pagesPasseComplementaire: Int {
        reportees.reduce(pagesRoutesPont ?? Tournee.pagesRoutesEstimees) {
            $0 + (routes[$1]?.pages ?? Tournee.pagesRoutesEstimees)
        }
    }

    /// L'instant de la passe complementaire d'une tournee finie a `fin` : le premier, au moins `delaiMiniPasse` apres,
    /// ou le budget couvre `pagesPasseComplementaire` ; nil si la derniere tournee n'a rien reporte, ou s'il n'y a pas
    /// de tables en memoire.
    public func instantPasseComplementaire(apres fin: Date) -> Date? {
        // Sans tables en memoire (la tournee les a lues incompletes), la passe n'aurait pas de maillage : la tournee
        // suivante relit les tables, qui sont dues.
        guard !reportees.isEmpty, tables != nil else { return nil }
        return budget.premierInstant(pour: pagesPasseComplementaire,
                                     auPlusTot: fin.addingTimeInterval(Tournee.delaiMiniPasse))
    }

    /// Muet : deux tournees de suite sans reponse.
    public func estMuet(_ cle: String) -> Bool { (echecs[cle] ?? 0) >= Tournee.echecsAvantMuet }

    /// La prochaine tournee lit les tables de voisins : aucune n'est connue, ou c'est la quatrieme.
    public var tablesDues: Bool { tables == nil || tourneesSansTables >= Tournee.periodeTables - 1 }
}

/// Bilan d'une tournee, pour les Reglages.
public struct BilanTournee: Hashable, Sendable {
    /// Une passe complementaire : les routes des routeurs reportes seulement, sans tables de voisins.
    public var complementaire = false
    /// La tournee a lu les tables de voisins (une sur quatre, ou faute de tables connues, ou pour un routeur inconnu).
    public var avecTables = false
    /// Tables demandees (coordinateur et routeurs).
    public var tablesDemandees = 0
    public var tablesLues = 0
    /// Tables lues mais incompletes deux fois (une ligne perdue en route) : gardees telles quelles.
    public var tablesIncoherentes = 0
    /// Tables de routage des routeurs demandees, et lues.
    public var routesRouteursDemandees = 0
    public var routesRouteursLues = 0
    /// Routeurs dont les routes n'ont pas ete demandees a cette tournee (budget de pages epuise, ou deux refus
    /// `cadence` de suite) : ils gardent leur chemin d'avant et passent en tete a la suivante.
    public var routesReportees = 0
    /// La passe des routes des routeurs s'est arretee sur deux refus `cadence` de suite.
    public var passeArreteeCadence = false
    /// Pages envoyees a la sonde pendant la tournee (`BudgetPages`).
    public var pages = 0
    /// Routeurs qui n'ont donne ni table ni routes (`delai`, `statut`) a cette tournee.
    public var sansReponse = 0
    /// Routeurs muets (deux tournees de suite sans reponse).
    public var muets = 0
    /// Attentes du retour de la sonde dans le reseau (perte du parent pendant la tournee).
    public var attentes = 0
    /// Pauses de 20 s sur un refus `cadence` de la sonde.
    public var pausesCadence = 0
    /// Routes du pont lues.
    public var routesLues = false
    /// Tournee incomplete : la derniere raison donnee par la sonde (`non_membre`, `cadence`, `occupee`...,
    /// `sans_reponse` quand elle ne repond pas) ; nil pour une tournee complete.
    public var lacune: String?

    public init() {}
}

/// Pourquoi une tournee n'a pas eu lieu.
public enum EmpechementTournee: Hashable, Sendable {
    /// La sonde n'est pas membre du reseau (elle cherche, ou se rattache).
    case horsReseau
    /// La sonde est suspendue : elle refuse `table` et `routes`.
    case suspendue
}

/// Le resultat d'une tournee : son maillage (nil si elle n'a pas eu lieu), la memoire a garder, son bilan et le
/// dernier `etat` lu de la sonde.
public struct ResultatTournee: Sendable {
    public var maillage: MaillageZigbee?
    public var memoire: MemoireTournee
    public var bilan: BilanTournee
    public var etat: EtatSonde
    public var empechement: EmpechementTournee?

    public init(maillage: MaillageZigbee?, memoire: MemoireTournee, bilan: BilanTournee, etat: EtatSonde,
                empechement: EmpechementTournee? = nil) {
        self.maillage = maillage
        self.memoire = memoire
        self.bilan = bilan
        self.etat = etat
        self.empechement = empechement
    }
}

/// La sonde s'est suspendue pendant la tournee : elle s'arrete sans maillage.
private enum ArretTournee: Error {
    case suspendue
}

/// La tournee du maillage (spec de l'app, section 6 ; consignes des etapes 3 bis et 3 ter) : `etat` de la sonde, ses
/// `voisins` ; une tournee sur quatre, la table de voisins de chaque routeur en largeur depuis le pont (`0000`) ; a
/// chaque tournee, la table de routage du pont (`routes 0000`), puis celle des routeurs connus (leur chemin vers le
/// pont), les plus anciennes d'abord, dans la limite du budget de pages.
public enum Tournee {
    /// Tournees de suite sans reponse avant qu'un routeur soit muet (comme Maillage Thread).
    public static let echecsAvantMuet = 2
    /// Les tables de voisins sont lues une tournee sur `periodeTables` (la qualite des liens bouge lentement).
    public static let periodeTables = 4
    /// Attentes du retour de la sonde par table, au plus (nuit E6 : une seule laissait perdre une table sur 400).
    public static let attentesParTable = 2
    /// Attente du retour de la sonde dans le reseau : `etat` toutes les 5 s, 120 s au plus (essai : 10 a 30 s).
    public static let attenteMembre: TimeInterval = 120
    public static let pasAttente: TimeInterval = 5
    /// Refus `cadence` (la sonde plafonne a 600 pages par 10 minutes) : pause avant de redemander, et duree de tournee
    /// au-dela de laquelle on ne redemande plus (la tournee est alors incomplete).
    public static let pauseCadence: TimeInterval = 20
    public static let dureeMax: TimeInterval = 600
    /// Refus `cadence` de suite qui arretent la passe des routes des routeurs (les routeurs restants passent a la
    /// tournee suivante, sans que la tournee soit incomplete).
    public static let refusCadenceAvantArret = 2
    /// Delai minimum entre la fin d'une tournee et la passe complementaire qui lit les routes reportees.
    public static let delaiMiniPasse: TimeInterval = 30
    /// Pages estimees des routes d'un routeur jamais lu (une lampe : environ 5 pages de 10 entrees).
    public static let pagesRoutesEstimees = 5
    /// Pages estimees de la table de voisins d'un routeur jamais lue, et des routes du pont (mesures au banc : environ
    /// 450 pages pour 35 routeurs, et 22 pour le pont).
    public static let pagesTableEstimees = 13
    public static let pagesRoutesPontEstimees = 22
    /// Echecs d'une requete imputes au routeur interroge : il n'a pas repondu (`delai`) ou a refuse (`statut`).
    public static let echecsDuRouteur: Set<String> = ["delai", "statut"]
    /// Lacune d'une tournee sans tables lues ni tables en memoire : son maillage ne connait que la sonde et son parent.
    public static let lacuneSansTables = "sans_tables"

    /// Une cible du parcours : son adresse courte (la plus recente vue) et sa cle, une fois connue (le pont, `0000`,
    /// n'a la sienne que par la table d'un routeur).
    private struct Cible {
        var court: UInt16
        var cle: String?
    }

    private enum Issue {
        /// Table lue (`incoherente` : incomplete deux fois, gardee telle quelle).
        case lue(ReponseListe<EntreeTable>, date: Date, incoherente: Bool)
        /// Le routeur n'a pas repondu (`delai`) ou a refuse (`statut`).
        case routeur
        /// La sonde n'a pas pu la demander : hors du reseau, occupee, sans reponse...
        case sonde
    }

    /// Une tournee. Pas de maillage si la sonde n'est pas membre ou si elle est suspendue (au debut, ou pendant la
    /// tournee) : aucun routeur ne passe alors pour muet, et la memoire rendue est celle d'avant.
    /// - Tables de voisins (`memoire.tablesDues`, ou un routeur inconnu vu en route) : parcours en largeur depuis
    ///   `0000`, sequentiel ; seuls le coordinateur et les routeurs sont interroges, une fois chacun (par cle, l'adresse
    ///   courte la plus recente vue avant son tour). Si le pont ne donne pas sa table, le parcours repart du parent de
    ///   la sonde et des routeurs qu'elle entend. Sinon, les tables de la memoire font les liens et la liste des
    ///   routeurs.
    /// - Routes du pont (`routes 0000`), prioritaires.
    /// - Routes des routeurs connus, par anciennete de leur derniere lecture reussie (jamais lus d'abord, puis dans
    ///   l'ordre du parcours), tant que le budget de pages restant (`BudgetPages`, garde dans la memoire) couvre
    ///   l'estimation de la requete (les pages de la derniere lecture du routeur, sinon `pagesRoutesEstimees`). Les
    ///   routeurs non lus gardent leur chemin d'avant (avec sa date) et passent en tete a la tournee suivante : la
    ///   tournee n'est pas incomplete pour autant, et ils ne sont pas en echec. Un prochain saut inconnu (une route
    ///   active vers une adresse courte qu'aucun noeud n'a) fait lire les tables de voisins si ce n'est fait, puis ce
    ///   routeur est interroge a son tour.
    /// - Sur `non_membre` (la sonde a perdu son parent), elle attend son retour (`etat` toutes les 5 s, 120 s au plus),
    ///   puis redemande, deux attentes par requete au plus ; une attente vaine, et les suivantes n'attendent plus
    ///   (jusqu'a la prochaine reponse).
    /// - Une reponse incomplete sans `partielle` est redemandee une fois, puis gardee telle quelle.
    /// - `cadence` : pause de 20 s et la meme requete, tant que la tournee dure moins de 10 min ; au-dela, elle s'arrete,
    ///   incomplete. Pendant la passe des routes des routeurs, le deuxieme refus de suite (ou la duree depassee) arrete
    ///   seulement la passe : les routeurs restants passent a la tournee suivante. Le routeur n'y est pour rien.
    /// - Chaque reponse a `table` ou `routes` compte ses pages dans le budget (une page sans `pages`).
    /// - Un routeur qui ne donne ni table ni routes par sa faute (`delai`, `statut`) compte un echec ; muet a deux de
    ///   suite.
    /// - Passe complementaire (`complementaire`, decision de Majid du 08/10) : lancee par l'app des que le budget couvre
    ///   les routes reportees (`MemoireTournee.instantPasseComplementaire`), sans attendre la tournee suivante. Elle ne
    ///   lit jamais les tables de voisins (ni pour un routeur inconnu vu en route : il rejoint la file et le maillage, ses
    ///   voisins seront lus a la prochaine tournee avec tables), et ne garde dans la file que les routeurs reportes
    ///   (`memoire.reportees`). Elle relit les routes du pont (prioritaires, comme toute tournee) : le maillage rendu
    ///   remplace le precedent et en porte la table de routage, qu'il faut donc a jour ; ces pages sont comptees dans
    ///   l'instant choisi. Elle ne compte pas dans le rythme des tables (une tournee sur quatre).
    /// - Les tables de voisins demandees par un routeur inconnu vu en route ne sont lues que si le budget restant couvre
    ///   leur estimation (`MemoireTournee.pagesTablesEstimees`) ; sinon la prochaine tournee les lira (elle sera due), et
    ///   donc attendra le budget (`MemoireTournee.instantProchaineTournee`, c'est l'app qui l'attend avant de lancer une
    ///   tournee : les tables et les routes du pont, comptees dans le budget, ne partent que s'il les couvre).
    /// `horloge` date les tables ; `attendre` fait les pauses (injectes par les tests). `avancement` est appele au debut
    /// de chaque etape, puis a chaque requete revenue, dans l'isolation de l'appelant ; `surBudget`, apres chaque
    /// requete revenue, avec le budget a jour (l'app le garde dans ses preferences).
    public static func executer<S: InterlocuteurSonde>(
        _ sonde: S, memoire: MemoireTournee, complementaire: Bool = false,
        horloge: @escaping @Sendable () -> Date = { Date() },
        attendre: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        isolation: isolated (any Actor)? = #isolation,
        avancement: (AvancementTournee) -> Void = { _ in },
        surBudget: (BudgetPages) -> Void = { _ in }
    ) async throws -> ResultatTournee {
        let debut = horloge()
        var bilan = BilanTournee()
        bilan.complementaire = complementaire
        avancement(AvancementTournee(etape: .etatSonde, fait: 0, total: 2))
        var etat = try await sonde.etat()
        try Task.checkCancellation()
        avancement(AvancementTournee(etape: .etatSonde, fait: 1, total: 2))
        guard etat.membre, !etat.suspendue else {
            return ResultatTournee(maillage: nil, memoire: memoire, bilan: bilan, etat: etat,
                                   empechement: etat.suspendue ? .suspendue : .horsReseau)
        }
        // Sans reponse a `voisins`, la tournee continue sans le signal vu par la sonde ; une liaison fermee fera
        // echouer la requete suivante.
        let voisins = (try? await sonde.voisins()) ?? []
        try Task.checkCancellation()
        avancement(AvancementTournee(etape: .etatSonde, fait: 2, total: 2))
        var dateEtat = horloge()

        // La sonde de retour dans le reseau : `etat` toutes les `pasAttente` s, `attenteMembre` s au plus.
        func attendreMembre() async throws -> Bool {
            let fin = horloge().addingTimeInterval(attenteMembre)
            while true {
                if let e = try? await sonde.etat(), e.membre {
                    etat = e
                    dateEtat = horloge()
                    return true
                }
                try Task.checkCancellation()
                if horloge().addingTimeInterval(pasAttente) > fin { return false }
                try await attendre(.seconds(pasAttente))
            }
        }

        var horsReseau = false
        // Arret de la tournee : un refus `cadence` au-dela de `dureeMax`.
        var arret = false
        // Les pages envoyees, gardees d'une tournee a l'autre.
        var budget = memoire.budget
        // Refus `cadence` de suite, et arret de la passe des routes des routeurs qu'ils provoquent.
        var refusDeSuite = 0
        var passeArretee = false
        // Une requete, avec la pause sur `cadence`, l'attente du retour de la sonde et une seconde demande d'une
        // reponse incomplete (comme `Essai.requete` de l'outil d'essai). Rend la reponse et si elle est restee
        // incomplete. Chaque reponse compte ses pages. `passe` : une requete de la passe des routes des routeurs, que
        // le deuxieme refus `cadence` de suite (ou la duree depassee) arrete (`passeArretee`) sans arreter la tournee.
        func demander<E>(passe: Bool = false,
                         _ requete: () async throws -> ReponseListe<E>?) async throws -> (ReponseListe<E>?, Bool) {
            var essais = 2, attentes = 0
            while true {
                let m = try await requete()
                let pages = m?.pages ?? 1
                budget.compter(pages, a: horloge())
                surBudget(budget)
                bilan.pages += pages
                try Task.checkCancellation()
                if m?.erreur == "cadence" {
                    refusDeSuite += 1
                    let dansLaDuree = horloge().addingTimeInterval(pauseCadence).timeIntervalSince(debut) <= dureeMax
                    if passe && (refusDeSuite >= refusCadenceAvantArret || !dansLaDuree) {
                        passeArretee = true
                        return (m, false)
                    }
                    if dansLaDuree {
                        bilan.pausesCadence += 1
                        try await attendre(.seconds(pauseCadence))
                        continue
                    }
                    arret = true
                    return (m, false)
                }
                refusDeSuite = 0
                let hors = m?.erreur == "non_membre"
                if hors && attentes < attentesParTable && !horsReseau {
                    attentes += 1
                    bilan.attentes += 1
                    if try await attendreMembre() { continue }
                    horsReseau = true
                } else if m != nil && !hors {
                    horsReseau = false
                }
                guard let r = m, !r.complete else { return (m, false) }
                essais -= 1
                if essais == 0 { return (r, true) }
            }
        }

        // Cles qui n'ont pas repondu par leur faute, et celles qui ont repondu (table ou routes).
        var fautes: Set<String> = []
        var repondus: Set<String> = []
        // Un echec de requete : la faute du routeur (`delai`, `statut`), la suspension de la sonde (fin de la tournee),
        // ou une lacune de la sonde.
        func noterEchec(_ erreur: String?, cle: String?) throws {
            let e = erreur ?? ""
            if echecsDuRouteur.contains(e) {
                if let cle { fautes.insert(cle) }
                return
            }
            if e == "suspendue" { throw ArretTournee.suspendue }
            bilan.lacune = e.isEmpty ? "sans_reponse" : e
        }

        do {
            // Parcours en largeur des tables de voisins.
            var file = [Cible(court: 0x0000, cle: nil)]
            var indexParCle: [String: Int] = [:]
            var issues: [Issue] = []
            var tablesFaites = false
            var lacuneTables = false
            var lues: [TableLue] = []
            var nonLuesTables: Set<String> = []
            // Pages deja envoyees au debut de la lecture des tables, et pages qu'elle a envoyees.
            var pagesAvantTables = 0
            var pagesTables = 0
            // Les tables d'un routeur inconnu n'ont pas ete lues faute de budget.
            var tablesReportees = false
            func prevoir(_ court: UInt16, _ cle: String?, type: TypeNoeud, deja: Int) {
                guard type == .coordinateur || type == .routeur else { return }
                if let cle {
                    if let j = indexParCle[cle] {
                        // Pas encore interroge : l'adresse courte la plus recente.
                        if j >= deja { file[j].court = court }
                        return
                    }
                    // La cle d'une cible deja prevue sans la sienne (le pont), par son adresse courte.
                    if let j = file.indices.first(where: { file[$0].cle == nil && file[$0].court == court }) {
                        file[j].cle = cle
                        indexParCle[cle] = j
                        return
                    }
                    indexParCle[cle] = file.count
                    file.append(Cible(court: court, cle: cle))
                } else if !file.contains(where: { $0.court == court }) {
                    file.append(Cible(court: court, cle: nil))
                }
            }
            func cle(_ c: Cible) -> String { c.cle ?? NoeudZigbee.cleProvisoire(court: c.court) }
            func lireTables() async throws {
                tablesFaites = true
                bilan.avecTables = true
                pagesAvantTables = bilan.pages
                var reprise = false
                var i = 0
                while i < file.count && !arret {
                    avancement(AvancementTournee(etape: .tables, fait: i, total: file.count))
                    let cible = file[i]
                    let (r, incoherente) = try await demander { try await sonde.table(cible.court) }
                    i += 1
                    bilan.tablesDemandees += 1
                    guard let r else {
                        issues.append(.sonde)
                        bilan.lacune = "sans_reponse"
                        continue
                    }
                    if r.ok {
                        issues.append(.lue(r, date: horloge(), incoherente: incoherente))
                        bilan.tablesLues += 1
                        if incoherente { bilan.tablesIncoherentes += 1 }
                        for e in r.liste {
                            guard let c = ProtocoleSonde.court(e.court) else { continue }
                            prevoir(c, ProtocoleSonde.ieee(e.ieee), type: c == 0 ? .coordinateur : e.typeNoeud, deja: i)
                        }
                        continue
                    }
                    issues.append(echecsDuRouteur.contains(r.erreur ?? "") ? .routeur : .sonde)
                    try noterEchec(r.erreur, cle: nil)
                    if arret { break }
                    // Le pont ne donne pas sa table : le parcours repart du parent de la sonde et des routeurs qu'elle
                    // entend.
                    if i == 1 && file.count == 1 && !reprise {
                        reprise = true
                        if let p = etat.parent, let c = ProtocoleSonde.court(p.court) {
                            prevoir(c, ProtocoleSonde.ieee(p.ieee), type: c == 0 ? .coordinateur : .routeur, deja: i)
                        }
                        for v in voisins {
                            guard let c = ProtocoleSonde.court(v.court) else { continue }
                            let type = v.type.flatMap(TypeNoeud.init(rawValue:)) ?? .inconnu
                            prevoir(c, ProtocoleSonde.ieee(v.ieee), type: c == 0 ? .coordinateur : type, deja: i)
                        }
                    }
                }
                avancement(AvancementTournee(etape: .tables, fait: i, total: file.count))
                lacuneTables = bilan.lacune != nil
                // Les tables, sous leurs cles (celle du pont n'est connue qu'a la fin).
                for (j, issue) in issues.enumerated() {
                    let k = cle(file[j])
                    switch issue {
                    case let .lue(r, date, _):
                        repondus.insert(k)
                        lues.append(TableLue(cle: k, court: file[j].court, entrees: r.liste, date: date, pages: r.pages))
                    case .routeur:
                        fautes.insert(k)
                        nonLuesTables.insert(k)
                    case .sonde:
                        nonLuesTables.insert(k)
                    }
                }
                // Prevus, jamais demandes (arret) : non lus.
                for c in file[issues.count...] { nonLuesTables.insert(cle(c)) }
                pagesTables = bilan.pages - pagesAvantTables
            }
            // Le maillage de tables lues, et de la sonde : les routeurs connus et leurs adresses courtes.
            func construction(_ tables: [TableLue]) -> ConstructionMaillage {
                var c = ConstructionMaillage()
                for t in tables { c.table(de: t.cle, court: t.court, entrees: t.entrees, date: t.date) }
                c.sonde(etat, voisins: voisins, date: dateEtat)
                return c
            }

            if memoire.tablesDues && !complementaire { try await lireTables() }

            // Table de routage du pont, prioritaire.
            var routes: [RouteZigbee] = []
            var pagesRoutesPont = memoire.pagesRoutesPont
            avancement(AvancementTournee(etape: .routes, fait: 0, total: 1))
            if !arret {
                let (r, _) = try await demander { try await sonde.routes(0x0000) }
                if let r, r.ok {
                    bilan.routesLues = true
                    pagesRoutesPont = r.pages ?? pagesRoutesPont
                    routes = r.liste.compactMap { e in
                        guard let d = ProtocoleSonde.court(e.destination), let p = ProtocoleSonde.court(e.prochain) else {
                            return nil
                        }
                        return RouteZigbee(destination: d, prochain: p, etat: e.etat ?? "inconnu",
                                           plusieursVersUn: e.plusieursVersUn ?? false)
                    }
                } else if r?.erreur == "suspendue" {
                    throw ArretTournee.suspendue
                } else if arret {
                    bilan.lacune = "cadence"
                }
            }
            avancement(AvancementTournee(etape: .routes, fait: 1, total: 1))

            // Routes des routeurs connus : les plus anciennes d'abord (jamais lues en tete, puis dans l'ordre du
            // parcours), tant que le budget couvre l'estimation de la requete.
            var fileRoutes: [(court: UInt16, cle: String)] = []
            var courtsPrevus: Set<UInt16> = []
            var courtsConnus: Set<UInt16> = []
            var vusEnRoute: [UInt16] = []
            var lectures: [String: RoutesLues] = [:]
            func prevoirRoutes() {
                let tables = tablesFaites ? lues : memoire.tables?.lues ?? []
                let base = construction(tables).noeudsFondus
                courtsConnus = Set(base.compactMap(\.court))
                let rang = Dictionary(tables.enumerated().map { ($1.cle, $0) }, uniquingKeysWith: { a, _ in a })
                for n in base.filter({ $0.type == .routeur })
                    .sorted(by: { (rang[$0.ieee] ?? .max, $0.ieee) < (rang[$1.ieee] ?? .max, $1.ieee) }) {
                    guard let c = n.court, courtsPrevus.insert(c).inserted else { continue }
                    fileRoutes.append((c, n.ieee))
                }
            }
            // Le reste de la file (a partir de `k`), par anciennete de la derniere lecture ; a egalite, l'ordre de la
            // file (le parcours).
            func ordonner(depuis k: Int) {
                let reste = fileRoutes[k...].enumerated().sorted { x, y in
                    let dx = memoire.routes[x.element.cle]?.date ?? .distantPast
                    let dy = memoire.routes[y.element.cle]?.date ?? .distantPast
                    return (dx, x.offset) < (dy, y.offset)
                }
                fileRoutes.replaceSubrange(k..., with: reste.map(\.element))
            }
            func estimation(_ cle: String) -> Int { memoire.routes[cle]?.pages ?? pagesRoutesEstimees }
            // Requetes de la file (a partir de `k`) que le budget restant couvre, dans l'ordre.
            func couvertes(depuis k: Int) -> Int {
                var reste = budget.restant(a: horloge())
                var n = 0
                for cible in fileRoutes[k...] {
                    let e = estimation(cible.cle)
                    guard e <= reste else { break }
                    reste -= e
                    n += 1
                }
                return n
            }
            prevoirRoutes()
            if complementaire { fileRoutes.removeAll { !memoire.reportees.contains($0.cle) } }
            ordonner(depuis: 0)
            refusDeSuite = 0
            var k = 0
            while k < fileRoutes.count && !arret {
                let prevues = couvertes(depuis: k)
                guard prevues > 0 else { break }
                avancement(AvancementTournee(etape: .routesRouteurs, fait: k, total: k + prevues))
                let cible = fileRoutes[k]
                let (r, _) = try await demander(passe: true) { try await sonde.routes(cible.court) }
                if passeArretee {
                    bilan.passeArreteeCadence = true
                    break
                }
                k += 1
                bilan.routesRouteursDemandees += 1
                guard let r, r.ok else {
                    try noterEchec(r?.erreur, cle: cible.cle)
                    continue
                }
                repondus.insert(cible.cle)
                bilan.routesRouteursLues += 1
                let date = horloge()
                lectures[cible.cle] = RoutesLues(date: date, pages: r.pages,
                                                 route: RouteVersPont.depuis(r.liste, date: date))
                // Un prochain saut inconnu : un routeur que les tables connues n'ont pas.
                let inconnus = Set(r.liste.compactMap { e -> UInt16? in
                    guard e.etat == "active", let p = ProtocoleSonde.court(e.prochain), p != 0, p < 0xFFF8,
                          !courtsConnus.contains(p), !courtsPrevus.contains(p) else { return nil }
                    return p
                })
                guard !inconnus.isEmpty else { continue }
                if !tablesFaites && !complementaire {
                    if budget.restant(a: horloge()) >= memoire.pagesTablesEstimees {
                        try await lireTables()
                        prevoirRoutes()
                    } else {
                        tablesReportees = true
                    }
                }
                for p in inconnus.sorted() where !courtsConnus.contains(p) && courtsPrevus.insert(p).inserted {
                    vusEnRoute.append(p)
                    fileRoutes.append((p, NoeudZigbee.cleProvisoire(court: p)))
                }
                ordonner(depuis: k)
            }
            bilan.routesReportees = fileRoutes.count - k
            avancement(AvancementTournee(etape: .routesRouteurs, fait: k, total: k))

            // Le maillage : les tables de cette tournee, ou celles de la memoire ; les routes lues a cette tournee, ou
            // les dernieres de la memoire.
            var c = construction(tablesFaites ? lues : memoire.tables?.lues ?? [])
            for p in vusEnRoute { c.routeurVuEnRoute(court: p) }
            // Ni tables lues ni tables en memoire (une passe complementaire apres une tournee aux tables incompletes) :
            // le maillage ne connait que la sonde et son parent, il n'est pas complet.
            if !tablesFaites && memoire.tables == nil && bilan.lacune == nil { bilan.lacune = Tournee.lacuneSansTables }
            var mem = memoire
            mem.budget = budget
            mem.reportees = fileRoutes[k...].map(\.cle)
            mem.pagesRoutesPont = pagesRoutesPont
            mem.routes.merge(lectures) { _, nouvelle in nouvelle }
            for r in repondus { mem.echecs[r] = nil }
            for f in fautes.subtracting(repondus) { mem.echecs[f, default: 0] += 1 }
            let muets = Set(mem.echecs.keys.filter { mem.estMuet($0) }).subtracting(repondus)
            let maillage = c.maillage(date: debut, routes: routes,
                                      nonLues: tablesFaites ? nonLuesTables : memoire.tables?.nonLues ?? [],
                                      muets: muets, complet: bilan.lacune == nil,
                                      routesVersPont: mem.routes.compactMapValues(\.route),
                                      dateTables: tablesFaites ? debut : memoire.tables?.date)
            // Les routeurs partis n'ont plus d'echecs ni de routes en memoire ; un maillage incomplet n'en dit rien (ce
            // qu'il n'a pas vu n'est pas parti).
            if maillage.complet {
                let presents = Set(maillage.noeuds.map(\.ieee))
                mem.echecs = mem.echecs.filter { presents.contains($0.key) }
                mem.routes = mem.routes.filter { presents.contains($0.key) }
            }
            bilan.muets = maillage.noeuds.filter(\.muet).count
            bilan.sansReponse = fautes.subtracting(repondus).count
            if tablesFaites && !lacuneTables {
                mem.tables = TablesVoisins(date: debut, lues: lues, nonLues: nonLuesTables)
                mem.tourneesSansTables = 0
                mem.pagesTables = pagesTables
            } else if tablesFaites {
                // Tables incompletes : celles d'avant restent la source, et la prochaine tournee les relit.
                mem.tourneesSansTables = periodeTables - 1
            } else if tablesReportees {
                // Les tables d'un routeur inconnu attendent le budget : la prochaine tournee les lira.
                mem.tourneesSansTables = periodeTables - 1
            } else if !complementaire {
                mem.tourneesSansTables += 1
            }
            return ResultatTournee(maillage: maillage, memoire: mem, bilan: bilan, etat: etat)
        } catch ArretTournee.suspendue {
            // Suspendue pendant la tournee : comme au debut, aucune tournee ; seules les pages envoyees restent.
            var mem = memoire
            mem.budget = budget
            return ResultatTournee(maillage: nil, memoire: mem, bilan: bilan,
                                   etat: (try? await sonde.etat()) ?? etat, empechement: .suspendue)
        }
    }
}

/// Construction du maillage d'une tournee a partir des tables lues (spec de l'app, section 4) :
/// - un noeud par adresse longue ; une adresse longue invalide (`0000000000000000`, `FFFFFFFFFFFFFFFF`, mal formee)
///   donne une cle provisoire tiree de l'adresse courte, fondue dans le noeud de meme adresse courte s'il en a une ;
/// - un voisin coordinateur ou routeur dans la table d'un routeur : un `LienRadio`, mesure par le proprietaire de la
///   table ; par sens, la mesure la plus recente l'emporte ;
/// - un voisin final, de relation `enfant` : un `LienParent` (parent = proprietaire, LQI de l'entree), le plus
///   recent l'emporte ; son `ecoute` dit s'il est endormi ;
/// - la sonde : un appareil final, sous le parent que donne son dernier `etat`.
struct ConstructionMaillage {
    private var noeuds: [String: NoeudZigbee] = [:]
    private var liens: [LienRadio] = []
    private var parents: [String: LienParent] = [:]
    private var sonde: String?
    private var signaux: [SignalSonde] = []

    private static func rang(_ t: TypeNoeud) -> Int {
        switch t {
        case .coordinateur: 3
        case .routeur: 2
        case .final: 1
        case .inconnu: 0
        }
    }

    /// Ajoute ou complete un noeud : l'adresse courte la plus recente, le role le plus sur, `ecoute` le plus recent.
    private mutating func noeud(_ cle: String, court: UInt16?, type: TypeNoeud, ecoute: Bool? = nil) {
        var n = noeuds[cle] ?? NoeudZigbee(ieee: cle, court: court, type: type)
        if let court { n.court = court }
        if Self.rang(type) > Self.rang(n.type) { n.type = type }
        if let ecoute { n.ecoute = ecoute }
        noeuds[cle] = n
    }

    private mutating func parent(_ p: LienParent) {
        if let avant = parents[p.enfant], let da = avant.date, let dp = p.date, da > dp { return }
        parents[p.enfant] = p
    }

    /// La table d'un routeur (ou du coordinateur, `court` 0), lue a `date`.
    mutating func table(de proprio: String, court: UInt16, entrees: [EntreeTable], date: Date) {
        noeud(proprio, court: court, type: court == 0 ? .coordinateur : .routeur)
        for e in entrees {
            guard let c = ProtocoleSonde.court(e.court) else { continue }
            let cle = ProtocoleSonde.ieee(e.ieee) ?? NoeudZigbee.cleProvisoire(court: c)
            guard cle != proprio else { continue }
            let type: TypeNoeud = c == 0 && e.typeNoeud != .final ? .coordinateur : e.typeNoeud
            noeud(cle, court: c, type: type, ecoute: type == .final ? e.ecoute : nil)
            switch type {
            case .coordinateur, .routeur:
                liens.append(LienRadio(mesurePar: proprio, de: cle, lqi: e.lqi, date: date))
            case .final where e.relation == "enfant":
                parent(LienParent(enfant: cle, parent: proprio, lqi: e.lqi, date: date))
            default:
                break
            }
        }
    }

    /// La sonde, d'apres son dernier `etat` (lu a `date`) : un appareil final qui ecoute, sous son parent ; le LQI du
    /// lien est celui que le parent donne dans sa table s'il l'y range en enfant, sinon celui de la sonde. Ses voisins
    /// donnent le signal qu'elle entend.
    mutating func sonde(_ etat: EtatSonde, voisins: [VoisinDeLaSonde], date: Date) {
        signaux = voisins.compactMap { v in
            guard let i = ProtocoleSonde.ieee(v.ieee), let lqi = v.lqi else { return nil }
            return SignalSonde(ieee: i, lqi: lqi)
        }
        guard let s = ProtocoleSonde.ieee(etat.ieee) else { return }
        sonde = s
        noeud(s, court: ProtocoleSonde.court(etat.court), type: .final, ecoute: true)
        guard let p = etat.parent, let pc = ProtocoleSonde.court(p.court) else { return }
        let pcle = ProtocoleSonde.ieee(p.ieee) ?? NoeudZigbee.cleProvisoire(court: pc)
        noeud(pcle, court: pc, type: pc == 0 ? .coordinateur : .routeur)
        let vu = parents[s].flatMap { $0.parent == pcle ? $0 : nil }
        parents[s] = LienParent(enfant: s, parent: pcle, lqi: vu?.lqi ?? p.lqi, date: vu?.date ?? date)
    }

    /// Un routeur vu seulement comme prochain saut d'une route, sous son adresse courte (cle provisoire).
    mutating func routeurVuEnRoute(court: UInt16) {
        noeud(NoeudZigbee.cleProvisoire(court: court), court: court, type: .routeur)
    }

    /// La cle vraie de chaque cle : une cle provisoire fondue dans le noeud de meme adresse courte qui a une adresse
    /// longue ; sinon elle-meme.
    private var vraies: (String) -> String {
        var parCourt: [UInt16: String] = [:]
        for n in noeuds.values where n.ieeeConnue {
            if let c = n.court { parCourt[c] = n.ieee }
        }
        let noeuds = noeuds
        return { cle in
            guard !NoeudZigbee.cleConnue(cle), let c = noeuds[cle]?.court, let i = parCourt[c] else { return cle }
            return i
        }
    }

    /// Les noeuds, les cles provisoires fondues, par cle.
    var noeudsFondus: [NoeudZigbee] {
        let vraie = vraies
        var fusion: [String: NoeudZigbee] = [:]
        for n in noeuds.values.sorted(by: { $0.ieee < $1.ieee }) {
            let k = vraie(n.ieee)
            if var deja = fusion[k] {
                if Self.rang(n.type) > Self.rang(deja.type) { deja.type = n.type }
                if deja.ecoute == nil { deja.ecoute = n.ecoute }
                fusion[k] = deja
            } else {
                var m = n
                m.ieee = k
                fusion[k] = m
            }
        }
        return fusion.values.sorted { $0.ieee < $1.ieee }
    }

    /// Le maillage : les cles provisoires fondues dans le noeud de meme adresse courte qui a une adresse longue ; les
    /// routeurs prevus et non lus marques (`tableNonLue`), les muets (`muets`, par cle) ; les chemins vers le pont
    /// d'apres les routes lues (`routesVersPont`, par cle de routeur).
    func maillage(date: Date, routes: [RouteZigbee], nonLues: Set<String>, muets: Set<String> = [],
                  complet: Bool, routesVersPont: [String: RouteVersPont] = [:], dateTables: Date? = nil) -> MaillageZigbee {
        let vraie = vraies
        var fusion = Dictionary(noeudsFondus.map { ($0.ieee, $0) }, uniquingKeysWith: { a, _ in a })
        let nonLuesVraies = Set(nonLues.map(vraie))
        let muetsVrais = Set(muets.map(vraie))
        for (k, var n) in fusion where n.route {
            n.tableNonLue = nonLuesVraies.contains(k)
            n.muet = muetsVrais.contains(k)
            fusion[k] = n
        }
        let radio = liens.compactMap { l -> LienRadio? in
            let a = vraie(l.a), b = vraie(l.b)
            guard a != b else { return nil }
            if a == l.a && b == l.b { return l }
            // Un bout renomme : la mesure garde son sens.
            var r = LienRadio(mesurePar: a, de: b, lqi: l.lqiA, date: l.dateA)
            if l.lqiB != nil || l.dateB != nil {
                r = r.fusionner(LienRadio(mesurePar: b, de: a, lqi: l.lqiB, date: l.dateB))
            }
            return r
        }
        var parentsVrais: [String: LienParent] = [:]
        for p in parents.values {
            var q = p
            q.enfant = vraie(p.enfant)
            q.parent = vraie(p.parent)
            guard q.enfant != q.parent else { continue }
            if let avant = parentsVrais[q.enfant], let da = avant.date, let dq = q.date, da > dq { continue }
            parentsVrais[q.enfant] = q
        }
        let noeudsVrais = fusion.values.sorted { $0.ieee < $1.ieee }
        let liensVrais = MaillageZigbee.reunir(radio)
        var routesVraies: [String: RouteVersPont] = [:]
        // Une cle provisoire et la vraie : la route la plus recente.
        for (k, r) in routesVersPont.sorted(by: { $0.key < $1.key }) {
            if let deja = routesVraies[vraie(k)], deja.date > r.date { continue }
            routesVraies[vraie(k)] = r
        }
        return MaillageZigbee(date: date, noeuds: noeudsVrais, liens: liensVrais,
                              parents: parentsVrais.values.sorted { $0.enfant < $1.enfant },
                              routesPont: routes, sonde: sonde.map(vraie), signaux: signaux, complet: complet,
                              chemins: CheminsPont.calculer(noeuds: noeudsVrais, liens: liensVrais, routes: routesVraies),
                              dateTables: dateTables)
    }
}
