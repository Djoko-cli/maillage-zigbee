import Foundation
import Testing
@testable import MaillageCoeur

/// Contrat d'export commun aux trois depots (`ContratExport.swift`, identique a l'octet dans Maillage Thread, Maillage
/// Zigbee et Maillage IoT) : manifeste version 1, `reglages.json`, noms de fichiers connus, chemins, empreintes. Ce
/// fichier se recopie dans les anciennes apps avec le contrat. Valeurs inventees seulement.
@Suite("Contrat d'export : manifeste, reglages, chemins, empreintes")
struct ContratExportTests {
    typealias C = ContratExport

    static let identifiant = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    /// 2026-10-17 12:00:00 UTC.
    static let date = Date(timeIntervalSince1970: 1_792_238_400)
    static let sha = String(repeating: "ab", count: 32)

    static let nonRepris: [C.FichierNonRepris] = [
        C.FichierNonRepris(chemin: "cache.tmp", raison: .horsContrat),
        C.FichierNonRepris(chemin: ".DS_Store", raison: .exclu),
    ]

    static func manifeste(app: C.AppSource = .maillageThread, fichiers: [C.Fichier]? = nil,
                          nonRepris: [C.FichierNonRepris]? = nil) -> C.Manifeste {
        C.Manifeste(identifiant: identifiant, app: app, versionApp: "9.9.9", date: date,
                    fichiers: fichiers ?? [
                        C.Fichier(chemin: "surnoms.json", taille: 12, sha256: sha),
                        C.Fichier(chemin: "Journal/journal-2026-10.jsonl", taille: 0, sha256: String(repeating: "0", count: 64)),
                        C.Fichier(chemin: "reglages.json", taille: 345, sha256: sha),
                    ], fichiersNonRepris: nonRepris ?? Self.nonRepris)
    }

    /// L'erreur est `Erreur.illisible` : retourne son texte (la cause, sans valeur), nil pour toute autre erreur.
    static func causeIllisible(_ erreur: any Error) -> String? {
        if case C.Erreur.illisible(let cause) = erreur { return cause }
        return nil
    }

    /// La cause d'illisibilite de la lecture du manifeste (nil : lecture reussie ou autre erreur).
    static func causeManifeste(_ json: String) -> String? {
        do { _ = try C.lireManifeste(Data(json.utf8)); return nil } catch { return causeIllisible(error) }
    }

    static func causeReglages(_ json: String) -> String? {
        do { _ = try C.lireReglages(Data(json.utf8)); return nil } catch { return causeIllisible(error) }
    }

    static func texte(_ d: Data) -> String { String(decoding: d, as: UTF8.self) }

    static func dossier() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("contrat-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    // MARK: Manifeste

    /// Aller-retour, et texte exact : cles triees, dates ISO 8601, ordre des fichiers garde, deux ecritures identiques.
    @Test func manifesteAllerRetour() throws {
        let m = Self.manifeste()
        let json = try C.ecrire(m)
        #expect(try C.lireManifeste(json) == m)
        #expect(try C.ecrire(m) == json, "ecriture deterministe")
        let attendu = """
        {
          "app" : "thread",
          "date" : "2026-10-17T12:00:00Z",
          "fichiers" : [
            {
              "chemin" : "surnoms.json",
              "sha256" : "\(Self.sha)",
              "taille" : 12
            },
            {
              "chemin" : "Journal/journal-2026-10.jsonl",
              "sha256" : "\(String(repeating: "0", count: 64))",
              "taille" : 0
            },
            {
              "chemin" : "reglages.json",
              "sha256" : "\(Self.sha)",
              "taille" : 345
            }
          ],
          "fichiersNonRepris" : [
            {
              "chemin" : ".DS_Store",
              "raison" : "exclu"
            },
            {
              "chemin" : "cache.tmp",
              "raison" : "horsContrat"
            }
          ],
          "format" : 1,
          "identifiant" : "00000000-0000-4000-8000-000000000001",
          "versionApp" : "9.9.9"
        }
        """
        #expect(Self.texte(json) == attendu)
    }

    /// Les valeurs brutes de l'app source sont stables : elles sont ecrites dans les exports.
    @Test func appsSource() {
        #expect(C.AppSource.maillageThread.rawValue == "thread")
        #expect(C.AppSource.maillageZigbee.rawValue == "zigbee")
        #expect(C.AppSource.allCases.count == 2)
        #expect(C.AppSource(rawValue: "zigbee") == .maillageZigbee)
    }

    /// Une date avec des fractions est ramenee a la seconde a la construction : ce qui s'ecrit se relit egal.
    @Test func dateALaSeconde() throws {
        let m = C.Manifeste(identifiant: Self.identifiant, app: .maillageZigbee, versionApp: "1", date: Self.date + 0.789,
                            fichiers: [], fichiersNonRepris: [])
        #expect(m.date == Self.date)
        #expect(try C.lireManifeste(C.ecrire(m)) == m)
    }

    /// Un format autre que 1 est refuse avec une erreur typee, meme si le reste du manifeste a une autre forme.
    @Test func formatInconnuRefuse() throws {
        for format in [0, 2, 99, -1] {
            let json = Data(#"{"format": \#(format), "inconnu": true}"#.utf8)
            #expect(throws: C.Erreur.formatInconnu(format)) { try C.lireManifeste(json) }
        }
        let bon = try C.ecrire(Self.manifeste())
        let v2 = Data(Self.texte(bon).replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2").utf8)
        #expect(throws: C.Erreur.formatInconnu(2)) { try C.lireManifeste(v2) }
        #expect(throws: C.Erreur.formatInconnu(2)) { try JSONDecoder().decode(C.Manifeste.self, from: v2) }
    }

    /// Une app source inconnue est refusee avec son nom ; l'ancien nom de cas n'est pas une valeur brute.
    @Test func appInconnueRefusee() throws {
        let bon = Self.texte(try C.ecrire(Self.manifeste()))
        for nom in ["matter", "", "maillageThread", "THREAD"] {
            let json = Data(bon.replacingOccurrences(of: "\"app\" : \"thread\"", with: "\"app\" : \"\(nom)\"").utf8)
            #expect(throws: C.Erreur.appInconnue(nom)) { try C.lireManifeste(json) }
        }
    }

    /// Un manifeste mal forme est "illisible", sans plantage, avec la cause (champ ou chemin, jamais une valeur) :
    /// JSON invalide, champ manquant, mauvais type.
    @Test func manifesteIllisible() throws {
        let bon = Self.texte(try C.ecrire(Self.manifeste()))
        let casses: [(String, String)] = [
            ("pas du JSON", "JSON invalide"),
            ("[]", "type inattendu : (racine)"),
            ("{}", "champ manquant : format"),
            (bon.replacingOccurrences(of: "\"versionApp\"", with: "\"autreCle\""), "champ manquant : versionApp"),
            (bon.replacingOccurrences(of: "\"fichiersNonRepris\"", with: "\"autreCle\""), "champ manquant : fichiersNonRepris"),
            (bon.replacingOccurrences(of: "\"taille\" : 12", with: "\"taille\" : \"12\""), "type inattendu : fichiers[0].taille"),
            (bon.replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : \"1\""), "type inattendu : format"),
            (bon.replacingOccurrences(of: "2026-10-17T12:00:00Z", with: "hier"), "valeur invalide"),
            (bon.replacingOccurrences(of: "00000000-0000-4000-8000-000000000001", with: "pas-un-uuid"), "valeur invalide : identifiant"),
            (bon.replacingOccurrences(of: "\"exclu\"", with: "\"autre\""), "valeur invalide : fichiersNonRepris[0].raison"),
        ]
        for (json, cause) in casses {
            #expect(Self.causeManifeste(json) == cause, "\(json.prefix(40))")
        }
    }

    /// Un manifeste altere est refuse a la lecture : chemin qui sort, empreinte mal formee, taille negative, doublon
    /// (casse comprise), nom reserve.
    @Test func manifesteAltereRefuse() throws {
        func avec(_ f: C.Fichier...) -> Data { (try? C.encodeur().encode(Self.manifeste(fichiers: f))) ?? Data() }
        let ok = C.Fichier(chemin: "surnoms.json", taille: 1, sha256: Self.sha)
        #expect(throws: C.Erreur.cheminInvalide("../x")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "../x", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminInvalide("/etc/passwd")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "/etc/passwd", taille: 1, sha256: Self.sha)))
        }
        for mauvaise in ["", "abc", String(repeating: "AB", count: 32), String(repeating: "g", count: 64),
                         String(repeating: "a", count: 63), String(repeating: "a", count: 65)] {
            #expect(throws: C.Erreur.empreinteInvalide("surnoms.json"), "\(mauvaise.count)") {
                try C.lireManifeste(avec(C.Fichier(chemin: "surnoms.json", taille: 1, sha256: mauvaise)))
            }
        }
        #expect(throws: C.Erreur.tailleInvalide("surnoms.json")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "surnoms.json", taille: -1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminEnDouble("SURNOMS.json")) {
            try C.lireManifeste(avec(ok, C.Fichier(chemin: "SURNOMS.json", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.cheminEnDouble("surnoms.json")) { try C.lireManifeste(avec(ok, ok)) }
        #expect(throws: C.Erreur.nomReserve("manifeste.json")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "manifeste.json", taille: 1, sha256: Self.sha)))
        }
        #expect(throws: C.Erreur.nomReserve("Manifeste.JSON")) {
            try C.lireManifeste(avec(C.Fichier(chemin: "Manifeste.JSON", taille: 1, sha256: Self.sha)))
        }
    }

