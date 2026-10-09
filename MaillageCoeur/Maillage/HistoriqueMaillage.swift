import Foundation

/// Releve d'une tournee pour l'historique (spec de l'app, sections 4 et 7) : les noeuds, le LQI de chaque lien radio
/// dans les deux sens, celui de chaque appareil final vers son parent, et ce que la sonde entend. Le LQI brut est garde,
/// pas la qualite : les seuils de `QualiteLien` peuvent changer, les courbes la recalculent. Une ligne JSON de
/// `maillage-AAAA-MM.jsonl`, en tableaux pour rester courte :
/// - `noeuds` : `[IEEE, role]`, le role en une lettre (`c` coordinateur, `r` routeur, `f` final, `i` inconnu), puis
///   `true` pour un routeur muet ;
/// - `liens` : `[a, b, LQI mesure par a, LQI mesure par b]` (null : inconnu), `a` < `b` ;
/// - `parents` : `[enfant, parent, LQI]` (null : inconnu) ;
/// - `signaux` : `[IEEE, LQI]`, les voisins que la sonde entend ;
/// - `sonde` : l'IEEE de la sonde (absent sans sonde connue) ;
/// - `chemins` : `[routeur, prochain saut]`, puis `true` pour un chemin suppose ; absent d'un releve d'avant les
///   chemins (lu sans chemins).
/// Un parent d'avant (`LienParent.dAvant`, appareil final absent des dernieres tables) n'est pas un lien vu : ni lui
/// ni le noeud qu'il a fait ajouter n'entrent dans le releve, sans quoi l'historique le rendrait toujours frais.
/// Les dates des mesures ne sont pas gardees : celle du releve suffit. Un role inconnu (version plus recente) se lit
/// `inconnu`. Les tables de voisins n'etant lues qu'une tournee sur quatre, les liens et les parents d'une tournee qui
/// ne les lit pas sont ceux des dernieres tables (la qualite retenue a ce moment).
public struct ReleveMaillage: Hashable, Sendable {
    /// Un noeud du releve.
    public struct Noeud: Hashable, Sendable {
        public let ieee: String
        public let type: TypeNoeud
        public let muet: Bool

        public init(ieee: String, type: TypeNoeud, muet: Bool = false) {
            self.ieee = ieee
            self.type = type
            self.muet = muet
        }
    }

    public let date: Date
    /// Par IEEE croissante.
    public let noeuds: [Noeud]
    /// Sans dates, reunis par paire, par `a` puis `b`.
    public let liens: [LienRadio]
    /// Sans dates, par enfant.
    public let parents: [LienParent]
    public let signaux: [SignalSonde]
    public let sonde: String?
    /// Le prochain saut de chaque routeur vers le pont, sans dates, par routeur.
    public let chemins: [Chemin]

    /// Le chemin d'un routeur vers le pont, dans un releve.
    public struct Chemin: Hashable, Sendable {
        public let routeur: String
        public let prochain: String
        public let suppose: Bool

        public init(routeur: String, prochain: String, suppose: Bool = false) {
            self.routeur = routeur
            self.prochain = prochain
            self.suppose = suppose
        }
    }

    public init(date: Date, noeuds: [Noeud], liens: [LienRadio], parents: [LienParent], signaux: [SignalSonde] = [],
                sonde: String? = nil, chemins: [Chemin] = []) {
        self.date = date
        self.noeuds = noeuds
        self.liens = liens
        self.parents = parents
        self.signaux = signaux
        self.sonde = sonde
        self.chemins = chemins
    }

