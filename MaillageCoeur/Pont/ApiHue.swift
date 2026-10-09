import Foundation

/// Les reponses de l'API v2 du pont Hue (CLIP v2) que l'app lit, et ce qu'elle en fait (spec de l'app, section 3).
/// Seuls les champs utiles sont decodes ; un element illisible d'une liste est ignore, sans rendre la liste illisible.
public enum ApiHue {
    /// Reference a une ressource (`{"rid": ..., "rtype": ...}`).
    public struct Ref: Decodable, Hashable, Sendable {
        public var rid: String
        public var rtype: String

        public init(rid: String, rtype: String) {
            self.rid = rid
            self.rtype = rtype
        }
    }

    /// `GET /clip/v2/resource/bridge` : l'identifiant du pont et son propre appareil (`owner`).
    public struct Pont: Decodable, Hashable, Sendable {
        public var identifiant: String
        public var appareil: String

        private enum CodingKeys: String, CodingKey {
            case identifiant = "bridge_id"
            case owner
        }

        public init(identifiant: String, appareil: String) {
            self.identifiant = identifiant
            self.appareil = appareil
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            identifiant = try c.decode(String.self, forKey: .identifiant)
            appareil = try c.decode(Ref.self, forKey: .owner).rid
        }
    }

    /// `GET /clip/v2/resource/device`.
    public struct Appareil: Decodable, Hashable, Sendable {
        public var id: String
        public var nom: String
        public var archetype: String?
        public var fabricant: String?
        public var modeleId: String?
        public var produit: String?
        public var logiciel: String?

        private enum CodingKeys: String, CodingKey {
            case id, metadata
            case produit = "product_data"
        }

        private enum Metadonnees: String, CodingKey {
            case name, archetype
        }

        private enum Produit: String, CodingKey {
            case manufacturer = "manufacturer_name"
            case model = "model_id"
            case product = "product_name"
            case software = "software_version"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            let m = try c.nestedContainer(keyedBy: Metadonnees.self, forKey: .metadata)
            nom = try m.decode(String.self, forKey: .name)
            archetype = try? m.decodeIfPresent(String.self, forKey: .archetype)
            let p = try? c.nestedContainer(keyedBy: Produit.self, forKey: .produit)
            fabricant = (try? p?.decodeIfPresent(String.self, forKey: .manufacturer)) ?? nil
            modeleId = (try? p?.decodeIfPresent(String.self, forKey: .model)) ?? nil
            produit = (try? p?.decodeIfPresent(String.self, forKey: .product)) ?? nil
            logiciel = (try? p?.decodeIfPresent(String.self, forKey: .software)) ?? nil
        }
    }

    /// `GET /clip/v2/resource/zigbee_connectivity` : l'etat de connexion et l'adresse longue d'un appareil ; pour le
    /// pont, le canal et l'extended PAN ID du reseau quand l'API les donne (`channel` :
    /// `{"status":"set","value":"channel_25"}`, `extended_pan_id` : 8 octets en hexa, separes ou non par `:`).
    public struct Connectivite: Decodable, Hashable, Sendable {
        public var appareil: String
        public var etat: String?
        public var adresse: String?
        public var canal: Int?
        /// 16 hexa majuscules, sans separateurs, dans l'ordre de l'API.
        public var epid: String?

        private enum CodingKeys: String, CodingKey {
            case owner, status, channel
            case adresse = "mac_address"
            case epid = "extended_pan_id"
        }

        private enum Canal: String, CodingKey {
            case value
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appareil = try c.decode(Ref.self, forKey: .owner).rid
            etat = try? c.decodeIfPresent(String.self, forKey: .status)
            adresse = try? c.decodeIfPresent(String.self, forKey: .adresse)
            if let n = try? c.decodeIfPresent(Int.self, forKey: .channel) {
                canal = n
            } else if let v = try? c.nestedContainer(keyedBy: Canal.self, forKey: .channel)
                        .decodeIfPresent(String.self, forKey: .value) {
                canal = Int(v.replacingOccurrences(of: "channel_", with: ""))
            }
            epid = (try? c.decodeIfPresent(String.self, forKey: .epid)).flatMap { $0.flatMap(ApiHue.adresseLongue) }
        }
    }

    /// `GET /clip/v2/resource/room` : le nom de la piece et ses appareils.
    public struct Piece: Decodable, Hashable, Sendable {
        public var nom: String
        public var appareils: [String]

        private enum CodingKeys: String, CodingKey {
            case metadata, children
        }

