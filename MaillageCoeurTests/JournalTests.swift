import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Journal en fichiers mensuels")
struct JournalTests {
    static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 4 * 3600)!
        return c
    }

    static func date(_ texte: String) -> Date {
        try! Date(texte, strategy: .iso8601)
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
    }

    @Test func ajouterEtLire() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let j = JournalFichiers(dossier: d, calendrier: Self.calendrier)
        #expect(try j.lire().isEmpty, "dossier absent")
        let a = Evenement(date: Self.date("2026-09-27T00:14:00Z"), type: .appareilDisparu,
                          sujet: Sujet(id: "A000000000000018", nom: "Prise bureau"))
        let b = Evenement(date: Self.date("2026-09-30T21:00:00Z"), type: .veille,
                          periode: DateInterval(start: Self.date("2026-09-30T20:00:00Z"), end: Self.date("2026-09-30T21:00:00Z")))
        let c = Evenement(date: Self.date("2026-09-27T00:10:00Z"), type: .routeurDisparu, sujet: Sujet(id: "A000000000000010", nom: "Plafonnier"))
        try j.ajouter([a, b])
        try j.ajouter([c])
        // 30/09 21:00 UTC = 01/10 01:00 a Asia/Tbilisi : fichier d'octobre.
        #expect(try j.fichiers().map(\.lastPathComponent) == ["journal-2026-09.jsonl", "journal-2026-10.jsonl"])
        #expect(try j.lire() == [c, a, b], "tries par date")
        let lignes = try String(contentsOf: d.appendingPathComponent("journal-2026-09.jsonl"), encoding: .utf8)
            .split(separator: "\n")
        #expect(lignes.count == 2, "une ligne par evenement, ajoutees a la fin")
    }

    @Test func ligneIllisibleIgnoree() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let j = JournalFichiers(dossier: d, calendrier: Self.calendrier)
        let e = Evenement(date: Self.date("2026-09-27T00:14:00Z"), type: .routeurApparu)
        try j.ajouter([e])
        let url = d.appendingPathComponent("journal-2026-09.jsonl")
        let f = try FileHandle(forWritingTo: url)
        try f.seekToEnd()
        try f.write(contentsOf: Data("{pas du json\n".utf8))
        try f.close()
        try Data("autre".utf8).write(to: d.appendingPathComponent("notes.txt"))
        #expect(try j.lire() == [e])
    }

    @Test func purge() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let j = JournalFichiers(dossier: d, calendrier: Self.calendrier)
        try j.ajouter([Evenement(date: Self.date("2026-09-10T00:00:00Z"), type: .veille),
                       Evenement(date: Self.date("2026-10-10T00:00:00Z"), type: .veille)])
        // Le 05/01/2027 : septembre fini le 01/10 (96 jours), octobre le 01/11 (65 jours).
        let supprimes = try j.purger(maintenant: Self.date("2027-01-05T12:00:00Z"))
        #expect(supprimes == ["journal-2026-09.jsonl"])
        #expect(try j.fichiers().map(\.lastPathComponent) == ["journal-2026-10.jsonl"])
        #expect(j.finDuMois("journal-2026-12.jsonl") == Self.date("2026-12-31T20:00:00Z"), "01/01/2027 00:00 a Asia/Tbilisi")
        #expect(j.finDuMois("autre.jsonl") == nil)
    }
}
