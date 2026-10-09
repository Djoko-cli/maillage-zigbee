import Foundation

/// Issue de la lecture de Maison par le Passeur.
public enum StatutPasseur: String, Codable, Hashable, Sendable {
    case ok
    /// L'utilisateur a refuse l'acces a Maison.
    case refuse
    /// Maison indisponible : prevu par le format, le Passeur ne l'ecrit pas aujourd'hui.
    case indisponible
    /// Echec du releve (aucun domicile, Maison sans reponse) ; `message` le detaille.
    case erreur
}

/// Accessoire de Maison, tel que le Passeur le releve (format fige : le Passeur, celui de Maillage Thread, ne change
/// pas).
public struct AccessoireReleve: Codable, Hashable, Sendable {
    public var nom: String
    public var piece: String?
    public var fabricant: String?
    public var modele: String?
    public var firmware: String?
    public var categorie: String?
    /// Noeud Matter de l'accessoire (16 hexa majuscules) : un pont Matter le partage avec les accessoires qu'il porte.
    public var noeudMatter: String?
    /// Accessoire de categorie pont.
    public var pont: Bool?
    /// Batterie (service Batterie de Maison) ; l'app garde celle du pont Hue.
    public var batterie: BatterieMaison?

    public init(nom: String, piece: String? = nil, fabricant: String? = nil, modele: String? = nil,
                firmware: String? = nil, categorie: String? = nil, noeudMatter: String? = nil, pont: Bool? = nil,
                batterie: BatterieMaison? = nil) {
        self.nom = nom
        self.piece = piece
        self.fabricant = fabricant
        self.modele = modele
        self.firmware = firmware
        self.categorie = categorie
        self.noeudMatter = noeudMatter
        self.pont = pont
        self.batterie = batterie
    }
}

/// Releve de Maison par le Passeur (app iOS « concue pour iPad », installee sur le Mac avec Maillage Thread) : les
/// accessoires avec leur nom et leur piece, les zones (les etages) et leurs pieces, le domicile. Il arrive par la boucle
/// locale (`EnvoiPasseur`), en JSON, au format du Passeur ; l'app garde le dernier releve reussi dans son conteneur
/// (`releve-maison.json`). Les noms et pieces de Maison l'emportent sur ceux du pont Hue (`FusionNoms`).
public struct ReleveMaison: Codable, Hashable, Sendable {
    /// Version du format du Passeur.
    public static let versionActuelle = 1

    public var version: Int
    public var date: Date
    public var statut: StatutPasseur
    public var message: String?
    /// Nom du domicile (plusieurs domiciles : leurs noms joints par « + »).
    public var domicile: String?
    public var accessoires: [AccessoireReleve]
    /// Zones de Maison, dans son ordre ; vide ou absent pour une maison qui n'en a pas.
    public var zones: [ZoneMaison]?

    public init(version: Int = ReleveMaison.versionActuelle, date: Date, statut: StatutPasseur = .ok,
                message: String? = nil, domicile: String? = nil, accessoires: [AccessoireReleve] = [],
                zones: [ZoneMaison]? = nil) {
        self.version = version
        self.date = date
        self.statut = statut
        self.message = message
        self.domicile = domicile
        self.accessoires = accessoires
        self.zones = zones
    }

    public enum Erreur: Error, Equatable {
        case versionTropRecente(Int)
    }

    /// Lit un releve (celui du Passeur, ou celui garde) ; refuse une version plus recente que celle de l'app.
    public static func lire(_ donnees: Data) throws -> ReleveMaison {
        let r = try CodageJSON.decodeur().decode(ReleveMaison.self, from: donnees)
        guard r.version <= versionActuelle else { throw Erreur.versionTropRecente(r.version) }
        return r
    }

    public func donnees() throws -> Data {
        try CodageJSON.encodeur(lisible: true).encode(self)
    }
}
