import Foundation

/// Nom affiche d'un noeud, par priorite : surnom (donne dans l'app) > nom de l'appareil sur le pont > l'adresse longue.
/// Un noeud se nomme par son adresse longue (IEEE), qui ne change pas : les surnoms sont gardes sous elle.
public struct ResolveurNoms: Hashable, Sendable {
    /// Adresse longue -> surnom.
    public var surnoms: [String: String]
    public var maison: NomsMaison?

    public init(surnoms: [String: String] = [:], maison: NomsMaison? = nil) {
        self.surnoms = surnoms
        self.maison = maison
    }

    /// L'appareil du pont d'adresse longue `ieee` ; nil si le pont ne le connait pas.
    public func accessoire(ieee: String) -> AccessoireMaison? {
        maison?.accessoire(ieee: ieee)
    }

    /// Le surnom, sinon le nom sur le pont ; nil s'il n'a ni l'un ni l'autre.
    public func nomConnu(ieee: String) -> String? {
        if let s = surnoms[ieee], !s.isEmpty { return s }
        if let m = accessoire(ieee: ieee)?.nom, !m.isEmpty { return m }
        return nil
    }

    /// Le surnom, sinon le nom sur le pont, sinon l'adresse longue.
    public func nom(ieee: String) -> String { nomConnu(ieee: ieee) ?? ieee }
}

/// Surnoms donnes dans l'app ("Renommer..."), gardes dans un fichier JSON.
public enum Surnoms {
    /// Vide si le fichier manque ou est illisible (`FichiersGardes`).
    public static func lire(_ url: URL) -> [String: String] {
        FichiersGardes.lire([String: String].self, url) ?? [:]
    }

    /// Un fichier illisible est d'abord mis de cote (`FichiersGardes`).
    public static func ecrire(_ surnoms: [String: String], dans url: URL) throws {
        try FichiersGardes.ecrire(surnoms, dans: url)
    }
}
