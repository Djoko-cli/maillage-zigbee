import Foundation

/// Avancement d'une tournee de la sonde (spec de l'app, section 6), montre dans la barre du graphe, le menu et les
/// Reglages (`Tournee.executer`).
public struct AvancementTournee: Hashable, Sendable {
    /// Etapes d'une tournee, dans l'ordre.
    public enum Etape: CaseIterable, Hashable, Sendable {
        /// `etat` et `voisins` de la sonde.
        case etatSonde
        /// Une `table` par routeur, en largeur depuis le pont (une tournee sur quatre).
        case tables
        /// `routes 0000` : la table de routage du pont, prioritaire.
        case routes
        /// Une `routes` par routeur connu, dans la limite du budget de pages : son chemin vers le pont.
        case routesRouteurs
    }

    public let etape: Etape
    /// Requetes de l'etape revenues.
    public let fait: Int
    /// Requetes prevues pour l'etape a ce moment ; 0 : rien a faire. Pour les routes des routeurs : celles que le budget
    /// de pages couvre dans cette passe (recalcule a chaque requete).
    public let total: Int

    public init(etape: Etape, fait: Int, total: Int) {
        self.etape = etape
        self.fait = fait
        self.total = total
    }
}
