import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Historique du maillage : releves et fichiers mensuels")
struct HistoriqueTests {
    static func date(_ texte: String) -> Date {
        try! Date(texte, strategy: .iso8601)
    }

    static func dossier() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("historique-\(UUID().uuidString)")
    }

    /// Petit maillage (valeurs inventees) : le pont, un routeur muet et un routeur ; un lien vu des deux cotes, un vu
    /// d'un seul ; la sonde sous le pont, un appareil final sous le routeur, au LQI inconnu ; deux signaux.
    static func maillage(_ date: Date) -> MaillageZigbee {
        MaillageZigbee(date: date,
                       noeuds: [NoeudZigbee(ieee: "A0000000000000A1", court: 0, type: .coordinateur),
                                NoeudZigbee(ieee: "A0000000000000A3", court: 0x2B3C, type: .routeur),
                                NoeudZigbee(ieee: "A0000000000000A2", court: 0x1A2B, type: .routeur, muet: true),
                                NoeudZigbee(ieee: "A0000000000000B1", court: 0x0A11, type: .final),
                                NoeudZigbee(ieee: "A0000000000000B2", court: 0x0A12, type: .final)],
                       liens: [LienRadio(mesurePar: "A0000000000000A1", de: "A0000000000000A2", lqi: 200, date: date),
                               LienRadio(mesurePar: "A0000000000000A3", de: "A0000000000000A1", lqi: 120, date: date),
                               LienRadio(mesurePar: "A0000000000000A1", de: "A0000000000000A3", lqi: 90, date: date)],
                       parents: [LienParent(enfant: "A0000000000000B2", parent: "A0000000000000A3", date: date),
                                 LienParent(enfant: "A0000000000000B1", parent: "A0000000000000A1", lqi: 180, date: date)],
                       routesPont: [RouteZigbee(destination: 0x2B3C, prochain: 0x2B3C, etat: "active")],
                       sonde: "A0000000000000B1",
                       signaux: [SignalSonde(ieee: "A0000000000000A1", lqi: 180), SignalSonde(ieee: "A0000000000000A3", lqi: 75)])
    }

    /// Une ligne par tournee, en tableaux : noeuds par adresse longue (un muet marque), liens reunis par paire avec les
    /// deux LQI, parents par enfant avec leur LQI, signaux, la sonde ; ni les dates des mesures, ni les adresses
    /// courtes, ni les routes du pont. Relue a l'identique.
    @Test func ligneDUnReleve() throws {
        let r = ReleveMaillage(Self.maillage(Self.date("2026-09-30T10:00:00Z")))
        let json = String(decoding: try CodageJSON.encodeur().encode(r), as: UTF8.self)
        #expect(json == #"{"date":"2026-09-30T10:00:00.000Z","liens":[["A0000000000000A1","A0000000000000A2",200,null],["A0000000000000A1","A0000000000000A3",90,120]],"noeuds":[["A0000000000000A1","c"],["A0000000000000A2","r",true],["A0000000000000A3","r"],["A0000000000000B1","f"],["A0000000000000B2","f"]],"parents":[["A0000000000000B1","A0000000000000A1",180],["A0000000000000B2","A0000000000000A3",null]],"signaux":[["A0000000000000A1",180],["A0000000000000A3",75]],"sonde":"A0000000000000B1"}"#)
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(json.utf8)) == r)
        #expect(r.parentSonde == "A0000000000000A1")
        #expect(r.liens.allSatisfy { $0.dateA == nil && $0.dateB == nil } && r.parents.allSatisfy { $0.date == nil })
        #expect(r.liens.map(\.qualite) == [3, 1], "la qualite se recalcule du LQI garde")
    }

    /// Un role inconnu (version plus recente) se lit `inconnu` ; sans signaux ni sonde, la ligne se lit ; un champ
    /// obligatoire manquant la rend illisible.
    @Test func lectureTolerante() throws {
        let futur = #"{"date":"2026-09-30T10:00:00.000Z","liens":[],"noeuds":[["A0000000000000A1","x"]],"parents":[]}"#
        let r = try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(futur.utf8))
        #expect(r.noeuds == [ReleveMaillage.Noeud(ieee: "A0000000000000A1", type: .inconnu)])
        #expect(r.signaux.isEmpty && r.sonde == nil && r.parentSonde == nil)
        let sansNoeuds = #"{"date":"2026-09-30T10:00:00.000Z","liens":[],"parents":[]}"#
        #expect(throws: DecodingError.self) { try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(sansNoeuds.utf8)) }
    }

    /// Un octet non UTF-8 (0xC3 isole : un caractere accentue coupe) abime sa ligne seulement : les
    /// autres lignes du fichier sont lues, pour l'historique comme pour le journal.
    @Test func octetNonUTF8() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let avant = ReleveMaillage(Self.maillage(Self.date("2026-09-20T10:00:00Z")))
        let apres = ReleveMaillage(Self.maillage(Self.date("2026-09-21T10:00:00Z")))
        try h.ajouter(avant)
        let f = try FileHandle(forWritingTo: d.appendingPathComponent("maillage-2026-09.jsonl"))
        try f.seekToEnd()
        try f.write(contentsOf: Data(#"{"date":"2026-09-20T11:00:00.000Z","noeuds":[],"x":""#.utf8) + Data([0xC3]))
        try f.write(contentsOf: Data("\"}\n".utf8))
        try f.close()
        try h.ajouter(apres)
        #expect(try h.lire(depuis: .distantPast) == [avant, apres])

        let j = JournalFichiers(dossier: d, calendrier: JournalTests.calendrier)
        let e1 = Evenement(date: Self.date("2026-09-10T00:00:00Z"), type: .veille)
        let e2 = Evenement(date: Self.date("2026-09-11T00:00:00Z"), type: .veille)
        try j.ajouter([e1])
        let g = try FileHandle(forWritingTo: d.appendingPathComponent("journal-2026-09.jsonl"))
        try g.seekToEnd()
        try g.write(contentsOf: Data([0x7B, 0xC3, 0x0A]))
        try g.close()
        try j.ajouter([e2])
        #expect(try j.lire() == [e1, e2])
    }

    /// Une tournee du pont Hue de la demo (21 noeuds, 16 liens, 7 parents : la telecommande et son parent d'avant n'y
    /// sont pas) tient en moins de 3 Ko ; une grande maison
    /// (100 noeuds, 120 liens, 60 parents), en moins de 12 Ko : 30 jours de releves (2 880) restent en memoire.
    @Test func tailleDUneLigne() throws {
        let r = ReleveMaillage(MaillageDemo.maillage)
        #expect(r.noeuds.count == 21 && r.liens.count == 16 && r.parents.count == 7)
        let octets = try CodageJSON.encodeur().encode(r).count
        #expect(octets < 3 * 1024, "\(octets) octets")
        func ieee(_ n: Int) -> String { String(format: "A00000000000%04X", n) }
        let grand = ReleveMaillage(date: r.date,
                                   noeuds: (0..<100).map { ReleveMaillage.Noeud(ieee: ieee($0), type: $0 < 40 ? .routeur : .final) },
                                   liens: (0..<120).map { LienRadio(a: ieee($0 % 40), b: ieee(($0 + 1) % 40 + 40), lqiA: 200, lqiB: 180) },
                                   parents: (40..<100).map { LienParent(enfant: ieee($0), parent: ieee($0 % 40), lqi: 150) })
        let taille = try CodageJSON.encodeur().encode(grand).count
        #expect(taille < 12 * 1024, "\(taille) octets")
    }

    /// Fichiers `maillage-AAAA-MM.jsonl` du dossier de l'app : un releve par ligne, au mois de sa
    /// date (calendrier local) ; relus depuis une date, du plus ancien au plus recent, sans ligne
    /// illisible ; purges 90 jours apres la fin de leur mois ; les autres fichiers du dossier (un
    /// journal, ici dans le meme dossier ; dans l'app, il a son sous-dossier `Journal` ; et les
    /// pieces choisies) ne sont ni lus ni purges.
    @Test func fichiersMensuels() throws {
        let d = Self.dossier()
        defer { try? FileManager.default.removeItem(at: d) }
        let h = HistoriqueFichiers(dossier: d, calendrier: JournalTests.calendrier)
        #expect(try h.lire(depuis: .distantPast).isEmpty, "dossier absent")
        let septembre = ReleveMaillage(Self.maillage(Self.date("2026-09-20T10:00:00Z")))
        let fin = ReleveMaillage(Self.maillage(Self.date("2026-09-30T21:00:00Z")))
        let octobre = ReleveMaillage(Self.maillage(Self.date("2026-10-03T09:00:00Z")))
        for r in [fin, septembre, octobre] { try h.ajouter(r) }
        let f = try FileHandle(forWritingTo: d.appendingPathComponent("maillage-2026-09.jsonl"))
        try f.seekToEnd()
        try f.write(contentsOf: Data("{pas du json\n".utf8))
        try f.close()
        try JournalFichiers(dossier: d, calendrier: JournalTests.calendrier)
            .ajouter([Evenement(date: Self.date("2026-09-10T00:00:00Z"), type: .veille)])
        try Data("{}".utf8).write(to: d.appendingPathComponent("pieces-routeurs.json"))
        // 30/09 21:00 UTC = 01/10 01:00 a Asia/Tbilisi : fichier d'octobre.
        #expect(h.nomFichier(fin.date) == "maillage-2026-10.jsonl")
        #expect(try h.lire(depuis: .distantPast) == [septembre, fin, octobre])
        #expect(try h.lire(depuis: Self.date("2026-09-25T00:00:00Z")) == [fin, octobre])
        let supprimes = try h.purger(maintenant: Self.date("2027-01-05T12:00:00Z"))
        #expect(supprimes == ["maillage-2026-09.jsonl"], "septembre fini depuis 96 jours ; le journal reste")
        #expect(try h.lire(depuis: .distantPast) == [fin, octobre])
        let restants = try FileManager.default.contentsOfDirectory(atPath: d.path).sorted()
        #expect(restants == ["journal-2026-09.jsonl", "maillage-2026-10.jsonl", "pieces-routeurs.json"])
    }

    /// Les chemins : `[routeur, prochain]`, `true` en plus pour un suppose, relus a l'identique ; un releve d'avant les
    /// chemins se lit sans chemins, et un releve sans chemin s'ecrit comme avant.
    @Test func cheminsDuReleve() throws {
        var m = Self.maillage(Self.date("2026-09-30T10:00:00Z"))
        m.chemins = [CheminPont(routeur: "A0000000000000A3", prochain: "A0000000000000A1", plusieursVersUn: true),
                     CheminPont(routeur: "A0000000000000A2", prochain: "A0000000000000A3", actif: false, suppose: true),
                     CheminPont(routeur: "A0000000000000A4", prochain: "~1A2B")]
        let r = ReleveMaillage(m)
        #expect(r.chemins == [ReleveMaillage.Chemin(routeur: "A0000000000000A2", prochain: "A0000000000000A3", suppose: true),
                              ReleveMaillage.Chemin(routeur: "A0000000000000A3", prochain: "A0000000000000A1")],
                "par routeur, sans cle provisoire")
        let json = String(decoding: try CodageJSON.encodeur().encode(r), as: UTF8.self)
        #expect(json.hasPrefix(#"{"chemins":[["A0000000000000A2","A0000000000000A3",true],["A0000000000000A3","A0000000000000A1"]],"date":"#))
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(json.utf8)) == r)
        let avant = #"{"date":"2026-09-30T10:00:00.000Z","liens":[],"noeuds":[["A0000000000000A1","c"]],"parents":[]}"#
        #expect(try CodageJSON.decodeur().decode(ReleveMaillage.self, from: Data(avant.utf8)).chemins.isEmpty)
    }
}
