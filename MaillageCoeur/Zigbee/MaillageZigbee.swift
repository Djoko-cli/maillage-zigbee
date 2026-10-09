import Foundation

/// Role d'un noeud Zigbee, tel que les tables de voisins le donnent (spec de la sonde, section 2 : `type`).
public enum TypeNoeud: String, Codable, Hashable, Sendable {
    case coordinateur, routeur, final, inconnu
}

/// Un noeud du maillage (spec de l'app, section 4). L'adresse longue (IEEE) est la cle de tout : historique,
/// surnoms, pieces choisies. L'adresse courte change au rattachement : jamais une cle.
public struct NoeudZigbee: Codable, Hashable, Sendable {
    /// 16 hexa majuscules, octet de poids fort d'abord. Un noeud dont aucune table ne donne une adresse longue valide
    /// porte a la place une cle provisoire, tiree de son adresse courte (`cleProvisoire(court:)`) : jamais une cle
    /// d'historique, de surnom ni de piece.
    public var ieee: String
    /// Adresse courte au moment de la tournee ; nil si elle n'est pas connue.
    public var court: UInt16?
    public var type: TypeNoeud
    /// Routeur muet : sa table n'a pas pu etre lue a deux tournees de suite (`MemoireTournee`) ; ses liens ne sont vus
    /// que par ses voisins.
    public var muet: Bool
    /// Routeur dont la table n'a pas ete lue a cette tournee (muet, sans reponse une fois, ou tournee incomplete) : ses
    /// enfants ne sont pas connus.
    public var tableNonLue: Bool
    /// Recepteur allume au repos, d'apres la table de son parent (`ecoute`) ; nil : inconnu. Un appareil final dont
    /// `ecoute` vaut faux est endormi.
    public var ecoute: Bool?

    public init(ieee: String, court: UInt16? = nil, type: TypeNoeud, muet: Bool = false, tableNonLue: Bool? = nil,
                ecoute: Bool? = nil) {
        self.ieee = ieee
        self.court = court
        self.type = type
        self.muet = muet
        self.tableNonLue = tableNonLue ?? muet
        self.ecoute = ecoute
    }

    /// Un routeur ou le coordinateur : il a une table de voisins, et des liens radio.
    public var route: Bool { type == .coordinateur || type == .routeur }

    /// Un appareil final au recepteur eteint au repos (`ecoute` faux) ; jamais un routeur.
    public var endormi: Bool { !route && ecoute == false }

    /// L'adresse longue est connue (16 hexa) : le noeud peut servir de cle.
    public var ieeeConnue: Bool { Self.cleConnue(ieee) }

    /// Cle d'un noeud sans adresse longue valide : « ~1A2B », d'apres son adresse courte.
    public static func cleProvisoire(court: UInt16) -> String { "~" + String(format: "%04X", court) }

    /// `cle` est une adresse longue (16 hexa), pas une cle provisoire.
    public static func cleConnue(_ cle: String) -> Bool {
        cle.utf8.count == 16 && cle.utf8.allSatisfy { $0.estHexa }
    }
}

/// Conversion du LQI (0 a 255, tel qu'une table de voisins le donne) en qualite de 0 a 3, a ce seul endroit
/// (spec de l'app, section 4 ; seuils de depart, a ajuster au banc) : 170 et plus, bonne (3) ; 100 a 169, moyenne (2) ;
/// 50 a 99, faible (1) ; sous 50, tres faible (0).
public enum QualiteLien {
    public static let seuilBonne = 170
    public static let seuilMoyenne = 100
    public static let seuilFaible = 50

    public static func depuis(lqi: Int) -> Int {
        switch lqi {
        case seuilBonne...: 3
        case seuilMoyenne..<seuilBonne: 2
        case seuilFaible..<seuilMoyenne: 1
        default: 0
        }
    }

    /// La qualite d'un LQI connu ; nil sinon.
    public static func depuis(lqi: Int?) -> Int? { lqi.map { depuis(lqi: $0) } }
}

/// Lien radio entre deux routeurs (ou un routeur et le coordinateur), `a` < `b` dans l'ordre des IEEE. Chacun le mesure
/// de son cote : `lqiA` est le LQI que `a` donne pour ce qu'il recoit de `b` (l'entree `b` de la table de `a`) ; `lqiB`,
/// l'inverse. Par sens, la mesure la plus recente l'emporte (`fusionner`).
public struct LienRadio: Codable, Hashable, Sendable {
    public var a: String
    public var b: String
    public var lqiA: Int?
    public var lqiB: Int?
    public var dateA: Date?
    public var dateB: Date?

