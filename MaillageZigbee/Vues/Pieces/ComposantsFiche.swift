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

    /// Le nombre de colonnes et leur largeur, pour `nombre` colonnes dans `largeur` pt. Sans largeur utilisable (nil, ou
    /// infinie), toutes les colonnes, a leur largeur minimale.
    static func grille(largeur proposee: CGFloat?, nombre n: Int, minimum: CGFloat = largeurMinimale,
                       espacement: CGFloat = 24) -> (colonnes: Int, largeur: CGFloat) {
        let largeur = RangeesFluides.largeurFinie(proposee)
        let c = colonnes(largeur: largeur, nombre: n, minimum: minimum, espacement: espacement)
        let l = largeur.map { max(0, ($0 - CGFloat(c - 1) * espacement) / CGFloat(c)) } ?? minimum
        return (c, l)
    }

    private func grille(_ largeur: CGFloat?, _ n: Int) -> (colonnes: Int, largeur: CGFloat) {
        Self.grille(largeur: largeur, nombre: n, minimum: minimum, espacement: espacement)
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
        let largeur = RangeesFluides.largeurFinie(proposal.width) ?? CGFloat(c) * l + CGFloat(c - 1) * espacement
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
/// Un element plus large que la rangee est borne a sa largeur : une pastille au nom tres long se tronque, elle ne deborde
/// pas sur la colonne voisine.
struct RangeesFluides: Layout {
    var espacement: CGFloat = 5
    var interligne: CGFloat = 5

    /// Une largeur proposee utilisable : nil si elle manque ou n'est pas finie.
    static func largeurFinie(_ l: CGFloat?) -> CGFloat? { l.flatMap { $0.isFinite ? $0 : nil } }

    /// La place et la taille de chaque element de taille voulue `tailles`, dans `largeur` pt (nil : sans limite), et la
    /// taille de l'ensemble. Les elements vont de gauche a droite, a la ligne quand il n'y a plus de place, et un
    /// element plus large que `largeur` est ramene a `largeur`.
    static func disposer(_ tailles: [CGSize], largeur: CGFloat?, espacement: CGFloat = 5, interligne: CGFloat = 5)
        -> (places: [CGPoint], tailles: [CGSize], total: CGSize) {
        let max = largeurFinie(largeur) ?? .infinity
        var places: [CGPoint] = []
        var bornees: [CGSize] = []
        var x: CGFloat = 0, y: CGFloat = 0, hauteur: CGFloat = 0, largeurUtile: CGFloat = 0
        for voulue in tailles {
            let t = CGSize(width: Swift.min(voulue.width, max), height: voulue.height)
            if x > 0 && x + t.width > max {
                x = 0
                y += hauteur + interligne
                hauteur = 0
            }
            places.append(CGPoint(x: x, y: y))
            bornees.append(t)
            x += t.width + espacement
            hauteur = Swift.max(hauteur, t.height)
            largeurUtile = Swift.max(largeurUtile, x - espacement)
        }
        return (places, bornees, CGSize(width: largeurFinie(largeur) ?? largeurUtile, height: tailles.isEmpty ? 0 : y + hauteur))
    }

    /// Les tailles voulues des elements dans `largeur` pt : un element qui se tronque (une ligne de texte) prend au plus
    /// cette largeur.
    private func mesurer(_ vues: Subviews, largeur: CGFloat?) -> [CGSize] {
        let proposition = ProposedViewSize(width: Self.largeurFinie(largeur), height: nil)
        return vues.map { $0.sizeThatFits(proposition) }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        Self.disposer(mesurer(subviews, largeur: proposal.width), largeur: proposal.width,
                      espacement: espacement, interligne: interligne).total
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let d = Self.disposer(mesurer(subviews, largeur: bounds.width), largeur: bounds.width,
                              espacement: espacement, interligne: interligne)
        for (i, v) in subviews.enumerated() {
            v.place(at: CGPoint(x: bounds.minX + d.places[i].x, y: bounds.minY + d.places[i].y), anchor: .topLeading,
                    proposal: ProposedViewSize(width: d.tailles[i].width, height: d.tailles[i].height))
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

/// La pastille compacte d'un noeud : un point de couleur (la qualite de son lien, ou la couleur de sa courbe) et son nom ;
/// un clic le choisit. La couleur ne porte jamais seule le sens : pour VoiceOver, le point est masque, `valeur` dit ce
/// qu'il veut dire (la qualite du lien), `indice` ce que le clic fait, et une pastille `enAvant` est annoncee choisie.
struct PastilleNoeud: View {
    let nom: String
    let couleur: Color
    /// Ce que le point de couleur dit (« qualité du lien : bonne ») ; nil, rien.
    var valeur: String?
    /// Ce que le clic fait, lu par VoiceOver ; nil, rien.
    var indice: String?
    /// La pastille est mise en avant (la courbe de la legende, choisie) : annoncee comme selectionnee.
    var enAvant = false
    var action: (() -> Void)?

    var body: some View {
        let contenu = HStack(spacing: 4) {
            Circle().fill(couleur).frame(width: 7, height: 7).accessibilityHidden(true)
            Text(verbatim: nom).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.09)))
        .accessibilityElement(children: .combine)
        Group {
            if let action {
                Button(action: action) { contenu }.buttonStyle(.plain)
            } else {
                contenu
            }
        }
        .accessibilityValue(valeur ?? "")
        .accessibilityHint(indice ?? "")
        .accessibilityAddTraits(enAvant ? .isSelected : [])
    }
}

extension NiveauQualite {
    /// Le nom du niveau, lu par VoiceOver (la couleur d'un lien ne le dit pas seule).
    var nom: String {
        switch self {
        case .bonne: String(localized: "bonne")
        case .moyenne: String(localized: "moyenne")
        case .faible: String(localized: "faible")
        case .inconnue: String(localized: "inconnue")
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
