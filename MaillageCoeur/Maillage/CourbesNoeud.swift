import Foundation

/// Periode des courbes de la fiche (spec de l'app, section 7) : 24 h, 7 j ou 30 j.
public enum PeriodeCourbes: String, CaseIterable, Hashable, Sendable, Identifiable {
    case jour, semaine, mois

    public var id: String { rawValue }

    public var duree: TimeInterval {
        switch self {
        case .jour: 24 * 3600
        case .semaine: 7 * 24 * 3600
        case .mois: 30 * 24 * 3600
        }
    }

    /// Pas des points, moyenne des releves du pas : chaque releve sur 24 h (288 points), 30 min
    /// sur 7 j (336), 2 h sur 30 j (360) ; sans pas, 30 j de releves feraient 8 640 points.
    public var pas: TimeInterval? {
        switch self {
        case .jour: nil
        case .semaine: 1800
        case .mois: 7200
        }
    }

    /// Ecart de plus de ce temps entre deux releves d'une meme courbe : elle se coupe en troncons, c'est un trou
    /// (20 min sur 24 h, 90 min sur 7 j, 6 h sur 30 j).
    public var ecartTroncon: TimeInterval { CourbesNoeud.ecartTroncon(pas: pas) }
}

/// Point d'une courbe. `troncon` : numero du morceau de courbe ; un trou (plus de 20 min entre
/// deux releves, ou de trois pas) en commence un autre, pour ne pas relier par-dessus le trou. `lqi` : pour la courbe
/// d'un lien, le LQI d'ou vient sa qualite (le moins bon des deux sens), lu au survol ; nil pour le signal (sa valeur
/// est deja un LQI) ou sans mesure.
public struct PointCourbe: Hashable, Sendable {
    public let date: Date
    public let valeur: Double
    public let troncon: Int
    public let lqi: Double?

    public init(date: Date, valeur: Double, troncon: Int, lqi: Double? = nil) {
        self.date = date
        self.valeur = valeur
        self.troncon = troncon
        self.lqi = lqi
    }
}

/// Qualite d'un lien au fil du temps (0 a 3, `QualiteLien`) : l'autre bout, par son adresse longue, ou
/// `CourbesNoeud.cleParent` pour le lien d'un appareil final vers son parent, quel qu'il soit.
public struct CourbeLien: Hashable, Sendable, Identifiable {
    public let id: String
    public let points: [PointCourbe]

    public init(id: String, points: [PointCourbe]) {
        self.id = id
        self.points = points
    }
}

/// Changement de parent, ou de prochain saut vers le pont : sa date (le premier releve sous le nouveau) et l'adresse
/// longue du nouveau parent ou prochain saut.
public struct ChangementParent: Hashable, Sendable {
    public let date: Date
    public let parent: String

    public init(date: Date, parent: String) {
        self.date = date
        self.parent = parent
    }
}

/// Courbes d'un noeud tirees de l'historique (spec de l'app, section 7 ; etape 5, section 3), sur une periode :
/// - routeur (ou le pont) : la qualite de chaque lien avec un routeur voisin (la moins bonne des deux mesures) et avec
///   chacun de ses enfants (celle que le routeur mesure), ses changements de prochain saut vers le pont, et le LQI que
///   la sonde en recoit, avec les changements de parent de la sonde, car ce signal depend d'abord de l'endroit ou elle
///   est posee ;
/// - appareil final : la qualite du lien vers son parent (inconnue si le parent ne la donne pas), avec ses changements
///   de parent.
/// Un noeud se reconnait d'un releve a l'autre par son adresse longue. `prioritaires` : les courbes montrees d'abord
/// (`ChoixCourbes`), celles du chemin puis celles des dependants.
public struct CourbesNoeud: Hashable, Sendable {
    /// Cle de la courbe d'un enfant vers son parent.
    public static let cleParent = "parent"
    /// Trou le plus long entre deux releves d'une meme courbe (sans pas) : une tournee toutes les 15 min ; au-dela de
    /// 20 min, il en manque.
    public static let ecartMax: TimeInterval = 20 * 60

    /// L'ecart qui coupe une courbe en troncons : trois pas, ou `ecartMax` sans pas.
    public static func ecartTroncon(pas: TimeInterval?) -> TimeInterval { pas.map { 3 * $0 } ?? ecartMax }

    public let debut: Date
    public let fin: Date
    /// Par adresse longue de l'autre bout (`cleParent` pour le lien d'un appareil final vers son parent).
    public let liens: [CourbeLien]
    public let parents: [ChangementParent]
    /// Les changements de prochain saut d'un routeur vers le pont (les chemins des releves).
    public let chemins: [ChangementParent]
    /// LQI que la sonde recoit du noeud (0 a 255).
    public let signal: [PointCourbe]
    public let parentsSonde: [ChangementParent]
    /// Les courbes a montrer d'abord, dans l'ordre : le lien du chemin (vers le prochain saut, le plus recent d'abord ;
    /// pour un appareil final, vers son parent), puis ceux des dependants de la periode (routeurs dont il etait le
    /// prochain saut, appareils dont il etait le parent), du plus faible au meilleur en moyenne, puis par cle. Seules y
    /// sont les cles qui ont une courbe.
    public let prioritaires: [String]

    public var estVide: Bool { liens.allSatisfy { $0.points.isEmpty } && parents.isEmpty && signal.isEmpty }

    /// La courbe d'un lien, par sa cle.
    public func courbe(_ cle: String) -> CourbeLien? { liens.first { $0.id == cle } }