    /// Releve d'un maillage : ses noeuds par IEEE, ses liens reunis par paire, ses parents par enfant, sans les dates
    /// des mesures. Un noeud sans adresse longue valide (cle provisoire) n'y entre pas, ni ses liens : il n'est jamais
    /// une cle d'historique.
    public init(_ m: MaillageZigbee) {
        let connue = NoeudZigbee.cleConnue
        let dAvant = Set(m.parents.filter(\.dAvant).map(\.enfant))
        self.init(date: m.date,
                  noeuds: m.noeuds.filter { $0.ieeeConnue && !dAvant.contains($0.ieee) }
                      .map { Noeud(ieee: $0.ieee, type: $0.type, muet: $0.muet) }
                      .sorted { $0.ieee < $1.ieee },
                  liens: MaillageZigbee.reunir(m.liens).filter { connue($0.a) && connue($0.b) }
                      .map { LienRadio(a: $0.a, b: $0.b, lqiA: $0.lqiA, lqiB: $0.lqiB) },
                  parents: m.parents.filter { !$0.dAvant && connue($0.enfant) && connue($0.parent) }
                      .map { LienParent(enfant: $0.enfant, parent: $0.parent, lqi: $0.lqi) }
                      .sorted { $0.enfant < $1.enfant },
                  signaux: m.signaux, sonde: m.sonde,
                  chemins: m.chemins.filter { connue($0.routeur) && connue($0.prochain) }
                      .map { Chemin(routeur: $0.routeur, prochain: $0.prochain, suppose: $0.suppose) }
                      .sorted { $0.routeur < $1.routeur })
    }

    /// Le parent de la sonde ; nil sans sonde, ou sans parent connu.
    public var parentSonde: String? {
        sonde.flatMap { s in parents.first { $0.enfant == s }?.parent }
    }
}

extension ReleveMaillage: Codable {
    private enum CodingKeys: String, CodingKey {
        case date, noeuds, liens, parents, signaux, sonde, chemins
    }

    /// Le role en une lettre.
    private static let codes: [TypeNoeud: String] = [.coordinateur: "c", .routeur: "r", .final: "f", .inconnu: "i"]

    private static func type(_ code: String) -> TypeNoeud {
        codes.first { $0.value == code }?.key ?? .inconnu
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        var noeuds: [Noeud] = []
        var n = try c.nestedUnkeyedContainer(forKey: .noeuds)
        while !n.isAtEnd {
            var l = try n.nestedUnkeyedContainer()
            let ieee = try l.decode(String.self)
            let type = Self.type(try l.decode(String.self))
            let muet = l.isAtEnd ? false : (try l.decodeIfPresent(Bool.self) ?? false)
            noeuds.append(Noeud(ieee: ieee, type: type, muet: muet))
        }
        var liens: [LienRadio] = []
        var li = try c.nestedUnkeyedContainer(forKey: .liens)
        while !li.isAtEnd {
            var l = try li.nestedUnkeyedContainer()
            liens.append(LienRadio(a: try l.decode(String.self), b: try l.decode(String.self),
                                   lqiA: try l.decodeIfPresent(Int.self), lqiB: try l.decodeIfPresent(Int.self)))
        }
        var parents: [LienParent] = []
        var p = try c.nestedUnkeyedContainer(forKey: .parents)
        while !p.isAtEnd {
            var l = try p.nestedUnkeyedContainer()
            parents.append(LienParent(enfant: try l.decode(String.self), parent: try l.decode(String.self),
                                      lqi: try l.decodeIfPresent(Int.self)))
        }
        var signaux: [SignalSonde] = []
        if var s = try? c.nestedUnkeyedContainer(forKey: .signaux) {
            while !s.isAtEnd {
                var l = try s.nestedUnkeyedContainer()
                signaux.append(SignalSonde(ieee: try l.decode(String.self), lqi: try l.decode(Int.self)))
            }
        }
        var chemins: [Chemin] = []
        if var ch = try? c.nestedUnkeyedContainer(forKey: .chemins) {
            while !ch.isAtEnd {
                var l = try ch.nestedUnkeyedContainer()
                let routeur = try l.decode(String.self)
                let prochain = try l.decode(String.self)
                let suppose = l.isAtEnd ? false : (try l.decodeIfPresent(Bool.self) ?? false)
                chemins.append(Chemin(routeur: routeur, prochain: prochain, suppose: suppose))
            }
        }
        self.init(date: try c.decode(Date.self, forKey: .date), noeuds: noeuds, liens: liens, parents: parents,
                  signaux: signaux, sonde: try c.decodeIfPresent(String.self, forKey: .sonde), chemins: chemins)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(date, forKey: .date)
        var n = c.nestedUnkeyedContainer(forKey: .noeuds)
        for x in noeuds {
            var l = n.nestedUnkeyedContainer()
            try l.encode(x.ieee)
            try l.encode(Self.codes[x.type] ?? "i")
            if x.muet { try l.encode(true) }
        }
        var li = c.nestedUnkeyedContainer(forKey: .liens)
        for x in liens {
            var l = li.nestedUnkeyedContainer()
            try l.encode(x.a)
            try l.encode(x.b)
            try l.encodeOuNul(x.lqiA)
            try l.encodeOuNul(x.lqiB)
        }
        var p = c.nestedUnkeyedContainer(forKey: .parents)
        for x in parents {
            var l = p.nestedUnkeyedContainer()
            try l.encode(x.enfant)
            try l.encode(x.parent)
            try l.encodeOuNul(x.lqi)
        }
        var s = c.nestedUnkeyedContainer(forKey: .signaux)
        for x in signaux {
            var l = s.nestedUnkeyedContainer()
            try l.encode(x.ieee)
            try l.encode(x.lqi)
        }
        try c.encodeIfPresent(sonde, forKey: .sonde)
        // Sans chemin, pas de cle : la ligne d'un releve sans chemins reste celle d'avant.
        guard !chemins.isEmpty else { return }
        var ch = c.nestedUnkeyedContainer(forKey: .chemins)
        for x in chemins {
            var l = ch.nestedUnkeyedContainer()
            try l.encode(x.routeur)
            try l.encode(x.prochain)
            if x.suppose { try l.encode(true) }
        }
    }
}