    public init(a: String, b: String, lqiA: Int? = nil, lqiB: Int? = nil, dateA: Date? = nil, dateB: Date? = nil) {
        self.a = a
        self.b = b
        self.lqiA = lqiA
        self.lqiB = lqiB
        self.dateA = dateA
        self.dateB = dateB
    }

    /// Le lien entre `x` et `y`, `a` < `b` quel que soit l'ordre donne, avec la mesure que `x` fait de `y` (`lqi`, a
    /// `date`).
    public init(mesurePar x: String, de y: String, lqi: Int?, date: Date? = nil) {
        if x < y {
            self.init(a: x, b: y, lqiA: lqi, dateA: date)
        } else {
            self.init(a: y, b: x, lqiB: lqi, dateB: date)
        }
    }

    /// La moins bonne des deux qualites connues (`QualiteLien`) ; nil si aucun sens n'est mesure.
    public var qualite: Int? {
        [lqiA, lqiB].compactMap { QualiteLien.depuis(lqi: $0) }.min()
    }

    /// Un des deux bouts.
    public func relie(_ ieee: String) -> Bool { a == ieee || b == ieee }

    /// L'autre bout ; nil si `ieee` n'en est pas un.
    public func autre(que ieee: String) -> String? {
        a == ieee ? b : b == ieee ? a : nil
    }

    /// Ce lien et `autre` (les memes bouts) reunis : par sens, la mesure la plus recente ; une mesure datee passe
    /// avant une mesure sans date, et a dates egales (ou sans date des deux cotes), celle de `autre`.
    public func fusionner(_ autre: LienRadio) -> LienRadio {
        func garder(_ l1: Int?, _ d1: Date?, _ l2: Int?, _ d2: Date?) -> (Int?, Date?) {
            guard l2 != nil else { return (l1, d1) }
            guard l1 != nil else { return (l2, d2) }
            switch (d1, d2) {
            case let (x?, y?): return x > y ? (l1, d1) : (l2, d2)
            case (_?, nil): return (l1, d1)
            default: return (l2, d2)
            }
        }
        var r = self
        (r.lqiA, r.dateA) = garder(lqiA, dateA, autre.lqiA, autre.dateA)
        (r.lqiB, r.dateB) = garder(lqiB, dateB, autre.lqiB, autre.dateB)
        return r
    }
}

/// Un appareil final et son parent ; `lqi` : mesure par le parent (l'entree « enfant » de sa table).
public struct LienParent: Codable, Hashable, Sendable {
    public var enfant: String
    public var parent: String
    public var lqi: Int?
    /// Date de la table qui a donne ce lien (`dAvant` : celle du dernier parent connu).
    public var date: Date?
    /// Le dernier parent connu (`ParentsConnus`), pas un lien lu dans les dernieres tables : l'appareil final (endormi)
    /// n'y est plus, mais son parent d'avant date de moins de 24 h. Le graphe le trace en pointilles, la fiche en dit
    /// l'age, le journal et l'historique ne le comptent pas comme un lien vu.
    public var dAvant: Bool

    public init(enfant: String, parent: String, lqi: Int? = nil, date: Date? = nil, dAvant: Bool = false) {
        self.enfant = enfant
        self.parent = parent
        self.lqi = lqi
        self.date = date
        self.dAvant = dAvant
    }

    public var qualite: Int? { QualiteLien.depuis(lqi: lqi) }

    private enum CodingKeys: String, CodingKey {
        case enfant, parent, lqi, date, dAvant
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(enfant: try c.decode(String.self, forKey: .enfant), parent: try c.decode(String.self, forKey: .parent),
                  lqi: try c.decodeIfPresent(Int.self, forKey: .lqi), date: try c.decodeIfPresent(Date.self, forKey: .date),
                  dAvant: try c.decodeIfPresent(Bool.self, forKey: .dAvant) ?? false)
    }

    /// Sans `dAvant` quand il est faux : un lien lu s'ecrit comme avant.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(enfant, forKey: .enfant)
        try c.encode(parent, forKey: .parent)
        try c.encodeIfPresent(lqi, forKey: .lqi)
        try c.encodeIfPresent(date, forKey: .date)
        if dAvant { try c.encode(true, forKey: .dAvant) }
    }
}