    /// Courbes du noeud d'adresse longue `cle` dans `releves` (du plus ancien au plus recent), sur la periode qui finit
    /// a `fin`.
    public init(cle: String, releves: [ReleveMaillage], periode: PeriodeCourbes, fin: Date) {
        let debut = fin.addingTimeInterval(-periode.duree)
        var liens: [String: [Brut]] = [:]
        var signal: [Brut] = []
        var parents: [ChangementParent] = []
        var chemins: [ChangementParent] = []
        var parentsSonde: [ChangementParent] = []
        var dernierParent: String?
        var dernierProchain: String?
        var dernierParentSonde: String?
        var prochains: [String] = []
        var dependants: Set<String> = []
        for r in releves where r.date >= debut && r.date <= fin {
            for l in r.liens {
                guard let autre = l.autre(que: cle), let q = l.qualite else { continue }
                liens[autre, default: []].append(Brut(r.date, Double(q), [l.lqiA, l.lqiB].compactMap { $0 }.min()))
            }
            if let s = r.signaux.first(where: { $0.ieee == cle }) { signal.append(Brut(r.date, Double(s.lqi), nil)) }
            if let e = r.parents.first(where: { $0.enfant == cle }) {
                if let d = dernierParent, d != e.parent { parents.append(ChangementParent(date: r.date, parent: e.parent)) }
                dernierParent = e.parent
                if let q = e.qualite { liens[Self.cleParent, default: []].append(Brut(r.date, Double(q), e.lqi)) }
            }
            for e in r.parents where e.parent == cle && e.enfant != cle {
                dependants.insert(e.enfant)
                if let q = e.qualite { liens[e.enfant, default: []].append(Brut(r.date, Double(q), e.lqi)) }
            }
            if let c = r.chemins.first(where: { $0.routeur == cle }) {
                if let d = dernierProchain, d != c.prochain { chemins.append(ChangementParent(date: r.date, parent: c.prochain)) }
                dernierProchain = c.prochain
                prochains.removeAll { $0 == c.prochain }
                prochains.insert(c.prochain, at: 0)
            }
            for c in r.chemins where c.prochain == cle && c.routeur != cle { dependants.insert(c.routeur) }
            if let p = r.parentSonde {
                if let d = dernierParentSonde, d != p { parentsSonde.append(ChangementParent(date: r.date, parent: p)) }
                dernierParentSonde = p
            }
        }
        self.debut = debut
        self.fin = fin
        let courbes = liens.keys.sorted().map { CourbeLien(id: $0, points: Self.reduire(liens[$0] ?? [], pas: periode.pas)) }
        self.liens = courbes
        self.parents = parents
        self.chemins = chemins
        self.signal = Self.reduire(signal, pas: periode.pas)
        self.parentsSonde = parentsSonde
        // Les prioritaires : le chemin, puis les dependants du plus faible au meilleur en moyenne.
        func moyenne(_ k: String) -> Double {
            guard let p = courbes.first(where: { $0.id == k })?.points, !p.isEmpty else { return .infinity }
            return p.map(\.valeur).reduce(0, +) / Double(p.count)
        }
        let avecCourbe = Set(courbes.map(\.id))
        let chemin = (dernierParent != nil ? [Self.cleParent] : prochains).filter { avecCourbe.contains($0) }
        let deps = dependants.subtracting(chemin).filter { avecCourbe.contains($0) }
            .map { (cle: $0, moyenne: moyenne($0)) }
            .sorted { ($0.moyenne, $0.cle) < ($1.moyenne, $1.cle) }
            .map { $0.cle }
        prioritaires = chemin + deps
    }

    /// Une mesure brute : sa date, sa valeur, et pour la qualite d'un lien, son LQI.
    struct Brut {
        let date: Date
        let valeur: Double
        let lqi: Int?

        init(_ date: Date, _ valeur: Double, _ lqi: Int?) {
            self.date = date
            self.valeur = valeur
            self.lqi = lqi
        }
    }

    /// Points d'une courbe de mesures sans LQI (`reduire(_:pas:)`).
    static func reduire(_ bruts: [(Date, Double)], pas: TimeInterval?) -> [PointCourbe] {
        reduire(bruts.map { Brut($0.0, $0.1, nil) }, pas: pas)
    }

    /// Points d'une courbe : la moyenne de chaque pas (datee du debut du pas, LQI compris, sur ses mesures connues), ou
    /// chaque releve sans pas ; un ecart de plus de trois pas (20 min sans pas) entre deux points ouvre un nouveau
    /// troncon.
    static func reduire(_ bruts: [Brut], pas: TimeInterval?) -> [PointCourbe] {
        var points: [(Date, Double, Double?)] = bruts.map { ($0.date, $0.valeur, $0.lqi.map(Double.init)) }
        if let pas {
            var groupes: [(debut: Date, valeurs: [Double], lqis: [Double])] = []
            for b in bruts {
                let debut = Date(timeIntervalSince1970: (b.date.timeIntervalSince1970 / pas).rounded(.down) * pas)
                let lqis = b.lqi.map { [Double($0)] } ?? []
                if groupes.last?.debut == debut {
                    groupes[groupes.count - 1].valeurs.append(b.valeur)
                    groupes[groupes.count - 1].lqis += lqis
                } else {
                    groupes.append((debut, [b.valeur], lqis))
                }
            }
            points = groupes.map { g in
                (g.debut, g.valeurs.reduce(0, +) / Double(g.valeurs.count),
                 g.lqis.isEmpty ? nil : g.lqis.reduce(0, +) / Double(g.lqis.count))
            }
        }
        let ecart = ecartTroncon(pas: pas)
        var troncon = 0
        var resultat: [PointCourbe] = []
        for (i, (d, v, lqi)) in points.enumerated() {
            if i > 0, d.timeIntervalSince(points[i - 1].0) > ecart { troncon += 1 }
            resultat.append(PointCourbe(date: d, valeur: v, troncon: troncon, lqi: lqi))
        }
        return resultat
    }
}
