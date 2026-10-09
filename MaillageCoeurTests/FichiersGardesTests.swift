import Foundation
import Testing
@testable import MaillageCoeur

/// Fichiers gardes dans le conteneur de l'app : places des pieces, pieces choisies, surnoms, identites
/// des routeurs. Un fichier d'une version plus recente n'est jamais reecrit ; un fichier illisible est
/// mis de cote avant d'etre remplace ; le cas ordinaire ne change pas. Dans un dossier temporaire, avec
/// des donnees inventees.
@Suite("Fichiers gardes : version plus recente, fichier illisible")
struct FichiersGardesTests {
    static let domicile = "Maison inventée"

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("fichiers-\(UUID().uuidString)")
    }

    /// Les noms des fichiers du dossier, tries.
    static func noms(_ d: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
    }

    /// Une sorte de fichier garde : son nom, et un aller-retour (lire, changer une valeur inventee,
    /// ecrire, relire) qui rend vrai si la valeur ecrite se relit.
    struct Sorte: Sendable, CustomTestStringConvertible {
        var nom: String
        var allerRetour: @Sendable (URL) throws -> Bool
        var testDescription: String { nom }
    }

    static let sortes = [
        Sorte(nom: "positions-pieces.json") { url in
            var p = PlacesGardees.lire(url)
            p.garder(SIMD2(1.5, -2.25), piece: "piece:Salon", etage: "zone:Étage", domicile: domicile)
            try p.ecrire(dans: url)
            return PlacesGardees.lire(url) == p
        },
        Sorte(nom: "pieces-routeurs.json") { url in
            var p = PiecesRouteurs.lire(url)
            p.choisir("Salon", appareil: "A000000000000010", domicile: domicile)
            try p.ecrire(dans: url)
            return PiecesRouteurs.lire(url) == p
        },
        Sorte(nom: "surnoms.json") { url in
            var s = Surnoms.lire(url)
            s["DEADBEEF00000001"] = "Lampe inventée"
            try Surnoms.ecrire(s, dans: url)
            return Surnoms.lire(url) == s
        },
    ]

    /// Un fichier illisible, mais present, est lu comme vide ; a la premiere ecriture, il est mis de
    /// cote (renomme `<nom>.illisible-AAAAMMJJ-HHMMSS.json` dans le meme dossier, son contenu intact),
    /// puis remplace par le fichier ecrit. La suivante ne met plus rien de cote.
    @Test(arguments: sortes)
    func illisibleMisDeCote(_ sorte: Sorte) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent(sorte.nom)
        let abime = Data("{pas du json".utf8)
        try abime.write(to: url)
        #expect(try sorte.allerRetour(url))
        let noms = try Self.noms(d)
        let base = url.deletingPathExtension().lastPathComponent
        let mis = noms.filter { $0 != sorte.nom }
        #expect(noms.contains(sorte.nom) && mis.count == 1, "\(noms)")
        let deCote = try #require(mis.first)
        #expect(deCote.wholeMatch(of: /(.+)\.illisible-\d{8}-\d{6}\.json/)?.output.1 == Substring(base), "\(deCote)")
        #expect(try Data(contentsOf: d.appendingPathComponent(deCote)) == abime, "son contenu intact")
        #expect(try sorte.allerRetour(url))
        #expect(try Self.noms(d) == noms, "rien de plus mis de cote")
    }

    /// Un fichier d'une version plus recente (ecrit par une app plus recente, peut-etre d'un autre
    /// schema) est lu comme vide, et jamais reecrit : l'app travaille en memoire, sans erreur.
    @Test(arguments: [#"{"maisons":{"Maison inventée":{"HomePod Palier":"Salon"}},"nouveau":true,"version":2}"#,
                      #"{"maisons":["un autre schéma"],"version":2}"#])
    func plusRecentJamaisReecrit(_ json: String) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let routeurs = d.appendingPathComponent("pieces-routeurs.json")
        let places = d.appendingPathComponent("positions-pieces.json")
        let recent = Data(json.utf8)
        try recent.write(to: routeurs)
        try recent.write(to: places)
        var p = PiecesRouteurs.lire(routeurs)
        #expect(p == PiecesRouteurs(), "lu comme vide")
        p.choisir("Bureau", appareil: "A000000000000001", domicile: Self.domicile)
        try p.ecrire(dans: routeurs)
        var g = PlacesGardees.lire(places)
        #expect(g == PlacesGardees(), "lu comme vide")
        g.ordonner(["zone:Étage"], domicile: Self.domicile)
        try g.ecrire(dans: places)
        #expect(try Data(contentsOf: routeurs) == recent && Data(contentsOf: places) == recent, "jamais reecrit")
        #expect(try Self.noms(d) == ["pieces-routeurs.json", "positions-pieces.json"], "rien de mis de cote")
    }

    /// Le cas ordinaire ne change pas : absent, le fichier est ecrit ; lisible et d'une version connue,
    /// il est relu et reecrit a sa place, sans rien mettre de cote.
    @Test(arguments: sortes)
    func casOrdinaire(_ sorte: Sorte) throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent(sorte.nom)
        #expect(try sorte.allerRetour(url), "absent")
        #expect(try sorte.allerRetour(url), "lisible")
        #expect(try Self.noms(d) == [sorte.nom])
    }

    /// Un champ `appareils` mal forme est ignore : le fichier se lit sans choix, il n'est pas mis de cote, et la
    /// premiere ecriture le remplace.
    @Test func appareilsMalFormes() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        let url = d.appendingPathComponent("pieces-routeurs.json")
        try Data(#"{"version": 1, "appareils": ["pas", "un", "dictionnaire"]}"#.utf8).write(to: url)
        var p = PiecesRouteurs.lire(url)
        #expect(p == PiecesRouteurs())
        p.choisir("Salon", appareil: "a000000000000020", domicile: Self.domicile)
        try p.ecrire(dans: url)
        #expect(PiecesRouteurs.lire(url).choix(appareil: "A000000000000020", domicile: Self.domicile) == "Salon",
                "cle en majuscules")
        #expect(try Self.noms(d) == ["pieces-routeurs.json"])
    }
}
