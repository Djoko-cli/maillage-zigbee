import AppKit
import MaillageCoeur
import SwiftUI

/// Legende de la vue par pieces (polissage B, section 2 ; maquette de la legende, colonne de droite) :
/// en bas a gauche, au-dessus de la fiche quand elle est ouverte ; quatre
/// groupes en grille de deux colonnes, qui ne montrent que ce que la scene affichee contient, chaque signe
/// dessine comme dans la scene (`SigneLegende`). En verre, comme les capsules du haut (verification du 02/10 :
/// le choix de Djoko, au lieu du panneau sombre de la maquette). Repliee, il ne reste que l'etiquette
/// « Legende » ; son etat est garde d'un lancement a l'autre, par la ligne du bas (`LigneDuBas`). Une legende
/// sans entree n'est pas montree.
struct LegendePieces: View {
    @Environment(\.accessibilityReduceMotion) private var reduire
    let rubriques: [Rubrique]
    /// Repliee ou ouverte : un clic sur l'en-tete bascule.
    @Binding var repliee: Bool

    /// La preference qui garde le repli.
    static let cleRepliee = "legendeRepliee"

    var body: some View {
        if !rubriques.isEmpty {
            // Le panneau parait depuis l'etiquette et s'y replie, en 0,45 s ; un fondu seul avec « Reduire les
            // animations ».
            if repliee {
                etiquette
                    .transition(Apparition.transitionLegende(reduire: reduire))
            } else {
                panneau
                    .transition(Apparition.transitionLegende(reduire: reduire))
            }
        }
    }

    /// « Legende ⌃ » : 11,5 pt semi-gras, marges de 6 x 12 pt ; le chevron vers le haut, qui ouvre la legende, centre
    /// sur la ligne de l'etiquette (`chevron`).
    private var etiquette: some View {
        Button {
            repliee = false
        } label: {
            HStack(spacing: 8) {
                Text("Légende")
                Self.chevron(repliee: true)
            }
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(Palette.texteLegende)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .verreDeLegende()
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    /// En-tete « Legende ⌄ » (7 pt dessous ; le chevron vers le bas, qui replie la legende), puis la grille ; marges de
    /// 9, 12, 11 et 12 pt. La largeur est celle de la grille : l'en-tete s'y etend, sans elargir le panneau.
    private var panneau: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                repliee = true
            } label: {
                HStack {
                    Text("Légende")
                    Spacer(minLength: 8)
                    Self.chevron(repliee: false)
                }
                .font(.system(size: 11.5, weight: .semibold))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            GrilleLegende {
                ForEach(rubriques, id: \.groupe) { r in
                    groupe(r)
                }
            }
        }
        .fixedSize()
        .font(.system(size: 11))
        .foregroundStyle(Palette.texteLegende)
        .padding(EdgeInsets(top: 9, leading: 12, bottom: 11, trailing: 12))
        .verreDeLegende()
    }

    /// Le chevron de l'en-tete ou de l'etiquette : il montre ce que fait un clic (choix de Djoko, 02/10, a l'inverse de
    /// la maquette A) : vers le bas, la legende ouverte, pour la replier ; vers le haut, repliee, pour l'ouvrir. Un
    /// symbole, et non les caracteres ⌄ et ⌃ de la maquette : centre sur la ligne de l'etiquette (le caractere ⌄ y
    /// tombait 3,5 pt trop bas, sur la ligne de base), a la taille de ces caracteres.
    static func chevron(repliee: Bool) -> some View {
        Image(systemName: repliee ? "chevron.up" : "chevron.down")
            .font(.system(size: 8.5, weight: .bold))
            .accessibilityHidden(true)
    }

