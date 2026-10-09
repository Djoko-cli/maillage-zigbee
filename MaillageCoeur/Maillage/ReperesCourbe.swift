import Foundation

/// Un repere de l'historique de la fiche : un trait vertical a la date du premier de ses changements de parent ou de
/// prochain saut. Des changements trop proches l'un de l'autre, a l'echelle affichee, se fondent en un seul repere
/// (`ReperesCourbe.regrouper`) ; sa bulle les liste, dans l'ordre (`visibles`, `autres`).
public struct RepereCourbe: Hashable, Sendable {
    /// Les changements du repere, du plus ancien au plus recent ; au moins un.
    public let changements: [ChangementParent]

    public init(changements: [ChangementParent]) {
        precondition(!changements.isEmpty, "un repere porte au moins un changement")
        self.changements = changements
    }

    /// La date du repere : celle de son premier changement.
    public var date: Date { changements[0].date }

    /// La date de son dernier changement (celle du repere s'il est seul).
    public var fin: Date { changements[changements.count - 1].date }

    /// Le nombre de changements fondus ; le petit « x4 » du trait n'apparait qu'a partir de 2.
    public var nombre: Int { changements.count }

    /// Les lignes de la bulle : les premiers changements, au plus `maximum`, dans l'ordre.
    public func visibles(maximum: Int = ReperesCourbe.lignesMax) -> [ChangementParent] {
        Array(changements.prefix(max(0, maximum)))
    }

    /// Les changements que la bulle ne liste pas (« et n autres »).
    public func autres(maximum: Int = ReperesCourbe.lignesMax) -> Int {
        max(0, changements.count - max(0, maximum))
    }
}

/// Les reperes des changements de parent ou de chemin sur un graphe de la fiche, sans texte dans le trace : seuls des
/// traits, lus au survol. Des changements a moins de `ecartMin` pt l'un du premier du repere (a l'echelle affichee :
/// la duree de la periode sur la largeur du trace) se fondent en un seul repere.
public enum ReperesCourbe {
    /// L'ecart sous lequel des changements se fondent en un seul repere (pt).
    public static let ecartMin: Double = 12
    /// Lignes de la bulle d'un repere, au plus ; les autres se resument en « et n autres ».
    public static let lignesMax = 6
    /// La distance du pointeur au trait (ou a l'etendue d'un repere groupe) sous laquelle la bulle s'ouvre (pt).
    public static let portee: Double = 6

    /// Les secondes que couvre un point du trace : `duree` sur `largeur` pt ; nil sans largeur.
    public static func secondesParPoint(duree: TimeInterval, largeur: Double) -> TimeInterval? {
        largeur > 0 && duree > 0 ? duree / largeur : nil
    }

    /// Les reperes de `changements` (dans n'importe quel ordre), du plus ancien au plus recent, sur un trace de
    /// `largeur` pt qui couvre `duree` : un changement ouvre un repere, et les suivants s'y fondent tant qu'ils sont a
    /// strictement moins de `ecart` pt du premier (le repere ne s'etire donc pas de proche en proche : deux reperes
    /// groupes sont toujours a `ecart` pt au moins l'un de l'autre). Sans largeur, aucun regroupement.
    public static func regrouper(_ changements: [ChangementParent], duree: TimeInterval, largeur: Double,
                                 ecart: Double = ecartMin) -> [RepereCourbe] {
        let tries = changements.sorted { $0.date < $1.date }
        let seuil = secondesParPoint(duree: duree, largeur: largeur).map { $0 * ecart } ?? 0
        var groupes: [[ChangementParent]] = []
        for ch in tries {
            if let premier = groupes.last?.first, ch.date.timeIntervalSince(premier.date) < seuil {
                groupes[groupes.count - 1].append(ch)
            } else {
                groupes.append([ch])
            }
        }
        return groupes.map { RepereCourbe(changements: $0) }
    }

    /// Le repere sous le pointeur, a l'heure `date` : celui dont l'etendue (de son premier a son dernier changement)
    /// est a moins de `portee` pt, le plus proche ; nil sans repere assez proche ni sans largeur.
    public static func sous(_ date: Date, parmi reperes: [RepereCourbe], duree: TimeInterval, largeur: Double,
                            portee: Double = portee) -> RepereCourbe? {
        guard let spp = secondesParPoint(duree: duree, largeur: largeur) else { return nil }
        func distance(_ r: RepereCourbe) -> TimeInterval {
            if date < r.date { return r.date.timeIntervalSince(date) }
            if date > r.fin { return date.timeIntervalSince(r.fin) }
            return 0
        }
        return reperes.map { ($0, distance($0)) }
            .filter { $0.1 < portee * spp }
            .min { $0.1 < $1.1 }?.0
    }
}
