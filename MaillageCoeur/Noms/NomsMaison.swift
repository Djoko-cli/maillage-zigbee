import Foundation

/// Batterie d'un appareil, telle que le pont la donne (`device_power` de l'API v2).
public struct BatterieMaison: Codable, Hashable, Sendable {
    /// Etat de charge.
    public enum Charge: String, Codable, Hashable, Sendable {
        case horsCharge
        case enCharge
        case nonRechargeable
    }

    /// Niveau, en %, a partir duquel la batterie est dite faible si
    /// l'accessoire ne le signale pas lui-meme.
    public static let seuilFaible = 20

    /// De 0 a 100 ; absent quand l'appareil ne donne que l'alerte.
    public var niveau: Int?
    public var charge: Charge?
    /// L'appareil signale lui-meme sa batterie faible.
    public var alerte: Bool?

    public init(niveau: Int? = nil, charge: Charge? = nil, alerte: Bool? = nil) {
        self.niveau = niveau
        self.charge = charge
        self.alerte = alerte
    }

    private enum CodingKeys: String, CodingKey {
        case niveau, charge, alerte
    }

    /// Un etat de charge inconnu (ecrit par une version plus recente de l'app)
    /// est ignore, plutot que de rendre tout le releve illisible.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        niveau = try c.decodeIfPresent(Int.self, forKey: .niveau)
        charge = (try? c.decodeIfPresent(Charge.self, forKey: .charge)) ?? nil
        alerte = try c.decodeIfPresent(Bool.self, forKey: .alerte)
    }

    /// Faible : l'accessoire le signale, ou son niveau est au plus au seuil.
    public var faible: Bool {
        alerte == true || niveau.map { $0 <= Self.seuilFaible } == true
    }
}

/// Etat de connexion d'un appareil vu par le pont (`zigbee_connectivity.status` de l'API v2), sous les noms de l'API.
public enum ConnexionZigbee: String, Codable, Hashable, Sendable {
    case connecte = "connected"
    case deconnecte = "disconnected"
    case problemeConnexion = "connectivity_issue"
    /// Le pont l'entend, mais ne l'atteint pas.
    case entrantSeul = "unidirectional_incoming"
    /// Un etat que l'app ne connait pas (API plus recente).
    case inconnue = "unknown"

    /// Un etat inconnu est garde comme `inconnue`, plutot que de rendre tout le releve illisible.
    public init(from decoder: any Decoder) throws {
        self = ConnexionZigbee(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .inconnue
    }

    /// L'etat de l'API (nil : absent) ; un etat inconnu donne `inconnue`.
    public static func depuis(api texte: String?) -> ConnexionZigbee? {
        texte.map { ConnexionZigbee(rawValue: $0) ?? .inconnue }
    }
}

/// Un appareil du pont (spec de l'app, section 3) : son nom, sa piece, ce qui le decrit, sa batterie, son adresse
/// longue (`zigbee_connectivity.mac_address`), la cle qui le rapproche du maillage de la sonde, et son etat de
/// connexion vu par le pont.
public struct AccessoireMaison: Codable, Hashable, Sendable {
    public var nom: String
    public var piece: String?
    public var fabricant: String?
    public var modele: String?
    public var firmware: String?
    public var categorie: String?
    /// Adresse longue Zigbee, 16 hexa majuscules ; nil pour un appareil qui n'est pas sur le maillage.
    public var ieee: String?
    /// Batterie, pour un appareil qui en a une.
    public var batterie: BatterieMaison?
    /// Etat de connexion selon le pont ; nil s'il ne le donne pas (demo, appareil sans Zigbee).
    public var connexion: ConnexionZigbee?
    /// Code du modele selon le pont (`product_data.model_id`, « LCA001 ») quand `modele` est le nom du produit : Maison
    /// peut donner l'un ou l'autre (`FusionNoms`).
    public var idModele: String?
    /// D'ou viennent le nom et la piece : de Maison (l'accessoire y a ete retrouve) ou du pont Hue ; nil sans releve de
    /// Maison (`FusionNoms`).
    public var origine: OrigineNom?

