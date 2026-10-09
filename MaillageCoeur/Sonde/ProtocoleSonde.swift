import Foundation

/// Protocole USB de la sonde Zigbee, v1 (spec de la sonde, section 2) : une commande texte par ligne vers la sonde ;
/// en retour, des lignes machine RS (0x1E), JSON compact en ASCII, LF, 4096 octets au plus, `v` et `t` en tete.
public enum ProtocoleSonde {
    public static let separateur: UInt8 = 0x1E
    public static let longueurMax = 4096
    /// `bonjour.produit` d'une sonde Zigbee : tout autre port est refuse (la sonde de Maillage Thread comprise).
    public static let produit = "sonde-zigbee"
    /// Une `table` (ou des `routes`) dure au plus 120 s sur la sonde, quelles que soient les pages : l'app attend sa
    /// reponse 125 s au plus.
    public static let echeanceTable: Duration = .seconds(125)
    /// `pages` d'une reponse, ramene entre 0 et cette borne a la lecture : la sonde n'en envoie pas plus de 600 par 10
    /// minutes, et une valeur demesuree (firmware fautif) ferait deborder les sommes du budget de pages.
    public static let pagesMax = 1000

    /// Adresse courte en texte : 4 hexa majuscules, sans `0x` (« 1A2B »).
    public static func texte(court: UInt16) -> String { String(format: "%04X", court) }

    /// Adresse courte lue : exactement 4 hexa ; nil sinon.
    public static func court(_ texte: String?) -> UInt16? {
        guard let texte, texte.utf8.count == 4, texte.utf8.allSatisfy({ $0.estHexa }) else { return nil }
        return UInt16(texte, radix: 16)
    }

    /// Adresse longue utilisable comme cle : 16 hexa, rendus en majuscules ; nil sinon, et pour les deux valeurs que
    /// la pile donne a une adresse inconnue (`0000000000000000`, `FFFFFFFFFFFFFFFF`).
    public static func ieee(_ texte: String?) -> String? {
        guard let texte, texte.utf8.count == 16, texte.utf8.allSatisfy({ $0.estHexa }) else { return nil }
        let t = texte.uppercased()
        guard t != String(repeating: "0", count: 16), t != String(repeating: "F", count: 16) else { return nil }
        return t
    }
}

/// Reponse a `bonjour` : `{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":"SONDE-Z1",
/// "ieee":"A000000000000001","membre":true,"role":"final","suspendue":false}`.
public struct Bonjour: Hashable, Sendable, Codable {
    public let produit: String
    public let version: String
    /// Nom de la sonde, garde par la carte (« SONDE-Z1 » par defaut).
    public let nom: String?
    /// Adresse longue de la sonde ; nil tant que la pile n'a pas demarre.
    public let ieee: String?
    public let membre: Bool?
    /// `final` ; nil hors adhesion.
    public let role: String?
    public let suspendue: Bool?

    public init(produit: String, version: String, nom: String? = nil, ieee: String? = nil, membre: Bool? = nil,
                role: String? = nil, suspendue: Bool? = nil) {
        self.produit = produit
        self.version = version
        self.nom = nom
        self.ieee = ieee
        self.membre = membre
        self.role = role
        self.suspendue = suspendue
    }

    public var estSonde: Bool { produit == ProtocoleSonde.produit }
}

/// Parent de la sonde dans `etat`.
public struct ParentSonde: Hashable, Sendable, Codable {
    /// 4 hexa.
    public let court: String
    public let ieee: String?
    public let lqi: Int?
    public let rssi: Int?

    public init(court: String, ieee: String?, lqi: Int?, rssi: Int?) {
        self.court = court
        self.ieee = ieee
        self.lqi = lqi
        self.rssi = rssi
    }
}

/// Reponse a `etat` : adhesion, adresses, parent, reseau (PAN, EPID, canal), suspension, refus de cadence,
/// rattachements echoues, pile.
public struct EtatSonde: Hashable, Sendable, Codable {
    public let membre: Bool
    public let recherche: Bool?
    /// Adresse courte de la sonde (4 hexa) ; nil hors adhesion.
    public let court: String?
    public let ieee: String?
    public let role: String?
    /// nil hors adhesion ou pendant un rattachement.
    public let parent: ParentSonde?
    /// PAN id (4 hexa) ; nil hors adhesion.
    public let pan: String?
    /// Extended PAN ID (16 hexa, octet de poids fort d'abord) ; nil hors adhesion.
    public let epid: String?
    public let canal: Int?
    public let suspendue: Bool
    /// Refus `cadence` depuis le demarrage de la sonde.
    public let refusCadence: Int?
    /// Rattachements echoues depuis la derniere fois que la sonde etait membre.
    public let rattachementsEchoues: Int?
    /// Version de la pile Zigbee de la sonde.
    public let pile: String?