    /// Un groupe : son titre (10 pt semi-gras, gris bleute), 4 pt, puis ses entrees, a 3 pt l'une de
    /// l'autre, et 3 pt dessous.
    private func groupe(_ r: Rubrique) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(r.groupe.titre)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.2)
                .foregroundStyle(Palette.titreLegende)
                .padding(.bottom, 1)
            ForEach(r.entrees, id: \.self) { e in
                ligne(e)
            }
        }
        .padding(.bottom, 3)
        .fixedSize()
    }

    /// Une entree : son signe, dessine comme dans la scene (`SigneLegende`), 7 pt, son texte.
    private func ligne(_ e: Entree) -> some View {
        HStack(spacing: 7) {
            SigneLegende(signe: Self.signe(e))
                .accessibilityHidden(true)
            Text(e.texte)
        }
    }

    /// Exemples des signes, comme dans la scene : la pastille d'une pile a 12 %, un repere « ailleurs ».
    static var exemplePile: String { String(localized: "\(12)\u{202F}%") }
    static var exempleAilleurs: String { String(localized: "→ Salon") }
}

extension LegendePieces {
    /// Une entree de la legende : un signe et son texte (spec du polissage B, section 2) ; la couronne du coordinateur
    /// et la lune d'un endormi sont leur signe, dans un nom de noeud comme dans la scene.
    enum Entree: Hashable, CaseIterable {
        case routeur, nonIdentifie, coordinateur
        case joignable, injoignable, disparu, endormi, pile
        case chemin, cheminSuppose, voisinEntendu
        case bonne, moyenne, faible, inconnue
        case versParent, parentDAvant, ailleurs

        var texte: String {
            switch self {
            case .routeur: String(localized: "routeur")
            case .nonIdentifie: String(localized: "inconnu du pont")
            case .coordinateur: String(localized: "coordinateur (le pont)")
            case .joignable: String(localized: "joignable")
            case .injoignable: String(localized: "injoignable")
            case .disparu: String(localized: "disparu")
            case .endormi: String(localized: "endormi")
            case .pile: String(localized: "pile")
            case .chemin: String(localized: "chemin vers le pont")
            case .cheminSuppose: String(localized: "chemin supposé")
            case .voisinEntendu: String(localized: "voisin entendu (à la sélection)")
            case .bonne: String(localized: "bonne")
            case .moyenne: String(localized: "moyenne")
            case .faible: String(localized: "faible")
            case .inconnue: String(localized: "inconnue")
            case .versParent: String(localized: "vers son parent")
            case .parentDAvant: String(localized: "parent d'avant (pointillé)")
            case .ailleurs: String(localized: "parent dans une autre pièce")
            }
        }
    }

    /// Les quatre groupes, dans l'ordre de la grille, et leurs entrees, dans l'ordre.
    enum Groupe: Hashable, CaseIterable {
        case routeurs, appareils, liens, autres

        var entrees: [Entree] {
            switch self {
            case .routeurs: [.routeur, .nonIdentifie, .coordinateur]
            case .appareils: [.joignable, .injoignable, .disparu, .endormi, .pile]
            case .liens: [.bonne, .moyenne, .faible, .inconnue]
            // Les traits des chemins avec celui vers un parent (etape 3 bis) : la rangee du bas prend une ligne de plus
            // quand ils depassent les qualites.
            case .autres: [.chemin, .cheminSuppose, .voisinEntendu, .versParent, .parentDAvant, .ailleurs]
            }
        }

        var titre: String {
            switch self {
            case .routeurs: String(localized: "Routeurs")
            case .appareils: String(localized: "Appareils")
            case .liens: String(localized: "Liens radio (qualité)")
            case .autres: String(localized: "Autres")
            }
        }
    }

    /// Un groupe montre, et ses entrees presentes.
    struct Rubrique: Equatable {
        var groupe: Groupe
        var entrees: [Entree]
    }

    /// Ce que la legende lit de la scene affichee : la couleur de chaque noeud, ceux que le pont ne connait pas, le
    /// coordinateur, les endormis, les piles, les liens, et si des reperes « ailleurs » sont poses (piece isolee).
    struct Lecture {
        var couleurs: [String: DessinNoeud.Couleur] = [:]
        var inconnus: Set<String> = []
        var chefs: Set<String> = []
        var endormis: Set<String> = []
        var piles: Set<String> = []
        var liens: [ScenePieces.Lien] = []
        var ailleurs = false
        /// Les liens montres.
        var mode = ModeLiens.tous
        /// Les voisins entendus se montrent a la selection (mode « chemins ») : sinon ni leur entree ni leurs qualites.
        var voisins = true
    }

