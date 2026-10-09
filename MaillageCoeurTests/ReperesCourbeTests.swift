import Foundation
import Testing
@testable import MaillageCoeur

/// Les reperes de changement de parent ou de chemin de la fiche : leur regroupement selon l'echelle affichee, leur
/// ordre, la bulle plafonnee, le repere sous le pointeur. Sans fenetre ; valeurs inventees.
@Suite("Reperes des changements de l'historique")
struct ReperesCourbeTests {
    typealias I = NomsDemo.Ieee

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let heure: TimeInterval = 3600
    /// Largeur du trace dans les tests (pt).
    static let largeur = 600.0

    /// Des changements de chemin a `decalages` secondes de `t0`, vers des destinations a, b, c...
    static func changements(_ decalages: [TimeInterval]) -> [ChangementParent] {
        decalages.enumerated().map { i, d in ChangementParent(date: t0.addingTimeInterval(d), parent: "n\(i)") }
    }

    static func regrouper(_ c: [ChangementParent], _ p: PeriodeCourbes, largeur: Double = largeur) -> [RepereCourbe] {
        ReperesCourbe.regrouper(c, duree: p.duree, largeur: largeur)
    }

    /// Le regroupement dépend de l'échelle : quatre changements espaces d'une heure restent quatre reperes sur 24 h
    /// (144 s par pt, 12 pt = 29 min), se fondent deux a deux sur 7 j... et tous ensemble sur 30 j.
    @Test func regroupementSelonLEchelle() {
        let c = Self.changements([0, 1, 2, 3].map { $0 * Self.heure })
        // 24 h sur 600 pt : 12 pt = 1 728 s.
        #expect(Self.regrouper(c, .jour).map(\.nombre) == [1, 1, 1, 1])
        // 7 j sur 600 pt : 12 pt = 12 096 s = 3 h 21 min ; tous a moins de 3 h du premier (3 h < 3 h 21).
        #expect(Self.regrouper(c, .semaine).map(\.nombre) == [4])
        // 30 j : 51 840 s = 14 h.
        #expect(Self.regrouper(c, .mois).map(\.nombre) == [4])
        // Un autre jeu : sur 7 j, le quatrieme est a 4 h du premier, hors des 3 h 21 min : un second repere.
        let d = Self.changements([0, 1, 2, 4].map { $0 * Self.heure })
        #expect(Self.regrouper(d, .semaine).map(\.nombre) == [3, 1])
        // Un trace plus large separe davantage : 1 200 pt, 24 h, 12 pt = 864 s.
        let e = Self.changements([0, 600, 1200, 1800])
        #expect(Self.regrouper(e, .jour, largeur: 600).map(\.nombre) == [3, 1], "1 728 s : 0, 600 et 1 200 s ensemble")
        #expect(Self.regrouper(e, .jour, largeur: 1200).map(\.nombre) == [2, 2], "864 s : 0 et 600 s, puis 1 200 et 1 800 s")
    }