/// Une route de la table de routage du coordinateur (le pont) : vers `destination`, par `prochain` (adresses courtes).
public struct RouteZigbee: Codable, Hashable, Sendable {
    public var destination: UInt16
    public var prochain: UInt16
    /// `active`, `decouverte`, `inactive`... tel que la sonde le donne.
    public var etat: String
    public var plusieursVersUn: Bool

    public init(destination: UInt16, prochain: UInt16, etat: String, plusieursVersUn: Bool = false) {
        self.destination = destination
        self.prochain = prochain
        self.etat = etat
        self.plusieursVersUn = plusieursVersUn
    }

    public var active: Bool { etat == "active" }
}

/// Le chemin d'un routeur vers le pont : le prochain saut de ses messages pour le coordinateur, d'apres la route
/// `0000` de sa table de routage (la route « plusieurs vers un » que le pont, concentrateur, entretient). Sans route
/// active, le chemin est **suppose** (`suppose`) : le voisin de meilleur LQI deja relie au pont.
public struct CheminPont: Codable, Hashable, Sendable {
    /// Cle du routeur (son adresse longue).
    public var routeur: String
    /// Cle du prochain saut : le pont, ou un autre routeur.
    public var prochain: String
    /// La route lue est une route « plusieurs vers un » (faux pour un chemin suppose sans route).
    public var plusieursVersUn: Bool
    /// La route lue est active (faux pour un chemin suppose).
    public var actif: Bool
    /// Chemin suppose, faute de route active vers le pont.
    public var suppose: Bool
    /// Lecture de la table de routage ; nil sans table lue.
    public var date: Date?

    public init(routeur: String, prochain: String, plusieursVersUn: Bool = false, actif: Bool = true,
                suppose: Bool = false, date: Date? = nil) {
        self.routeur = routeur
        self.prochain = prochain
        self.plusieursVersUn = plusieursVersUn
        self.actif = actif
        self.suppose = suppose
        self.date = date
    }
}

/// La route vers le pont (`destination 0000`) lue dans la table de routage d'un routeur, adresse courte du prochain
/// saut non resolue.
public struct RouteVersPont: Hashable, Sendable {
    public var prochain: UInt16
    public var actif: Bool
    public var plusieursVersUn: Bool
    public var date: Date

    public init(prochain: UInt16, actif: Bool, plusieursVersUn: Bool, date: Date) {
        self.prochain = prochain
        self.actif = actif
        self.plusieursVersUn = plusieursVersUn
        self.date = date
    }

    /// La route vers `0000` d'une table de routage : l'entree active d'abord, puis « plusieurs vers un », puis la
    /// premiere ; nil sans entree vers `0000` (ou sans prochain saut lisible).
    public static func depuis(_ entrees: [EntreeRoute], date: Date) -> RouteVersPont? {
        let versPont = entrees.compactMap { e -> RouteVersPont? in
            guard ProtocoleSonde.court(e.destination) == 0, let p = ProtocoleSonde.court(e.prochain) else { return nil }
            return RouteVersPont(prochain: p, actif: e.etat == "active", plusieursVersUn: e.plusieursVersUn ?? false,
                                 date: date)
        }
        return versPont.first { $0.actif } ?? versPont.first { $0.plusieursVersUn } ?? versPont.first
    }
}

