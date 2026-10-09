import MaillageCoeur
import SwiftUI

/// Textes d'une image : ce que chaque nom affiche.
struct TextesScene: Equatable {
    struct Piece: Equatable {
        var nom: String
        var compte: String
    }

    var noeuds: [String: LibellesNoeuds.Libelle] = [:]
    /// Nom et compte de chaque piece, par indice.
    var pieces: [Int: Piece] = [:]
    var etages: [Int: String] = [:]
    var maison = ""
    /// Repere « ailleurs », par id de l'enfant.
    var ailleurs: [String: String] = [:]
}

/// Ce qu'une image dessine : la scene projetee, les noms poses et leurs textes.
struct ImagePieces {
    var projetee: SceneProjetee
    var etiquettes: [Etiquette]
    var traits: [PlacementNoms.Trait]
    var textes: TextesScene
    var apparences: [String: DessinNoeud.Apparence]
    /// Noeuds routeurs : leur nom en 12 points.
    var routeurs: Set<String>
    var teintesPieces: [Int: Int]
    var selection: String?
    /// Pixels par point de l'ecran.
    var echelle: Double
}

/// Textes resolus, gardes d'une image a l'autre pour une echelle d'ecran : la mise en forme d'un
/// texte est ce qui coute le plus dans une image.
@MainActor
final class CacheTextes {
    private var textes: [String: GraphicsContext.ResolvedText] = [:]
    private var echelle = 0.0

    func resolu(_ ctx: GraphicsContext, _ cle: String, echelle e: Double, _ texte: () -> Text) -> GraphicsContext.ResolvedText {
        if e != echelle {
            textes.removeAll()
            echelle = e
        }
        if let r = textes[cle] { return r }
        let r = ctx.resolve(texte())
        textes[cle] = r
        return r
    }
}

/// Dessin d'une image de la vue par pieces dans un `Canvas` (spec, section 5), couche par couche,
/// sans tri de profondeur global.
@MainActor
enum RenduCanvas {
    enum Couche: CaseIterable {
        case plateaux, blocs, liensEnfants, liensRouteurs, pastilles, sphere, traits, noms
    }

    /// Ordre des couches, de la plus basse a la plus haute : plateaux et equateur, blocs, liens enfant
    /// -> parent (avec les rattachements et les fils « ailleurs »), liens entre routeurs, pastilles (et
    /// l'anneau de la selection), lisere de la sphere, traits de rappel, noms.
    static let couches: [Couche] = [.plateaux, .blocs, .liensEnfants, .liensRouteurs, .pastilles, .sphere, .traits, .noms]

    private static let grand = StylesNoms.grand

    static func dessiner(_ ctx: inout GraphicsContext, _ image: ImagePieces, palette: Palette, cache: CacheTextes) {
        for c in couches {
            switch c {
            case .plateaux: dessinerPlateaux(&ctx, image, palette)
            case .blocs: dessinerBlocs(&ctx, image)
            case .liensEnfants: dessinerLiensEnfants(&ctx, image, palette)
            case .liensRouteurs: dessinerLiensRouteurs(&ctx, image, palette)
            case .pastilles: dessinerPastilles(&ctx, image, palette)
            case .sphere: dessinerSphere(&ctx, image, palette)
            case .traits: dessinerTraits(&ctx, image, palette)
            case .noms: dessinerNoms(&ctx, image, palette, cache)
            }
        }
    }

    static func chemin(_ points: [CGPoint], ferme: Bool) -> Path {
        var p = Path()
        p.addLines(points)
        if ferme { p.closeSubpath() }
        return p
    }

