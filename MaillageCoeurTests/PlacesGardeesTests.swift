import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Scene : places gardees")
struct PlacesGardeesTests {
    static func fichier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("positions-\(UUID().uuidString)/positions-pieces.json")
    }

    static func scene(zones: [ZoneMaison]) throws -> ScenePieces {
        ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: false), libelles: ScenePiecesTests.libelles,
                    piecesNoeuds: ["Apple TV": "Salon", "HomePod": "Chambre"], zones: zones, chefs: [], piecesMaison: true)
    }

    /// Aller-retour sur disque : places et ordre des etages, par maison ; un fichier absent ou
    /// illisible donne des places vides.
    @Test func allerRetour() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PlacesGardees()
        p.garder(SIMD2(1.5, -2.25), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "Maison")
        p.ordonner(["zone:Étage", "zone:Rez-de-chaussée"], domicile: "Maison")
        p.garder(SIMD2(3, 4), piece: "piece:Salon", etage: "maison", domicile: "Chalet")
        try p.ecrire(dans: url)
        let relu = PlacesGardees.lire(url)
        #expect(relu == p)
        #expect(relu.maison("Maison").ordreEtages == ["zone:Étage", "zone:Rez-de-chaussée"])
        #expect(relu.maison("Maison").etages["zone:Rez-de-chaussée"]?["piece:Salon"] == PlacesGardees.Place(x: 1.5, z: -2.25))
        #expect(PlacesGardees.lire(url.appendingPathExtension("absent")) == PlacesGardees())
        try Data("pas du json".utf8).write(to: url)
        #expect(PlacesGardees.lire(url) == PlacesGardees())
    }

    /// Pieces fixees : celles qui ont une place gardee dans leur etage. Renommee, ou passee dans un
    /// autre etage, une piece perd sa place ; les autres la gardent.
    @Test func pieceRenommeeOuDeplacee() throws {
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = try Self.scene(zones: zones)
        var p = PlacesGardees()
        p.garder(SIMD2(1, 2), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        p.garder(SIMD2(3, 4), piece: "piece:Chambre", etage: "zone:Étage", domicile: "")
        let salon = try #require(s.pieces.firstIndex { $0.nom == .maison("Salon") })
        let chambre = try #require(s.pieces.firstIndex { $0.nom == .maison("Chambre") })
        #expect(p.fixees(s, domicile: "") == [salon: SIMD2(1, 2), chambre: SIMD2(3, 4)])
        #expect(p.fixees(s, domicile: "Autre").isEmpty)
        // La chambre passe au rez-de-chaussee : elle perd sa place, le salon garde la sienne.
        let deplacee = try Self.scene(zones: [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon", "Chambre"])])
        let salon2 = try #require(deplacee.pieces.firstIndex { $0.nom == .maison("Salon") })
        #expect(p.fixees(deplacee, domicile: "") == [salon2: SIMD2(1, 2)])
    }

    /// Une place non finie (camera degeneree pendant un glisser) n'est pas gardee : `ecrire` la
    /// refuserait, a chaque appel, pour toutes les maisons.
    @Test func placeNonFinieRefusee() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PlacesGardees()
        p.garder(SIMD2(1, 2), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        for v in [Double.nan, .infinity, -.infinity] {
            p.garder(SIMD2(v, 0), piece: "piece:Chambre", etage: "zone:Étage", domicile: "")
            p.garder(SIMD2(0, v), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        }
        #expect(p.maison("").etages["zone:Étage"] == nil)
        #expect(p.maison("").etages["zone:Rez-de-chaussée"] == ["piece:Salon": PlacesGardees.Place(x: 1, z: 2)])
        try p.ecrire(dans: url)
        #expect(PlacesGardees.lire(url) == p)
    }

    /// Pieces fixees : une place a plus de `borne` unites du centre de son plateau (fichier abime ou
    /// edite a la main) est ignoree. Lue dans un fichier, elle ne donne ni plateau infini, ni fichier
    /// qu'on ne pourrait plus ecrire.
    @Test func placeDemesureeIgnoree() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = try Self.scene(zones: zones)
        let salon = try #require(s.pieces.firstIndex { $0.nom == .maison("Salon") })
        let chambre = try #require(s.pieces.firstIndex { $0.nom == .maison("Chambre") })
        var abime = PlacesGardees()
        abime.garder(SIMD2(1e308, 0), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        abime.garder(SIMD2(3, 4), piece: "piece:Chambre", etage: "zone:Étage", domicile: "")
        try abime.ecrire(dans: url)
        var p = PlacesGardees.lire(url)
        #expect(p == abime)
        let fixees = p.fixees(s, domicile: "")
        #expect(fixees == [chambre: SIMD2(3, 4)])
        let d = DispositionPieces(scene: s, cartes: CartesPieces.cartes(s, largeurs: [:]), fixees: fixees)
        #expect(d.rayons.allSatisfy(\.isFinite) && d.positions.allSatisfy { $0.x.isFinite && $0.y.isFinite })
        try p.ecrire(dans: url)
        // La borne : a sa distance, une place compte ; au-dela, non.
        let b = PlacesGardees.borne
        p.garder(SIMD2(0.6 * b, -0.8 * b), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        #expect(p.fixees(s, domicile: "")[salon] == SIMD2(0.6 * b, -0.8 * b))
        p.garder(SIMD2(0.6 * b, -0.81 * b), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        #expect(p.fixees(s, domicile: "")[salon] == nil)
    }

    /// Les zones a cote (polissage C, section 1.2), un champ facultatif de la version 1, comme `appareils` dans
    /// `pieces-routeurs.json` : sans zone a cote, il n'est pas ecrit, et le fichier reste celui d'avant ; un
    /// aller-retour sur disque garde l'ordre, les places et les choix ; une app d'avant relit l'ordre et les
    /// places d'un fichier d'apres ; un champ mal forme est ignore, sans perdre l'ordre ni les places.
    /// « Replacer les pieces automatiquement » garde l'ordre et les choix de niveau.
    @Test func zonesACote() throws {
        let url = Self.fichier()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        var p = PlacesGardees()
        p.garder(SIMD2(1.5, -2.25), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "Maison")
        p.ordonner(["zone:Rez-de-chaussée", "zone:Étage"], domicile: "Maison")
        try p.ecrire(dans: url)
        #expect(!String(decoding: try Data(contentsOf: url), as: UTF8.self).contains("aCote"), "un fichier d'avant")
        #expect(PlacesGardees.lire(url) == p && PlacesGardees.lire(url).maison("Maison").aCote.isEmpty)
        let r = Rangement(ordre: ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage"],
                          aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)])
        p.ranger(r, domicile: "Maison")
        try p.ecrire(dans: url)
        let relu = PlacesGardees.lire(url)
        #expect(relu == p && relu.version == PlacesGardees.versionActuelle && PlacesGardees.versionActuelle == 1)
        #expect(relu.rangement("Maison") == r && relu.maison("Maison").etages == p.maison("Maison").etages)
        // Une app d'avant : son schema, sans le champ.
        struct AncienneMaison: Decodable {
            var ordreEtages: [String]
            var etages: [String: [String: PlacesGardees.Place]]
        }
        struct Ancienne: Decodable {
            var version: Int
            var maisons: [String: AncienneMaison]
        }
        let ancienne = try JSONDecoder().decode(Ancienne.self, from: Data(contentsOf: url))
        #expect(ancienne.version == 1 && ancienne.maisons["Maison"]?.ordreEtages == r.ordre)
        #expect(ancienne.maisons["Maison"]?.etages == p.maison("Maison").etages)
        // Un champ mal forme.
        let texte = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        #expect(texte.contains("\"dehors\" : true"))
        try Data(texte.replacingOccurrences(of: "\"dehors\" : true", with: "\"dehors\" : \"oui\"").utf8).write(to: url)
        let abime = PlacesGardees.lire(url).maison("Maison")
        #expect(abime.aCote.isEmpty && abime.ordreEtages == r.ordre && abime.etages == p.maison("Maison").etages)
        p.replacer(domicile: "Maison")
        #expect(p.maison("Maison").etages.isEmpty && p.rangement("Maison") == r)
    }

    /// Ordre des etages garde, puis « Replacer les pieces automatiquement » : les places partent,
    /// l'ordre reste.
    @Test func ordreDesEtagesEtReplacement() throws {
        var p = PlacesGardees()
        p.ordonner(["zone:Étage", "zone:Rez-de-chaussée"], domicile: "")
        p.garder(SIMD2(1, 2), piece: "piece:Salon", etage: "zone:Rez-de-chaussée", domicile: "")
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"])]
        let s = ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: false), libelles: [:],
                            piecesNoeuds: ["Apple TV": "Salon", "HomePod": "Chambre"], zones: zones, chefs: [],
                            piecesMaison: true, ordreEtages: p.maison("").ordreEtages)
        #expect(s.etages.map(\.id) == ["zone:Étage", "zone:Rez-de-chaussée"])
        p.replacer(domicile: "")
        #expect(p.maison("").etages.isEmpty)
        #expect(p.maison("").ordreEtages == ["zone:Étage", "zone:Rez-de-chaussée"])
    }
}