/// Calcul des chemins vers le pont (consigne de l'etape 3 bis, section 2).
public enum CheminsPont {
    /// Les chemins des routeurs (`type == .routeur`) de `noeuds`, par cle de routeur :
    /// - une route active dont le prochain saut est un noeud connu (le pont ou un routeur, par son adresse courte) donne
    ///   le chemin lu ;
    /// - sinon, le chemin suppose : le voisin (liens radio) de meilleur LQI (la moins bonne des deux mesures ; un lien
    ///   sans mesure passe apres) qui est lui-meme relie au pont, le pont compris, par des chemins sans boucle ; tour par
    ///   tour, un routeur relie par un chemin suppose peut servir au suivant ; a LQI egal, la plus petite cle.
    /// Un routeur sans voisin relie n'a pas de chemin. Ordre : par cle de routeur.
    public static func calculer(noeuds: [NoeudZigbee], liens: [LienRadio],
                                routes: [String: RouteVersPont]) -> [CheminPont] {
        let parCourt = Dictionary(noeuds.compactMap { n in n.court.map { ($0, n) } }, uniquingKeysWith: { a, b in
            a.ieeeConnue ? a : b
        })
        let coordinateur = noeuds.first { $0.type == .coordinateur }?.ieee
        let routeurs = noeuds.filter { $0.type == .routeur }.map(\.ieee).sorted()
        var chemins: [String: CheminPont] = [:]
        for r in routeurs {
            guard let route = routes[r], route.actif, let p = parCourt[route.prochain], p.route, p.ieee != r else {
                continue
            }
            chemins[r] = CheminPont(routeur: r, prochain: p.ieee, plusieursVersUn: route.plusieursVersUn, actif: true,
                                    date: route.date)
        }
        var relies: Set<String> = coordinateur.map { [$0] } ?? []
        for r in routeurs where Self.sauts(de: r, chemins: chemins, coordinateur: coordinateur) != nil {
            relies.insert(r)
        }
        var voisins: [String: [(String, Int)]] = [:]
        for l in MaillageZigbee.reunir(liens) {
            let lqi = [l.lqiA, l.lqiB].compactMap { $0 }.min() ?? -1
            voisins[l.a, default: []].append((l.b, lqi))
            voisins[l.b, default: []].append((l.a, lqi))
        }
        var enAttente = routeurs.filter { chemins[$0] == nil }
        while !enAttente.isEmpty {
            var nouveaux: [String: CheminPont] = [:]
            for r in enAttente {
                let candidats = (voisins[r] ?? []).filter { relies.contains($0.0) && $0.0 != r }
                guard let meilleur = candidats.min(by: { ($1.1, $0.0) < ($0.1, $1.0) }) else { continue }
                let route = routes[r]
                nouveaux[r] = CheminPont(routeur: r, prochain: meilleur.0, plusieursVersUn: route?.plusieursVersUn ?? false,
                                         actif: false, suppose: true, date: route?.date)
            }
            guard !nouveaux.isEmpty else { break }
            chemins.merge(nouveaux) { a, _ in a }
            relies.formUnion(nouveaux.keys)
            enAttente.removeAll { nouveaux[$0] != nil }
        }
        return chemins.values.sorted { $0.routeur < $1.routeur }
    }

    /// Sauts jusqu'au pont en suivant les chemins depuis `ieee` (le pont : 0) ; nil si le chemin est incomplet (un
    /// noeud sans chemin, ou une boucle).
    static func sauts(de ieee: String, chemins: [String: CheminPont], coordinateur: String?) -> Int? {
        var x = ieee
        var vus: Set<String> = []
        var n = 0
        while x != coordinateur {
            guard vus.insert(x).inserted, let c = chemins[x] else { return nil }
            x = c.prochain
            n += 1
        }
        return n
    }
}

/// Ce que la sonde entend d'un voisin (sa propre table de voisins) : le « signal vu par la sonde ».
public struct SignalSonde: Codable, Hashable, Sendable {
    public var ieee: String
    public var lqi: Int

    public init(ieee: String, lqi: Int) {
        self.ieee = ieee
        self.lqi = lqi
    }
}

/// Le maillage d'une tournee (spec de l'app, sections 4 et 6) : les noeuds par IEEE, les liens radio entre routeurs
/// (deux sens), les liens des appareils finaux vers leur parent, la table de routage du pont, et la sonde.
public struct MaillageZigbee: Codable, Hashable, Sendable {
    /// Debut de la tournee.
    public var date: Date
    public var noeuds: [NoeudZigbee]
    public var liens: [LienRadio]
    public var parents: [LienParent]
    /// Table de routage du coordinateur.
    public var routesPont: [RouteZigbee]
    /// IEEE de la sonde.
    public var sonde: String?
    /// Les voisins que la sonde entend, avec leur LQI.
    public var signaux: [SignalSonde]
    /// Toutes les tables prevues ont ete demandees, et aucune n'a echoue du fait de la sonde (hors du reseau, cadence,
    /// sans reponse) : un routeur absent est vraiment parti. Faux, le suivi n'en tire ni depart ni absence.
    public var complet: Bool
    /// Le chemin de chaque routeur vers le pont (`CheminsPont`), par routeur.
    public var chemins: [CheminPont]
    /// Debut de la tournee dont viennent les tables de voisins (liens radio, parents, qualites) : elles ne sont lues
    /// qu'une tournee sur quatre ; nil si elles ne sont pas connues.
    public var dateTables: Date?

