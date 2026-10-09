import Foundation
@testable import MaillageCoeur
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Journal et historique de la sonde dans l'app")
struct JournalMaillageTests {
    /// Un appareil du pont de la demo.
    static let appareil = NomsDemo.Ieee.interrupteurSalon
    static let r1 = "A0000000000000C1"
    static let r5 = "A0000000000000C5"

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("maillage-\(UUID().uuidString)")
    }

    /// Mode direct sans sonde, avec les noms du pont de la demo ; journal et historique dans `dossier`.
    static func surveillance(_ mode: Surveillance.Mode = .direct, dossier: URL?) -> Surveillance {
        let s = Surveillance(mode: mode, dossier: dossier)
        s.noms.maison = NomsDemo.maison
        return s
    }

    /// Maillage invente : le pont, les routeurs r1 et r5, que le pont ne connait pas, relies ; l'appareil, enfant de
    /// `parent` (1 ou 5) ; la sonde entend r1.
    static func maillage(_ s: Surveillance, _ date: Date, parent: Int) throws -> MaillageZigbee {
        MaillageZigbee(date: date,
                       noeuds: [NoeudZigbee(ieee: NomsDemo.Ieee.pont, court: 0, type: .coordinateur),
                                NoeudZigbee(ieee: r1, court: 0x0400, type: .routeur),
                                NoeudZigbee(ieee: r5, court: 0x1400, type: .routeur),
                                NoeudZigbee(ieee: appareil, court: 0x0A11, type: .final)],
                       liens: [LienRadio(a: r1, b: r5, lqiA: 200, lqiB: 120, dateA: date, dateB: date)],
                       parents: [LienParent(enfant: appareil, parent: parent == 1 ? r1 : r5, lqi: 200, date: date)],
                       signaux: [SignalSonde(ieee: r1, lqi: 170)])
    }

    /// Changement de parent de l'appareil : au journal (en memoire et sur disque), sous son id et son
    /// nom du graphe, avec le nom des deux routeurs ; chaque tournee a son releve dans
    /// `maillage-AAAA-MM.jsonl`, relu par un nouveau lancement.
    @Test func journalEtHistoriqueSurDisque() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Self.surveillance(dossier: dossier)
        // Des secondes entieres : le fichier garde les dates a la milliseconde.
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        s.recevoir(try Self.maillage(s, t, parent: 1), a: t.addingTimeInterval(1))
        s.recevoir(try Self.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(301))
        let e = try #require(s.evenements.last)
        #expect(e.type == .parentChange)
        #expect(e.sujet == Sujet(id: Self.appareil, nom: "Interrupteur salon"))
        #expect(e.avant == Self.r1 && e.apres == Self.r5, "inconnus du pont : leur adresse longue")
        #expect(try JournalFichiers(dossier: dossier.appendingPathComponent("Journal")).lire().last == e)
        #expect(s.historique.map(\.date) == [t, t.addingTimeInterval(300)])
        let fichier = dossier.appendingPathComponent(HistoriqueFichiers(dossier: dossier).nomFichier(t.addingTimeInterval(300)))
        #expect(FileManager.default.fileExists(atPath: fichier.path))
        let relu = Surveillance(mode: .direct, dossier: dossier)
        await relu.chargerHistorique()
        #expect(relu.historique == s.historique)
    }

    /// Relecture de l'historique avec des releves deja en memoire : le releve d'un lancement
    /// precedent est relu ; celui recu depuis (sa date est tronquee a la milliseconde sur le disque)
    /// n'est pas repris en double ; le fichier d'un mois fini depuis plus de 90 jours est supprime.
    @Test func chargementFusionneSansDoublon() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        let a = Self.surveillance(dossier: dossier)
        a.recevoir(try Self.maillage(a, t, parent: 1), a: t.addingTimeInterval(1))
        // Sous la milliseconde : la copie du disque est a t + 300.000, celle de la memoire a t + 300.0004.
        let tard = t.addingTimeInterval(300.0004)
        let b = Self.surveillance(dossier: dossier)
        b.recevoir(try Self.maillage(b, tard, parent: 1), a: t.addingTimeInterval(301))
        let ancien = dossier.appendingPathComponent("maillage-2020-01.jsonl")
        FileManager.default.createFile(atPath: ancien.path, contents: Data())
        await b.chargerHistorique()
        #expect(b.historique.map(\.date) == [t, tard], "relu sans doublon, sans sa copie du disque")
        #expect(!FileManager.default.fileExists(atPath: ancien.path), "mois fini depuis plus de 90 jours")
    }

    /// Une purge qui echoue (vieux fichier dans un dossier sans droit d'ecriture) n'empeche ni la
    /// lecture du journal ni celle de l'historique.
    @Test func purgeEnEchecNeBloquePasLaLecture() async throws {
        let dossier = Self.dossier()
        let journalDossier = dossier.appendingPathComponent("Journal")
        defer {
            for d in [journalDossier, dossier] { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: d.path) }
            try? FileManager.default.removeItem(at: dossier)
        }
        let t = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down) - 600)
        let e = Evenement(date: t, type: .veille)
        try JournalFichiers(dossier: journalDossier).ajouter([e])
        let r = ReleveMaillage(try Self.maillage(Self.surveillance(dossier: nil), t, parent: 1))
        try HistoriqueFichiers(dossier: dossier).ajouter(r)
        FileManager.default.createFile(atPath: journalDossier.appendingPathComponent("journal-2020-01.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: dossier.appendingPathComponent("maillage-2020-01.jsonl").path, contents: Data())
        for d in [journalDossier, dossier] { try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: d.path) }
        let s = Surveillance(mode: .direct, dossier: dossier)
        s.chargerJournal()
        #expect(s.erreurJournal == nil)
        #expect(s.evenements == [e])
        await s.chargerHistorique()
        #expect(s.historique == [r])
        #expect(FileManager.default.fileExists(atPath: journalDossier.appendingPathComponent("journal-2020-01.jsonl").path),
                "la purge a bien echoue")
    }

    /// Les fichiers sont purges quand le mois change pendant que l'app tourne (elle peut durer des
    /// semaines), pas a chaque tournee : deux tournees du meme mois ne purgent pas ; la premiere d'un
    /// autre mois purge le journal et l'historique. Ni en demo, ni sans dossier.
    @Test func purgeAuChangementDeMois() async throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let s = Self.surveillance(dossier: dossier)
        s.chargerJournal()
        await s.chargerHistorique()
        let anciens = [dossier.appendingPathComponent("Journal/journal-2020-01.jsonl"),
                       dossier.appendingPathComponent("maillage-2020-01.jsonl")]
        func creer() {
            for u in anciens {
                try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: u.path, contents: Data())
            }
        }
        func presents() -> [Bool] { anciens.map { FileManager.default.fileExists(atPath: $0.path) } }
        let t = Date()
        creer()
        s.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        #expect(presents() == [true, true], "meme mois que la derniere purge (celle du chargement)")
        // Un mois plus tard au moins : 45 jours.
        let plus = t.addingTimeInterval(45 * 24 * 3600)
        s.recevoir(try Self.maillage(s, plus, parent: 1), a: plus)
        #expect(presents() == [false, false], "mois change : journal et historique purges")
        creer()
        s.recevoir(try Self.maillage(s, plus.addingTimeInterval(300), parent: 1), a: plus.addingTimeInterval(300))
        #expect(presents() == [true, true], "une fois par mois")
        // Demo : rien n'est ecrit ni purge.
        let demo = Self.surveillance(.demo, dossier: dossier)
        demo.recevoir(try Self.maillage(demo, plus, parent: 1), a: plus.addingTimeInterval(90 * 24 * 3600))
        #expect(presents() == [true, true])
    }

    /// Demo : ni releve en memoire, ni fichier, meme avec un dossier ; le journal du maillage reste
    /// en memoire. Direct sans dossier : l'historique en memoire seulement.
    @Test func rienSurDisqueEnDemo() throws {
        let dossier = Self.dossier()
        defer { try? FileManager.default.removeItem(at: dossier) }
        let demo = Self.surveillance(.demo, dossier: dossier)
        let t = Date()
        demo.recevoir(try Self.maillage(demo, t, parent: 1), a: t)
        demo.recevoir(try Self.maillage(demo, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        #expect(demo.historique.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: dossier.path))
        #expect(demo.evenements.last?.type == .parentChange)
        let memoire = Self.surveillance(dossier: nil)
        memoire.recevoir(try Self.maillage(memoire, t, parent: 1), a: t)
        #expect(memoire.historique.count == 1)
    }

    /// Sonde oubliee : le maillage suivant est un point de depart (un demarrage, pas de « a change de parent » calcule
    /// par-dessus l'oubli) ; l'historique en memoire reste.
    @Test func oubliRepartDeZero() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        s.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        s.oublierMaillage()
        let avant = s.evenements.count
        s.recevoir(try Self.maillage(s, t.addingTimeInterval(300), parent: 5), a: t.addingTimeInterval(300))
        #expect(s.evenements.count == avant + 1 && s.evenements.last?.type == .surveillanceDemarree, "point de depart")
        #expect(s.historique.count == 2)
    }

    /// L'historique en memoire garde 30 jours, comptes depuis la reception du dernier maillage.
    @Test func trenteJoursEnMemoire() throws {
        let s = Self.surveillance(dossier: nil)
        let t = Date()
        let vieux = t.addingTimeInterval(-Surveillance.dureeHistorique - 60)
        s.recevoir(try Self.maillage(s, vieux, parent: 1), a: vieux)
        s.recevoir(try Self.maillage(s, t, parent: 1), a: t)
        #expect(s.historique.map(\.date) == [t])
    }
}