    /// L'ecriture refuse elle aussi ce que la lecture refuserait : on ne produit pas un export illisible.
    @Test func ecritureRefuseLesMemesCas() {
        #expect(throws: C.Erreur.cheminInvalide("a/../../x")) {
            try C.ecrire(Self.manifeste(fichiers: [C.Fichier(chemin: "a/../../x", taille: 1, sha256: Self.sha)]))
        }
    }

    // MARK: Chemins

    @Test(arguments: [
        "surnoms.json", "Journal/journal-2026-10.jsonl", "Thread/x.json", "a/b/c.txt", "maillage-2026-09.jsonl",
        "nom avec espaces.json", "accentué.json", "..x", "x..", "a/..b/c", ".cache", "a/.b",
    ])
    func cheminsValides(_ chemin: String) throws {
        #expect(C.cheminEstValide(chemin))
        try C.verifierChemin(chemin)
    }

    @Test(arguments: [
        "", "/", "/etc/passwd", "/surnoms.json", "..", "../x", "a/../../x", "a/..", "a/../b", "./x", "a/./b", "a//b",
        "a/", "x/", "//x", "a\\b", "a\u{0}b", "a\nb", "a\tb", "a\u{7F}b", ".", "a/.", "~/../x",
        String(repeating: "a", count: 300), Array(repeating: "d", count: 600).joined(separator: "/"),
    ])
    func cheminsRefuses(_ chemin: String) {
        #expect(!C.cheminEstValide(chemin))
        #expect(throws: C.Erreur.cheminInvalide(chemin)) { try C.verifierChemin(chemin) }
    }

    /// Resolution dans un dossier : un chemin normal, y compris vers un fichier pas encore ecrit, reste dedans.
    @Test func resoudreDansLeDossier() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = try C.resoudre("Journal/journal-2026-10.jsonl", dans: d)
        #expect(url.standardizedFileURL.path == d.standardizedFileURL.appendingPathComponent("Journal/journal-2026-10.jsonl").path)
        #expect(throws: C.Erreur.cheminInvalide("../x")) { try C.resoudre("../x", dans: d) }
        #expect(throws: C.Erreur.cheminInvalide("/tmp/x")) { try C.resoudre("/tmp/x", dans: d) }
    }

    /// Un lien symbolique du dossier vers l'exterieur, sur le fichier ou sur un dossier du chemin, est refuse.
    @Test func lienSymboliqueRefuse() throws {
        let d = try Self.dossier(), dehors = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d); try? FileManager.default.removeItem(at: dehors) }
        try Data("dehors".utf8).write(to: dehors.appendingPathComponent("secret.json"))
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("lien.json"),
                                                   withDestinationURL: dehors.appendingPathComponent("secret.json"))
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("Journal"), withDestinationURL: dehors)
        #expect(throws: C.Erreur.lienSymbolique("lien.json")) { try C.resoudre("lien.json", dans: d) }
        #expect(throws: C.Erreur.lienSymbolique("Journal/secret.json")) { try C.resoudre("Journal/secret.json", dans: d) }
        #expect(throws: C.Erreur.lienSymbolique("lien.json")) { try C.Fichier.decrire(chemin: "lien.json", dans: d) }
    }

    /// Le dossier lui-meme peut etre derriere un lien (`/var` -> `/private/var`) sans que ses fichiers soient refuses.
    @Test func dossierDerriereUnLien() throws {
        let vrai = try Self.dossier()
        let lien = FileManager.default.temporaryDirectory.appendingPathComponent("contrat-lien-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: vrai); try? FileManager.default.removeItem(at: lien) }
        try FileManager.default.createSymbolicLink(at: lien, withDestinationURL: vrai)
        try Data("x".utf8).write(to: vrai.appendingPathComponent("surnoms.json"))
        let f = try C.Fichier.decrire(chemin: "surnoms.json", dans: lien)
        #expect(f.taille == 1)
    }

    // MARK: Empreintes

    /// SHA-256 de contenus connus (FIPS 180-2), en hexadecimal minuscule.
    @Test func empreinteConnue() throws {
        #expect(C.sha256(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(C.sha256(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let f = d.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: f)
        #expect(try C.sha256(fichier: f) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let vide = d.appendingPathComponent("vide")
        try Data().write(to: vide)
        #expect(try C.sha256(fichier: vide) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    /// Un fichier de plusieurs tailles de tampon donne la meme empreinte que son contenu d'un bloc.
    @Test func empreinteParBlocs() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        var contenu = Data()
        for i in 0..<(3 * 1024 * 1024 + 17) { contenu.append(UInt8(truncatingIfNeeded: i &* 31 &+ 7)) }
        let f = d.appendingPathComponent("gros.bin")
        try contenu.write(to: f)
        #expect(try C.sha256(fichier: f) == C.sha256(contenu))
    }

    /// Un fichier absent n'a pas d'empreinte : l'erreur passe, rien n'est invente.
    @Test func empreinteFichierAbsent() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(throws: (any Error).self) { try C.sha256(fichier: d.appendingPathComponent("absent")) }
    }

    /// `Fichier.decrire` : taille et empreinte du fichier du dossier, sous son chemin relatif.
    @Test func decrireUnFichier() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        try FileManager.default.createDirectory(at: d.appendingPathComponent("Journal"), withIntermediateDirectories: true)
        try Data("abc".utf8).write(to: d.appendingPathComponent("Journal/journal-2026-10.jsonl"))
        let f = try C.Fichier.decrire(chemin: "Journal/journal-2026-10.jsonl", dans: d)
        #expect(f == C.Fichier(chemin: "Journal/journal-2026-10.jsonl", taille: 3,
                               sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
        #expect(throws: (any Error).self) { try C.Fichier.decrire(chemin: "Journal", dans: d) }
        #expect(throws: (any Error).self) { try C.Fichier.decrire(chemin: "absent.json", dans: d) }
    }

    @Test func formeDUneEmpreinte() {
        #expect(C.empreinteEstValide(Self.sha))
        #expect(!C.empreinteEstValide(Self.sha.uppercased()))
        #expect(!C.empreinteEstValide(String(Self.sha.dropLast())))
        #expect(!C.empreinteEstValide(""))
    }

    // MARK: Reglages

    /// Un reglage de chaque type, ecrit puis relu egal ; le texte porte le type et la valeur, cles triees.
    @Test func reglagesAllerRetour() throws {
        let r = C.Reglages(app: .maillageZigbee, valeurs: [
            "grapheDejaOuvert": .bool(true),
            "etagesEnGrille": .bool(false),
            "sondePagesTables": .entier(7),
            "negatif": .entier(-3),
            "decimal": .decimal(0.25),
            "sondeNom": .texte("Sonde 1 é"),
            "vide": .texte(""),
            "pont.hue": .donnees(Data([0x00, 0x01, 0xFE, 0xFF])),
            "AppleLanguages": .listeTextes(["fr", "en"]),
            "listeVide": .listeTextes([]),
            "sondeJournalPages": .listeEntiers([1, 2, 300, -4]),
        ], nonRepris: ["SUHasLaunchedBefore": .horsContrat, "vuePieces3D": .typeInattendu])
        let json = try C.ecrire(r)
        #expect(try C.lireReglages(json) == r)
        #expect(try C.ecrire(r) == json)
        let t = Self.texte(json)
        #expect(t.contains("\"pont.hue\" : {\n      \"type\" : \"donnees\",\n      \"valeur\" : \"AAH+/w==\"\n    }"))
        #expect(t.contains("\"sondePagesTables\" : {\n      \"type\" : \"entier\",\n      \"valeur\" : 7\n    }"))
        #expect(t.contains("\"SUHasLaunchedBefore\" : \"horsContrat\""))
        #expect(t.contains("\"vuePieces3D\" : \"typeInattendu\""))
        #expect(t.contains("\"app\" : \"zigbee\""))
        #expect(t.contains("\"format\" : 1"))
        let cles = t.components(separatedBy: "\n").compactMap { l -> String? in
            guard l.hasPrefix("    \""), l.hasSuffix(": {"), let f = l.dropFirst(5).firstIndex(of: "\"") else { return nil }
            return String(l.dropFirst(5)[..<f])
        }
        #expect(cles == cles.sorted(), "cles triees")
    }

    /// Un 1 entier et un 1,0 decimal, un booleen et un 1 : le type ecrit est celui qu'on relit.
    @Test func typesNeSeConfondentPas() throws {
        let r = C.Reglages(app: .maillageThread, valeurs: ["a": .entier(1), "b": .decimal(1.0), "c": .bool(true),
                                                          "d": .texte("1"), "e": .listeEntiers([1])], nonRepris: [:])
        let relu = try C.lireReglages(C.ecrire(r))
        #expect(relu.valeurs["a"] == .entier(1))
        #expect(relu.valeurs["b"] == .decimal(1.0))
        #expect(relu.valeurs["c"] == .bool(true))
        #expect(relu.valeurs["d"] == .texte("1"))
        #expect(relu.valeurs["e"] == .listeEntiers([1]))
        #expect(relu.valeurs["a"] != .decimal(1.0))
    }

    @Test func reglagesVides() throws {
        let r = C.Reglages(app: .maillageThread, valeurs: [:], nonRepris: [:])
        #expect(try C.lireReglages(C.ecrire(r)) == r)
    }

    /// Format inconnu, app inconnue, type de valeur inconnu (jamais ignore en silence), cle vide, JSON mal forme.
    @Test func reglagesRefuses() throws {
        let bon = Self.texte(try C.ecrire(C.Reglages(app: .maillageThread, valeurs: ["a": .bool(true)], nonRepris: [:])))
        let v2 = Data(bon.replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2").utf8)
        #expect(throws: C.Erreur.formatInconnu(2)) { try C.lireReglages(v2) }
        let app = Data(bon.replacingOccurrences(of: "\"thread\"", with: "\"autre\"").utf8)
        #expect(throws: C.Erreur.appInconnue("autre")) { try C.lireReglages(app) }
        let type = Data(bon.replacingOccurrences(of: "\"bool\"", with: "\"date\"").utf8)
        #expect(throws: C.Erreur.valeurInconnue(cle: "a", type: "date")) { try C.lireReglages(type) }
        let vide = Data(bon.replacingOccurrences(of: "\"a\"", with: "\"\"").utf8)
        #expect(throws: C.Erreur.cleInvalide) { try C.lireReglages(vide) }
        #expect(Self.causeReglages(bon.replacingOccurrences(of: "true", with: "\"oui\"")) == "type inattendu : valeurs.a.valeur")
        #expect(Self.causeReglages("{}") == "champ manquant : format")
        #expect(Self.causeReglages("pas du json") == "JSON invalide")
        #expect(Self.causeReglages(bon.replacingOccurrences(of: "\"nonRepris\"", with: "\"autre\"")) == "champ manquant : nonRepris")
    }

    /// Un decimal qui ne s'ecrit pas en JSON (NaN, infini) n'est jamais ecrit tronque : l'ecriture echoue.
    @Test func decimalNonFini() {
        let r = C.Reglages(app: .maillageThread, valeurs: ["x": .decimal(.nan)], nonRepris: [:])
        #expect(throws: (any Error).self) { try C.ecrire(r) }
    }

    // MARK: Fichiers et reglages connus

    @Test func fichiersConnusDeThread() {
        let attendus = ["surnoms.json", "associations.json", "identites-routeurs.json", "dernier-maillage.json",
                        "dernieres-adresses.json", "noms.json", "pieces-routeurs.json", "positions-pieces.json",
                        "maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        #expect(C.fichiersConnus(de: .maillageThread).map(\.modele) == attendus)
    }

    @Test func fichiersConnusDeZigbee() {
        let attendus = ["surnoms.json", "dernier-maillage.json", "appariements-maison.json", "noms-pont.json",
                        "releve-maison.json", "pieces-routeurs.json", "positions-pieces.json",
                        "maillage-AAAA-MM.jsonl", "Journal/journal-AAAA-MM.jsonl"]
        #expect(C.fichiersConnus(de: .maillageZigbee).map(\.modele) == attendus)
    }

    @Test func correspondanceDesNomsConnus() {
        #expect(C.estConnu("surnoms.json", de: .maillageThread))
        #expect(C.estConnu("maillage-2026-10.jsonl", de: .maillageThread))
        #expect(C.estConnu("Journal/journal-2026-09.jsonl", de: .maillageZigbee))
        #expect(C.estConnu("noms.json", de: .maillageThread))
        #expect(!C.estConnu("noms.json", de: .maillageZigbee), "noms.json est le releve de Thread seulement")
        #expect(C.estConnu("releve-maison.json", de: .maillageZigbee))
        #expect(!C.estConnu("associations.json", de: .maillageZigbee))
        #expect(!C.estConnu("Thread/surnoms.json", de: .maillageThread), "pas de dossier d'un module dans l'export")
        for faux in ["maillage-2026-13.jsonl", "maillage-2026-00.jsonl", "maillage-26-10.jsonl", "maillage-2026-1.jsonl",
                     "maillage-2026-10.json", "Maillage-2026-10.jsonl", "journal-2026-10.jsonl", "Journal/journal-2026-10.json",
                     "maillage-2026-10.jsonl.bak", "maillage-abcd-10.jsonl", "Journal/maillage-2026-10.jsonl",
                     "reglages.json", "manifeste.json", ".DS_Store", ""] {
            #expect(!C.estConnu(faux, de: .maillageThread), "\(faux)")
            #expect(!C.estConnu(faux, de: .maillageZigbee), "\(faux)")
        }
    }

    @Test func moisDesFichiersMensuels() {
        #expect(C.mois(de: "maillage-2026-10.jsonl") == C.Mois(annee: 2026, mois: 10))
        #expect(C.mois(de: "Journal/journal-2025-01.jsonl") == C.Mois(annee: 2025, mois: 1))
        #expect(C.mois(de: "surnoms.json") == nil)
        #expect(C.mois(de: "maillage-2026-13.jsonl") == nil)
        #expect(C.Mois(annee: 2025, mois: 12) < C.Mois(annee: 2026, mois: 1))
        #expect(C.Mois(annee: 2026, mois: 2) < C.Mois(annee: 2026, mois: 10))
    }

    @Test func fichiersExclus() {
        for nom in [".DS_Store", "Journal/.DS_Store", "noms.illisible-20261017-120000.json", "Journal/x.illisible-1.json",
                    "._surnoms.json", "Journal/._journal-2026-10.jsonl"] {
            #expect(C.estExcluDeLExport(nom), "\(nom)")
        }
        for nom in ["surnoms.json", "illisible.json", "x.illisible-1.txt", "maillage-2026-10.jsonl", "_x.json", "x._json"] {
            #expect(!C.estExcluDeLExport(nom), "\(nom)")
        }
    }

    /// Les reglages de l'inventaire (17/10) : chacun a son type, par app ; les cles absentes de la liste restent a
    /// l'import de dire "ignore".
    @Test func reglagesConnus() {
        func types(_ app: C.AppSource) -> [String: C.TypeValeur] {
            Dictionary(uniqueKeysWithValues: C.reglagesConnus(de: app).map { ($0.cle, $0.type) })
        }
        let communs: [String: C.TypeValeur] = [
            "vuePieces3D": .bool, "etagesEnGrille": .bool, "legendeRepliee": .bool, "grapheDejaOuvert": .bool,
            "ouvertureSessionProposee": .bool, "AppleLanguages": .listeTextes,
        ]
        let thread = communs.merging([
            "sondeSerieUSB": .texte, "sondeNom": .texte, "sondeHote": .texte, "sondeLiaison": .texte,
            "scissionsNotifiees": .listeTextes,
            "notification.scission": .bool, "notification.routeurDisparu": .bool, "notification.pertes": .bool,
            "notification.informations": .bool,
        ]) { a, _ in a }
        let zigbee = communs.merging([
            "sondeSerieUSB": .texte, "sondeNom": .texte, "sondeIeee": .texte, "sondeNomWifi": .texte,
            "sondePagesTables": .entier, "sondeChemin": .texte,
            "pont.hue": .donnees, "liensMontres": .texte, "voisinsALaSelection": .bool,
            "notification.routeurDisparu": .bool, "notification.pertes": .bool, "notification.informations": .bool,
        ]) { a, _ in a }
        #expect(types(.maillageThread) == thread)
        #expect(types(.maillageZigbee) == zigbee)
        #expect(C.reglagesConnus(de: .maillageThread).count == thread.count, "pas de cle en double")
        #expect(C.reglagesConnus(de: .maillageZigbee).count == zigbee.count, "pas de cle en double")
        #expect(types(.maillageZigbee)["notification.scission"] == nil, "Zigbee n'a pas de scission")
    }

    /// Jamais dans les reglages : Sparkle, etats de fenetre, onglet des reglages, signet de l'ancien dossier des noms,
    /// secrets. Ils ne sont dans aucune liste connue.
    @Test func reglagesNonRepris() {
        for cle in ["SUHasLaunchedBefore", "SULastCheckTime", "SUUpdateGroupIdentifier", "NSWindow Frame graphe",
                    "reglages.onglet", "dossierNoms", "motDePasseWifi", "cleSonde"] {
            for app in C.AppSource.allCases {
                #expect(!C.reglagesConnus(de: app).contains { $0.cle == cle }, "\(cle)")
                #expect(C.typeAttendu(cle: cle, de: app) == nil)
            }
        }
        #expect(C.typeAttendu(cle: "sondeLiaison", de: .maillageThread) == .texte)
        #expect(C.typeAttendu(cle: "sondeLiaison", de: .maillageZigbee) == nil)
        #expect(C.Valeur.listeEntiers([]).type == .listeEntiers)
        #expect(C.Valeur.donnees(Data()).type == .donnees)
    }

    /// Les noms que l'export reserve au contrat.
    @Test func nomsReserves() {
        #expect(C.nomManifeste == "manifeste.json")
        #expect(C.nomReglages == "reglages.json")
        #expect(C.formatCourant == 1)
    }

    // MARK: Identite des anciennes apps

    /// Identifiant de bundle, nom affiche et dossier d'Application Support des deux anciennes apps (project.yml et
    /// `Surveillance.swift` de chacune) : constantes du contrat, jamais dans le JSON.
    @Test func identiteDesAnciennesApps() {
        #expect(C.AppSource.maillageThread.identifiantBundle == "fr.djoko.maillage")
        #expect(C.AppSource.maillageZigbee.identifiantBundle == "fr.djoko.maillage.zigbee")
        #expect(C.AppSource.maillageThread.nomApp == "Maillage Thread")
        #expect(C.AppSource.maillageZigbee.nomApp == "Maillage Zigbee")
        #expect(C.AppSource.maillageThread.dossierDonnees == "Maillage Thread")
        #expect(C.AppSource.maillageZigbee.dossierDonnees == "Maillage Zigbee")
        #expect(Set(C.AppSource.allCases.map(\.identifiantBundle)).count == 2)
    }

    // MARK: Ce qui n'est pas repris : fichiers

    @Test func fichiersNonReprisTries() {
        let m = Self.manifeste(nonRepris: [
            C.FichierNonRepris(chemin: "zeta.bin", raison: .horsContrat),
            C.FichierNonRepris(chemin: "Alpha.bin", raison: .horsContrat),
            C.FichierNonRepris(chemin: ".DS_Store", raison: .exclu),
        ])
        #expect(m.fichiersNonRepris.map(\.chemin) == [".DS_Store", "Alpha.bin", "zeta.bin"])
    }

    /// Un fichier non repris est cite avec sa raison ; un chemin invalide, un doublon (entre eux ou avec un fichier
    /// repris, casse comprise) ou `manifeste.json` sont refuses, a l'ecriture comme a la lecture.
    @Test func fichiersNonReprisRefuses() throws {
        func avec(_ n: C.FichierNonRepris...) -> C.Manifeste { Self.manifeste(nonRepris: n) }
        func nr(_ c: String) -> C.FichierNonRepris { C.FichierNonRepris(chemin: c, raison: .horsContrat) }
        let cas: [(C.Manifeste, C.Erreur)] = [
            (avec(nr("../x")), .cheminInvalide("../x")),
            (avec(nr("/etc/x")), .cheminInvalide("/etc/x")),
            (avec(nr("a.bin"), nr("a.bin")), .cheminEnDouble("a.bin")),
            (avec(nr("a.bin"), nr("A.BIN")), .cheminEnDouble("a.bin")),  // trie : A.BIN d'abord
            (avec(nr("surnoms.json")), .cheminEnDouble("surnoms.json")),
            (avec(nr("SURNOMS.json")), .cheminEnDouble("SURNOMS.json")),
            (avec(nr("manifeste.json")), .nomReserve("manifeste.json")),
        ]
        for (m, erreur) in cas {
            #expect(throws: erreur) { try C.ecrire(m) }
            let json = (try? C.encodeur().encode(m)) ?? Data()
            #expect(throws: erreur) { try C.lireManifeste(json) }
        }
    }

    @Test func raisonsNonReprises() {
        #expect(C.RaisonNonRepris.allCases.map(\.rawValue) == ["horsContrat", "exclu", "typeInattendu", "transitoire"])
    }

    /// Classement de ce qu'une ancienne app voit dans son `Application Support` : le meme pour les deux apps.
    @Test func classerLesFichiersVus() throws {
        let vus = ["surnoms.json", "noms.json", "Journal/journal-2026-10.jsonl", ".DS_Store", "Journal/.DS_Store",
                   "noms.illisible-1.json", "Sparkle.xml", "Thread/x.json", "associations.json", "reglages.json",
                   "manifeste.json", "maillage-2026-10.jsonl"]
        let thread = try C.classerFichiers(vus: vus, de: .maillageThread)
        #expect(thread.aCopier == ["Journal/journal-2026-10.jsonl", "associations.json", "maillage-2026-10.jsonl",
                                   "noms.json", "surnoms.json"])
        #expect(thread.nonRepris == [
            C.FichierNonRepris(chemin: ".DS_Store", raison: .exclu),
            C.FichierNonRepris(chemin: "Journal/.DS_Store", raison: .exclu),
            C.FichierNonRepris(chemin: "Sparkle.xml", raison: .horsContrat),
            C.FichierNonRepris(chemin: "Thread/x.json", raison: .horsContrat),
            C.FichierNonRepris(chemin: "noms.illisible-1.json", raison: .exclu),
        ])
        let zigbee = try C.classerFichiers(vus: vus, de: .maillageZigbee)
        #expect(zigbee.aCopier == ["Journal/journal-2026-10.jsonl", "maillage-2026-10.jsonl", "surnoms.json"])
        #expect(zigbee.nonRepris.contains(C.FichierNonRepris(chemin: "noms.json", raison: .horsContrat)))
        #expect(zigbee.nonRepris.contains(C.FichierNonRepris(chemin: "associations.json", raison: .horsContrat)))
        // rien n'est perdu en silence, sauf les deux noms reserves de la racine, que l'export ecrit lui-meme
        #expect(zigbee.aCopier.count + zigbee.nonRepris.count == vus.count - 2)
        #expect(thread.aCopier.count + thread.nonRepris.count == vus.count - 2)
        #expect(throws: C.Erreur.cheminInvalide("../x")) { try C.classerFichiers(vus: ["../x"], de: .maillageThread) }
    }

    /// `manifeste.json` et `reglages.json` a la racine du dossier de l'app (a la casse pres) sont ecrits par l'export
    /// lui-meme : le classement les ecarte, ni copies ni cites. Dans un sous-dossier ils ne genent pas : hors contrat.
    @Test func nomsReservesDeLaRacineEcartes() throws {
        for app in C.AppSource.allCases {
            let vus = ["manifeste.json", "reglages.json", "Manifeste.JSON", "REGLAGES.json", "Journal/manifeste.json",
                       "surnoms.json", "Sparkle.xml"]
            let classes = try C.classerFichiers(vus: vus, de: app)
            #expect(classes.aCopier == ["surnoms.json"])
            #expect(classes.nonRepris == [
                C.FichierNonRepris(chemin: "Journal/manifeste.json", raison: .horsContrat),
                C.FichierNonRepris(chemin: "Sparkle.xml", raison: .horsContrat),
            ])
            let seuls = try C.classerFichiers(vus: ["manifeste.json", "reglages.json"], de: app)
            #expect(seuls.aCopier.isEmpty && seuls.nonRepris.isEmpty)
            // l'ecriture du manifeste a partir du classement reussit, sans filtre supplementaire
            let fichiers = classes.aCopier.map { C.Fichier(chemin: $0, taille: 1, sha256: Self.sha) }
                + [C.Fichier(chemin: C.nomReglages, taille: 1, sha256: Self.sha)]
            let m = Self.manifeste(app: app, fichiers: fichiers, nonRepris: classes.nonRepris)
            #expect(try C.lireManifeste(C.ecrire(m)) == m)
        }
    }

    // MARK: Ce qui n'est pas repris : reglages

    @Test func reglagesNonReprisRefuses() throws {
        let bon = Self.texte(try C.ecrire(C.Reglages(app: .maillageThread, valeurs: ["a": .bool(true)],
                                                    nonRepris: ["SUHasLaunchedBefore": .horsContrat])))
        #expect(try C.lireReglages(Data(bon.utf8)).nonRepris == ["SUHasLaunchedBefore": .horsContrat])
        let vide = Data(bon.replacingOccurrences(of: "\"SUHasLaunchedBefore\"", with: "\"\"").utf8)
        #expect(throws: C.Erreur.cleInvalide) { try C.lireReglages(vide) }
        let double = Data(bon.replacingOccurrences(of: "\"SUHasLaunchedBefore\"", with: "\"a\"").utf8)
        #expect(throws: C.Erreur.cleEnDouble("a")) { try C.lireReglages(double) }
        #expect(Self.causeReglages(bon.replacingOccurrences(of: "\"horsContrat\"", with: "\"autre\""))
                == "valeur invalide : nonRepris.SUHasLaunchedBefore")
        // l'ecriture refuse les memes cas
        #expect(throws: C.Erreur.cleInvalide) {
            try C.ecrire(C.Reglages(app: .maillageThread, valeurs: [:], nonRepris: ["": .horsContrat]))
        }
        #expect(throws: C.Erreur.cleEnDouble("a")) {
            try C.ecrire(C.Reglages(app: .maillageThread, valeurs: ["a": .bool(true)], nonRepris: ["a": .typeInattendu]))
        }
    }

    // MARK: Lecture des reglages d'une ancienne app

    /// Un booleen n'est pas un nombre, un nombre n'est pas un booleen : `1` ne devient jamais `true`, `true` jamais `1`.
    /// Une valeur du mauvais type est citee `typeInattendu`, jamais perdue en silence ni convertie.
    @Test func reglagesBoolContreEntier() {
        let thread = C.reglages(depuis: [
            "vuePieces3D": true, "legendeRepliee": false,
            "etagesEnGrille": 1, "grapheDejaOuvert": 0, "ouvertureSessionProposee": 1.0,
        ], app: .maillageThread)
        #expect(thread.valeurs == ["vuePieces3D": .bool(true), "legendeRepliee": .bool(false)])
        #expect(thread.nonRepris == ["etagesEnGrille": .typeInattendu, "grapheDejaOuvert": .typeInattendu,
                                     "ouvertureSessionProposee": .typeInattendu])
        #expect(thread.app == .maillageThread)

        let zigbee = C.reglages(depuis: ["sondePagesTables": 7, "voisinsALaSelection": true], app: .maillageZigbee)
        #expect(zigbee.valeurs == ["sondePagesTables": .entier(7), "voisinsALaSelection": .bool(true)])
        #expect(zigbee.nonRepris.isEmpty)
        for mauvais: Any in [true, false, 7.5, "7", Double.nan] {
            let r = C.reglages(depuis: ["sondePagesTables": mauvais], app: .maillageZigbee)
            #expect(r.valeurs.isEmpty, "\(mauvais)")
            #expect(r.nonRepris == ["sondePagesTables": .typeInattendu], "\(mauvais)")
        }
        let negatif = C.reglages(depuis: ["sondePagesTables": -3], app: .maillageZigbee)
        #expect(negatif.valeurs == ["sondePagesTables": .entier(-3)])
    }

    /// Chaque type de l'inventaire est lu strictement : texte, donnees, listes de textes et d'entiers.
    @Test func reglagesTypesStricts() {
        let ok = C.reglages(depuis: [
            "sondeNom": "Sonde 1", "pont.hue": Data([1, 2, 3]), "sondeIeee": "0000000000000001",
            "AppleLanguages": ["fr", "en"],
        ], app: .maillageZigbee)
        #expect(ok.valeurs == [
            "sondeNom": .texte("Sonde 1"), "pont.hue": .donnees(Data([1, 2, 3])),
            "sondeIeee": .texte("0000000000000001"), "AppleLanguages": .listeTextes(["fr", "en"]),
        ])
        #expect(ok.nonRepris.isEmpty)
        let mauvais = C.reglages(depuis: [
            "sondeNom": 12, "pont.hue": "texte", "sondeIeee": 5,
            "AppleLanguages": ["fr", 1] as [Any], "sondeChemin": ["a"] as [String],
        ], app: .maillageZigbee)
        #expect(mauvais.valeurs.isEmpty)
        #expect(mauvais.nonRepris == [
            "sondeNom": .typeInattendu, "pont.hue": .typeInattendu, "sondeIeee": .typeInattendu,
            "AppleLanguages": .typeInattendu, "sondeChemin": .typeInattendu,
        ])
        #expect(C.reglages(depuis: ["AppleLanguages": [String]()], app: .maillageZigbee).valeurs
                == ["AppleLanguages": .listeTextes([])])
    }

    /// `sondeJournalPages` est la fenetre glissante de 10 minutes du budget de la tournee, ecrite par Maillage Zigbee
    /// en `[Double]` (instant, pages, instant, pages...) : sans sens apres un export pris plus tot, elle n'est jamais
    /// reprise, quel que soit son type, et jamais citee `typeInattendu`. Seule sa cle est citee, sans valeur.
    @Test func budgetDeTourneeEstTransitoire() throws {
        for brut: Any in [[1_760_000_000.5, 12.0, 1_760_000_060.75, 7.0] as [Double], [1, 2, 300] as [Int],
                          [Double](), "texte", true] {
            let r = C.reglages(depuis: ["sondeJournalPages": brut], app: .maillageZigbee)
            #expect(r.valeurs.isEmpty, "aucune valeur gardee : \(brut)")
            #expect(r.nonRepris == ["sondeJournalPages": .transitoire], "\(brut)")
        }
        #expect(C.typeAttendu(cle: "sondeJournalPages", de: .maillageZigbee) == nil)
        #expect(!C.reglagesConnus(de: .maillageZigbee).contains { $0.cle == "sondeJournalPages" })
        // Le domaine persistant d'une vraie lecture (liste de Double dans UserDefaults), cle citee et valeur absente.
        let nom = "fr.djoko.test.contrat-\(UUID().uuidString)"
        let defauts = try #require(UserDefaults(suiteName: nom))
        defer { defauts.removePersistentDomain(forName: nom) }
        defauts.set([1_760_000_000.5, 12.0] as [Double], forKey: "sondeJournalPages")
        let r = C.reglagesPersistants(de: .maillageZigbee, domaine: nom, defauts: defauts)
        #expect(r.valeurs.isEmpty)
        #expect(r.nonRepris == ["sondeJournalPages": .transitoire])
        #expect(try C.lireReglages(C.ecrire(r)) == r)
        #expect(Self.texte(try C.ecrire(r)).contains("\"sondeJournalPages\" : \"transitoire\""))
        // Maillage Thread n'a pas cette cle : citee `horsContrat` comme toute cle inconnue.
        #expect(C.reglages(depuis: ["sondeJournalPages": [1.0]], app: .maillageThread).nonRepris
                == ["sondeJournalPages": .horsContrat])
    }

    /// Une cle inconnue (Sparkle, fenetres, onglet, ancien dossier des noms, ou une cle de l'autre app) est citee
    /// `horsContrat`, sans valeur ; une cle connue absente reste absente (aucun defaut).
    @Test func reglagesCleInconnueEstCitee() throws {
        let domaine: [String: Any] = [
            "SUHasLaunchedBefore": true, "NSWindow Frame graphe": "10 20 300 400", "reglages.onglet": "notifications",
            "dossierNoms": Data([9]), "motDePasseWifi": "secret-invente", "scissionsNotifiees": ["a"],
            "vuePieces3D": true,
        ]
        let r = C.reglages(depuis: domaine, app: .maillageZigbee)
        #expect(r.valeurs == ["vuePieces3D": .bool(true)])
        #expect(Set(r.nonRepris.keys) == ["SUHasLaunchedBefore", "NSWindow Frame graphe", "reglages.onglet", "dossierNoms",
                                          "motDePasseWifi", "scissionsNotifiees"])
        #expect(r.nonRepris.values.allSatisfy { $0 == .horsContrat })
        #expect(C.reglages(depuis: ["scissionsNotifiees": ["a"]], app: .maillageThread).valeurs
                == ["scissionsNotifiees": .listeTextes(["a"])], "connue de Thread")
        let vide = C.reglages(depuis: [:], app: .maillageThread)
        #expect(vide.valeurs.isEmpty && vide.nonRepris.isEmpty, "sondeLiaison absente : ni valeur ni defaut")
        // Le resultat s'ecrit et se relit egal.
        #expect(try C.lireReglages(C.ecrire(r)) == r)
        // Une cle vide ne peut pas etre citee : elle est ignoree, l'ecriture reste possible.
        #expect(C.reglages(depuis: ["": 1], app: .maillageThread).nonRepris.isEmpty)
    }

    /// Lecture du domaine persistant de l'app, jamais des valeurs globales du Mac : `AppleLanguages` n'est repris que
    /// si l'app l'a ecrit elle-meme. Domaine invente (jamais celui d'une vraie app).
    @Test func reglagesLangueDeLAppEtNonDuMac() throws {
        let nom = "fr.djoko.test.contrat-\(UUID().uuidString)"
        let defauts = try #require(UserDefaults(suiteName: nom))
        defer { defauts.removePersistentDomain(forName: nom) }
        defauts.set(true, forKey: "vuePieces3D")
        defauts.set(1, forKey: "etagesEnGrille")
        defauts.set(7, forKey: "sondePagesTables")
        let sans = C.reglagesPersistants(de: .maillageZigbee, domaine: nom, defauts: defauts)
        #expect(sans.valeurs["AppleLanguages"] == nil, "la langue du Mac n'est pas celle de l'app")
        #expect(sans.nonRepris["AppleLanguages"] == nil)
        #expect(sans.valeurs["vuePieces3D"] == .bool(true))
        #expect(sans.valeurs["sondePagesTables"] == .entier(7))
        #expect(sans.nonRepris["etagesEnGrille"] == .typeInattendu, "un 1 entier n'est pas un booleen")
        #expect(sans.app == .maillageZigbee)
        defauts.set(["fr"], forKey: "AppleLanguages")
        let avec = C.reglagesPersistants(de: .maillageZigbee, domaine: nom, defauts: defauts)
        #expect(avec.valeurs["AppleLanguages"] == .listeTextes(["fr"]), "la langue choisie dans l'app est reprise")
        #expect(C.reglagesPersistants(de: .maillageThread, domaine: nom + ".vide", defauts: defauts).valeurs.isEmpty)
    }

    // MARK: Description d'un fichier en un seul passage

    /// Taille et empreinte viennent des memes octets : un fichier qui grandit pendant la lecture donne une taille et une
    /// empreinte qui se correspondent, toujours un prefixe du fichier (le fichier ne fait qu'avancer).
    @Test func empreinteEtTailleDesMemesOctets() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let url = d.appendingPathComponent("grandit.jsonl")
        try Data(repeating: 0x41, count: 2 * 1024 * 1024).write(to: url)
        let petit = d.appendingPathComponent("petit.json")
        try Data("abc".utf8).write(to: petit)
        let (taille, sha) = try C.empreinte(fichier: petit)
        #expect(taille == 3)
        #expect(sha == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(try C.sha256(fichier: petit) == sha)

        let fini = DispatchSemaphore(value: 0)
        let chunk = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 1) })
        Thread.detachNewThread {
            if let ecrivain = try? FileHandle(forWritingTo: url) {
                _ = try? ecrivain.seekToEnd()
                for _ in 0..<3000 { try? ecrivain.write(contentsOf: chunk) }
                try? ecrivain.close()
            }
            fini.signal()
        }
        var mesures: [(Int64, String)] = []
        var descriptions: [C.Fichier] = []
        for _ in 0..<25 {
            mesures.append(try C.empreinte(fichier: url))
            descriptions.append(try C.Fichier.decrire(chemin: "grandit.jsonl", dans: d))
        }
        fini.wait()
        let final = try Data(contentsOf: url)
        #expect(final.count == 2 * 1024 * 1024 + 3000 * 4096)
        for (t, h) in mesures {
            #expect(t >= 2 * 1024 * 1024 && Int(t) <= final.count)
            #expect(C.sha256(final.prefix(Int(t))) == h, "taille \(t) et empreinte decrivent les memes octets")
        }
        for f in descriptions {
            #expect(C.sha256(final.prefix(Int(f.taille))) == f.sha256, "decrire : taille \(f.taille) coherente")
        }
    }

    // MARK: Verification d'un dossier d'export

    struct Export {
        let dossier: URL
        let manifeste: C.Manifeste
        let reglages: C.Reglages
    }

    /// Un export valide, ecrit sur le disque : des fichiers connus, `reglages.json`, `manifeste.json`. `fichiers` :
    /// chemin -> contenu (inventes).
    static func exportValide(app: C.AppSource = .maillageThread,
                             fichiers: [String: String] = ["surnoms.json": "{}", "Journal/journal-2026-10.jsonl": "ligne\n"],
                             nonRepris: [C.FichierNonRepris]? = nil) throws -> Export {
        let d = try dossier()
        let reglages = C.Reglages(app: app, valeurs: ["vuePieces3D": .bool(true)], nonRepris: ["SUHasLaunchedBefore": .horsContrat])
        var tous = fichiers
        tous["reglages.json"] = texte(try C.ecrire(reglages))
        for (chemin, contenu) in tous {
            let url = try C.resoudre(chemin, dans: d)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(contenu.utf8).write(to: url)
        }
        let decrits = try tous.keys.sorted().map { try C.Fichier.decrire(chemin: $0, dans: d) }
        let m = manifeste(app: app, fichiers: decrits, nonRepris: nonRepris)
        try C.ecrire(m).write(to: d.appendingPathComponent("manifeste.json"))
        return Export(dossier: d, manifeste: m, reglages: reglages)
    }

    /// Reecrit le manifeste du dossier (pour fabriquer un export altere).
    static func remplacerManifeste(_ m: C.Manifeste, dans d: URL) throws {
        try C.ecrire(m).write(to: d.appendingPathComponent("manifeste.json"))
    }

    @Test func dossierValideAccepte() throws {
        for app in C.AppSource.allCases {
            let e = try Self.exportValide(app: app)
            defer { try? FileManager.default.removeItem(at: e.dossier) }
            let (m, r) = try C.verifierDossier(e.dossier)
            #expect(m == e.manifeste)
            #expect(r == e.reglages)
            #expect(m.fichiers.map(\.chemin) == ["Journal/journal-2026-10.jsonl", "reglages.json", "surnoms.json"])
        }
        // Un dossier d'export sans aucun fichier repris : le seul reglages.json suffit.
        let seul = try Self.exportValide(fichiers: [:])
        defer { try? FileManager.default.removeItem(at: seul.dossier) }
        #expect(try C.verifierDossier(seul.dossier).0.fichiers.map(\.chemin) == ["reglages.json"])
    }

    /// Le Finder peut poser un `.DS_Store` dans le dossier : tolere. Tout autre fichier non liste est refuse.
    @Test func dossierAvecDSStoreAccepte() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        try Data("x".utf8).write(to: e.dossier.appendingPathComponent(".DS_Store"))
        try Data("x".utf8).write(to: e.dossier.appendingPathComponent("Journal/.DS_Store"))
        _ = try C.verifierDossier(e.dossier)
    }

    /// Copie sur une cle FAT ou exFAT, macOS pose un compagnon AppleDouble `._<nom>` a cote de chaque fichier : tolere,
    /// comme `.DS_Store`, a toute profondeur. Seuls les noms qui COMMENCENT par `._` le sont ; tout autre fichier non
    /// liste reste refuse.
    @Test func dossierAvecFichiersAppleDoubleAccepte() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        for chemin in ["._manifeste.json", "._reglages.json", "Journal/._journal-2026-10.jsonl", "Thread/._dernier-maillage.json"] {
            let url = e.dossier.appendingPathComponent(chemin)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("x".utf8).write(to: url)
        }
        let (m, _) = try C.verifierDossier(e.dossier)
        #expect(!m.fichiers.contains { $0.chemin.contains("._") })
    }

    @Test func dossierAvecFauxAppleDoubleRefuse() throws {
        for chemin in ["_x.json", "x._json", "Journal/_x.json", "Journal/x._jsonl", ".x.json"] {
            let e = try Self.exportValide()
            defer { try? FileManager.default.removeItem(at: e.dossier) }
            try Data("x".utf8).write(to: e.dossier.appendingPathComponent(chemin))
            #expect(throws: C.Erreur.fichierEnTrop(chemin)) { try C.verifierDossier(e.dossier) }
        }
    }

    @Test func dossierSansManifeste() throws {
        let d = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        #expect(throws: C.Erreur.manifesteAbsent) { try C.verifierDossier(d) }
        #expect(throws: C.Erreur.manifesteAbsent) { try C.verifierDossier(d.appendingPathComponent("absent")) }
    }

    /// Un manifeste illisible, d'un autre format ou d'une app inconnue donne l'erreur du contrat, rien de plus vague.
    @Test func dossierManifesteRefuse() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let cible = e.dossier.appendingPathComponent("manifeste.json")
        let bon = Self.texte(try Data(contentsOf: cible))
        func essayer(_ json: String) -> (any Error)? {
            try? Data(json.utf8).write(to: cible)
            do { _ = try C.verifierDossier(e.dossier); return nil } catch { return error }
        }
        #expect(Self.causeIllisible(essayer("pas du JSON") ?? C.Erreur.manifesteAbsent) == "JSON invalide")
        #expect(essayer(bon.replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2")) as? C.Erreur == .formatInconnu(2))
        #expect(essayer(bon.replacingOccurrences(of: "\"app\" : \"thread\"", with: "\"app\" : \"matter\"")) as? C.Erreur
                == .appInconnue("matter"))
        #expect(essayer(bon.replacingOccurrences(of: "\"surnoms.json\"", with: "\"../surnoms.json\"")) as? C.Erreur
                == .cheminInvalide("../surnoms.json"))
    }

    @Test func dossierSansReglagesListes() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let sans = e.manifeste.fichiers.filter { $0.chemin != "reglages.json" }
        try Self.remplacerManifeste(Self.manifeste(fichiers: sans), dans: e.dossier)
        #expect(throws: C.Erreur.reglagesAbsents) { try C.verifierDossier(e.dossier) }
    }

    @Test func dossierFichierManquant() throws {
        for manquant in ["surnoms.json", "Journal/journal-2026-10.jsonl", "reglages.json"] {
            let e = try Self.exportValide()
            defer { try? FileManager.default.removeItem(at: e.dossier) }
            try FileManager.default.removeItem(at: e.dossier.appendingPathComponent(manquant))
            #expect(throws: C.Erreur.fichierManquant(manquant)) { try C.verifierDossier(e.dossier) }
        }
    }

    @Test func dossierFichierEnTrop() throws {
        for (chemin, dossierIntermediaire) in [("autre.json", false), ("Journal/autre.jsonl", true), ("Neuf/profond/x.bin", true)] {
            let e = try Self.exportValide()
            defer { try? FileManager.default.removeItem(at: e.dossier) }
            let url = e.dossier.appendingPathComponent(chemin)
            if dossierIntermediaire {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            }
            try Data("x".utf8).write(to: url)
            #expect(throws: C.Erreur.fichierEnTrop(chemin)) { try C.verifierDossier(e.dossier) }
        }
        // Un fichier mis de cote par l'app (illisible) n'est pas copie : s'il est la, il est en trop.
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        try Data("x".utf8).write(to: e.dossier.appendingPathComponent("noms.illisible-1.json"))
        #expect(throws: C.Erreur.fichierEnTrop("noms.illisible-1.json")) { try C.verifierDossier(e.dossier) }
    }

    @Test func dossierFichierInconnuDeLApp() throws {
        // associations.json est a Thread seulement ; autre.txt n'est a personne.
        for (app, chemin) in [(C.AppSource.maillageZigbee, "associations.json"), (.maillageThread, "autre.txt"),
                              (.maillageThread, "Thread/surnoms.json"), (.maillageThread, "maillage-2026-13.jsonl")] {
            let e = try Self.exportValide(app: app, fichiers: [chemin: "{}"])
            defer { try? FileManager.default.removeItem(at: e.dossier) }
            #expect(throws: C.Erreur.fichierInconnu(chemin)) { try C.verifierDossier(e.dossier) }
        }
    }

    @Test func dossierTailleOuEmpreinteFausse() throws {
        // Taille fausse : le manifeste annonce un octet de plus.
        let t = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: t.dossier) }
        let faux = t.manifeste.fichiers.map {
            $0.chemin == "surnoms.json" ? C.Fichier(chemin: $0.chemin, taille: $0.taille + 1, sha256: $0.sha256) : $0
        }
        try Self.remplacerManifeste(Self.manifeste(fichiers: faux), dans: t.dossier)
        #expect(throws: C.Erreur.tailleFausse("surnoms.json")) { try C.verifierDossier(t.dossier) }
        // Empreinte fausse : meme taille, contenu change apres le manifeste.
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        try Data("[]".utf8).write(to: e.dossier.appendingPathComponent("surnoms.json"))
        #expect(throws: C.Erreur.empreinteFausse("surnoms.json")) { try C.verifierDossier(e.dossier) }
        // Contenu plus court : la taille est refusee d'abord.
        try Data("{".utf8).write(to: e.dossier.appendingPathComponent("surnoms.json"))
        #expect(throws: C.Erreur.tailleFausse("surnoms.json")) { try C.verifierDossier(e.dossier) }
    }

    /// `reglages.json` est dans le manifeste comme les autres : un octet change, meme taille, est refuse par l'empreinte.
    @Test func dossierReglagesEmpreinteFausse() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let url = e.dossier.appendingPathComponent("reglages.json")
        let original = Self.texte(try Data(contentsOf: url))
        // Une seule lettre de la cle change : meme taille, JSON toujours lisible. Seule l'empreinte voit le changement.
        let altere = original.replacingOccurrences(of: "vuePieces3D", with: "vuePieces3E")
        #expect(altere != original && altere.utf8.count == original.utf8.count)
        try Data(altere.utf8).write(to: url)
        #expect(throws: C.Erreur.empreinteFausse("reglages.json")) { try C.verifierDossier(e.dossier) }
    }

    /// `reglages.json` grandit ou retrecit d'un octet : refuse par la taille, avant l'empreinte.
    @Test func dossierReglagesTailleFausse() throws {
        // Un octet de plus (espace en fin, JSON toujours valide).
        let plus = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: plus.dossier) }
        let urlPlus = plus.dossier.appendingPathComponent("reglages.json")
        let octetsPlus = try Data(contentsOf: urlPlus) + Data(" ".utf8)
        try octetsPlus.write(to: urlPlus)
        #expect(throws: C.Erreur.tailleFausse("reglages.json")) { try C.verifierDossier(plus.dossier) }
        // Un octet de moins.
        let moins = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: moins.dossier) }
        let urlMoins = moins.dossier.appendingPathComponent("reglages.json")
        let octetsMoins = Data(try Data(contentsOf: urlMoins).dropLast())
        try octetsMoins.write(to: urlMoins)
        #expect(throws: C.Erreur.tailleFausse("reglages.json")) { try C.verifierDossier(moins.dossier) }
    }

    @Test func dossierReglagesIncoherents() throws {
        // Reglages d'une autre app que le manifeste (empreinte juste : le fichier est bien celui annonce).
        let e = try Self.exportValide(app: .maillageThread)
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let autres = try C.ecrire(C.Reglages(app: .maillageZigbee, valeurs: [:], nonRepris: [:]))
        try autres.write(to: e.dossier.appendingPathComponent("reglages.json"))
        let decrits = try e.manifeste.fichiers.map { try C.Fichier.decrire(chemin: $0.chemin, dans: e.dossier) }
        try Self.remplacerManifeste(Self.manifeste(app: .maillageThread, fichiers: decrits), dans: e.dossier)
        #expect(throws: C.Erreur.appDifferente) { try C.verifierDossier(e.dossier) }
        // reglages.json illisible, mais annonce correctement.
        try Data("pas du json".utf8).write(to: e.dossier.appendingPathComponent("reglages.json"))
        let decrits2 = try e.manifeste.fichiers.map { try C.Fichier.decrire(chemin: $0.chemin, dans: e.dossier) }
        try Self.remplacerManifeste(Self.manifeste(app: .maillageThread, fichiers: decrits2), dans: e.dossier)
        #expect(throws: C.Erreur.illisible("JSON invalide")) { try C.verifierDossier(e.dossier) }
    }

    @Test func dossierLienSymbolique() throws {
        let dehors = try Self.dossier()
        defer { try? FileManager.default.removeItem(at: dehors) }
        try Data("{}".utf8).write(to: dehors.appendingPathComponent("secret.json"))
        // Fichier liste remplace par un lien.
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let cible = e.dossier.appendingPathComponent("surnoms.json")
        try FileManager.default.removeItem(at: cible)
        try FileManager.default.createSymbolicLink(at: cible, withDestinationURL: dehors.appendingPathComponent("secret.json"))
        #expect(throws: C.Erreur.lienSymbolique("surnoms.json")) { try C.verifierDossier(e.dossier) }
        // Lien en plus, vers un dossier ou un fichier.
        let f = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: f.dossier) }
        try FileManager.default.createSymbolicLink(at: f.dossier.appendingPathComponent("Voisin"), withDestinationURL: dehors)
        #expect(throws: C.Erreur.lienSymbolique("Voisin")) { try C.verifierDossier(f.dossier) }
    }

    /// Le fichier de reglages est lu une seule fois : ce qui est verifie est ce qui est decode.
    @Test func dossierReglagesLusUneFois() throws {
        let e = try Self.exportValide()
        defer { try? FileManager.default.removeItem(at: e.dossier) }
        let (_, r) = try C.verifierDossier(e.dossier)
        #expect(r.valeurs["vuePieces3D"] == .bool(true))
        #expect(r.nonRepris["SUHasLaunchedBefore"] == .horsContrat)
    }

    // MARK: Cas du manifeste relus (relecture de la tache 1)

    /// Deux chemins qui ne different que par la normalisation Unicode sont le meme fichier pour le Mac.
    @Test func cheminsNFCEtNFD() {
        let nfc = "caf\u{E9}.json", nfd = "cafe\u{301}.json"
        #expect(nfc.unicodeScalars.count != nfd.unicodeScalars.count, "deux suites d'octets differentes")
        let m = Self.manifeste(fichiers: [C.Fichier(chemin: nfc, taille: 1, sha256: Self.sha),
                                          C.Fichier(chemin: nfd, taille: 1, sha256: Self.sha)])
        #expect(throws: C.Erreur.cheminEnDouble(nfd)) { try C.ecrire(m) }
    }

    /// Seul le manifeste de la racine est reserve ; un `manifeste.json` dans un dossier est un chemin comme un autre
    /// (la verification d'un dossier le refuse comme fichier inconnu).
    @Test func nomReserveSeulementALaRacine() throws {
        let m = Self.manifeste(fichiers: [C.Fichier(chemin: "Journal/manifeste.json", taille: 1, sha256: Self.sha)])
        #expect(try C.lireManifeste(C.ecrire(m)) == m)
        #expect(!C.estConnu("Journal/manifeste.json", de: .maillageThread))
    }

    /// Un champ ajoute au manifeste par une version future du format 1 est ignore (lecture tolerante) ; la regle est
    /// ecrite dans le contrat.
    @Test func champInconnuTolere() throws {
        let m = Self.manifeste()
        let bon = Self.texte(try C.ecrire(m))
        let plus = bon.replacingOccurrences(of: "\"format\" : 1,", with: "\"format\" : 1,\n  \"ajoute\" : true,")
        #expect(try C.lireManifeste(Data(plus.utf8)) == m)
    }
}
