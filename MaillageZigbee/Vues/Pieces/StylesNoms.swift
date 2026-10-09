import SwiftUI

/// Styles des noms de la vue par pieces (spec de la vue par pieces, section 6), les memes pour la
/// mesure (`MesureNoms`) et le dessin (`RenduCanvas`).
enum StylesNoms {
    /// Place proposee pour mesurer un texte d'une ligne.
    static let grand = CGSize(width: 10_000, height: 10_000)

    /// Appareil en 11 points, routeur en 12 ; semi-gras au survol et a la selection.
    static func noeud(_ texte: String, routeur: Bool, fort: Bool) -> Text {
        Text(verbatim: texte).font(.system(size: routeur ? 12 : 11, weight: fort ? .semibold : .regular))
    }

    /// Nom d'une piece en 12 points, son compte en 11.
    static func nomPiece(_ nom: String) -> Text { Text(verbatim: nom).font(.system(size: 12)) }
    static func comptePiece(_ compte: String) -> Text { Text(verbatim: compte).font(.system(size: 11)) }

    /// Nom d'un etage en 12 points ; « ⌂ Maison » en 13 ; repere « ailleurs » en 11.
    static func etage(_ nom: String) -> Text { Text(verbatim: nom).font(.system(size: 12)) }
    static func maison(_ texte: String) -> Text { Text(verbatim: texte).font(.system(size: 13)) }
    static func ailleurs(_ texte: String) -> Text { Text(verbatim: texte).font(.system(size: 11)) }
}