        private enum Metadonnees: String, CodingKey {
            case name
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nom = try c.nestedContainer(keyedBy: Metadonnees.self, forKey: .metadata).decode(String.self, forKey: .name)
            let enfants = (try? c.decodeIfPresent(Liste<Ref>.self, forKey: .children))?.elements ?? []
            appareils = enfants.filter { $0.rtype == "device" }.map(\.rid)
        }
    }

    /// `GET /clip/v2/resource/device_power` : la pile d'un appareil.
    public struct Alimentation: Decodable, Hashable, Sendable {
        public var appareil: String
        public var niveau: Int?
        /// `normal`, `low`, `critical`.
        public var etat: String?

        private enum CodingKeys: String, CodingKey {
            case owner
            case pile = "power_state"
        }

        private enum Pile: String, CodingKey {
            case niveau = "battery_level"
            case etat = "battery_state"
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            appareil = try c.decode(Ref.self, forKey: .owner).rid
            let p = try? c.nestedContainer(keyedBy: Pile.self, forKey: .pile)
            niveau = (try? p?.decodeIfPresent(Int.self, forKey: .niveau)) ?? nil
            etat = (try? p?.decodeIfPresent(String.self, forKey: .etat)) ?? nil
        }

        /// La batterie de l'app ; nil sans niveau ni etat (l'appareil n'a pas de pile).
        public var batterie: BatterieMaison? {
            guard niveau != nil || etat != nil else { return nil }
            let alerte = etat.map { $0 == "low" || $0 == "critical" }
            return BatterieMaison(niveau: niveau.map { min(max($0, 0), 100) }, alerte: alerte)
        }
    }

    /// Une liste tolerante : chaque element illisible est ignore.
    struct Liste<T: Decodable>: Decodable {
        var elements: [T]

        private struct Peutetre: Decodable {
            var valeur: T?
            init(from decoder: any Decoder) throws { valeur = try? T(from: decoder) }
        }

        init(from decoder: any Decoder) throws {
            elements = try [Peutetre](from: decoder).compactMap(\.valeur)
        }
    }

    /// L'enveloppe d'une reponse : `{"errors": [{"description": ...}], "data": [...]}`.
    private struct Enveloppe<T: Decodable>: Decodable {
        struct Erreur: Decodable {
            var description: String?
        }

        var errors: [Erreur]?
        var data: Liste<T>?
    }

    public enum ErreurLecture: Error, Equatable, Sendable {
        /// Corps illisible, ou sans `data`.
        case illisible
        /// `data` vide et des erreurs (leur description, la premiere).
        case erreurs(String)
    }

    /// Les elements `data` d'une reponse. Une reponse sans `data` est illisible ; une reponse aux `data` vides et avec
    /// des erreurs est une erreur ; des erreurs a cote de donnees sont ignorees.
    public static func lire<T: Decodable>(_ type: T.Type, _ corps: Data) throws(ErreurLecture) -> [T] {
        guard let e = try? JSONDecoder().decode(Enveloppe<T>.self, from: corps), let data = e.data else {
            throw .illisible
        }
        if data.elements.isEmpty, let erreur = e.errors?.first {
            throw .erreurs(erreur.description ?? "")
        }
        return data.elements
    }

    /// Adresse longue de `mac_address` (« a0:00:00:00:00:00:00:12 », parfois suivie de « -0b », l'endpoint) :
    /// 16 hexa majuscules, sans separateurs ni endpoint ; nil si ce n'est pas une adresse de 8 octets.
    public static func adresseLongue(_ mac: String) -> String? {
        let sansEndpoint = mac.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let hexa = sansEndpoint.filter { $0 != ":" }.trimmingCharacters(in: .whitespaces)
        guard hexa.utf8.count == 16, hexa.utf8.allSatisfy({ $0.estHexa }) else { return nil }
        return hexa.uppercased()
    }
}