    public init(membre: Bool, recherche: Bool? = nil, court: String? = nil, ieee: String? = nil, role: String? = nil,
                parent: ParentSonde? = nil, pan: String? = nil, epid: String? = nil, canal: Int? = nil,
                suspendue: Bool = false, refusCadence: Int? = nil, rattachementsEchoues: Int? = nil,
                pile: String? = nil) {
        self.membre = membre
        self.recherche = recherche
        self.court = court
        self.ieee = ieee
        self.role = role
        self.parent = parent
        self.pan = pan
        self.epid = epid
        self.canal = canal
        self.suspendue = suspendue
        self.refusCadence = refusCadence
        self.rattachementsEchoues = rattachementsEchoues
        self.pile = pile
    }

    private enum CodingKeys: String, CodingKey {
        case membre, recherche, court, ieee, role, parent, pan, epid, canal, suspendue, pile
        case refusCadence = "refus_cadence"
        case rattachementsEchoues = "rattachements_echoues"
    }

    /// `suspendue` manque aux lignes qui ne le donnent pas : la sonde ne l'est pas.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        membre = try c.decode(Bool.self, forKey: .membre)
        recherche = try c.decodeIfPresent(Bool.self, forKey: .recherche)
        court = try c.decodeIfPresent(String.self, forKey: .court)
        ieee = try c.decodeIfPresent(String.self, forKey: .ieee)
        role = try c.decodeIfPresent(String.self, forKey: .role)
        parent = try c.decodeIfPresent(ParentSonde.self, forKey: .parent)
        pan = try c.decodeIfPresent(String.self, forKey: .pan)
        epid = try c.decodeIfPresent(String.self, forKey: .epid)
        canal = try c.decodeIfPresent(Int.self, forKey: .canal)
        suspendue = try c.decodeIfPresent(Bool.self, forKey: .suspendue) ?? false
        refusCadence = try c.decodeIfPresent(Int.self, forKey: .refusCadence)
        rattachementsEchoues = try c.decodeIfPresent(Int.self, forKey: .rattachementsEchoues)
        pile = try c.decodeIfPresent(String.self, forKey: .pile)
    }
}

/// Un voisin de la sonde (`voisins`, sa propre table) : `{"court":"1A2B","ieee":"A000000000000002","type":"routeur",
/// "relation":"parent","lqi":180,"rssi":-71,"cout_sortant":1,"age":0}`.
public struct VoisinDeLaSonde: Hashable, Sendable, Codable {
    public let court: String
    public let ieee: String?
    public let type: String?
    public let relation: String?
    public let lqi: Int?
    public let rssi: Int?
    public let coutSortant: Int?
    public let age: Int?

    public init(court: String, ieee: String?, type: String?, relation: String?, lqi: Int?, rssi: Int? = nil,
                coutSortant: Int? = nil, age: Int? = nil) {
        self.court = court
        self.ieee = ieee
        self.type = type
        self.relation = relation
        self.lqi = lqi
        self.rssi = rssi
        self.coutSortant = coutSortant
        self.age = age
    }

    private enum CodingKeys: String, CodingKey {
        case court, ieee, type, relation, lqi, rssi, age
        case coutSortant = "cout_sortant"
    }
}

/// Une entree de la table des voisins d'un routeur (`table`) : `{"court":"0000","ieee":"A000000000000003",
/// "type":"coordinateur","relation":"aucune","ecoute":true,"profondeur":0,"admission":false,"lqi":212}`.
public struct EntreeTable: Hashable, Sendable, Codable {
    public let court: String
    public let ieee: String?
    /// `coordinateur`, `routeur`, `final` ou `inconnu`.
    public let type: String?
    /// `parent`, `enfant`, `frere`, `aucune` ou `ancien_enfant`.
    public let relation: String?
    /// Recepteur allume au repos ; nil : inconnu.
    public let ecoute: Bool?
    public let profondeur: Int?
    public let admission: Bool?
    public let lqi: Int?

    public init(court: String, ieee: String?, type: String?, relation: String?, ecoute: Bool? = nil,
                profondeur: Int? = nil, admission: Bool? = nil, lqi: Int?) {
        self.court = court
        self.ieee = ieee
        self.type = type
        self.relation = relation
        self.ecoute = ecoute
        self.profondeur = profondeur
        self.admission = admission
        self.lqi = lqi
    }

