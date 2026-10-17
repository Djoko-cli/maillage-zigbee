import Foundation
import Testing
@testable import MaillageCoeur

/// L'export d'exemple anonymise de Maillage Zigbee 1.2.0 (`docs/export-exemple/`), que la session de fusion recopie
/// dans les tests de Maillage IoT : le format ecrit et le format lu ne peuvent pas diverger sans qu'un test casse.
///
/// Tout est invente, cles comprises (`0000000000000001`, `SONDE-Z1`, « Piece 1 »). Il porte un exemplaire de chaque
/// fichier et de chaque reglage de l'inventaire de Maillage Zigbee, plus des historiques de plus de 90 jours, et des
/// fichiers et reglages non repris. Il est ecrit par `ExportReprise` lui-meme, avec une date et un identifiant fixes :
/// deux ecritures donnent les memes octets.
///
/// Ces tests lisent le depot mais ne l'ecrivent pas (le dossier est copie a la main) : `docs/export-exemple/` absent ou
/// different, le test ecrit l'export dans son dossier temporaire, dit ou, et echoue ; le copier, le controler
/// (controle d'anonymisation), puis relancer.
@Suite("Export d'exemple : docs/export-exemple")
struct ExportExempleTests {
    static let dossierDepot = Catalogues.racine.appendingPathComponent("docs/export-exemple")
    /// Ou le test ecrit l'export qu'il construit (`TMPDIR` du lanceur de tests).
    static var dossierEcrit: URL { FileManager.default.temporaryDirectory.appendingPathComponent("export-exemple") }

    static let identifiant = UUID(uuidString: "5E0F0000-0000-4000-8000-00000000A001")!
    static let date = Date(timeIntervalSince1970: 1_792_238_400)  // 2026-10-17T12:00:00Z

    // Les noeuds inventes.
    static let pont = "0000000000000001", routeur1 = "0000000000000002", routeur2 = "0000000000000003"
    static let final1 = "0000000000000004", final2 = "0000000000000005", sonde = "0000000000000011"

    // MARK: Les fichiers de l'app (valeurs inventees)

    static func calendrier() -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    static func jour(_ mois: Int, _ jour: Int, _ heure: Int = 10, _ minute: Int = 0) -> Date {
        calendrier().date(from: DateComponents(year: 2026, month: mois, day: jour, hour: heure, minute: minute))!
    }

    static func maillage(_ d: Date, lqi: Int) -> MaillageZigbee {
        MaillageZigbee(
            date: d,
            noeuds: [NoeudZigbee(ieee: pont, court: 0, type: .coordinateur),
                     NoeudZigbee(ieee: routeur1, court: 0x0A01, type: .routeur),
                     NoeudZigbee(ieee: routeur2, court: 0x0A02, type: .routeur),
                     NoeudZigbee(ieee: final1, court: 0x0B01, type: .final, ecoute: true),
                     NoeudZigbee(ieee: final2, court: 0x0B02, type: .final, ecoute: false),
                     NoeudZigbee(ieee: sonde, court: 0x0B03, type: .final, ecoute: true)],
            liens: [LienRadio(a: pont, b: routeur1, lqiA: lqi, lqiB: lqi - 5),
                    LienRadio(a: routeur1, b: routeur2, lqiA: lqi - 20, lqiB: nil)],
            parents: [LienParent(enfant: final1, parent: routeur1, lqi: lqi),
                      LienParent(enfant: final2, parent: routeur2, lqi: lqi - 40),
                      LienParent(enfant: sonde, parent: routeur1, lqi: lqi - 10)],
            routesPont: [RouteZigbee(destination: 0x0A01, prochain: 0x0A01, etat: "active"),
                         RouteZigbee(destination: 0x0A02, prochain: 0x0A01, etat: "active")],
            sonde: sonde, signaux: [SignalSonde(ieee: routeur1, lqi: lqi - 10)],
            chemins: [CheminPont(routeur: routeur1, prochain: pont),
                      CheminPont(routeur: routeur2, prochain: routeur1, suppose: true)],
            dateTables: d)
    }

    /// `dernier-maillage.json` : le maillage garde (`Surveillance.MaillageGarde`).
    struct MaillageGarde: Codable {
        var maillage: MaillageZigbee
        var recu: Date
        var incomplet: Bool
    }

    static func ecrireApp(dans dossier: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: dossier, withIntermediateDirectories: true)
        func fichier(_ nom: String) -> URL { dossier.appendingPathComponent(nom) }