    static func segment(_ a: CGPoint, _ b: CGPoint) -> Path {
        var p = Path()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    /// Plateaux (degrade radial de la couleur de zone, 0,26 au centre, 0,08 au bord ; contour d'un
    /// pixel a 0,45 ; une fois et demie plus clairs sous le pointeur, quand on peut cliquer le disque) et
    /// equateur, du plus loin au plus proche.
    private static func dessinerPlateaux(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        let pixel = 1 / image.echelle
        let p = image.projetee
        var fond = p.plateaux.indices.map { (p.plateaux[$0].profondeur, $0) }
        if let eq = p.equateur { fond.append((eq.profondeur, -1)) }
        for (_, i) in fond.sorted(by: { $0.0 > $1.0 }) {
            if i < 0, let eq = p.equateur {
                for m in eq.contour {
                    ctx.stroke(chemin(m, ferme: false), with: .color(palette.equateur.opacity(eq.opacite)), lineWidth: pixel)
                }
                continue
            }
            let pl = p.plateaux[i]
            var g = ctx
            g.opacity = pl.opacite
            let k = pl.eclaire ? 1.5 : 1
            let degrade = Gradient(colors: [palette.zone.opacity(0.26 * k), palette.zone.opacity(0.08 * k)])
            let forme = chemin(pl.polygone, ferme: true)
            if let m = pl.disque {
                var d = g
                d.concatenate(m)
                d.fill(forme.applying(m.inverted()), with: .radialGradient(degrade, center: .zero, startRadius: 0, endRadius: 1))
            }
            for m in pl.contour {
                g.stroke(chemin(m, ferme: false), with: .color(palette.zone.opacity(min(1, 0.45 * k))), lineWidth: pixel)
            }
        }
    }

    /// Blocs de verre, du plus loin au plus proche : faces visibles eclairees, puis aretes d'un pixel.
    private static func dessinerBlocs(_ ctx: inout GraphicsContext, _ image: ImagePieces) {
        let pixel = 1 / image.echelle
        for b in image.projetee.blocs {
            for f in b.faces {
                ctx.fill(chemin(f.points, ferme: true), with: .color(Palette.couleur(f.teinte).opacity(b.opaciteVerre)))
            }
            var aretes = Path()
            for (a, c) in b.aretes {
                aretes.move(to: a)
                aretes.addLine(to: c)
            }
            ctx.stroke(aretes, with: .color(Palette.couleur(b.teinte).opacity(b.opaciteAretes)), lineWidth: pixel)
        }
    }

    /// Liens enfant -> parent d'un pixel ; rattachements supposes et parents d'avant en pointilles ; fils « ailleurs »
    /// en tirets verts.
    private static func dessinerLiensEnfants(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        let pixel = 1 / image.echelle
        for l in image.projetee.liensEnfants {
            dessinerLienEnfant(&ctx, de: l.a, a: l.b, rattachement: l.genre == .rattachement || l.suppose,
                               opacite: l.opacite, eclaire: l.eclaire, pixel: pixel, palette: palette)
        }
        for f in image.projetee.fils {
            ctx.stroke(segment(f.a, f.b), with: .color(palette.filAilleurs.opacity(f.opacite)),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        }
    }

    /// Un lien enfant -> parent : un pixel de l'encre de la palette ; un rattachement suppose en pointilles, plus
    /// epais eclaire. La legende le reprend.
    static func dessinerLienEnfant(_ ctx: inout GraphicsContext, de a: CGPoint, a b: CGPoint, rattachement: Bool,
                                   opacite: Double, eclaire: Bool, pixel: CGFloat, palette: Palette) {
        let couleur = palette.encre.opacity(opacite)
        if rattachement {
            ctx.stroke(segment(a, b), with: .color(couleur), style: StrokeStyle(lineWidth: eclaire ? 1.6 : 1, dash: [2, 4]))
        } else {
            ctx.stroke(segment(a, b), with: .color(couleur), lineWidth: pixel)
        }
    }

    /// Liens entre routeurs : les voisins entendus d'abord (dessous), puis les liens radio et les chemins vers le pont.
    private static func dessinerLiensRouteurs(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        for l in image.projetee.liensRouteurs where l.voisin {
            dessinerVoisin(&ctx, de: l.a, a: l.b, qualite: l.qualite, opacite: l.opacite, palette: palette)
        }
        for l in image.projetee.liensRouteurs where !l.voisin {
            if l.genre == .chemin {
                dessinerChemin(&ctx, de: l.a, a: l.b, qualite: l.qualite, suppose: l.suppose, opacite: l.opacite,
                               palette: palette)
            } else {
                dessinerLienRadio(&ctx, de: l.a, a: l.b, qualite: l.qualite, opacite: l.opacite, palette: palette)
            }
        }
    }

    /// Le chemin d'un routeur vers le pont : comme un lien radio (2 points, la couleur de la qualite du lien entre les
    /// deux, gris si elle est inconnue), en pointilles s'il est suppose. La legende le reprend.
    static func dessinerChemin(_ ctx: inout GraphicsContext, de a: CGPoint, a b: CGPoint, qualite: Int?, suppose: Bool,
                               opacite: Double, palette: Palette) {
        let style = suppose ? StrokeStyle(lineWidth: 2, lineCap: .round, dash: [0.5, 4.5])
            : StrokeStyle(lineWidth: 2, lineCap: .round)
        ctx.stroke(segment(a, b), with: .color(palette.lienSonde(qualite).opacity(opacite)), style: style)
    }

    /// Un voisin entendu d'un noeud selectionne (mode « chemins ») : un trait fin (1 point) de la couleur de sa qualite,
    /// estompe. La legende le reprend.
    static func dessinerVoisin(_ ctx: inout GraphicsContext, de a: CGPoint, a b: CGPoint, qualite: Int?, opacite: Double,
                               palette: Palette) {
        ctx.stroke(segment(a, b), with: .color(palette.lienSonde(qualite).opacity(opacite)), lineWidth: 1)
    }

    /// Un lien radio entre routeurs : 2 points, la couleur de sa qualite, bouts ronds. La legende le reprend.
    static func dessinerLienRadio(_ ctx: inout GraphicsContext, de a: CGPoint, a b: CGPoint, qualite: Int?, opacite: Double,
                                  palette: Palette) {
        ctx.stroke(segment(a, b), with: .color(palette.lienSonde(qualite).opacity(opacite)),
                   style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }

    /// Pastilles, du plus loin au plus proche, puis l'anneau de la selection ; en mode focus, estompees si elles ne sont
    /// pas mises en avant.
    private static func dessinerPastilles(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        for d in image.projetee.disques {
            guard let a = image.apparences[d.noeud] else { continue }
            var g = ctx
            g.opacity = d.opacite * d.focus
            DessinNoeud.dessiner(&g, centre: d.centre, rayon: d.rayon, apparence: a, palette: palette)
            if d.noeud == image.selection {
                DessinNoeud.dessinerSelection(&g, centre: d.centre, rayon: d.rayon, palette: palette)
            }
        }
    }

    /// Lisere de la sphere : transparent au centre, lumineux au bord de son contour exact.
    private static func dessinerSphere(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        guard let sp = image.projetee.sphere else { return }
        var g = ctx
        g.concatenate(sp.transfo)
        g.fill(Path(ellipseIn: CGRect(x: -1, y: -1, width: 2, height: 2)),
               with: .radialGradient(palette.degradeBulle(force: sp.force), center: .zero, startRadius: 0, endRadius: 1))
    }

    /// Traits de rappel des noms ecartes de leur objet : un pixel.
    private static func dessinerTraits(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette) {
        var traits = Path()
        for t in image.traits {
            traits.move(to: t.depart)
            traits.addLine(to: t.arrivee)
        }
        ctx.stroke(traits, with: .color(palette.trait), lineWidth: 1 / image.echelle)
    }

    /// Aligne sur les pixels de l'ecran : un texte net.
    private static func aligner(_ v: CGFloat, _ echelle: Double) -> CGFloat { (v * echelle).rounded() / echelle }

    /// Noms poses : immobiles, alignes sur les pixels ; en mouvement, a leur place fractionnaire. En mode focus, le nom
    /// d'un noeud estompe s'estompe avec lui.
    private static func dessinerNoms(_ ctx: inout GraphicsContext, _ image: ImagePieces, _ palette: Palette,
                                     _ cache: CacheTextes) {
        let e = image.echelle
        for l in image.etiquettes where l.vu {
            var g = ctx
            if l.pale { g.opacity = 0.45 }
            let r = l.immobile
                ? CGRect(x: aligner(l.rect.minX, e), y: aligner(l.rect.minY, e), width: l.rect.width, height: l.rect.height)
                : l.rect
            switch l.genre {
            case .noeud(let id):
                guard let libelle = image.textes.noeuds[id] else { continue }
                g.opacity *= image.projetee.facteur(noeud: id)
                let routeur = image.routeurs.contains(id)
                let texte = cache.resolu(g, "n|\(routeur)|\(l.fort)|" + libelle.texte, echelle: e) {
                    texteNom(libelle.texte, routeur: routeur, fort: l.fort, palette: palette)
                }
                dessinerNom(&g, texte, dans: r, palette: palette)
                if let p = libelle.pastille {
                    let largeur = ceil(texte.measure(in: grand).width)
                    DessinNoeud.dessinerPastille(&g, p, gauche: CGPoint(x: r.minX + 5 + largeur + 5, y: r.midY),
                                                 palette: palette)
                }
            case .piece(let i):
                guard let t = image.textes.pieces[i] else { continue }
                let couleur = Palette.teintePiece(image.teintesPieces[i] ?? 0)
                g.fill(Path(roundedRect: r, cornerRadius: 6), with: .color(palette.fondNomPiece))
                g.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 5.5),
                         with: .color(couleur.opacity(0.6)), lineWidth: 1)
                let nom = cache.resolu(g, "pn|" + t.nom, echelle: e) {
                    StylesNoms.nomPiece(t.nom).foregroundStyle(palette.texteNomPiece)
                }
                let compte = cache.resolu(g, "pc|" + t.compte, echelle: e) {
                    StylesNoms.comptePiece(t.compte).foregroundStyle(palette.comptePiece)
                }
                let tn = nom.measure(in: grand)
                let haut = l.immobile ? aligner(r.midY - tn.height / 2, e) : r.midY - tn.height / 2
                let ligne = haut + nom.firstBaseline(in: grand)
                let x = r.minX + 8
                // Le point pose sur la ligne de base, comme dans la maquette.
                g.fill(Path(ellipseIn: CGRect(x: x, y: ligne - 8, width: 8, height: 8)), with: .color(couleur))
                g.draw(nom, at: CGPoint(x: x + 14, y: haut), anchor: .topLeading)
                g.draw(compte, at: CGPoint(x: x + 14 + ceil(tn.width) + 6, y: ligne - compte.firstBaseline(in: grand)),
                       anchor: .topLeading)
            case .etage(let i):
                // Souligne sous le pointeur : un clic l'isole (polissage C, section 5.1).
                guard let nom = image.textes.etages[i] else { continue }
                let texte = cache.resolu(g, "e|\(l.fort)|" + nom, echelle: e) {
                    StylesNoms.etage(nom).underline(l.fort).foregroundStyle(palette.zone.opacity(0.95))
                }
                g.draw(texte, at: r.origin, anchor: .topLeading)
            case .maison:
                let texte = image.textes.maison
                g.drawLayer { c in
                    c.addFilter(.shadow(color: .black, radius: 1.5, x: 0, y: 1))
                    let resolu = cache.resolu(c, "m|" + texte, echelle: e) {
                        StylesNoms.maison(texte).foregroundStyle(palette.texteMaison)
                    }
                    c.draw(resolu, at: r.origin, anchor: .topLeading)
                }
            case .ailleurs(let id):
                guard let texte = image.textes.ailleurs[id] else { continue }
                let resolu = cache.resolu(g, "a|" + texte, echelle: e) { texteAilleurs(texte, palette: palette) }
                dessinerAilleurs(&g, resolu, dans: r, palette: palette)
            }
        }
    }

    /// Le texte du nom d'un noeud : 12 points pour un routeur, 11 pour un appareil ; semi-gras et blanc au survol
    /// et a la selection. La legende le reprend (la couronne, la lune, des candidats).
    static func texteNom(_ texte: String, routeur: Bool, fort: Bool, palette: Palette) -> Text {
        StylesNoms.noeud(texte, routeur: routeur, fort: fort).foregroundStyle(fort ? .white : palette.texteNom)
    }

    /// Le nom d'un noeud dans sa boite `r` : la pastille sombre aux coins de 4 points, le texte a 5 points du bord.
    static func dessinerNom(_ g: inout GraphicsContext, _ texte: GraphicsContext.ResolvedText, dans r: CGRect,
                            palette: Palette) {
        g.fill(Path(roundedRect: r, cornerRadius: 4), with: .color(palette.fondNom))
        g.draw(texte, at: CGPoint(x: r.minX + 5, y: r.midY), anchor: .leading)
    }

    /// Le texte d'un repere « ailleurs ».
    static func texteAilleurs(_ texte: String, palette: Palette) -> Text {
        StylesNoms.ailleurs(texte).foregroundStyle(palette.texteAilleurs)
    }

    /// Un repere « ailleurs » dans sa boite `r` : fond sombre aux coins de 4 points, bordure en tirets, le texte a
    /// 6 points du bord. La legende le reprend.
    static func dessinerAilleurs(_ g: inout GraphicsContext, _ texte: GraphicsContext.ResolvedText, dans r: CGRect,
                                 palette: Palette) {
        let forme = Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
        g.fill(forme, with: .color(palette.fondAilleurs))
        g.stroke(forme, with: .color(palette.texteAilleurs.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        g.draw(texte, at: CGPoint(x: r.minX + 6, y: r.midY), anchor: .leading)
    }
}
