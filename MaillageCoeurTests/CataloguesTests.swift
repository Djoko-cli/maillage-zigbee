import Foundation
import Testing

/// Catalogues de textes de l'app, lus dans le depot. Ces tests vivent ici (et
/// non dans MaillageZigbeeTests) : les tests de l'app tournent dans l'app
/// sandboxee, qui ne peut pas lire le depot.
enum Catalogues {
    static let racine = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // MaillageCoeurTests
        .deletingLastPathComponent()  // racine du depot

    static let textes = racine.appendingPathComponent("MaillageZigbee/Ressources/Localizable.xcstrings")
    static let infoPlist = racine.appendingPathComponent("MaillageZigbee/Ressources/InfoPlist.xcstrings")

    static func entrees(_ chemin: URL) throws -> (source: String, cles: [String: [String: Any]]) {
        let d = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: chemin)) as? [String: Any])
        let cles = try #require(d["strings"] as? [String: [String: Any]])
        return (d["sourceLanguage"] as? String ?? "", cles)
    }

    /// Dossier des produits (`.../Build/Products/Debug`) : celui de ce paquet de test.
    private final class Ancre {}
    static var produits: URL { Bundle(for: Ancre.self).bundleURL.deletingLastPathComponent() }

    /// `.stringsdata` de l'app : `Build/Intermediates.noindex/MaillageZigbee.build/<config>/MaillageZigbee.build/Objects-normal/<arch>/`.
    static var stringsdata: [URL] {
        let config = produits.lastPathComponent
        let objets = produits.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Intermediates.noindex/MaillageZigbee.build")
            .appendingPathComponent(config)
            .appendingPathComponent("MaillageZigbee.build/Objects-normal")
        let fm = FileManager.default
        var fichiers: [URL] = []
        for arch in (try? fm.contentsOfDirectory(at: objets, includingPropertiesForKeys: nil)) ?? [] {
            for f in (try? fm.contentsOfDirectory(at: arch, includingPropertiesForKeys: nil)) ?? []
            where f.pathExtension == "stringsdata" {
                fichiers.append(f)
            }
        }
        return fichiers
    }

    static var stringsdataDisponibles: Bool { !stringsdata.isEmpty }

    /// Cles extraites du code de l'app (table Localizable).
    static func clesExtraites() throws -> Set<String> {
        var cles = Set<String>()
        for f in stringsdata {
            let d = try JSONSerialization.jsonObject(with: Data(contentsOf: f)) as? [String: Any]
            let tables = d?["tables"] as? [String: [[String: Any]]] ?? [:]
            for e in tables["Localizable"] ?? [] {
                if let k = e["key"] as? String { cles.insert(k) }
            }
        }
        return cles
    }

    /// Specificateurs d'un format, sans leur position (`%1$@` -> `@`), dans l'ordre.
    static func specificateurs(_ s: String) -> [String] {
        let motif = /%(?:\d+\$)?(lld|ld|d|@|lf|f|%)/
        return s.matches(of: motif).map { String($0.output.1) }
    }

    /// Unites de texte d'une localisation : simple, ou formes du pluriel.
    static func unites(_ loc: [String: Any]) -> [String: [String: Any]] {
        if let u = loc["stringUnit"] as? [String: Any] { return ["": u] }
        let pluriel = (loc["variations"] as? [String: Any])?["plural"] as? [String: [String: Any]] ?? [:]
        return pluriel.compactMapValues { $0["stringUnit"] as? [String: Any] }
    }
}

@Suite("Catalogues de textes (francais source, anglais complet)")
struct CataloguesTests {
    @Test(arguments: [Catalogues.textes, Catalogues.infoPlist])
    func chaqueCleATraductionAnglaise(_ chemin: URL) throws {
        let (source, cles) = try Catalogues.entrees(chemin)
        #expect(source == "fr", "le francais est la langue de developpement")
        #expect(!cles.isEmpty)
        for (cle, entree) in cles {
            #expect(entree["extractionState"] as? String != "stale", "cle perimee : \(cle)")
            let locs = entree["localizations"] as? [String: [String: Any]] ?? [:]
            let en = try #require(locs["en"], "pas d'anglais : \(cle)")
            let unites = Catalogues.unites(en)
            #expect(!unites.isEmpty, "anglais vide : \(cle)")
            if unites.keys.contains(where: { !$0.isEmpty }) {
                #expect(unites["one"] != nil && unites["other"] != nil, "pluriel incomplet : \(cle)")
            }
            let attendus = Catalogues.specificateurs(cle)
            for (forme, u) in unites {
                #expect(u["state"] as? String == "translated", "anglais non valide (\(forme)) : \(cle)")
                let valeur = u["value"] as? String ?? ""
                #expect(!valeur.isEmpty, "anglais vide (\(forme)) : \(cle)")
                #expect(Catalogues.specificateurs(valeur).sorted() == attendus.sorted(),
                        "specificateurs differents : \(cle) -> \(valeur)")
            }
        }
    }

    /// Le code et le catalogue vont ensemble : aucune cle du code ne manque,
    /// aucune cle du catalogue n'est morte (apres un changement de texte :
    /// outils/synchroniser-textes.sh puis outils/traduire.py).
    @Test(.enabled(if: Catalogues.stringsdataDisponibles, "produits de compilation introuvables"))
    func codeEtCatalogueAlignes() throws {
        let extraites = try Catalogues.clesExtraites()
        let catalogue = Set(try Catalogues.entrees(Catalogues.textes).cles.keys)
        #expect(!extraites.isEmpty)
        #expect(extraites.subtracting(catalogue).sorted() == [], "absentes du catalogue")
        #expect(catalogue.subtracting(extraites).sorted() == [], "inutilisees")
    }

    /// Plus rien de Thread dans l'interface (etape 1 du prototype) : aucune cle ni aucune traduction ne parle de Thread,
    /// de partition, de routeur de bordure, de Matter ni de HomeKit. Depuis l'etape 4 bis, le Passeur revient (les noms
    /// de Maison), et l'app que le Passeur accompagne, « Maillage Thread », peut etre nommee : l'aide dit ou il
    /// s'installe.
    @Test(arguments: [Catalogues.textes, Catalogues.infoPlist])
    func rienDeThread(_ chemin: URL) throws {
        let mots = ["thread", "partition", "bordure", "border router", "matter", "homekit"]
        for (cle, entree) in try Catalogues.entrees(chemin).cles {
            let locs = entree["localizations"] as? [String: [String: Any]] ?? [:]
            let valeurs = locs.values.flatMap { Catalogues.unites($0).values.compactMap { $0["value"] as? String } }
            for texte in [cle] + valeurs {
                let sansLApp = texte.lowercased().replacingOccurrences(of: "maillage thread", with: "")
                for m in mots {
                    #expect(!sansLApp.contains(m), "« \(m) » dans : \(texte)")
                }
            }
        }
    }
}