        try Surnoms.ecrire([routeur1: "Lampe A", final1: "Capteur B"], dans: fichier("surnoms.json"))
        let actuel = jour(10, 17, 11, 45)
        try CodageJSON.encodeur().encode(MaillageGarde(maillage: maillage(actuel, lqi: 200), recu: actuel, incomplet: false))
            .write(to: fichier("dernier-maillage.json"))
        try MemoireAppariements(ids: [routeur1: "00000000-0000-4000-8000-0000000000C1",
                                      final1: "00000000-0000-4000-8000-0000000000C2"])
            .ecrire(dans: fichier("appariements-maison.json"))
        let accessoires = [
            AccessoireMaison(nom: "Lampe A", piece: "Pièce 1", fabricant: "Fabricant 1", modele: "Modèle 1",
                             firmware: "1.0.0", categorie: "light", ieee: routeur1, connexion: .connecte,
                             idModele: "MOD001", origine: .maison, idHue: "00000000-0000-4000-8000-0000000000B1",
                             idMaison: "00000000-0000-4000-8000-0000000000C1"),
            AccessoireMaison(nom: "Capteur B", piece: "Pièce 2", fabricant: "Fabricant 1", modele: "Modèle 2",
                             firmware: "1.0.0", categorie: "sensor", ieee: final1,
                             batterie: BatterieMaison(niveau: 80, charge: .nonRechargeable), connexion: .connecte,
                             origine: .pont, idHue: "00000000-0000-4000-8000-0000000000B2"),
        ]
        try NomsMaison(date: actuel, domicile: "Maison 1", accessoires: accessoires,
                       zones: [ZoneMaison(nom: "Étage 1", pieces: ["Pièce 1", "Pièce 2"])],
                       reseau: ReseauZigbee(canal: 15, epid: "0000000000000099")).donnees()
            .write(to: fichier("noms-pont.json"))
        try ReleveMaison(date: actuel, domicile: "Maison 1",
                         accessoires: [AccessoireReleve(nom: "Lampe A", piece: "Pièce 1", fabricant: "Fabricant 1",
                                                        modele: "Modèle 1", firmware: "1.0.0", categorie: "Lampe",
                                                        id: "00000000-0000-4000-8000-0000000000C1")],
                         zones: [ZoneMaison(nom: "Étage 1", pieces: ["Pièce 1", "Pièce 2"])]).donnees()
            .write(to: fichier("releve-maison.json"))
        var pieces = PiecesRouteurs()
        pieces.choisir("Pièce 2", appareil: sonde, domicile: "Maison 1")
        pieces.choisir("Pièce 1", appareil: final2, domicile: "0000000000000001")
        try pieces.ecrire(dans: fichier("pieces-routeurs.json"))
        var places = PlacesGardees()
        places.maisons["Maison 1"] = PlacesGardees.Maison(
            ordreEtages: ["Étage 1", "Étage 2"],
            etages: ["Étage 1": ["piece:Pièce 1": .init(x: 2.5, z: -3)]],
            aCote: ["Étage 2": .init(etage: "Étage 1")])
        try places.ecrire(dans: fichier("positions-pieces.json"))

        // L'historique du maillage et le journal : le mois en cours, et des mois de plus de 90 jours.
        let cal = calendrier()
        let historique = HistoriqueFichiers(dossier: dossier, calendrier: cal)
        for (mois, jourDuMois, lqi) in [(10, 1, 180), (10, 8, 190), (10, 17, 200), (6, 20, 150), (6, 21, 155), (5, 3, 140)] {
            try historique.ajouter(ReleveMaillage(maillage(jour(mois, jourDuMois), lqi: lqi)))
        }
        let journal = JournalFichiers(dossier: dossier.appendingPathComponent("Journal"), calendrier: cal)
        try journal.ajouter([
            Evenement(date: jour(10, 1, 8), type: .surveillanceDemarree, details: ["routeurs": "3", "appareils": "5"]),
            Evenement(date: jour(10, 9, 14), type: .cheminChange, sujet: Sujet(id: routeur2, nom: "Routeur Pièce 2"),
                      avant: "Lampe A", apres: "Passerelle"),
            Evenement(date: jour(10, 12, 9), type: .parentChange, sujet: Sujet(id: final1, nom: "Capteur B"),
                      avant: "Lampe A", apres: "Routeur Pièce 2"),
            Evenement(date: jour(10, 15, 22), type: .veille, periode: DateInterval(start: jour(10, 15, 22), end: jour(10, 16, 7))),
            Evenement(date: jour(6, 21, 10), type: .appareilDisparu, sujet: Sujet(id: final2, nom: "Capteur C")),
            Evenement(date: jour(5, 3, 10), type: .routeurDisparu, sujet: Sujet(id: routeur2, nom: "Routeur Pièce 2")),
        ])