    /// Les entrees que la scene contient (spec du polissage B, section 2) : chaque couleur de noeud ; un noeud que le
    /// pont ne connait pas, en gris (« inconnu du pont ») ; le coordinateur, un endormi, une pile ; chaque qualite d'un
    /// lien radio ou d'un chemin (selon le mode des liens) ; un chemin, un chemin suppose, les voisins entendus (en
    /// mode « chemins », qu'un noeud soit selectionne ou non : la legende ne bouge pas a la selection) ; un lien vers un
    /// parent ; un repere « ailleurs ». Un appareil d'etat inconnu, en gris, n'a pas
    /// d'entree a lui.
    static func entrees(_ l: Lecture) -> Set<Entree> {
        var r = Set<Entree>()
        for c in l.couleurs.values {
            switch c {
            case .routeur: r.insert(.routeur)
            case .appareil(.joignable): r.insert(.joignable)
            case .appareil(.injoignable): r.insert(.injoignable)
            case .appareil(.disparu): r.insert(.disparu)
            case .routeurInconnu, .appareil(.inconnu): break
            }
        }
        if !l.inconnus.isEmpty { r.insert(.nonIdentifie) }
        if !l.chefs.isEmpty { r.insert(.coordinateur) }
        if !l.endormis.isEmpty { r.insert(.endormi) }
        if !l.piles.isEmpty { r.insert(.pile) }
        func qualite(_ q: Int?) {
            switch NiveauQualite(q) {
            case .bonne: r.insert(.bonne)
            case .moyenne: r.insert(.moyenne)
            case .faible: r.insert(.faible)
            case .inconnue: r.insert(.inconnue)
            }
        }
        for lien in l.liens {
            switch (lien.genre, l.mode) {
            case (.radio, .tous):
                qualite(lien.qualite)
            case (.radio, .chemins):
                // Les voisins entendus ne paraissent qu'a la selection d'un noeud ; la legende ne change pas avec elle :
                // leur entree et leurs qualites sont la des qu'il y en a, sauf s'ils sont masques.
                guard l.voisins else { break }
                r.insert(.voisinEntendu)
                qualite(lien.qualite)
            case (.chemin, .chemins):
                r.insert(lien.suppose ? .cheminSuppose : .chemin)
                qualite(lien.qualite)
            case (.chemin, .tous), (.rattachement, _):
                break
            case (.parent, _):
                // Le parent d'avant (appareil final absent des dernieres tables) est trace en pointilles.
                r.insert(lien.suppose ? .parentDAvant : .versParent)
            }
        }
        if l.ailleurs { r.insert(.ailleurs) }
        return r
    }

    /// Les groupes a montrer, dans l'ordre, chacun avec ses entrees presentes ; un groupe sans entree
    /// disparait.
    static func rubriques(_ l: Lecture) -> [Rubrique] {
        let presentes = entrees(l)
        return Groupe.allCases.compactMap { g in
            let e = g.entrees.filter(presentes.contains)
            return e.isEmpty ? nil : Rubrique(groupe: g, entrees: e)
        }
    }
}

extension LegendePieces.Lecture {
    /// Lecture de la scene d'un rendu (`EntreeScene`) ; `ailleurs` : des reperes « ailleurs » sont
    /// poses ; `mode` : les liens montres ; `voisins` : les voisins entendus se montrent a la selection.
    init(_ e: EntreeScene, ailleurs: Bool, mode: ModeLiens = .tous, voisins: Bool = true) {
        let ids = e.scene.noeuds.map(\.id)
        couleurs = Dictionary(ids.compactMap { id in e.apparences[id].map { (id, $0.couleur) } },
                              uniquingKeysWith: { a, _ in a })
        inconnus = Set(e.scene.noeuds.filter(\.inconnu).map(\.id))
        chefs = Set(e.scene.noeuds.filter(\.chef).map(\.id))
        endormis = Set(e.scene.noeuds.filter { LibellesNoeuds.endormi(e.appareils[$0.id], routeur: $0.routeur) }
            .map(\.id))
        piles = Set(ids.filter { e.libelles[$0]?.pastille != nil })
        liens = e.scene.liens
        self.ailleurs = ailleurs
        self.mode = mode
        self.voisins = voisins
    }
}

