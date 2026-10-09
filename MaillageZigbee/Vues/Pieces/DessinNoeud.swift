import MaillageCoeur
import SwiftUI

/// Dessin d'un noeud, le meme que celui du graphe d'avant (spec de la vue par pieces, section 5) :
/// routeur en sphere brillante (degrade du blanc vers sa couleur, decale en haut a gauche) avec un
/// halo, appareil en pastille pleine de la couleur de son etat avec un halo, appareil disparu en
/// anneau ; anneau blanc de la selection ; pastille orange d'une batterie faible.
enum DessinNoeud {
    /// Couleur d'un noeud, resolue par la palette au dessin.
    enum Couleur: Hashable {
        case routeur
        /// Routeur que le pont ne connait pas.
        case routeurInconnu
        case appareil(EtatAffiche)
    }

    enum Forme: Hashable {
        /// Sphere brillante et son halo (rayon de l'ombre, en points).
        case sphere(halo: CGFloat)
        case pastille
        /// Appareil disparu.
        case anneau
    }

    struct Apparence: Hashable {
        var forme: Forme
        var couleur: Couleur
    }

    /// Apparence d'un noeud : sphere pour le coordinateur ou un routeur, pastille pour un appareil final, anneau pour un
    /// appareil disparu. `etat` : celui de l'appareil. La legende reprend les memes (`apparenceRouteur`,
    /// `apparenceAppareil`).
    static func apparence(_ n: ScenePieces.Noeud, etat: EtatAffiche?) -> Apparence {
        switch n.genre {
        case .centre, .routeur: apparenceRouteur(centre: n.genre == .centre, inconnu: n.inconnu)
        case .appareil: apparenceAppareil(n.inconnu ? .inconnu : etat)
        }
    }

    /// Un routeur : sphere brillante, au halo de 10 pour le coordinateur, de 5 sinon ; grise si le pont ne le connait
    /// pas.
    static func apparenceRouteur(centre: Bool = false, inconnu: Bool) -> Apparence {
        Apparence(forme: .sphere(halo: centre ? 10 : 5), couleur: inconnu ? .routeurInconnu : .routeur)
    }

    /// Un appareil : pastille de la couleur de son etat (inconnu sans etat), anneau s'il a disparu.
    static func apparenceAppareil(_ etat: EtatAffiche?) -> Apparence {
        let e = etat ?? .inconnu
        return Apparence(forme: e == .disparu ? .anneau : .pastille, couleur: .appareil(e))
    }

    static func couleur(_ c: Couleur, palette: Palette) -> Color {
        switch c {
        case .routeur: palette.routeur
        case .routeurInconnu: palette.routeurInconnu
        case .appareil(let e): palette.appareil(e)
        }
    }

    /// Le noeud, centre en `centre`, de rayon `rayon`.
    static func dessiner(_ ctx: inout GraphicsContext, centre c: CGPoint, rayon r: CGFloat, apparence: Apparence,
                         palette: Palette) {
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        let couleur = couleur(apparence.couleur, palette: palette)
        switch apparence.forme {
        case .sphere(let halo):
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: couleur.opacity(0.8), radius: halo))
                l.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [.white.opacity(0.9), couleur]),
                                                                    center: CGPoint(x: c.x - r / 3, y: c.y - r / 3),
                                                                    startRadius: 0, endRadius: r * 1.3))
            }
        case .pastille:
            ctx.drawLayer { l in
                l.addFilter(.shadow(color: couleur.opacity(0.8), radius: 4))
                l.fill(Path(ellipseIn: rect), with: .color(couleur))
            }
        case .anneau:
            ctx.stroke(Path(ellipseIn: rect), with: .color(couleur), lineWidth: 2)
        }
    }

    /// Anneau du noeud selectionne, 4 points autour de sa pastille.
    static func dessinerSelection(_ ctx: inout GraphicsContext, centre c: CGPoint, rayon r: CGFloat, palette: Palette) {
        let a = r + 4
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - a, y: c.y - a, width: 2 * a, height: 2 * a)),
                   with: .color(palette.selection), lineWidth: 2)
    }

    static let policePastille = Font.caption2.weight(.semibold)

    static var iconePastille: Text {
        Text(Image(systemName: "exclamationmark.triangle.fill")).font(policePastille)
    }

    static func textePastille(_ valeur: String) -> Text {
        Text(verbatim: valeur).font(policePastille)
    }

    /// Capsule de la pastille : 6 pt, l'icone, 3 pt, la valeur, 6 pt ; 2 pt dessus et dessous.
    static func taillePastille(icone: CGSize, valeur: CGSize) -> CGSize {
        CGSize(width: 6 + icone.width + 3 + valeur.width + 6, height: max(icone.height, valeur.height) + 4)
    }

    /// Pastille orange en surbrillance d'une batterie faible : petit triangle et texte, dans une
    /// capsule qui luit ; le milieu de son bord gauche en `gauche`.
    static func dessinerPastille(_ ctx: inout GraphicsContext, _ texte: String, gauche: CGPoint, palette: Palette) {
        let icone = ctx.resolve(iconePastille.foregroundStyle(palette.texteBatterieFaible))
        let valeur = ctx.resolve(textePastille(texte).foregroundStyle(palette.texteBatterieFaible))
        let ti = icone.measure(in: StylesNoms.grand)
        let tv = valeur.measure(in: StylesNoms.grand)
        let taille = taillePastille(icone: ti, valeur: tv)
        let cadre = CGRect(x: gauche.x, y: gauche.y - taille.height / 2, width: taille.width, height: taille.height)
        let capsule = Path(roundedRect: cadre, cornerRadius: cadre.height / 2)
        ctx.drawLayer { l in
            l.addFilter(.shadow(color: palette.batterieFaible.opacity(0.9), radius: 6))
            l.fill(capsule, with: .color(palette.batterieFaible))
        }
        ctx.draw(icone, at: CGPoint(x: cadre.minX + 6, y: cadre.midY), anchor: .leading)
        ctx.draw(valeur, at: CGPoint(x: cadre.minX + 6 + ti.width + 3, y: cadre.midY), anchor: .leading)
    }
}