    /// « A moins de 12 pt » : strictement. Un changement a 12 pt pile du premier ouvre un autre repere. Le repere ne
    /// s'etire pas de proche en proche : un changement se compare au premier du repere, non au precedent.
    @Test func ecartStrictEtSansChainage() {
        let spp = PeriodeCourbes.jour.duree / Self.largeur   // 144 s par pt
        let pile = Self.changements([0, 12 * spp])
        #expect(Self.regrouper(pile, .jour).map(\.nombre) == [1, 1])
        let presque = Self.changements([0, 12 * spp - 1])
        #expect(Self.regrouper(presque, .jour).map(\.nombre) == [2])
        // 0, 8, 16 pt : 16 est a 8 pt du precedent mais a 16 pt du premier.
        let chaine = Self.changements([0, 8 * spp, 16 * spp])
        let g = Self.regrouper(chaine, .jour)
        #expect(g.map(\.nombre) == [2, 1])
        // Deux reperes se suivent toujours a 12 pt au moins l'un de l'autre.
        let dense = Self.changements((0..<200).map { Double($0) * 7 * 60 })
        let dates = Self.regrouper(dense, .jour).map(\.date)
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) >= 12 * spp })
    }

    /// Les reperes sortent du plus ancien au plus recent, et leurs changements aussi, quel que soit l'ordre d'entree ;
    /// un repere a la date de son premier changement. Aucun changement, aucun repere ; sans largeur, aucun regroupement.
    @Test func ordreEtCas() {
        let c = Self.changements([3 * Self.heure, 0, 60, 3 * Self.heure + 30])
        let g = Self.regrouper(c, .semaine)
        #expect(g.count == 1 && g[0].changements.map(\.date) == c.map(\.date).sorted())
        #expect(g[0].date == Self.t0 && g[0].fin == Self.t0.addingTimeInterval(3 * Self.heure + 30))
        let deux = Self.regrouper(c, .jour)
        #expect(deux.map(\.date) == [Self.t0, Self.t0.addingTimeInterval(3 * Self.heure)])
        #expect(deux.map(\.nombre) == [2, 2])
        #expect(Self.regrouper([], .jour).isEmpty)
        #expect(Self.regrouper(c, .jour, largeur: 0).map(\.nombre) == [1, 1, 1, 1], "sans largeur, rien ne se fond")
        #expect(ReperesCourbe.secondesParPoint(duree: 86400, largeur: 0) == nil)
        #expect(ReperesCourbe.secondesParPoint(duree: 86400, largeur: 600) == 144)
        // Deux changements a la meme date ne font qu'un repere.
        let memeDate = Self.changements([0, 0])
        #expect(Self.regrouper(memeDate, .jour).map(\.nombre) == [2])
    }

    /// La bulle d'un repere liste au plus six changements, dans l'ordre, puis le nombre des autres.
    @Test func plafondDeLaBulle() {
        func repere(_ n: Int) -> RepereCourbe {
            RepereCourbe(changements: Self.changements((0..<n).map { Double($0) * 60 }))
        }
        #expect(ReperesCourbe.lignesMax == 6)
        let un = repere(1)
        #expect(un.nombre == 1 && un.visibles().count == 1 && un.autres() == 0)
        let six = repere(6)
        #expect(six.visibles().map(\.parent) == ["n0", "n1", "n2", "n3", "n4", "n5"] && six.autres() == 0)
        let sept = repere(7)
        #expect(sept.visibles().count == 6 && sept.autres() == 1)
        let onze = repere(11)
        #expect(onze.visibles().map(\.parent) == ["n0", "n1", "n2", "n3", "n4", "n5"], "les premiers, dans l'ordre")
        #expect(onze.autres() == 5 && onze.nombre == 11)
        #expect(onze.visibles(maximum: 2).count == 2 && onze.autres(maximum: 2) == 9)
        #expect(onze.visibles(maximum: 0).isEmpty && onze.autres(maximum: 0) == 11)
        #expect(onze.visibles(maximum: 50).count == 11 && onze.autres(maximum: 50) == 0)
    }

    /// Le repere sous le pointeur : le plus proche a moins de 6 pt de son trait (ou de son etendue s'il en fond
    /// plusieurs), aucun plus loin ni sans largeur.
    @Test func repereSousLePointeur() {
        let spp = PeriodeCourbes.jour.duree / Self.largeur
        let g = Self.regrouper(Self.changements([0, 5 * spp, 100 * spp]), .jour)
        #expect(g.map(\.nombre) == [2, 1])
        func sous(_ pt: Double) -> Date? {
            ReperesCourbe.sous(Self.t0.addingTimeInterval(pt * spp), parmi: g, duree: PeriodeCourbes.jour.duree,
                               largeur: Self.largeur)?.date
        }
        #expect(sous(0) == Self.t0 && sous(3) == Self.t0, "dans l'etendue du repere groupe")
        #expect(sous(5 + 5.9) == Self.t0 && sous(-5.9) == Self.t0)
        #expect(sous(5 + 6) == nil && sous(-6) == nil, "a 6 pt pile : trop loin")
        #expect(sous(95) == Self.t0.addingTimeInterval(100 * spp) && sous(106.5) == nil)
        #expect(sous(50) == nil)
        #expect(ReperesCourbe.sous(Self.t0, parmi: g, duree: 86400, largeur: 0) == nil)
        #expect(ReperesCourbe.sous(Self.t0, parmi: [], duree: 86400, largeur: 600) == nil)
    }

    /// Sur l'historique de la demo : la lampe du bureau hesite onze fois (dix changements 15 min l'un de l'autre, puis le
    /// passage au lampadaire 10 h avant la fin). Sur 24 h, ils se fondent deux a deux ; sur 7 j, en un seul repere
    /// dont la bulle liste six lignes et « 4 autres » (dix changements moins six), puis un repere isole.
    @Test func demoDuBureau() {
        let c = CourbesNoeud(cle: I.lampeBureau, releves: MaillageDemo.historique, periode: .jour, fin: MaillageDemo.fin)
        #expect(c.chemins.count == 11 && c.chemins.last?.parent == I.lampadaireSalon)
        #expect(zip(c.chemins, c.chemins.dropFirst()).allSatisfy { $0.parent != $1.parent }, "chaque changement change")
        let jour = ReperesCourbe.regrouper(c.chemins, duree: PeriodeCourbes.jour.duree, largeur: 700)
        #expect(jour.map(\.nombre) == [2, 2, 2, 2, 2, 1], "24 h sur 700 pt : 12 pt = 24 min")
        let semaine = ReperesCourbe.regrouper(c.chemins, duree: PeriodeCourbes.semaine.duree, largeur: 700)
        #expect(semaine.map(\.nombre) == [10, 1], "7 j sur 700 pt : 12 pt = 2 h 53 min")
        #expect(semaine[0].visibles().count == 6 && semaine[0].autres() == 4)
    }
}