    /// Le role ; un type que l'app ne connait pas est `inconnu`.
    public var typeNoeud: TypeNoeud { type.flatMap(TypeNoeud.init(rawValue:)) ?? .inconnu }
}

/// Une entree de la table de routage d'un routeur (`routes`) : `{"destination":"3C4D","etat":"active",
/// "prochain":"1A2B","memoire_limitee":false,"plusieurs_vers_un":false,"enregistrement":false}`.
public struct EntreeRoute: Hashable, Sendable, Codable {
    public let destination: String
    /// `active`, `decouverte`, `echec_decouverte`, `inactive`, `validation` ou `inconnu`.
    public let etat: String?
    public let prochain: String
    public let memoireLimitee: Bool?
    public let plusieursVersUn: Bool?
    public let enregistrement: Bool?

    public init(destination: String, etat: String?, prochain: String, memoireLimitee: Bool? = nil,
                plusieursVersUn: Bool? = nil, enregistrement: Bool? = nil) {
        self.destination = destination
        self.etat = etat
        self.prochain = prochain
        self.memoireLimitee = memoireLimitee
        self.plusieursVersUn = plusieursVersUn
        self.enregistrement = enregistrement
    }

    private enum CodingKeys: String, CodingKey {
        case destination, etat, prochain, enregistrement
        case memoireLimitee = "memoire_limitee"
        case plusieursVersUn = "plusieurs_vers_un"
    }
}

/// Une ligne d'une reponse en liste (`voisins`, `table`, `routes`) : l'en-tete (repris sur chaque ligne), une part de
/// la liste et `suite` (vrai sauf sur la derniere ligne) ; ou un echec, sur une seule ligne (`ok` faux, `erreur`,
/// `statut` pour un code ZDO). Une entree illisible est ignoree : une table qui n'est pas `partielle` n'a alors plus
/// son `total` d'entrees, et l'app la redemande.
public struct LigneListe<Entree: Codable & Hashable & Sendable>: Hashable, Sendable, Decodable {
    public let id: Int?
    public let cible: String?
    public let ok: Bool?
    public let ms: Int?
    public let pages: Int?
    public let total: Int?
    public let partielle: Bool?
    public let liste: [Entree]?
    public let suite: Bool?
    public let erreur: String?
    public let statut: String?

    public init(id: Int? = nil, cible: String? = nil, ok: Bool? = nil, ms: Int? = nil, pages: Int? = nil,
                total: Int? = nil, partielle: Bool? = nil, liste: [Entree]? = nil, suite: Bool? = nil,
                erreur: String? = nil, statut: String? = nil) {
        self.id = id
        self.cible = cible
        self.ok = ok
        self.ms = ms
        self.pages = pages
        self.total = total
        self.partielle = partielle
        self.liste = liste
        self.suite = suite
        self.erreur = erreur
        self.statut = statut
    }

    private enum CodingKeys: String, CodingKey {
        case id, cible, ok, ms, pages, total, partielle, liste, suite, erreur, statut
    }

    private struct Peutetre: Decodable {
        var valeur: Entree?
        init(from decoder: any Decoder) throws { valeur = try? Entree(from: decoder) }
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        cible = try c.decodeIfPresent(String.self, forKey: .cible)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok)
        ms = try c.decodeIfPresent(Int.self, forKey: .ms)
        pages = try c.decodeIfPresent(Int.self, forKey: .pages).map { min(max($0, 0), ProtocoleSonde.pagesMax) }
        total = try c.decodeIfPresent(Int.self, forKey: .total)
        partielle = try c.decodeIfPresent(Bool.self, forKey: .partielle)
        liste = try c.decodeIfPresent([Peutetre].self, forKey: .liste).map { $0.compactMap(\.valeur) }
        suite = try c.decodeIfPresent(Bool.self, forKey: .suite)
        erreur = try c.decodeIfPresent(String.self, forKey: .erreur)
        statut = try c.decodeIfPresent(String.self, forKey: .statut)
    }
}

/// Une reponse en liste, ses lignes reunies (`FusionLignes`) : l'en-tete de la premiere ligne et toutes les entrees,
/// dans l'ordre ; ou l'echec.
public struct ReponseListe<Entree: Codable & Hashable & Sendable>: Hashable, Sendable {
    public var id: Int?
    public var cible: String?
    public var ok: Bool
    public var ms: Int?
    public var pages: Int?
    public var total: Int?
    public var partielle: Bool
    public var liste: [Entree]
    /// Raison de l'echec : `delai`, `statut`, `cadence`, `occupee`, `suspendue`, `non_membre`, `envoi`... ou une erreur
    /// generale de la sonde (`syntaxe`, `inconnue`...).
    public var erreur: String?
    /// Code ZDO de la reponse (« 0x84 ») quand `erreur` vaut `statut`.
    public var statut: String?

