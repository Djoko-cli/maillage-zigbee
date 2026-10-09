import MaillageCoeur
import SwiftUI

// Composants de la fiche du noeud, sans protocole (etape 5, section 2) : les colonnes, la pastille d'un noeud, la barre
// de repartition des qualites, les rangees fluides et la grille d'une liste. Le contenu de chaque colonne est propre au
// protocole (`FicheNoeud`, pour Zigbee).

/// Les colonnes de la fiche : cote a cote, de largeur egale ; dans une fiche trop etroite, moins de colonnes, un
/// diviseur de leur nombre (4, 2, puis 1), pour des rangees pleines. Chaque rangee prend la hauteur de sa plus haute
/// colonne.
struct ColonnesFiche: Layout {
    /// Largeur minimale d'une colonne (pt).
    var minimum: CGFloat = ColonnesFiche.largeurMinimale
    var espacement: CGFloat = 24
    var interligne: CGFloat = 14

    static let largeurMinimale: CGFloat = 190

    /// Le nombre de colonnes d'une rangee, pour `nombre` colonnes dans `largeur` pt : le plus grand diviseur de `nombre`
    /// dont les colonnes tiennent a `minimum` pt au moins, `espacement` entre elles ; 1 au moins ; toutes sans largeur.
    static func colonnes(largeur: CGFloat?, nombre: Int, minimum: CGFloat = largeurMinimale,
                         espacement: CGFloat = 24) -> Int {
        guard nombre > 1 else { return 1 }
        guard let largeur, largeur.isFinite else { return nombre }
        for c in stride(from: nombre, to: 0, by: -1) where nombre % c == 0 {
            if CGFloat(c) * minimum + CGFloat(c - 1) * espacement <= largeur { return c }
        }
        return 1
    }

    /// Le nombre de colonnes et leur largeur, dans `largeur` pt.
    private func grille(_ largeur: CGFloat?, _ n: Int) -> (colonnes: Int, largeur: CGFloat) {
        let c = Self.colonnes(largeur: largeur, nombre: n, minimum: minimum, espacement: espacement)
        let l = largeur.map { max(0, ($0 - CGFloat(c - 1) * espacement) / CGFloat(c)) } ?? minimum
        return (c, l)
    }