    public init(nom: String, piece: String? = nil, fabricant: String? = nil, modele: String? = nil,
                firmware: String? = nil, categorie: String? = nil, ieee: String? = nil,
                batterie: BatterieMaison? = nil, connexion: ConnexionZigbee? = nil, idModele: String? = nil,
                origine: OrigineNom? = nil) {
        self.nom = nom
        self.piece = piece
        self.fabricant = fabricant
        self.modele = modele
        self.firmware = firmware
        self.categorie = categorie
        self.ieee = ieee
        self.batterie = batterie
        self.connexion = connexion
        self.idModele = idModele
        self.origine = origine
    }
}

/// Origine du nom et de la piece d'un appareil du pont (`FusionNoms`).
public enum OrigineNom: String, Codable, Hashable, Sendable {
    /// Retrouve dans Maison : son nom et sa piece de Maison.
    case maison
    /// Pas retrouve dans Maison : son nom et sa piece de l'app Hue.
    case pont
}

/// Le reseau Zigbee du pont, d'apres son `zigbee_connectivity` : canal et extended PAN ID (16 hexa majuscules).
public struct ReseauZigbee: Codable, Hashable, Sendable {
    public var canal: Int?
    public var epid: String?

    public init(canal: Int?, epid: String?) {
        self.canal = canal
        self.epid = epid
    }

    /// La sonde (`etat`) est-elle sur ce reseau ? Faux si le canal ou l'extended PAN ID connus des deux cotes
    /// different ; vrai sinon (rien a comparer compris). L'extended PAN ID est compare dans les deux ordres des octets :
    /// l'API du pont ne dit pas le sien.
    public func accueille(_ e: EtatSonde) -> Bool {
        guard e.membre else { return true }
        if let a = canal, let b = e.canal, a != b { return false }
        if let a = epid, let b = ProtocoleSonde.ieee(e.epid) ?? e.epid?.uppercased() {
            return a == b || a == Self.inverse(b)
        }
        return true
    }

    /// Les octets d'un hexa dans l'ordre inverse.
    static func inverse(_ hexa: String) -> String {
        let c = Array(hexa)
        return stride(from: c.count - 2, through: 0, by: -2).map { String(c[$0...$0 + 1]) }.joined()
    }
}

/// Zone de la maison, en general un etage, et ses pieces, dans son ordre. Une piece peut appartenir a plusieurs zones.
/// Les zones viennent de Maison (`ReleveMaison`) : le pont Hue n'a pas d'etages ; sans zones, la vue montre un seul
/// plateau.
public struct ZoneMaison: Codable, Hashable, Sendable {
    public var nom: String
    public var pieces: [String]

    public init(nom: String, pieces: [String] = []) {
        self.nom = nom
        self.pieces = pieces
    }
}

/// Les noms de la maison : ses appareils, ses pieces et ses zones. Le pont Hue donne les appareils (`LectureHue`,
/// `NomsPont`) ; le releve de Maison, par le Passeur, leurs noms, leurs pieces et les zones (`FusionNoms`). `domicile`
/// (celui de Maison, sinon l'identifiant du pont) est la cle des choix de l'utilisateur (places gardees, pieces
/// choisies).
public struct NomsMaison: Codable, Hashable, Sendable {
    public static let versionActuelle = 1

    public var version: Int
    public var date: Date
    public var domicile: String?
    public var accessoires: [AccessoireMaison]
    /// Zones, dans leur ordre ; nil ou vide pour une maison qui n'en a pas.
    public var zones: [ZoneMaison]?
    /// Le reseau Zigbee du pont (canal, extended PAN ID), quand l'API le donne.
    public var reseau: ReseauZigbee?

    public init(version: Int = NomsMaison.versionActuelle, date: Date, domicile: String? = nil,
                accessoires: [AccessoireMaison] = [], zones: [ZoneMaison]? = nil, reseau: ReseauZigbee? = nil) {
        self.version = version
        self.date = date
        self.domicile = domicile
        self.accessoires = accessoires
        self.zones = zones
        self.reseau = reseau
    }

    public enum Erreur: Error, Equatable {
        case versionTropRecente(Int)
    }

    /// Lit un releve garde ; refuse une version plus recente que celle de l'app.
    public static func lire(_ donnees: Data) throws -> NomsMaison {
        let n = try CodageJSON.decodeur().decode(NomsMaison.self, from: donnees)
        guard n.version <= versionActuelle else { throw Erreur.versionTropRecente(n.version) }
        return n
    }

    /// L'appareil d'adresse longue `ieee` (sans egard a la casse) ; nil si le pont ne le connait pas.
    public func accessoire(ieee: String) -> AccessoireMaison? {
        let x = ieee.uppercased()
        return accessoires.first { $0.ieee?.uppercased() == x }
    }

    public func donnees() throws -> Data {
        try CodageJSON.encodeur(lisible: true).encode(self)
    }
}