    public init(id: Int? = nil, cible: String? = nil, ok: Bool, ms: Int? = nil, pages: Int? = nil, total: Int? = nil,
                partielle: Bool = false, liste: [Entree] = [], erreur: String? = nil, statut: String? = nil) {
        self.id = id
        self.cible = cible
        self.ok = ok
        self.ms = ms
        self.pages = pages
        self.total = total
        self.partielle = partielle
        self.liste = liste
        self.erreur = erreur
        self.statut = statut
    }

    /// Un echec, sans liste.
    public static func echec(_ erreur: String, id: Int? = nil, cible: String? = nil) -> ReponseListe {
        ReponseListe(id: id, cible: cible, ok: false, erreur: erreur)
    }

    /// Une reponse reussie et non `partielle` porte exactement `total` entrees : sinon une ligne s'est perdue en route,
    /// et la table est a redemander. Un echec, une table `partielle` ou sans `total` sont complets.
    public var complete: Bool {
        guard ok, !partielle, let total else { return true }
        return liste.count == total
    }
}

/// Reunit les lignes d'une reponse en liste : chaque ligne `suite` s'ajoute, la derniere (`suite` faux ou absent) rend
/// la reponse ; un echec (`ok` faux) la rend tout de suite. Un echec garde ses `pages` s'il en donne (le budget de pages de
/// l'app les compte).
public struct FusionLignes<Entree: Codable & Hashable & Sendable>: Sendable {
    private var premiere: LigneListe<Entree>?
    private var entrees: [Entree] = []

    public init() {}

    /// Aucune ligne recue depuis la derniere reponse rendue.
    public var vide: Bool { premiere == nil }

    public mutating func ajouter(_ l: LigneListe<Entree>) -> ReponseListe<Entree>? {
        if l.ok == false || (l.erreur != nil && l.liste == nil) {
            premiere = nil
            entrees = []
            return ReponseListe(id: l.id, cible: l.cible, ok: false, pages: l.pages, erreur: l.erreur ?? "",
                                statut: l.statut)
        }
        let p = premiere ?? l
        premiere = p
        entrees += l.liste ?? []
        guard l.suite != true else { return nil }
        defer {
            premiere = nil
            entrees = []
        }
        return ReponseListe(id: p.id, cible: p.cible, ok: true, ms: p.ms, pages: p.pages, total: p.total,
                            partielle: p.partielle ?? false, liste: entrees)
    }
}

/// Signal de la pile Zigbee, donne de lui-meme par la sonde (`signal`) : `{"signal":"0x32",
/// "nom":"NLME_STATUS_INDICATION","ok":true,"detail":9}`. L'app n'en tire qu'un compteur : jamais une ligne du journal
/// de l'utilisateur.
public struct SignalPile: Hashable, Sendable, Codable {
    public let signal: String
    public let nom: String?
    public let ok: Bool?
    public let detail: Int?

    public init(signal: String, nom: String? = nil, ok: Bool? = nil, detail: Int? = nil) {
        self.signal = signal
        self.nom = nom
        self.ok = ok
        self.detail = detail
    }

    /// `NLME_STATUS_INDICATION` de statut 9 : la pile declare le parent perdu (spec de la sonde, section 8, E7).
    public var parentPerdu: Bool { nom == "NLME_STATUS_INDICATION" && detail == 9 }
}

/// Message de la sonde, d'apres son type.
public enum MessageSonde: Hashable, Sendable {
    case bonjour(Bonjour)
    case etat(EtatSonde)
    /// La sonde n'a pas servi une commande sans id (`{"t":"etat","erreur":"occupee"}`, de meme pour `voisins`).
    case refusee(commande: String, erreur: String)
    case voisins(LigneListe<VoisinDeLaSonde>)
    case table(LigneListe<EntreeTable>)
    case routes(LigneListe<EntreeRoute>)
    case signal(SignalPile)
    /// Reponse a `oubli` (que l'app n'envoie jamais d'elle-meme).
    case oubli(Bool)
    /// `{"t":"erreur","erreur":"inconnue"}` : commande inconnue, mal formee (`syntaxe`), ligne trop longue...
    case erreur(String)
    /// Un type que l'app ne lit pas.
    case inconnu(String)

    private struct Entete: Decodable {
        let v: Int
        let t: String
    }

    private struct Erreur: Decodable {
        let erreur: String
    }

    private struct Oubli: Decodable {
        let ok: Bool
    }