    /// La hauteur de chaque rangee.
    private func rangees(_ vues: Subviews, colonnes c: Int, largeur l: CGFloat) -> [CGFloat] {
        stride(from: 0, to: vues.count, by: c).map { debut in
            vues[debut..<min(vues.count, debut + c)].map {
                $0.sizeThatFits(ProposedViewSize(width: l, height: nil)).height
            }.max() ?? 0
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let (c, l) = grille(proposal.width, subviews.count)
        let h = rangees(subviews, colonnes: c, largeur: l)
        let largeur = proposal.width ?? CGFloat(c) * l + CGFloat(c - 1) * espacement
        return CGSize(width: largeur, height: h.reduce(0, +) + CGFloat(max(0, h.count - 1)) * interligne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (c, l) = grille(bounds.width, subviews.count)
        var y = bounds.minY
        for (r, hauteur) in rangees(subviews, colonnes: c, largeur: l).enumerated() {
            for k in 0..<c where r * c + k < subviews.count {
                subviews[r * c + k].place(at: CGPoint(x: bounds.minX + CGFloat(k) * (l + espacement), y: y),
                                          anchor: .topLeading, proposal: ProposedViewSize(width: l, height: hauteur))
            }
            y += hauteur + interligne
        }
    }
}

/// Le titre d'une colonne de la fiche.
struct TitreColonne: View {
    let titre: LocalizedStringKey

    var body: some View {
        Text(titre).font(.caption.weight(.semibold)).foregroundStyle(.secondary).textCase(.uppercase)
    }
}

/// Des elements poses en rangees qui passent a la ligne (les pastilles des dependants, celles de la legende des courbes).
struct RangeesFluides: Layout {
    var espacement: CGFloat = 5
    var interligne: CGFloat = 5

    /// La place de chaque element dans `largeur` pt (a gauche, en haut) et la taille de l'ensemble.
    private func poser(_ vues: Subviews, largeur: CGFloat?) -> (places: [CGPoint], taille: CGSize) {
        let max = largeur ?? .infinity
        var places: [CGPoint] = []
        var x: CGFloat = 0, y: CGFloat = 0, hauteur: CGFloat = 0, largeurUtile: CGFloat = 0
        for v in vues {
            let t = v.sizeThatFits(.unspecified)
            if x > 0 && x + t.width > max {
                x = 0
                y += hauteur + interligne
                hauteur = 0
            }
            places.append(CGPoint(x: x, y: y))
            x += t.width + espacement
            hauteur = Swift.max(hauteur, t.height)
            largeurUtile = Swift.max(largeurUtile, x - espacement)
        }
        return (places, CGSize(width: largeur ?? largeurUtile, height: vues.isEmpty ? 0 : y + hauteur))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        poser(subviews, largeur: proposal.width).taille
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let p = poser(subviews, largeur: bounds.width).places
        for (v, q) in zip(subviews, p) {
            v.place(at: CGPoint(x: bounds.minX + q.x, y: bounds.minY + q.y), anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// Une liste en grille sur plusieurs colonnes, de `minimum` pt au moins chacune, remplie colonne par colonne (de haut
/// en bas, puis de gauche a droite) : l'ordre de la liste se lit comme un texte en colonnes.
struct GrilleListe: Layout {
    var minimum: CGFloat = 210
    var espacement: CGFloat = 16
    var interligne: CGFloat = 3

    /// Le nombre de colonnes dans `largeur` pt : autant que la place en donne, 1 au moins. Peu d'elements ne remplissent
    /// que les premieres : une colonne garde sa largeur, son LQI reste pres du nom.
    static func colonnes(largeur: CGFloat?, minimum: CGFloat = 210, espacement: CGFloat = 16) -> Int {
        guard let largeur, largeur.isFinite else { return 1 }
        return max(1, Int((largeur + espacement) / (minimum + espacement)))
    }

    private func mesure(_ vues: Subviews, _ largeur: CGFloat?)
        -> (colonnes: Int, lignes: Int, largeur: CGFloat, hauteur: CGFloat) {
        let c = Self.colonnes(largeur: largeur, minimum: minimum, espacement: espacement)
        let l = largeur.map { max(0, ($0 - CGFloat(c - 1) * espacement) / CGFloat(c)) } ?? minimum
        let h = vues.map { $0.sizeThatFits(ProposedViewSize(width: l, height: nil)).height }.max() ?? 0
        return (c, (vues.count + c - 1) / c, l, h)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = mesure(subviews, proposal.width)
        return CGSize(width: proposal.width ?? CGFloat(m.colonnes) * m.largeur + CGFloat(m.colonnes - 1) * espacement,
                      height: CGFloat(m.lignes) * m.hauteur + CGFloat(max(0, m.lignes - 1)) * interligne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = mesure(subviews, bounds.width)
        guard m.lignes > 0 else { return }
        for (i, v) in subviews.enumerated() {
            let colonne = i / m.lignes, ligne = i % m.lignes
            v.place(at: CGPoint(x: bounds.minX + CGFloat(colonne) * (m.largeur + espacement),
                                y: bounds.minY + CGFloat(ligne) * (m.hauteur + interligne)),
                    anchor: .topLeading, proposal: ProposedViewSize(width: m.largeur, height: m.hauteur))
        }
    }
}

/// La pastille compacte d'un noeud : un point de couleur (la qualite de son lien) et son nom ; un clic le choisit.
struct PastilleNoeud: View {
    let nom: String
    let couleur: Color
    var action: (() -> Void)?

    var body: some View {
        let contenu = HStack(spacing: 4) {
            Circle().fill(couleur).frame(width: 7, height: 7)
            Text(verbatim: nom).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        if let action {
            Button(action: action) { contenu }.buttonStyle(.plain)
        } else {
            contenu
        }
    }
}

/// La barre de repartition des qualites : une part par niveau, proportionnelle a son nombre, aux couleurs de la legende.
struct BarreRepartition: View {
    let parts: [(couleur: Color, nombre: Int)]

    var body: some View {
        Canvas { ctx, taille in
            let total = parts.reduce(0) { $0 + $1.nombre }
            guard total > 0 else { return }
            var x: CGFloat = 0
            for p in parts {
                let l = taille.width * CGFloat(p.nombre) / CGFloat(total)
                ctx.fill(Path(CGRect(x: x, y: 0, width: max(0, l - 1), height: taille.height)), with: .color(p.couleur))
                x += l
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

extension Palette {
    /// La couleur d'un niveau de qualite, celle de la legende (`lienSonde`).
    func couleur(_ n: NiveauQualite) -> Color {
        switch n {
        case .bonne: lienSonde(3)
        case .moyenne: lienSonde(2)
        case .faible: lienSonde(1)
        case .inconnue: lienSonde(nil)
        }
    }
}
