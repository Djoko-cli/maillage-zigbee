import Foundation
import Testing
@testable import MaillageCoeur

/// L'assemblage du dossier d'export pour Maillage IoT (`ExportReprise`), sur des dossiers temporaires : ce qui est
/// copie, ce qui est cite sans l'etre, les reglages repris et non repris, la relecture, et le fait que l'app n'est
/// jamais modifiee. Les valeurs sont inventees.
@Suite("Export pour Maillage IoT : assemblage du dossier")
struct ExportRepriseTests {
    /// Un dossier temporaire neuf, supprime a la fin de `corps`.
    static func avecDossier<T>(_ corps: (URL) throws -> T) throws -> T {
        let racine = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-reprise-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: racine, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: racine) }
        return try corps(racine)
    }

    static func ecrire(_ texte: String, _ chemin: String, dans dossier: URL) throws {
        let url = dossier.appendingPathComponent(chemin)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(texte.utf8).write(to: url)
    }

    /// Une app inventee : trois fichiers connus, un journal et un historique, plus de quoi ne pas etre repris.
    static func fabriquerSource(_ source: URL) throws {
        try ecrire("{\"0000000000000001\":\"Lampe\"}\n", "surnoms.json", dans: source)
        try ecrire("{\"version\":1}\n", "pieces-routeurs.json", dans: source)
        try ecrire("{\"version\":1,\"maisons\":{}}\n", "positions-pieces.json", dans: source)
        try ecrire("{\"date\":\"2026-10-01T10:00:00.000Z\"}\n{\"date\":\"2026-10-01T10:15:00.000Z\"}\n",
                   "maillage-2026-10.jsonl", dans: source)
        // Plus de 90 jours : l'export le reprend (c'est l'import qui l'ecarte).
        try ecrire("{\"date\":\"2026-05-01T10:00:00.000Z\"}\n", "maillage-2026-05.jsonl", dans: source)
        try ecrire("{\"type\":\"veille\"}\n", "Journal/journal-2026-10.jsonl", dans: source)
        // Non repris.
        try ecrire("x", ".DS_Store", dans: source)
        try ecrire("{}", "surnoms.illisible-20261001-120000.json", dans: source)
        try ecrire("ancien", "ancien-reglage.txt", dans: source)
        try ecrire("{}", "Divers/autre.json", dans: source)
    }

    static let reglagesVides = ContratExport.Reglages(app: .maillageZigbee, valeurs: [:], nonRepris: [:])

    static func exporter(source: URL, destination: URL, temporaire: URL? = nil,
                         reglages: ContratExport.Reglages = reglagesVides,
                         avantRelecture: (URL) throws -> Void = { _ in },
                         apresDeplacement: (URL) throws -> Void = { _ in }) throws -> ExportReprise.Resultat {
        try ExportReprise.exporter(depuis: source, app: .maillageZigbee, versionApp: "1.2.0", reglages: reglages,
                                   vers: destination, identifiant: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!,
                                   date: Date(timeIntervalSince1970: 1_792_000_000.75),
                                   temporaire: temporaire ?? destination.deletingLastPathComponent(),
                                   avantRelecture: avantRelecture, apresDeplacement: apresDeplacement)
    }

    /// Les fichiers (chemin relatif -> octets) sous un dossier.
    static func contenu(_ dossier: URL) throws -> [String: Data] {
        var resultat: [String: Data] = [:]
        guard let liste = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.isRegularFileKey])
        else { return resultat }
        let racine = dossier.resolvingSymlinksInPath().path + "/"
        for case let url as URL in liste where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            resultat[String(url.resolvingSymlinksInPath().path.dropFirst(racine.count))] = try Data(contentsOf: url)
        }
        return resultat
    }

    // MARK: Le dossier

    @Test func ledossierCopieLesFichiersConnusEtSeRelit() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), sortie = tmp.appendingPathComponent("sortie")
            try FileManager.default.createDirectory(at: sortie, withIntermediateDirectories: true)
            try Self.fabriquerSource(source)
            let export = sortie.appendingPathComponent("Export")
            let r = try Self.exporter(source: source, destination: export)

            let (manifeste, reglages) = try ContratExport.verifierDossier(export)
            #expect(manifeste == r.manifeste)
            #expect(reglages == r.reglages)
            #expect(manifeste.app == .maillageZigbee)
            #expect(manifeste.versionApp == "1.2.0")
            #expect(manifeste.identifiant == UUID(uuidString: "00000000-0000-0000-0000-00000000000A"))
            // A la seconde, comme le contrat l'ecrit.
            #expect(manifeste.date == Date(timeIntervalSince1970: 1_792_000_000))
            #expect(manifeste.fichiers.map(\.chemin) == [
                "Journal/journal-2026-10.jsonl", "maillage-2026-05.jsonl", "maillage-2026-10.jsonl",
                "pieces-routeurs.json", "positions-pieces.json", "surnoms.json", "reglages.json",
            ])
            // Copie a l'octet : l'historique de plus de 90 jours y est.
            for chemin in ["Journal/journal-2026-10.jsonl", "maillage-2026-05.jsonl", "maillage-2026-10.jsonl",
                           "pieces-routeurs.json", "positions-pieces.json", "surnoms.json"] {
                #expect(try Data(contentsOf: export.appendingPathComponent(chemin))
                        == Data(contentsOf: source.appendingPathComponent(chemin)), "\(chemin)")
            }
        }
    }

    @Test func lesFichiersNonReprisSontCites() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            let r = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"))
            #expect(r.manifeste.fichiersNonRepris == [
                .init(chemin: ".DS_Store", raison: .exclu),
                .init(chemin: "Divers/autre.json", raison: .horsContrat),
                .init(chemin: "ancien-reglage.txt", raison: .horsContrat),
                .init(chemin: "surnoms.illisible-20261001-120000.json", raison: .exclu),
            ])
            // Rien de tout cela n'est copie.
            let present = try Self.contenu(tmp.appendingPathComponent("Export")).keys
            #expect(!present.contains(".DS_Store"))
            #expect(!present.contains("ancien-reglage.txt"))
            #expect(!present.contains("Divers/autre.json"))
        }
    }

    @Test func lesNomsReservesDeLAppNeSontPasCopies() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.ecrire("{\"a\":1}", "manifeste.json", dans: source)
            try Self.ecrire("{\"a\":1}", "reglages.json", dans: source)
            let r = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"))
            // Ces noms sont ceux de l'export : le manifeste ne peut pas les citer (`nomReserve`).
            #expect(r.manifeste.fichiersNonRepris.isEmpty)
            #expect(r.manifeste.fichiers.map(\.chemin) == ["reglages.json"])
            // Le reglages.json de l'export est celui de l'export, pas celui de l'app.
            #expect(try ContratExport.lireReglages(Data(contentsOf: tmp.appendingPathComponent("Export/reglages.json")))
                    == Self.reglagesVides)
        }
    }

    @Test func unLienSymboliqueDeLAppNEstPasSuivi() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.ecrire("secret", "../hors-source.txt", dans: source)
            try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("surnoms.json"),
                                                       withDestinationURL: tmp.appendingPathComponent("hors-source.txt"))
            let r = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"))
            #expect(r.manifeste.fichiers.map(\.chemin) == ["reglages.json"])
            #expect(r.manifeste.fichiersNonRepris == [.init(chemin: "surnoms.json", raison: .horsContrat)])
        }
    }

    @Test func sansDossierDeDonneesIlNYAQueLesReglages() throws {
        try Self.avecDossier { tmp in
            let r = try Self.exporter(source: tmp.appendingPathComponent("absent"),
                                      destination: tmp.appendingPathComponent("Export"))
            #expect(r.manifeste.fichiers.map(\.chemin) == ["reglages.json"])
            #expect(r.manifeste.fichiersNonRepris.isEmpty)
            _ = try ContratExport.verifierDossier(tmp.appendingPathComponent("Export"))
        }
    }

    @Test func lExportNeModifieRienDansLApp() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            let avant = try Self.contenu(source)
            let dates = try Self.dates(source)
            _ = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"))
            #expect(try Self.contenu(source) == avant)
            #expect(try Self.dates(source) == dates)
        }
    }

    static func dates(_ dossier: URL) throws -> [String: Date] {
        var d: [String: Date] = [:]
        for case let url as URL in FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey])! {
            d[url.lastPathComponent] = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }
        return d
    }

    // MARK: Emplacement

    @Test func ecritDansLeDossierTemporaireAvantDeDeplacer() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), brouillon = tmp.appendingPathComponent("brouillon")
            try Self.fabriquerSource(source)
            try FileManager.default.createDirectory(at: brouillon, withIntermediateDirectories: true)
            let export = tmp.appendingPathComponent("Export")
            var vuAvantDeplacement = false
            _ = try Self.exporter(source: source, destination: export, temporaire: brouillon) { dossier in
                // A la relecture, le dossier est dans le brouillon et la destination n'existe pas encore.
                vuAvantDeplacement = dossier.path.hasPrefix(brouillon.path)
                    && !FileManager.default.fileExists(atPath: export.path)
            }
            #expect(vuAvantDeplacement)
            // Le brouillon est vide a la fin.
            #expect(try FileManager.default.contentsOfDirectory(atPath: brouillon.path).isEmpty)
            #expect(FileManager.default.fileExists(atPath: export.appendingPathComponent("manifeste.json").path))
        }
    }

    @Test func remplaceUnDossierExistantQueLUtilisateurAConfirme() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), export = tmp.appendingPathComponent("Export")
            try Self.fabriquerSource(source)
            try Self.ecrire("vieux", "reste-d-un-ancien-export.txt", dans: export)
            _ = try Self.exporter(source: source, destination: export)
            #expect(!FileManager.default.fileExists(atPath: export.appendingPathComponent("reste-d-un-ancien-export.txt").path))
            _ = try ContratExport.verifierDossier(export)
        }
    }

    @Test func refuseUneDestinationDansLesDonneesDeLApp() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            let avant = try Self.contenu(source)
            #expect(throws: ExportReprise.Erreur.destinationDansLesDonnees) {
                try Self.exporter(source: source, destination: source.appendingPathComponent("Export"),
                                  temporaire: tmp)
            }
            #expect(try Self.contenu(source) == avant)
        }
    }

    /// Un dossier qui CONTIENT les donnees de l'app serait remplace avec elles : refuse comme un dossier qui y est.
    @Test func refuseUneDestinationQuiContientLesDonneesDeLApp() throws {
        try Self.avecDossier { tmp in
            let parent = tmp.appendingPathComponent("Application Support")
            let source = parent.appendingPathComponent("Maillage Zigbee")
            try Self.fabriquerSource(source)
            let avant = try Self.contenu(source)
            #expect(throws: ExportReprise.Erreur.destinationDansLesDonnees) {
                try Self.exporter(source: source, destination: parent, temporaire: tmp)
            }
            // Le parent du parent, et le dossier de donnees lui-meme.
            #expect(throws: ExportReprise.Erreur.destinationDansLesDonnees) {
                try Self.exporter(source: source, destination: tmp, temporaire: tmp)
            }
            #expect(throws: ExportReprise.Erreur.destinationDansLesDonnees) {
                try Self.exporter(source: source, destination: source, temporaire: tmp)
            }
            #expect(try Self.contenu(source) == avant)
        }
    }

    /// Une erreur du contrat levee pendant l'assemblage (ici un nom de fichier invalide dans le dossier de l'app) est
    /// celle de l'assemblage, avec le chemin : l'app peut la dire en mots. Rien n'est ecrit.
    @Test func uneErreurDuContratPendantLAssemblageEstNommee() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), brouillon = tmp.appendingPathComponent("brouillon")
            try Self.fabriquerSource(source)
            let nom = "parasite\u{01}.json"
            try Self.ecrire("x", nom, dans: source)
            try FileManager.default.createDirectory(at: brouillon, withIntermediateDirectories: true)
            let export = tmp.appendingPathComponent("Export")
            #expect(throws: ExportReprise.Erreur.assemblage(.cheminInvalide(nom))) {
                try Self.exporter(source: source, destination: export, temporaire: brouillon)
            }
            #expect(!FileManager.default.fileExists(atPath: export.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: brouillon.path).isEmpty)
        }
    }

    // MARK: Relecture

    @Test func uneRelectureQuiEchouePasseLaDestinationEtNettoieLeBrouillon() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), brouillon = tmp.appendingPathComponent("brouillon")
            try Self.fabriquerSource(source)
            try FileManager.default.createDirectory(at: brouillon, withIntermediateDirectories: true)
            let export = tmp.appendingPathComponent("Export")
            #expect(throws: ExportReprise.Erreur.relecture(.tailleFausse("surnoms.json"))) {
                try Self.exporter(source: source, destination: export, temporaire: brouillon) { dossier in
                    // Un octet change entre l'ecriture et la relecture.
                    try Data("{}".utf8).write(to: dossier.appendingPathComponent("surnoms.json"))
                }
            }
            #expect(!FileManager.default.fileExists(atPath: export.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: brouillon.path).isEmpty)
        }
    }

    @Test func uneRelectureQuiEchoueLaisseIntactLAncienExport() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), export = tmp.appendingPathComponent("Export")
            try Self.fabriquerSource(source)
            try Self.ecrire("ancien", "ancien.txt", dans: export)
            #expect(throws: ExportReprise.Erreur.self) {
                try Self.exporter(source: source, destination: export) { dossier in
                    try FileManager.default.removeItem(at: dossier.appendingPathComponent("surnoms.json"))
                }
            }
            #expect(try Self.contenu(export) == ["ancien.txt": Data("ancien".utf8)])
        }
    }

    /// La relecture FINALE (sur la destination) echoue alors qu'un export existait : l'ancien dossier est remis tel quel,
    /// la destination ne garde rien du nouveau, et rien ne traine dans le dossier temporaire.
    @Test func uneRelectureFinaleQuiEchoueRemetLAncienExport() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), export = tmp.appendingPathComponent("Export")
            let brouillon = tmp.appendingPathComponent("brouillon")
            try Self.fabriquerSource(source)
            try Self.ecrire("ancien", "ancien.txt", dans: export)
            try Self.ecrire("autre", "Dossier/autre.txt", dans: export)
            try FileManager.default.createDirectory(at: brouillon, withIntermediateDirectories: true)
            let avant = try Self.contenu(export)
            #expect(throws: ExportReprise.Erreur.relecture(.fichierManquant("surnoms.json"))) {
                try Self.exporter(source: source, destination: export, temporaire: brouillon, apresDeplacement: { dossier in
                    // Le dossier est a sa destination, abime apres coup.
                    try FileManager.default.removeItem(at: dossier.appendingPathComponent("surnoms.json"))
                })
            }
            #expect(try Self.contenu(export) == avant)
            #expect(try FileManager.default.contentsOfDirectory(atPath: brouillon.path).isEmpty)
        }
    }

    /// Sans ancien dossier, une relecture finale ratee ne laisse rien a la destination.
    @Test func uneRelectureFinaleQuiEchoueSansAncienNeLaisseRien() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source"), export = tmp.appendingPathComponent("Export")
            try Self.fabriquerSource(source)
            #expect(throws: ExportReprise.Erreur.self) {
                try Self.exporter(source: source, destination: export, apresDeplacement: { dossier in
                    try FileManager.default.removeItem(at: dossier.appendingPathComponent("surnoms.json"))
                })
            }
            #expect(!FileManager.default.fileExists(atPath: export.path))
        }
    }

    // MARK: Reglages

    @Test func lesReglagesReprisEtLesAutresVontDansReglagesJson() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            let domaine: [String: Any] = [
                "sondeNom": "SONDE-Z1", "sondeJournalPages": [1_792_237_800.0, 12.0, 1_792_238_000.0, 15.0], "sondePagesTables": 4,
                "pont.hue": Data("{\"adresse\":\"192.0.2.10\"}".utf8), "voisinsALaSelection": true,
                "AppleLanguages": ["fr"],
                // Non repris : Sparkle, fenetre, onglet, ancien signet.
                "SUHasLaunchedBefore": true, "NSWindow Frame graphe": "0 0 10 10", "reglages.onglet": "pont",
                "dossierNoms": Data([1, 2]),
                // Type inattendu : un entier pour un booleen.
                "vuePieces3D": 1,
            ]
            let reglages = ContratExport.reglages(depuis: domaine, app: .maillageZigbee)
            let r = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"), reglages: reglages)
            let relus = try ContratExport.lireReglages(Data(contentsOf: tmp.appendingPathComponent("Export/reglages.json")))
            #expect(relus == r.reglages)
            #expect(relus.valeurs["sondeNom"] == .texte("SONDE-Z1"))
            // Le journal des pages est transitoire : cite, jamais repris.
            #expect(relus.valeurs["sondeJournalPages"] == nil)
            #expect(relus.valeurs["sondePagesTables"] == .entier(4))
            #expect(relus.valeurs["pont.hue"] == .donnees(Data("{\"adresse\":\"192.0.2.10\"}".utf8)))
            #expect(relus.valeurs["voisinsALaSelection"] == .bool(true))
            #expect(relus.valeurs["AppleLanguages"] == .listeTextes(["fr"]))
            #expect(relus.nonRepris == [
                "SUHasLaunchedBefore": .horsContrat, "NSWindow Frame graphe": .horsContrat,
                "reglages.onglet": .horsContrat, "dossierNoms": .horsContrat, "vuePieces3D": .typeInattendu,
                "sondeJournalPages": .transitoire,
            ])
            // Une cle absente de l'app reste absente : aucun defaut.
            #expect(relus.valeurs["legendeRepliee"] == nil)
            #expect(relus.valeurs["sondeChemin"] == nil)
        }
    }

    @Test func leJournalDesPagesEstTransitoireQuelQueSoitSonType() throws {
        for brut: Any in [[1_792_237_800.0, 12.0], [1, 2, 3], "texte", true, 7, Data([1])] {
            let r = ContratExport.reglages(depuis: ["sondeJournalPages": brut, "sondePagesTables": 4], app: .maillageZigbee)
            #expect(r.nonRepris == ["sondeJournalPages": .transitoire])
            #expect(r.valeurs == ["sondePagesTables": .entier(4)])
        }
        // Maillage Thread n'a pas de reglage transitoire.
        #expect(ContratExport.transitoires(de: .maillageThread).isEmpty)
    }

    @Test func lesReglagesViennentDuDomaineDeLAppEtPasDesReglagesGlobaux() throws {
        let nom = "fr.djoko.maillage.zigbee.tests.export-" + UUID().uuidString
        let defauts = UserDefaults.standard
        defauts.setPersistentDomain(["sondeNom": "SONDE-Z1", "SUHasLaunchedBefore": true], forName: nom)
        defer { defauts.removePersistentDomain(forName: nom) }
        let r = ContratExport.reglagesPersistants(de: .maillageZigbee, domaine: nom, defauts: defauts)
        #expect(r.valeurs == ["sondeNom": .texte("SONDE-Z1")])
        #expect(r.nonRepris == ["SUHasLaunchedBefore": .horsContrat])
        // Les langues du Mac (domaine global) ne sont jamais lues comme un choix de l'app.
        #expect(r.valeurs["AppleLanguages"] == nil)
    }

    @Test func aucunSecretDuTrousseauNiMotDePasseWifiNEntre() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            // Meme si un domaine portait de tels noms, rien d'autre que l'inventaire n'est repris.
            let domaine: [String: Any] = ["cleDuPont": "SECRET", "motDePasseWifi": "SECRET", "sondeNomWifi": "RESEAU-1"]
            let r = try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"),
                                      reglages: ContratExport.reglages(depuis: domaine, app: .maillageZigbee))
            #expect(Set(r.reglages.valeurs.keys) == ["sondeNomWifi"])
            #expect(r.reglages.nonRepris == ["cleDuPont": .horsContrat, "motDePasseWifi": .horsContrat])
            let tout = try Self.contenu(tmp.appendingPathComponent("Export"))
            #expect(tout.values.allSatisfy { String(decoding: $0, as: UTF8.self).contains("SECRET") == false })
        }
    }

    @Test func refuseDesReglagesDUneAutreApp() throws {
        try Self.avecDossier { tmp in
            let source = tmp.appendingPathComponent("source")
            try Self.fabriquerSource(source)
            let autre = ContratExport.Reglages(app: .maillageThread, valeurs: [:], nonRepris: [:])
            #expect(throws: ExportReprise.Erreur.relecture(.appDifferente)) {
                try Self.exporter(source: source, destination: tmp.appendingPathComponent("Export"), reglages: autre)
            }
        }
    }
}
