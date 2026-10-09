import Foundation

// Ce que la fiche du noeud range dans ses colonnes, sans protocole (etape 5, section 2) : les voisins entendus et leur
// resume par qualite, les dependants. Le protocole les remplit (Zigbee : `FicheZigbee`).

/// Le niveau d'une qualite de lien (0 a 3), celui de la legende : 3 bonne, 2 moyenne, 1 et 0 faible ; inconnue.
public enum NiveauQualite: Int, CaseIterable, Hashable, Sendable {
    case bonne, moyenne, faible, inconnue

    public init(_ qualite: Int?) {
        switch qualite {
        case 3?: self = .bonne
        case 2?: self = .moyenne
        case 1?, 0?: self = .faible
        default: self = .inconnue
        }
    }
}

/// Un voisin entendu du noeud de la fiche : la qualite de leur lien (0 a 3, nil inconnue) et le LQI de chaque sens,
/// celui que le noeud mesure (`lqiIci`) puis celui que le voisin mesure (`lqiLa`).
public struct VoisinFiche: Hashable, Sendable, Identifiable {
    public var id: String
    public var qualite: Int?
    public var lqiIci: Int?
    public var lqiLa: Int?

    public init(id: String, qualite: Int?, lqiIci: Int? = nil, lqiLa: Int? = nil) {
        self.id = id
        self.qualite = qualite
        self.lqiIci = lqiIci
        self.lqiLa = lqiLa
    }

    /// Le moins bon des deux LQI connus ; nil sans mesure.
    public var lqiMin: Int? { [lqiIci, lqiLa].compactMap { $0 }.min() }
}

/// Le resume des voisins entendus : « 28 voisins · 6 bons · 9 moyens · 13 faibles », et la barre de leur repartition.
public struct ResumeVoisins: Hashable, Sendable {
    public var total: Int
    /// Par niveau, dans l'ordre de `NiveauQualite` (bonne, moyenne, faible, inconnue).
    public var parNiveau: [NiveauQualite: Int]

    public init(_ voisins: [VoisinFiche]) {
        total = voisins.count
        parNiveau = Dictionary(grouping: voisins, by: { NiveauQualite($0.qualite) }).mapValues(\.count)
    }

    public func nombre(_ n: NiveauQualite) -> Int { parNiveau[n] ?? 0 }

    /// Les parts de la barre de repartition, de la meilleure qualite a l'inconnue, sans les niveaux absents.
    public var parts: [(niveau: NiveauQualite, nombre: Int)] {
        NiveauQualite.allCases.compactMap { n in nombre(n) > 0 ? (n, nombre(n)) : nil }
    }

    /// Les voisins de la meilleure qualite a la plus faible (l'inconnue a la fin) ; a qualite egale, le meilleur LQI
    /// (le moins bon des deux sens ; sans mesure, apres), puis le nom.
    public static func trier(_ voisins: [VoisinFiche], nom: (String) -> String) -> [VoisinFiche] {
        voisins.map { (v: $0, nom: nom($0.id)) }.sorted { a, b in
            let qa = a.v.qualite ?? -1, qb = b.v.qualite ?? -1
            if qa != qb { return qa > qb }
            let la = a.v.lqiMin ?? -1, lb = b.v.lqiMin ?? -1
            if la != lb { return la > lb }
            return a.nom.localizedStandardCompare(b.nom) == .orderedAscending
        }.map(\.v)
    }
}

/// Un dependant du noeud de la fiche : un noeud qui passe par lui vers le centre du reseau (en Zigbee, un routeur dont
/// le prochain saut est lui, ou un appareil dont il est le parent), avec la qualite de son lien vers lui.
public struct DependantFiche: Hashable, Sendable, Identifiable {
    public var id: String
    public var qualite: Int?
    /// Un routeur (sinon un appareil) : les routeurs viennent d'abord.
    public var routeur: Bool

    public init(id: String, qualite: Int?, routeur: Bool) {
        self.id = id
        self.qualite = qualite
        self.routeur = routeur
    }

    /// Les routeurs d'abord, puis les appareils, chacun par nom.
    public static func trier(_ d: [DependantFiche], nom: (String) -> String) -> [DependantFiche] {
        d.map { (d: $0, nom: nom($0.id)) }.sorted { a, b in
            if a.d.routeur != b.d.routeur { return a.d.routeur }
            return a.nom.localizedStandardCompare(b.nom) == .orderedAscending
        }.map(\.d)
    }
}
