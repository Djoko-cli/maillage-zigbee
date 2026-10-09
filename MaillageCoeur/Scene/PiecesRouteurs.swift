import Foundation

/// Piece d'un noeud que le pont ne place pas (spec de la vue par pieces, section 2.3 ; spec de l'app, section 4) : un
/// noeud que la sonde seule connait, la sonde elle-meme, un appareil sans piece sur le pont. La piece du pont, sinon le
/// choix (« Placer dans une piece… », dans sa fiche), garde par maison (`domicile`) sous l'adresse longue du noeud dans
/// `pieces-routeurs.json`, sinon « Sans piece ». Un choix dont la piece n'est plus une piece de la maison ne compte pas.
public struct PiecesRouteurs: Hashable, Sendable, Codable {
    public static let versionActuelle = 1

    public var version = PiecesRouteurs.versionActuelle
    /// Par domicile ("" : maison sans nom) : adresse longue (16 hexa majuscules) -> piece choisie.
    public var appareils: [String: [String: String]] = [:]

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case version, appareils
    }

    /// `appareils` mal forme est ignore : aucun choix plutot qu'un fichier perdu.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        appareils = (try? c.decodeIfPresent([String: [String: String]].self, forKey: .appareils)) ?? [:]
    }

    /// Vide si le fichier manque, est illisible, ou d'une version plus recente (`FichiersGardes`).
    public static func lire(_ url: URL) -> PiecesRouteurs {
        FichiersGardes.lire(PiecesRouteurs.self, url, version: versionActuelle) ?? PiecesRouteurs()
    }

    /// Rien n'est ecrit sur un fichier d'une version plus recente ; un fichier illisible est d'abord mis
    /// de cote (`FichiersGardes`).
    public func ecrire(dans url: URL) throws {
        try FichiersGardes.ecrire(self, dans: url, version: Self.versionActuelle)
    }

    /// Piece choisie pour un noeud (son adresse longue) ; nil : aucune, il est « Sans piece ».
    public func choix(appareil ieee: String, domicile: String) -> String? {
        appareils[domicile]?[ieee.uppercased()]
    }

    /// Garde le choix d'une piece pour un noeud (son adresse longue) ; nil, « Sans piece », l'efface.
    public mutating func choisir(_ piece: String?, appareil ieee: String, domicile: String) {
        appareils[domicile, default: [:]][ieee.uppercased()] = piece
        if appareils[domicile]?.isEmpty == true { appareils[domicile] = nil }
    }

    /// Cle du choix d'un noeud : son adresse longue ; nil s'il n'en a pas (ni choix ni menu).
    public static func cle(_ n: GrapheReseau.Noeud) -> String? {
        n.extMac?.uppercased()
    }

    /// Piece de chaque noeud du graphe : celle du pont (`deMaison`, par id de noeud) ; sinon la piece choisie sous sa
    /// cle (`cle(_:)`), si elle est encore une piece de la maison (`pieces`). Un noeud qui n'y est pas va dans « Sans
    /// piece ».
    public func piecesNoeuds(_ graphe: GrapheReseau, deMaison: [String: String], parmi pieces: [String],
                             domicile: String) -> [String: String] {
        var resultat = deMaison.filter { !$0.value.isEmpty }
        for n in graphe.noeuds where resultat[n.id] == nil {
            if let x = Self.cle(n), let c = choix(appareil: x, domicile: domicile), pieces.contains(c) {
                resultat[n.id] = c
            }
        }
        return resultat
    }

    /// Pieces de la maison : celles des appareils et celles des zones, sans doublon, par nom.
    public static func pieces(de maison: NomsMaison?) -> [String] {
        guard let maison else { return [] }
        var toutes = Set(maison.accessoires.compactMap(\.piece))
        for z in maison.zones ?? [] { toutes.formUnion(z.pieces) }
        return toutes.filter { !$0.isEmpty }.sorted()
    }
}