    /// JSON d'une ligne machine, sans RS ni LF ; nil si illisible ou d'une autre version.
    public static func lire(_ json: Data) -> MessageSonde? {
        let d = JSONDecoder()
        guard let e = try? d.decode(Entete.self, from: json), e.v == 1 else { return nil }
        switch e.t {
        case "bonjour": return (try? d.decode(Bonjour.self, from: json)).map { .bonjour($0) }
        case "etat":
            if let etat = try? d.decode(EtatSonde.self, from: json) { return .etat(etat) }
            return (try? d.decode(Erreur.self, from: json)).map { .refusee(commande: "etat", erreur: $0.erreur) }
        case "voisins":
            guard let l = try? d.decode(LigneListe<VoisinDeLaSonde>.self, from: json) else { return nil }
            if l.liste == nil, let erreur = l.erreur { return .refusee(commande: "voisins", erreur: erreur) }
            return l.liste == nil ? nil : .voisins(l)
        case "table":
            return (try? d.decode(LigneListe<EntreeTable>.self, from: json)).flatMap { Self.valide($0) }.map { .table($0) }
        case "routes":
            return (try? d.decode(LigneListe<EntreeRoute>.self, from: json)).flatMap { Self.valide($0) }.map { .routes($0) }
        case "signal": return (try? d.decode(SignalPile.self, from: json)).map { .signal($0) }
        case "oubli": return (try? d.decode(Oubli.self, from: json)).map { .oubli($0.ok) }
        case "erreur": return (try? d.decode(Erreur.self, from: json)).map { .erreur($0.erreur) }
        default: return .inconnu(e.t)
        }
    }

    /// Une ligne de `table` ou `routes` porte son id, sa cible et `ok` ; une ligne reussie, sa liste.
    private static func valide<E>(_ l: LigneListe<E>) -> LigneListe<E>? {
        guard l.id != nil, l.cible != nil, let ok = l.ok else { return nil }
        return ok && l.liste == nil ? nil : l
    }
}

/// Commande envoyee a la sonde. L'app n'envoie jamais `oubli`, `suspendre`, `reprendre`, `nom` ni `echecs` : aucune
/// commande ne les ecrit.
public enum CommandeSonde: Hashable, Sendable {
    case bonjour
    case etat
    case voisins
    /// Table des voisins de `cible`, sous l'id `id` ; delai par page en ms (500 a 5000, 5000 par defaut).
    case table(cible: UInt16, id: Int, delaiMs: Int? = nil)
    /// Table de routage de `cible`, memes regles.
    case routes(cible: UInt16, id: Int, delaiMs: Int? = nil)

    /// Ligne a envoyer, fin de ligne comprise.
    public var ligne: String {
        switch self {
        case .bonjour: "bonjour\n"
        case .etat: "etat\n"
        case .voisins: "voisins\n"
        case let .table(cible, id, delai): Self.requete("table", cible, id, delai)
        case let .routes(cible, id, delai): Self.requete("routes", cible, id, delai)
        }
    }

    private static func requete(_ genre: String, _ cible: UInt16, _ id: Int, _ delaiMs: Int?) -> String {
        var l = "\(genre) \(ProtocoleSonde.texte(court: cible)) \(id)"
        if let delaiMs { l += " \(min(max(delaiMs, 500), 5000))" }
        return l + "\n"
    }
}

/// Decoupe le flux USB en lignes machine (RS ... LF), sans le RS ; le reste
/// (journaux de la pile, lignes humaines) est ignore, comme une ligne trop longue.
/// La ligne machine commence au dernier RS de la ligne, comme dans le pont Halo : ce qui le
/// precede (queue d'un journal sans fin de ligne, invite, ligne machine coupee) est abandonne.
public struct DecoupeurLignes: Sendable {
    private var tampon: [UInt8] = []
    private var tropLongue = false

    public init() {}

    public mutating func ajouter(_ d: Data) -> [Data] {
        var lignes: [Data] = []
        for o in d {
            if o == ProtocoleSonde.separateur {
                // Le JSON est de l'ASCII imprimable, sans RS : un RS ouvre toujours une ligne machine.
                tampon.removeAll(keepingCapacity: true)
                tampon.append(o)
                tropLongue = false
            } else if o == 0x0A {
                if !tropLongue, tampon.first == ProtocoleSonde.separateur {
                    var l = tampon.dropFirst()
                    if l.last == 0x0D { l = l.dropLast() }
                    lignes.append(Data(l))
                }
                tampon.removeAll(keepingCapacity: true)
                tropLongue = false
            } else if tampon.count < ProtocoleSonde.longueurMax {
                tampon.append(o)
            } else {
                tropLongue = true
            }
        }
        return lignes
    }
}