    public init(date: Date, noeuds: [NoeudZigbee] = [], liens: [LienRadio] = [], parents: [LienParent] = [],
                routesPont: [RouteZigbee] = [], sonde: String? = nil, signaux: [SignalSonde] = [], complet: Bool = true,
                chemins: [CheminPont] = [], dateTables: Date? = nil) {
        self.date = date
        self.noeuds = noeuds
        self.liens = liens
        self.parents = parents
        self.routesPont = routesPont
        self.sonde = sonde
        self.signaux = signaux
        self.complet = complet
        self.chemins = chemins
        self.dateTables = dateTables
    }

    public func noeud(_ ieee: String) -> NoeudZigbee? { noeuds.first { $0.ieee == ieee } }

    /// Le noeud d'adresse courte `court` a cette tournee.
    public func noeud(court: UInt16) -> NoeudZigbee? { noeuds.first { $0.court == court } }

    /// Le coordinateur (le pont) ; nil s'il n'est pas dans le maillage.
    public var coordinateur: NoeudZigbee? { noeuds.first { $0.type == .coordinateur } }

    /// Le parent d'un appareil final ; nil s'il n'en a pas.
    public func parent(de ieee: String) -> LienParent? { parents.first { $0.enfant == ieee } }

    /// Le parent de la sonde ; nil sans sonde, ou sans parent connu.
    public var parentSonde: String? { sonde.flatMap { parent(de: $0)?.parent } }

    /// Les liens radio d'un routeur.
    public func liens(de ieee: String) -> [LienRadio] { liens.filter { $0.relie(ieee) } }

    /// Les enfants d'un routeur.
    public func enfants(de ieee: String) -> [LienParent] { parents.filter { $0.parent == ieee } }

    /// Le prochain saut du pont vers un noeud, par la route active de sa table vers l'adresse courte du noeud ; nil
    /// sans route connue (noeud sans adresse courte, route absente ou inactive, prochain saut inconnu).
    public func viaPont(vers ieee: String) -> NoeudZigbee? {
        guard let court = noeud(ieee)?.court,
              let r = routesPont.first(where: { $0.destination == court && $0.active }) else { return nil }
        return noeud(court: r.prochain)
    }

    /// Le chemin d'un routeur vers le pont ; nil sans chemin.
    public func chemin(de ieee: String) -> CheminPont? { chemins.first { $0.routeur == ieee } }

    /// Sauts jusqu'au pont : pour un routeur, en suivant les chemins ; pour un appareil final, son parent puis les
    /// chemins de celui-ci ; 0 pour le pont. Nil si le chemin est incomplet (sans chemin ni parent, ou une boucle).
    public func sauts(de ieee: String) -> Int? {
        let parRouteur = Dictionary(chemins.map { ($0.routeur, $0) }, uniquingKeysWith: { a, _ in a })
        let pont = coordinateur?.ieee
        if let n = noeud(ieee), !n.route, let p = parent(de: ieee) {
            return CheminsPont.sauts(de: p.parent, chemins: parRouteur, coordinateur: pont).map { $0 + 1 }
        }
        return CheminsPont.sauts(de: ieee, chemins: parRouteur, coordinateur: pont)
    }

    /// Le prochain saut d'un noeud vers le pont : le prochain de son chemin (routeur) ou son parent (appareil final) ;
    /// nil pour le pont, ou sans chemin ni parent.
    public func prochainSaut(de ieee: String) -> String? {
        if let c = chemin(de: ieee) { return c.prochain }
        guard noeud(ieee)?.route != true else { return nil }
        return parent(de: ieee)?.parent
    }

    /// Le lien radio (reuni) entre deux noeuds ; nil s'il n'est pas dans les tables.
    public func lien(entre x: String, et y: String) -> LienRadio? {
        let (a, b) = x < y ? (x, y) : (y, x)
        let l = liens.filter { $0.a == a && $0.b == b }
        guard var r = l.first else { return nil }
        for autre in l.dropFirst() { r = r.fusionner(autre) }
        return r
    }

    /// Les liens radio reunis par paire de noeuds (`LienRadio.fusionner`) : un lien vu deux fois, une fois par
    /// chaque routeur, n'en fait qu'un. Ordre : par `a`, puis `b`.
    public static func reunir(_ liens: [LienRadio]) -> [LienRadio] {
        var parPaire: [String: LienRadio] = [:]
        for l in liens {
            let cle = l.a + "|" + l.b
            parPaire[cle] = parPaire[cle].map { $0.fusionner(l) } ?? l
        }
        return parPaire.values.sorted { ($0.a, $0.b) < ($1.a, $1.b) }
    }
}
