import Foundation

/// Les appariements deja trouves entre les appareils du pont Hue et les accessoires de Maison : adresse longue de
/// l'appareil (16 hexa majuscules) -> identifiant HomeKit de l'accessoire (`AccessoireReleve.id`). `FusionNoms` la
/// reapplique en premier : l'identifiant HomeKit ne change pas quand l'utilisateur renomme une tuile ou la change de
/// piece, alors que le nom et la piece qui servaient a retrouver l'accessoire, eux, changent. Elle se garde dans le
/// dossier de l'app (`appariements-maison.json`), a cote du releve de Maison.
public struct MemoireAppariements: Codable, Hashable, Sendable {
    public static let versionActuelle = 1
    public static let fichier = "appariements-maison.json"

    public var version: Int
    public var ids: [String: String]

    public init(ids: [String: String] = [:]) {
        version = Self.versionActuelle
        self.ids = ids
    }

    /// Fichier de la memoire dans le dossier de l'app.
    public static func fichier(dossier: URL) -> URL {
        dossier.appendingPathComponent(fichier)
    }

    /// La memoire gardee ; vide si le fichier manque, est illisible ou d'une version plus recente (elle se refait au
    /// releve suivant : ce n'est qu'un cache).
    public static func lire(_ url: URL) -> MemoireAppariements {
        guard let d = try? Data(contentsOf: url),
              let m = try? JSONDecoder().decode(MemoireAppariements.self, from: d),
              m.version <= versionActuelle else { return MemoireAppariements() }
        return m
    }

    /// Ecrit la memoire d'un bloc (fichier temporaire puis renommage), en creant le dossier au besoin.
    public func ecrire(dans url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .prettyPrinted]
        try e.encode(self).write(to: url, options: .atomic)
    }
}