/// Grille de la legende (maquette : `grid-template-columns: 1fr 1fr ; gap: 9px 18px`) : deux colonnes
/// de meme largeur, celle du groupe le plus large, et au moins la moitie d'un panneau de 440 pt ; les
/// groupes se rangent deux par deux, dans l'ordre. La maquette borne le panneau a 440 pt, et ses
/// entrees, qui ne passent jamais a la ligne, en debordent quand elles y sont toutes : la grille
/// s'elargit plutot.
struct GrilleLegende: Layout {
    static let largeurPanneau: CGFloat = 440
    /// Marges du panneau, a gauche et a droite.
    static let marges: CGFloat = 24
    static let ecartColonnes: CGFloat = 18
    static let ecartRangs: CGFloat = 9

    /// Largeur des deux colonnes, d'apres la largeur de chaque groupe.
    static func largeurColonne(_ largeurs: [CGFloat]) -> CGFloat {
        max((largeurPanneau - marges - ecartColonnes) / 2, largeurs.max() ?? 0)
    }

    private struct Mise {
        var colonne: CGFloat
        var tailles: [CGSize]
        var rangs: [CGFloat]
    }

    private func mise(_ subviews: Subviews) -> Mise {
        let tailles = subviews.map { $0.sizeThatFits(.unspecified) }
        let rangs = stride(from: 0, to: tailles.count, by: 2).map { i in
            max(tailles[i].height, i + 1 < tailles.count ? tailles[i + 1].height : 0)
        }
        return Mise(colonne: Self.largeurColonne(tailles.map(\.width)), tailles: tailles, rangs: rangs)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let m = mise(subviews)
        return CGSize(width: 2 * m.colonne + Self.ecartColonnes,
                      height: m.rangs.reduce(0, +) + Self.ecartRangs * CGFloat(max(0, m.rangs.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let m = mise(subviews)
        var y = bounds.minY
        for (k, hauteur) in m.rangs.enumerated() {
            for c in 0..<2 where 2 * k + c < subviews.count {
                let i = 2 * k + c
                subviews[i].place(at: CGPoint(x: bounds.minX + CGFloat(c) * (m.colonne + Self.ecartColonnes), y: y),
                                  proposal: ProposedViewSize(m.tailles[i]))
            }
            y += hauteur + Self.ecartRangs
        }
    }
}

/// « Releve de la sonde ancien » : une petite pastille orange, a cote de la ligne de niveau, en haut a gauche
/// (`RangeeNiveau`), quand le releve de la sonde a plus de 16 minutes (polissage B, section 2). Le dessin de la
/// pastille du coordinateur de la fiche (10,5 pt, marges de 2 x 8 pt, capsule teintee a 0,16 au filet de 0,5 pt a 0,5), en
/// orange.
struct PastilleAncien: View {
    /// Sa hauteur (pt), mesuree : celle de la rangee de la ligne de niveau (`RangeeNiveau`).
    static let hauteur = NSHostingView(rootView: PastilleAncien()).fittingSize.height

    var body: some View {
        Text("Relevé de la sonde ancien")
            .font(.system(size: 10.5))
            .foregroundStyle(Palette(sombre: true).avertissement)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Palette(sombre: true).avertissement.opacity(0.16)))
            .overlay(Capsule().strokeBorder(Palette(sombre: true).avertissement.opacity(0.5), lineWidth: 0.5))
    }
}

extension View {
    /// Verre de la legende (verification du 02/10 : le choix de Djoko, au lieu du panneau sombre de la maquette A) :
    /// celui des capsules du haut, en rectangle aux coins de 10 pt ; le texte, clair, se lit sur la scene sombre. Une
    /// capture, qui ne rend pas le verre, pose a sa place le fond des capsules dans les captures (rgba(40, 48, 72,
    /// 0,38), filet de 0,5 pt blanc a 0,22, ombre noire a 0,35), aux memes coins.
    func verreDeLegende() -> some View {
        modifier(VerreDeLegende())
    }
}

private struct VerreDeLegende: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        if capture {
            content
                .background(RoundedRectangle(cornerRadius: 10).fill(fondVerreCapture.opacity(0.38))
                    .shadow(color: .black.opacity(0.35), radius: 9, y: 6))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        } else {
            content.glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
    }
}
