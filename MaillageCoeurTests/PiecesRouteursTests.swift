import Foundation
import Testing
@testable import MaillageCoeur

/// Les pieces choisies, gardees sur disque (`pieces-routeurs.json`), et les pieces de la maison. En Zigbee, tout noeud
/// se choisit sous son adresse longue (`PiecesAppareilsTests`) : il n'y a plus de routeur de bordure, ni de regle du nom.
@Suite("Scene : pieces choisies sur disque, pieces de la maison")
struct PiecesRouteursTests {
    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("routeurs-\(UUID().uuidString)/pieces-routeurs.json")
    }

    /// Pieces de la maison : celles des appareils et celles des zones, sans doublon ni nom vide.
    @Test func piecesDeLaMaison() {
        let maison = NomsMaison(date: Date(timeIntervalSince1970: 1_790_000_000), accessoires: [
            AccessoireMaison(nom: "Lampe", piece: "Salon"), AccessoireMaison(nom: "Prise", piece: ""),
            AccessoireMaison(nom: "Pont"),
        ], zones: [ZoneMaison(nom: "Étage", pieces: ["Chambre", "Salon"])])
        #expect(PiecesRouteurs.pieces(de: maison) == ["Chambre", "Salon"])
        #expect(PiecesRouteurs.pieces(de: nil).isEmpty)
    }

    /// Aller-retour sur disque ; un fichier absent, illisible ou d'une version plus recente donne des
    /// choix vides.
    @Test func allerRetour() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PiecesRouteurs()
        p.choisir("Salon", appareil: "A000000000000010", domicile: "Maison")
        p.choisir("Bureau", appareil: "A000000000000001", domicile: "")
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url) == p)
        #expect(PiecesRouteurs.lire(url).choix(appareil: "A000000000000010", domicile: "Maison") == "Salon")
        #expect(PiecesRouteurs.lire(url.appendingPathExtension("absent")) == PiecesRouteurs())
        try Data(#"{"version":2,"appareils":{}}"#.utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
        try Data("pas du json".utf8).write(to: url)
        #expect(PiecesRouteurs.lire(url) == PiecesRouteurs())
    }
}
