import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : cartes des pieces")
struct CartesPiecesTests {
    typealias Ligne = CartesPieces.Ligne

    static func proche(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 1e-9 }

    /// Le salon de la maquette : six lignes (le chef, trois routeurs d'Apple, un routeur, un appareil),
    /// le nom le plus long de 143 px : une colonne de 210 x 224 px, 8,75 x 9,33 unites.
    @Test func tailleDepuisLesLargeurs() {
        let c = CartesPieces.carte([Ligne(rayon: 8, largeurNom: 100), Ligne(rayon: 15, largeurNom: 80),
                                    Ligne(rayon: 13, largeurNom: 95), Ligne(rayon: 13, largeurNom: 100),
                                    Ligne(rayon: 8, largeurNom: 90), Ligne(rayon: 7, largeurNom: 143)])
        #expect(c.colonnes == 1)
        #expect(Self.proche(c.largeur * 24, 210) && Self.proche(c.profondeur * 24, 224))
        #expect(Self.proche(c.places[0].x, -76.0 / 24) && Self.proche(c.places[0].y, -89.0 / 24), "14 + rmax du bord")
        let milieu: Double = 8 + 30 + 21
        #expect(Self.proche(c.places[1].y, (milieu - 112) / 24), "au milieu de sa ligne de 42 px")
        #expect(c.places.allSatisfy { Self.proche($0.x, c.places[0].x) })
    }

    /// Nombre de colonnes : le rapport largeur / hauteur le plus proche de 1,3 ; douze lignes de 30 px
    /// et des noms de 60 px : deux colonnes (1,13), plutot qu'une (0,30) ou trois (2,45).
    @Test func choixDesColonnes() {
        let c = CartesPieces.carte(Array(repeating: Ligne(rayon: 7, largeurNom: 60), count: 12))
        #expect(c.colonnes == 2)
        #expect(Self.proche(c.largeur * 24, 222) && Self.proche(c.profondeur * 24, 196))
        #expect(Self.proche(c.places[0].x, -90.0 / 24) && Self.proche(c.places[6].x, 21.0 / 24))
        #expect(Self.proche(c.places[0].y, -75.0 / 24) && Self.proche(c.places[6].y, c.places[0].y), "en haut de la 2e")
        let sixieme: Double = 8 + 5 * 30 + 15
        #expect(Self.proche(c.places[5].y, (sixieme - 98) / 24))
    }

    /// Jamais de colonne vide : quatre lignes ne font pas trois colonnes (2 + 2 + 0) ; sept en font
    /// trois (3 + 3 + 1), remplies dans l'ordre des lignes.
    @Test func sansColonneVide() {
        let haute = Ligne(rayon: 15, largeurNom: 0)
        #expect(CartesPieces.carte(Array(repeating: haute, count: 4)).colonnes == 2)
        let sept = CartesPieces.carte(Array(repeating: haute, count: 7))
        #expect(sept.colonnes == 3)
        #expect(sept.places.count == 7)
        #expect(sept.places[0].x < sept.places[3].x && sept.places[3].x < sept.places[6].x)
        #expect(Self.proche(sept.places[2].x, sept.places[0].x) && Self.proche(sept.places[6].y, sept.places[0].y))
        #expect(CartesPieces.carte([haute]).colonnes == 1)
    }

    /// Un nom de plus de 40 caracteres est coupe : ses 39 premiers, puis « … » ; 40, tel quel.
    @Test func nomCoupe() {
        let quarante = String(repeating: "a", count: 40)
        #expect(CartesPieces.couper(quarante) == quarante)
        let long = "Détecteur de passage allée de la chambre d'amis ☾"
        let coupe = CartesPieces.couper(long)
        #expect(coupe.count == 40 && coupe.hasSuffix("…") && long.hasPrefix(String(coupe.dropLast())))
        #expect(CartesPieces.couper(String(repeating: "👑", count: 41)).count == 40)
    }

    /// Le nom affiche et le nom que la carte reserve (polissage D, section 2) : la couronne, ☾ et ⚠︎, dans cet ordre,
    /// chacun apres une espace ; la carte reserve la couronne a un noeud qui route, ☾ a un autre, ⚠︎ a tous (la pastille,
    /// a un noeud dont la pile est connue : `ScenePiecesTests.cleSansLesBadges`). Le nom que montre un chef (routeur)
    /// ou un endormi (autre noeud), avec ou sans ⚠︎, est un debut du nom reserve, et le nom nu aussi. Les autres noms
    /// affiches (⚠︎ seul ou ☾ sur un routeur, par exemple) n'en sont pas un debut : la largeur de toutes les variantes
    /// est verifiee, avec la vraie police, par `NomsSceneTests.reserveDesBadges`.
    @Test func badgesReserves() {
        #expect(CartesPieces.texte("Lampe", chef: false, endormi: false, alerte: false) == "Lampe")
        #expect(CartesPieces.texte("Lampe", chef: true, endormi: true, alerte: true) == "Lampe 👑 ☾ ⚠︎")
        #expect(CartesPieces.texte("Lampe", chef: false, endormi: true, alerte: false) == "Lampe ☾")
        #expect(CartesPieces.texte("Lampe", chef: false, endormi: false, alerte: true) == "Lampe ⚠︎")
        #expect(CartesPieces.texte("Prise", chef: true, endormi: false, alerte: false) == "Prise 👑")
        #expect(CartesPieces.texteReserve("Prise", routeur: true) == "Prise 👑 ⚠︎")
        #expect(CartesPieces.texteReserve("Lampe", routeur: false) == "Lampe ☾ ⚠︎")
        for routeur in [false, true] {
            let reserve = CartesPieces.texteReserve("Nom", routeur: routeur)
            for alerte in [false, true] {
                let affiche = CartesPieces.texte("Nom", chef: routeur, endormi: !routeur, alerte: alerte)
                #expect(reserve.hasPrefix(affiche), "\(affiche) dans \(reserve)")
            }
        }
    }

    /// Une carte par piece de la scene, dans l'ordre de ses lignes ; les largeurs viennent de l'app.
    @Test func cartesDeLaScene() throws {
        let g = try ScenePiecesTests.graphe(sonde: false)
        let s = ScenePieces(graphe: g, libelles: ScenePiecesTests.libelles, piecesNoeuds: ["Apple TV": "Salon"], zones: nil,
                            chefs: [], piecesMaison: true)
        let cartes = CartesPieces.cartes(s, largeurs: ["Apple TV": 70])
        #expect(cartes.count == s.pieces.count)
        let salon = try #require(s.pieces.firstIndex { $0.nom == .maison("Salon") })
        let largeur: Double = 14 + 30 + 9 + 70 + 14
        #expect(Self.proche(cartes[salon].largeur * 24, largeur))
        #expect(Self.proche(cartes[salon].profondeur * 24, 58))
    }
}
