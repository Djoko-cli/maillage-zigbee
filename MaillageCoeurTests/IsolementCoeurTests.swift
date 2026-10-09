import Foundation
import Testing
@testable import MaillageCoeur

/// Les regles de l'isolement, sorties du moteur (polissage D, section 5) : la provenance, la remontee, le clic sur le
/// nom ou le disque d'un etage, le recalage sur une nouvelle scene. La rotation lente, qui ne depend pas de
/// l'isolement, est dans `CameraSceneTests`.
@Suite("Scene : isolement")
struct IsolementCoeurTests {
    /// La provenance (polissage C, section 5.4) : depuis la maison, aucune ; depuis un etage isole, cet etage, meme pour
    /// une piece d'un autre etage ; d'une piece a une autre, elle reste pour une piece de l'etage d'ou l'on vient, et
    /// devient la maison pour une autre.
    @Test func isoler() {
        #expect(Isolement.maison.isoler(piece: "p", etage: "a") == .piece("p", provenance: nil))
        #expect(Isolement.etage("a").isoler(piece: "p", etage: "a") == .piece("p", provenance: "a"))
        #expect(Isolement.etage("a").isoler(piece: "p", etage: "b") == .piece("p", provenance: "a"),
                "depuis un etage isole, une piece d'un autre etage")
        #expect(Isolement.piece("q", provenance: "a").isoler(piece: "p", etage: "a") == .piece("p", provenance: "a"))
        #expect(Isolement.piece("q", provenance: "a").isoler(piece: "p", etage: "b") == .piece("p", provenance: nil))
        #expect(Isolement.piece("q", provenance: nil).isoler(piece: "p", etage: "a") == .piece("p", provenance: nil))
    }

    /// La remontee (section 5.4) : une piece ouverte depuis un etage, a l'etage de la piece (celui du fil, pas
    /// forcement sa provenance), dans une maison de plusieurs plateaux ; sinon la maison ; un etage, la maison ; a la
    /// maison, Echap seulement.
    @Test func remonter() {
        let depuisA = Isolement.piece("p", provenance: "a")
        #expect(depuisA.remonter(etageDeLaPiece: "b", plusieursPlateaux: true, clavier: true) == .etage("b"))
        #expect(depuisA.remonter(etageDeLaPiece: "b", plusieursPlateaux: true, clavier: false) == .etage("b"))
        #expect(depuisA.remonter(etageDeLaPiece: "b", plusieursPlateaux: false, clavier: true) == .maison)
        #expect(depuisA.remonter(etageDeLaPiece: nil, plusieursPlateaux: true, clavier: true) == .maison)
        #expect(Isolement.piece("p", provenance: nil).remonter(etageDeLaPiece: "b", plusieursPlateaux: true, clavier: true)
                == .maison)
        for clavier in [false, true] {
            #expect(Isolement.etage("a").remonter(etageDeLaPiece: nil, plusieursPlateaux: true, clavier: clavier) == .maison)
        }
        #expect(Isolement.maison.remonter(etageDeLaPiece: nil, plusieursPlateaux: true, clavier: true) == .maison)
        #expect(Isolement.maison.remonter(etageDeLaPiece: nil, plusieursPlateaux: true, clavier: false) == .rien)
    }

    /// Le clic sur le nom ou le disque d'un etage (section 5.4), et la main qui s'y pose : il isole l'etage, sauf son
    /// propre disque, l'etage isole ; son nom, si. Dans une maison d'un seul plateau, seulement depuis une piece isolee,
    /// pour revenir a la maison.
    @Test func clicSurUnEtage() {
        for disque in [false, true] {
            for i in [Isolement.maison, .etage("b"), .piece("p", provenance: "a"), .piece("p", provenance: nil)] {
                #expect(i.clicEtage("a", disque: disque, plusieursPlateaux: true, pieceIsolee: false) == .isoler)
                #expect(i.clicEtage("a", disque: disque, plusieursPlateaux: false, pieceIsolee: true) == .maison)
                #expect(i.clicEtage("a", disque: disque, plusieursPlateaux: false, pieceIsolee: false) == .rien)
                #expect(i.cliquable("a", disque: disque, plusieursPlateaux: true, pieceIsolee: false))
                #expect(i.cliquable("a", disque: disque, plusieursPlateaux: false, pieceIsolee: true))
                #expect(!i.cliquable("a", disque: disque, plusieursPlateaux: false, pieceIsolee: false))
            }
        }
        let a = Isolement.etage("a")
        #expect(a.clicEtage("a", disque: true, plusieursPlateaux: true, pieceIsolee: false) == .rien, "son propre disque")
        #expect(!a.cliquable("a", disque: true, plusieursPlateaux: true, pieceIsolee: false))
        #expect(a.clicEtage("a", disque: false, plusieursPlateaux: true, pieceIsolee: false) == .isoler, "son nom")
        #expect(a.cliquable("a", disque: false, plusieursPlateaux: true, pieceIsolee: false))
    }

    /// Une nouvelle scene : la piece ou l'etage isoles qui disparaissent rendent la maison ; presents, rien ne change,
    /// meme si l'etage de la provenance a disparu.
    @Test func recaler() {
        let pieces: Set = ["p"], etages: Set = ["a"]
        #expect(Isolement.piece("q", provenance: "a").recaler(pieces: pieces, etages: etages) == .maison)
        #expect(Isolement.piece("p", provenance: "z").recaler(pieces: pieces, etages: etages) == .piece("p", provenance: "z"))
        #expect(Isolement.etage("b").recaler(pieces: pieces, etages: etages) == .maison)
        #expect(Isolement.etage("a").recaler(pieces: pieces, etages: etages) == .etage("a"))
        #expect(Isolement.maison.recaler(pieces: [], etages: []) == .maison)
    }
}