/// Reponse a une demande de liaison (`POST /api` avec `devicetype` et `generateclientkey`) : la cle d'application, ou
/// l'attente du bouton (erreur 101), ou une autre erreur. La cle n'apparait jamais dans une description (journal,
/// echec de test).
public enum ReponseLiaison: Equatable, Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    /// `username` : la cle d'application. Le `clientkey` (Entertainment) n'est pas garde.
    case cle(String)
    /// Erreur 101 : le bouton du pont n'a pas ete appuye.
    case boutonNonAppuye
    case erreur(type: Int, description: String)

    /// Erreur de l'API « link button not pressed ».
    public static let codeBouton = 101

    private struct Element: Decodable {
        struct Succes: Decodable {
            var username: String?
        }

        struct Erreur: Decodable {
            var type: Int?
            var description: String?
        }

        var success: Succes?
        var error: Erreur?
    }

    /// La reponse ; nil si le corps n'est pas une liste de succes ou d'erreurs.
    public static func lire(_ corps: Data) -> ReponseLiaison? {
        guard let elements = try? JSONDecoder().decode([Element].self, from: corps) else { return nil }
        for e in elements {
            if let cle = e.success?.username, !cle.isEmpty { return .cle(cle) }
        }
        guard let erreur = elements.compactMap(\.error).first else { return nil }
        if erreur.type == codeBouton { return .boutonNonAppuye }
        return .erreur(type: erreur.type ?? 0, description: erreur.description ?? "")
    }

    public var description: String {
        switch self {
        case .cle: "cle(<masquee>)"
        case .boutonNonAppuye: "boutonNonAppuye"
        case .erreur(let type, let description): "erreur(\(type), \(description))"
        }
    }

    public var debugDescription: String { description }
}

/// Une lecture complete du pont : ses cinq ressources, d'ou l'app tire les noms de la maison.
public struct LectureHue: Hashable, Sendable {
    public var pont: ApiHue.Pont
    public var appareils: [ApiHue.Appareil]
    public var connectivites: [ApiHue.Connectivite]
    public var pieces: [ApiHue.Piece]
    public var alimentations: [ApiHue.Alimentation]

    public init(pont: ApiHue.Pont, appareils: [ApiHue.Appareil], connectivites: [ApiHue.Connectivite],
                pieces: [ApiHue.Piece], alimentations: [ApiHue.Alimentation]) {
        self.pont = pont
        self.appareils = appareils
        self.connectivites = connectivites
        self.pieces = pieces
        self.alimentations = alimentations
    }

    /// Les noms de la maison : `domicile` = l'identifiant du pont, en majuscules ; un appareil par device, le pont
    /// compris (son adresse longue est celle du coordinateur), avec sa piece, son fabricant, son modele (le nom du
    /// produit, sinon son code ; avec un nom de produit, le code a part, dans `idModele`), son logiciel, son archetype,
    /// son adresse longue, sa pile et son etat de connexion. Pas de zones : Hue n'a pas d'etages (elles viennent de
    /// Maison, `FusionNoms`). Appareils ranges par nom, puis par adresse longue.
    public func noms(date: Date) -> NomsMaison {
        var pieceDe: [String: String] = [:]
        for p in pieces.sorted(by: { $0.nom < $1.nom }) {
            for a in p.appareils where pieceDe[a] == nil { pieceDe[a] = p.nom }
        }
        var connectiviteDe: [String: ApiHue.Connectivite] = [:]
        for c in connectivites where connectiviteDe[c.appareil] == nil { connectiviteDe[c.appareil] = c }
        var batterieDe: [String: BatterieMaison] = [:]
        for a in alimentations where batterieDe[a.appareil] == nil {
            if let b = a.batterie { batterieDe[a.appareil] = b }
        }
        let accessoires = appareils.map { a in
            let c = connectiviteDe[a.id]
            return AccessoireMaison(nom: a.nom, piece: pieceDe[a.id], fabricant: a.fabricant,
                                    modele: a.produit ?? a.modeleId, firmware: a.logiciel, categorie: a.archetype,
                                    ieee: c?.adresse.flatMap(ApiHue.adresseLongue), batterie: batterieDe[a.id],
                                    connexion: ConnexionZigbee.depuis(api: c?.etat),
                                    idModele: a.produit == nil ? nil : a.modeleId)
        }.sorted { ($0.nom, $0.ieee ?? "") < ($1.nom, $1.ieee ?? "") }
        let reseau = connectiviteDe[pont.appareil].flatMap { c -> ReseauZigbee? in
            c.canal == nil && c.epid == nil ? nil : ReseauZigbee(canal: c.canal, epid: c.epid)
        }
        return NomsMaison(date: date, domicile: CertificatPont.identifiant(pont.identifiant) ?? pont.identifiant.uppercased(),
                          accessoires: accessoires, reseau: reseau)
    }

    /// L'appareil du pont lui-meme ; nil s'il n'est pas dans la liste.
    public var appareilDuPont: ApiHue.Appareil? {
        appareils.first { $0.id == pont.appareil }
    }
}