private extension UnkeyedEncodingContainer {
    /// La valeur, ou null.
    mutating func encodeOuNul<T: Encodable>(_ v: T?) throws {
        if let v { try encode(v) } else { try encodeNil() }
    }
}

/// Historique des tournees sur disque (spec de la sonde, section 6) : JSON Lines mensuel
/// (`maillage-AAAA-MM.jsonl`) dans le dossier de l'app, garde 90 jours comme le journal.
public struct HistoriqueFichiers: Sendable {
    private let fichiers: FichiersMensuels

    public init(dossier: URL, calendrier: Calendar = .current) {
        fichiers = FichiersMensuels(dossier: dossier, prefixe: "maillage", calendrier: calendrier)
    }

    /// Nom du fichier du mois d'une date (« maillage-2026-09.jsonl »).
    public func nomFichier(_ date: Date) -> String { fichiers.nomFichier(date) }

    /// Ajoute le releve a la fin du fichier de son mois.
    public func ajouter(_ r: ReleveMaillage) throws {
        try fichiers.ajouter([(date: r.date, json: try CodageJSON.encodeur().encode(r))])
    }

    /// Releves dates de `debut` ou apres, du plus ancien au plus recent ; seuls les fichiers des
    /// mois qui finissent apres `debut` sont lus. Une ligne illisible est ignoree.
    public func lire(depuis debut: Date) throws -> [ReleveMaillage] {
        let decodeur = CodageJSON.decodeur()
        return try fichiers.lignes(depuis: debut)
            .compactMap { try? decodeur.decode(ReleveMaillage.self, from: $0) }
            .filter { $0.date >= debut }
            .sorted { $0.date < $1.date }
    }

    /// Supprime les fichiers des mois finis depuis plus de 90 jours ; rend leurs noms.
    @discardableResult
    public func purger(maintenant: Date) throws -> [String] {
        try fichiers.purger(maintenant: maintenant)
    }
}