        // Ce que l'export ne reprend pas : un fichier mis de cote, un reste d'ancienne version, un fichier du Finder.
        try Data("{}\n".utf8).write(to: fichier("surnoms.illisible-20261001-120000.json"))
        try Data("ancien signet\n".utf8).write(to: fichier("ancien-signet.txt"))
        try Data([0, 0, 0, 1]).write(to: fichier(".DS_Store"))
    }

    // MARK: Les reglages

    /// Les 19 reglages de l'inventaire de Maillage Zigbee, un de chaque, et ceux qui n'en sont pas.
    static func domaine() -> [String: Any] {
        let pont = #"{"adresse":"192.0.2.10","identifiant":"0000000000000001","manuel":false,"modele":"BSB002"}"#
        return [
            // Sonde
            "sondeSerieUSB": "SERIE-0001", "sondeNom": "SONDE-Z1", "sondeIeee": sonde, "sondeNomWifi": "RESEAU-1",
            "sondeJournalPages": [12, 13, 14, 15, 16], "sondePagesTables": 4, "sondeChemin": "usb",
            // Pont Hue : l'adresse et l'identifiant, jamais la cle.
            "pont.hue": Data(pont.utf8),
            // Vue par pieces
            "liensMontres": "tous", "voisinsALaSelection": false,
            "vuePieces3D": true, "etagesEnGrille": false, "legendeRepliee": true,
            // Notifications
            "notification.routeurDisparu": true, "notification.pertes": false, "notification.informations": true,
            // Commun
            "grapheDejaOuvert": true, "ouvertureSessionProposee": true, "AppleLanguages": ["fr"],
            // Non repris
            "SUHasLaunchedBefore": true, "SUUpdateGroupIdentifier": "groupe", "NSWindow Frame graphe": "10 10 800 600 0 0 1440 900",
            "reglages.onglet": "pont", "dossierNoms": Data([1, 2, 3]),
        ]
    }

    // MARK: Ecriture

    /// Assemble l'export d'exemple dans `destination` (qui ne doit pas exister).
    @discardableResult
    static func assembler(vers destination: URL) throws -> ExportReprise.Resultat {
        let racine = FileManager.default.temporaryDirectory.appendingPathComponent("export-exemple-source-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: racine) }
        let app = racine.appendingPathComponent("Maillage Zigbee")
        try ecrireApp(dans: app)
        return try ExportReprise.exporter(
            depuis: app, app: .maillageZigbee, versionApp: "1.2.0",
            reglages: ContratExport.reglages(depuis: domaine(), app: .maillageZigbee), vers: destination,
            identifiant: identifiant, date: date)
    }

    static func lister(_ dossier: URL) throws -> [String: Data] {
        var tout: [String: Data] = [:]
        let base = dossier.resolvingSymlinksInPath().path + "/"
        guard let liste = FileManager.default.enumerator(at: dossier, includingPropertiesForKeys: [.isRegularFileKey])
        else { return tout }
        for case let url as URL in liste where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            tout[String(url.resolvingSymlinksInPath().path.dropFirst(base.count))] = try Data(contentsOf: url)
        }
        return tout
    }

    // MARK: Tests

    /// L'exemple a un exemplaire de chaque fichier et de chaque reglage de l'inventaire, un historique de plus de 90
    /// jours, et des elements non repris.
    @Test func lExempleCouvreLInventaire() throws {
        let destination = Self.dossierEcrit.appendingPathComponent("couverture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        let r = try Self.assembler(vers: destination)

        let fichiers = r.manifeste.fichiers.map(\.chemin)
        for connu in ["surnoms.json", "dernier-maillage.json", "appariements-maison.json", "noms-pont.json",
                      "releve-maison.json", "pieces-routeurs.json", "positions-pieces.json"] {
            #expect(fichiers.contains(connu), "\(connu)")
        }
        #expect(fichiers.contains("reglages.json"))
        let mensuels = fichiers.compactMap(ContratExport.mois(de:))
        #expect(mensuels.contains(.init(annee: 2026, mois: 10)))
        // Plus de 90 jours avant l'export (17/10/2026) : fin juin, mai.
        #expect(mensuels.contains(.init(annee: 2026, mois: 6)) && mensuels.contains(.init(annee: 2026, mois: 5)))
        #expect(fichiers.contains("maillage-2026-06.jsonl") && fichiers.contains("Journal/journal-2026-06.jsonl"))
        #expect(r.manifeste.fichiersNonRepris == [
            .init(chemin: ".DS_Store", raison: .exclu),
            .init(chemin: "ancien-signet.txt", raison: .horsContrat),
            .init(chemin: "surnoms.illisible-20261001-120000.json", raison: .exclu),
        ])

        // Chaque reglage de l'inventaire y est, sous son type ; les autres sont cites, sans valeur.
        let attendus = ContratExport.reglagesConnus(de: .maillageZigbee)
        #expect(attendus.count == 19)
        for a in attendus {
            #expect(r.reglages.valeurs[a.cle]?.type == a.type, "\(a.cle)")
        }
        #expect(Set(r.reglages.valeurs.keys) == Set(attendus.map(\.cle)))
        #expect(r.reglages.nonRepris == ["SUHasLaunchedBefore": .horsContrat, "SUUpdateGroupIdentifier": .horsContrat,
                                         "NSWindow Frame graphe": .horsContrat, "reglages.onglet": .horsContrat,
                                         "dossierNoms": .horsContrat])
    }

    /// Les fichiers de l'exemple se relisent avec les lecteurs de l'app : l'exemple est un vrai export.
    @Test func lesFichiersDeLExempleSeLisentComme_L_AppLesLit() throws {
        let destination = Self.dossierEcrit.appendingPathComponent("lecture-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: destination) }
        try Self.assembler(vers: destination)
        func f(_ nom: String) -> URL { destination.appendingPathComponent(nom) }

        #expect(Surnoms.lire(f("surnoms.json")).count == 2)
        let garde = try CodageJSON.decodeur().decode(MaillageGarde.self, from: Data(contentsOf: f("dernier-maillage.json")))
        #expect(garde.maillage.noeuds.count == 6)
        #expect(MemoireAppariements.lire(f("appariements-maison.json")).ids.count == 2)
        #expect(try NomsMaison.lire(Data(contentsOf: f("noms-pont.json"))).accessoires.count == 2)
        #expect(try ReleveMaison.lire(Data(contentsOf: f("releve-maison.json"))).accessoires.count == 1)
        #expect(PiecesRouteurs.lire(f("pieces-routeurs.json")).appareils.count == 2)
        #expect(PlacesGardees.lire(f("positions-pieces.json")).maisons["Maison 1"]?.etages.count == 1)
        // Les mois lus par les lecteurs de l'app : 3 releves en octobre, 2 en juin, 1 en mai.
        let historique = HistoriqueFichiers(dossier: destination, calendrier: Self.calendrier())
        #expect(try historique.lire(depuis: .distantPast).count == 6)
        let journal = JournalFichiers(dossier: f("Journal"), calendrier: Self.calendrier())
        #expect(try journal.lire().count == 6)
    }

    /// Le dossier copie dans le depot : il passe `verifierDossier`, et il est l'export que l'app ecrit aujourd'hui.
    /// Absent ou different, l'export a jour est ecrit dans le dossier temporaire du test, a copier a la main.
    @Test func leDossierDuDepotEstLExportAJour() throws {
        let aJour = Self.dossierEcrit.appendingPathComponent("zigbee-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: aJour.deletingLastPathComponent(), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: aJour) }
        try Self.assembler(vers: aJour)

        guard FileManager.default.fileExists(atPath: Self.dossierDepot.path) else {
            let ecrit = Self.dossierEcrit.appendingPathComponent("a-copier")
            try? FileManager.default.removeItem(at: ecrit)
            try FileManager.default.copyItem(at: aJour, to: ecrit)
            Issue.record("docs/export-exemple absent : l'export est ecrit dans \(ecrit.path) ; le copier dans docs/export-exemple/, le controler, puis relancer")
            return
        }
        // Le dossier du depot passe la relecture du contrat.
        let (manifeste, reglages) = try ContratExport.verifierDossier(Self.dossierDepot)
        #expect(manifeste.app == .maillageZigbee)
        #expect(manifeste.versionApp == "1.2.0")
        #expect(reglages.app == .maillageZigbee)
        // ... et il est l'export que le code ecrit.
        let depot = try Self.lister(Self.dossierDepot).filter { $0.key != ".DS_Store" }
        let neuf = try Self.lister(aJour)
        if depot != neuf {
            let ecrit = Self.dossierEcrit.appendingPathComponent("a-copier")
            try? FileManager.default.removeItem(at: ecrit)
            try FileManager.default.copyItem(at: aJour, to: ecrit)
            Issue.record("docs/export-exemple n'est plus l'export que le code ecrit : le nouveau est dans \(ecrit.path)")
        }
    }

    /// Deux ecritures donnent les memes octets (identifiant et date fixes).
    @Test func deuxEcrituresSontIdentiques() throws {
        let a = Self.dossierEcrit.appendingPathComponent("a-" + UUID().uuidString)
        let b = Self.dossierEcrit.appendingPathComponent("b-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: Self.dossierEcrit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: a); try? FileManager.default.removeItem(at: b) }
        try Self.assembler(vers: a)
        try Self.assembler(vers: b)
        #expect(try Self.lister(a) == Self.lister(b))
    }
}
