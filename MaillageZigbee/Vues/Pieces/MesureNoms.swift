import AppKit
import MaillageCoeur
import SwiftUI

/// Tailles des noms de la vue par pieces, mesurees hors du `Canvas` avec les memes `Text` que le
/// dessin (`StylesNoms`) : SwiftUI les met en page comme le `Canvas`, a l'echelle d'ecran 1,
/// arrondies au point entier superieur. Une taille par texte, gardee (spec, section 4.2 : les
/// largeurs des noms passent au coeur).
@MainActor
final class MesureNoms {
    private enum Nature: Hashable {
        case noeud(routeur: Bool), nomPiece, comptePiece, etage, maison, ailleurs, icone, valeur
    }

    private struct Cle: Hashable {
        var texte: String
        var nature: Nature
    }

    private var hote: NSHostingController<AnyView>?
    private var tailles: [Cle: CGSize] = [:]
    private var pastilleLaPlusLarge: String?

    /// Boite du nom d'un noeud : le texte en semi-gras (sa place ne change pas au survol), 5 points de
    /// chaque cote, puis la pastille d'une batterie faible, 5 points apres.
    func noeud(_ l: LibellesNoeuds.Libelle, routeur: Bool) -> CGSize {
        let t = mesurer(Cle(texte: l.texte, nature: .noeud(routeur: routeur))) {
            StylesNoms.noeud(l.texte, routeur: routeur, fort: true)
        }
        var taille = CGSize(width: t.width + 10, height: t.height)
        if let p = l.pastille {
            let c = pastille(p)
            taille.width += c.width + 5
            taille.height = max(taille.height, c.height)
        }
        return taille
    }

    /// Boite que la carte reserve au nom d'un noeud (polissage D, section 2) : son nom et tous les badges qu'il peut
    /// porter, affiches ou non (`CartesPieces.texteReserve`), puis, pour un noeud dont la pile est connue (`pile`), la
    /// plus large des pastilles d'une pile faible. Un badge qui parait ou s'en va n'y change rien.
    func reserve(_ nom: String, routeur: Bool, pile: Bool) -> CGSize {
        noeud(LibellesNoeuds.Libelle(texte: CartesPieces.texteReserve(nom, routeur: routeur),
                                     pastille: pile ? pastilleReservee : nil, nom: nom),
              routeur: routeur)
    }

    /// La plus large des pastilles d'une pile faible : de 0 a 100 %, ou « faible ».
    var pastilleReservee: String {
        if let p = pastilleLaPlusLarge { return p }
        let textes = (0...100).compactMap { LibellesNoeuds.pastilleBatterie(BatterieMaison(niveau: $0, alerte: true)) }
            + [LibellesNoeuds.pastilleBatterie(BatterieMaison(alerte: true))].compactMap { $0 }
        let p = textes.max { pastille($0).width < pastille($1).width } ?? ""
        pastilleLaPlusLarge = p
        return p
    }

    /// Boite du glyphe d'un nom (la couronne, la lune), dessine seul dans la legende : celle de son nom, sans ses 5 points
    /// de chaque cote. La legende en prend la hauteur ; sa largeur est celle d'un noeud (`SigneLegende.largeurGlyphe`).
    func glyphe(_ texte: String, routeur: Bool) -> CGSize {
        let n = noeud(LibellesNoeuds.Libelle(texte: texte), routeur: routeur)
        return CGSize(width: n.width - 10, height: n.height)
    }

    /// Capsule de la pastille d'une batterie faible.
    func pastille(_ valeur: String) -> CGSize {
        DessinNoeud.taillePastille(icone: mesurer(Cle(texte: "", nature: .icone)) { DessinNoeud.iconePastille },
                                   valeur: mesurer(Cle(texte: valeur, nature: .valeur)) { DessinNoeud.textePastille(valeur) })
    }

    /// Nom d'une piece : bordure 1, marge 7, point 8, 6, nom, 6, compte, marge 7, bordure 1 ; 20 de haut.
    func piece(nom: String, compte: String) -> CGSize {
        let n = mesurer(Cle(texte: nom, nature: .nomPiece)) { StylesNoms.nomPiece(nom) }
        let c = mesurer(Cle(texte: compte, nature: .comptePiece)) { StylesNoms.comptePiece(compte) }
        return CGSize(width: n.width + c.width + 36, height: 20)
    }

    func etage(_ nom: String) -> CGSize {
        mesurer(Cle(texte: nom, nature: .etage)) { StylesNoms.etage(nom) }
    }

    func maison(_ texte: String) -> CGSize {
        mesurer(Cle(texte: texte, nature: .maison)) { StylesNoms.maison(texte) }
    }

    /// Repere « ailleurs » : 5 points de marge et 1 de bordure de chaque cote.
    func ailleurs(_ texte: String) -> CGSize {
        let t = mesurer(Cle(texte: texte, nature: .ailleurs)) { StylesNoms.ailleurs(texte) }
        return CGSize(width: t.width + 12, height: t.height + 2)
    }

    private func mesurer(_ cle: Cle, _ texte: () -> Text) -> CGSize {
        if let t = tailles[cle] { return t }
        let hote = self.hote ?? NSHostingController(rootView: AnyView(EmptyView()))
        self.hote = hote
        hote.rootView = AnyView(texte().environment(\.displayScale, 1))
        let s = hote.sizeThatFits(in: StylesNoms.grand)
        let t = CGSize(width: ceil(s.width), height: ceil(s.height))
        tailles[cle] = t
        return t
    }
}
