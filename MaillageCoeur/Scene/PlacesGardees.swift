import Foundation

/// Places gardees de la vue par pieces (spec de la vue par pieces, section 2.4), dans
/// `positions-pieces.json` : par maison (`domicile` de Maison), l'ordre des etages et, par etage, la
/// place (x, z) de chaque piece deplacee, par rapport au centre du plateau, en unites. Une piece est
/// reconnue par la cle de son etage et la sienne : renommee, ou passee dans un autre etage, elle
/// perd sa place. Depuis le polissage C, le choix de niveau des zones a cote (`aCote`).
public struct PlacesGardees: Hashable, Sendable, Codable {
    /// Version 1 : l'ordre et les places, puis, depuis le polissage C, les zones a cote (`aCote`), un champ
    /// facultatif, comme `appareils` dans `pieces-routeurs.json`. Un fichier d'avant se lit sans perte ; une
    /// app d'avant lit encore l'ordre et les places d'un fichier d'apres, et ignore le champ.
    public static let versionActuelle = 1
    /// Distance au centre de son plateau au-dela de laquelle une place gardee est ignoree (unites) : elle
    /// vient d'un fichier abime ou edite a la main, un glisser restant dans le plateau. Un plateau fait
    /// quelques dizaines d'unites (24 px chacune) ; la borne laisse deux ordres de grandeur de marge, et
    /// les carres des calculs (1e8) restent loin de tout debordement.
    public static let borne = 10_000.0

    public struct Place: Hashable, Sendable, Codable {
        public var x: Double
        public var z: Double

        public init(x: Double, z: Double) {
            self.x = x
            self.z = z
        }
    }

    /// Le choix d'une zone a cote (polissage C, section 1.2) : la cle de l'etage principal dont elle partage
    /// le niveau, et si elle est hors de la maison.
    public struct ACote: Hashable, Sendable, Codable {
        public var etage: String
        public var dehors: Bool

        public init(etage: String, dehors: Bool = false) {
            self.etage = etage
            self.dehors = dehors
        }
    }

    public struct Maison: Hashable, Sendable, Codable {
        /// Cles des plateaux, du bas vers le haut, zones a cote comprises.
        public var ordreEtages: [String] = []
        /// Cle d'etage -> cle de piece -> place.
        public var etages: [String: [String: Place]] = [:]
        /// Cle d'une zone a cote -> son choix ; un plateau qui n'y est pas est un etage.
        public var aCote: [String: ACote] = [:]

        public init(ordreEtages: [String] = [], etages: [String: [String: Place]] = [:], aCote: [String: ACote] = [:]) {
            self.ordreEtages = ordreEtages
            self.etages = etages
            self.aCote = aCote
        }

        private enum CodingKeys: String, CodingKey {
            case ordreEtages, etages, aCote
        }

        /// `aCote` manque aux fichiers d'avant le polissage C : des etages seulement. Mal forme, il est ignore
        /// de meme : un champ facultatif ne doit pas faire perdre l'ordre ni les places.
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            ordreEtages = try c.decode([String].self, forKey: .ordreEtages)
            etages = try c.decode([String: [String: Place]].self, forKey: .etages)
            aCote = (try? c.decodeIfPresent([String: ACote].self, forKey: .aCote)) ?? [:]
        }

        /// Sans zone a cote, le champ n'est pas ecrit : le fichier reste celui d'avant le polissage C.
        public func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(ordreEtages, forKey: .ordreEtages)
            try c.encode(etages, forKey: .etages)
            if !aCote.isEmpty { try c.encode(aCote, forKey: .aCote) }
        }
    }

    public var version = PlacesGardees.versionActuelle
    /// Par domicile ("" : maison sans nom).
    public var maisons: [String: Maison] = [:]

    public init() {}

    /// Vide si le fichier manque, est illisible, ou d'une version plus recente (`FichiersGardes`).
    public static func lire(_ url: URL) -> PlacesGardees {
        FichiersGardes.lire(PlacesGardees.self, url, version: versionActuelle) ?? PlacesGardees()
    }

    /// Rien n'est ecrit sur un fichier d'une version plus recente ; un fichier illisible est d'abord mis
    /// de cote (`FichiersGardes`).
    public func ecrire(dans url: URL) throws {
        try FichiersGardes.ecrire(self, dans: url, version: Self.versionActuelle)
    }

    public func maison(_ domicile: String) -> Maison { maisons[domicile] ?? Maison() }

    /// Garde la place d'une piece deplacee : elle est desormais fixee. Une place non finie (camera
    /// degeneree pendant un glisser) est refusee : JSON ne l'ecrit pas, et `ecrire` echouerait ensuite
    /// a chaque appel.
    public mutating func garder(_ place: SIMD2<Double>, piece: String, etage: String, domicile: String) {
        guard place.x.isFinite, place.y.isFinite else { return }
        maisons[domicile, default: Maison()].etages[etage, default: [:]][piece] = Place(x: place.x, z: place.y)
    }

    /// Garde l'ordre des etages (cles, du bas vers le haut).
    public mutating func ordonner(_ etages: [String], domicile: String) {
        maisons[domicile, default: Maison()].ordreEtages = etages
    }

    /// L'ordre des plateaux et les choix de niveau de la maison (polissage C, section 1.2).
    public func rangement(_ domicile: String) -> Rangement {
        let m = maison(domicile)
        return Rangement(ordre: m.ordreEtages, aCote: m.aCote)
    }

    /// Garde l'ordre des plateaux et les choix de niveau, apres un choix du menu du clic droit. Le nouvel ordre, celui
    /// des plateaux de la scene, est fondu dans l'ordre garde : un plateau absent de la scene y garde son rang relatif
    /// (polissage D, section 4 ; `Rangement.fondre`).
    public mutating func ranger(_ r: Rangement, domicile: String) {
        maisons[domicile, default: Maison()].ordreEtages = Rangement.fondre(r.ordre, dans: maison(domicile).ordreEtages)
        maisons[domicile, default: Maison()].aCote = r.aCote
    }

    /// « Replacer les pieces automatiquement » : oublie les places de la maison, garde l'ordre des etages et
    /// les choix de niveau.
    public mutating func replacer(domicile: String) {
        maisons[domicile]?.etages = [:]
    }

    /// Pieces fixees d'une scene : indice de piece -> place gardee, pour les pieces qui en ont une dans
    /// leur etage. Une place non finie, ou a plus de `borne` du centre, est ignoree : la piece est libre.
    public func fixees(_ scene: ScenePieces, domicile: String) -> [Int: SIMD2<Double>] {
        let m = maison(domicile)
        var r: [Int: SIMD2<Double>] = [:]
        for (i, p) in scene.pieces.enumerated() {
            if let place = m.etages[scene.etages[p.etage].id]?[p.id], place.x.isFinite, place.z.isFinite,
               hypot(place.x, place.z) <= Self.borne {
                r[i] = SIMD2(place.x, place.z)
            }
        }
        return r
    }
}
