import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Courbes d'un noeud tirees de l'historique")
struct CourbesNoeudTests {
    /// Debut d'un pas de 30 min et de 2 h.
    static let t0 = Date(timeIntervalSince1970: 1_790_006_400)
    static let a0 = "A0000000000000A0"
    static let a1 = "A0000000000000A1"
    static let b1 = "A0000000000000B1"
    static let sonde = "A0000000000000FE"

    /// Releve a `minutes` de t0 (valeurs inventees) : les routeurs a0 et a1 et leur lien, de LQI `lqi` mesure par a0 et
    /// 200 par a1 ; l'appareil b1 sous `parent`, au LQI `lqiEnfant` ; la sonde sous `parentSonde`, qui entend a0 a
    /// `signal`.
    static func releve(_ minutes: Double, lqi: Int? = 200, parent: String = a0, lqiEnfant: Int? = 200,
                       parentSonde: String = a0, signal: Int = 180) -> ReleveMaillage {
        ReleveMaillage(date: t0.addingTimeInterval(minutes * 60),
                       noeuds: [.init(ieee: a0, type: .routeur), .init(ieee: a1, type: .routeur),
                                .init(ieee: b1, type: .final), .init(ieee: sonde, type: .final)],
                       liens: [LienRadio(a: a0, b: a1, lqiA: lqi, lqiB: 200)],
                       parents: [LienParent(enfant: b1, parent: parent, lqi: lqiEnfant),
                                 LienParent(enfant: sonde, parent: parentSonde, lqi: 190)],
                       signaux: [SignalSonde(ieee: a0, lqi: signal)], sonde: sonde)
    }

    static func minutes(_ m: Double) -> Date { t0.addingTimeInterval(m * 60) }

    /// Routeur : la qualite de son lien avec chaque voisin (la moins bonne des deux mesures, `QualiteLien`) et le LQI que
    /// la sonde en recoit, a chaque releve de la periode.
    @Test func routeur() {
        let releves = [Self.releve(0, lqi: 200, signal: 180), Self.releve(15, lqi: 120, signal: 150),
                       Self.releve(30, lqi: 70, signal: 120)]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(35))
        #expect(c.courbe(Self.a1) == CourbeLien(id: Self.a1, points: [
            PointCourbe(date: Self.minutes(0), valeur: 3, troncon: 0, lqi: 200),
            PointCourbe(date: Self.minutes(15), valeur: 2, troncon: 0, lqi: 120),
            PointCourbe(date: Self.minutes(30), valeur: 1, troncon: 0, lqi: 70)]))
        // Ses enfants (l'appareil b1 et la sonde) ont aussi leur courbe (etape 5), de la qualite que le routeur mesure.
        #expect(c.liens.map(\.id) == [Self.a1, Self.b1, Self.sonde])
        #expect(c.courbe(Self.sonde)?.points.map(\.lqi) == [190, 190, 190])
        #expect(c.signal.map(\.valeur) == [180, 150, 120])
        #expect(c.parents.isEmpty)
        #expect(c.debut == Self.minutes(35).addingTimeInterval(-24 * 3600))
        #expect(CourbesNoeud(cle: Self.a1, releves: releves, periode: .jour, fin: Self.minutes(35)).signal.isEmpty,
                "la sonde n'entend pas a1")
    }

    /// Appareil final : la qualite du lien vers son parent, quel qu'il soit (inconnue : pas de point), et ses
    /// changements de parent, a la date du premier releve sous le nouveau.
    @Test func enfant() {
        let releves = [Self.releve(0), Self.releve(15), Self.releve(30, parent: Self.a1, lqiEnfant: 120),
                       Self.releve(45, parent: Self.a1, lqiEnfant: nil)]
        let c = CourbesNoeud(cle: Self.b1, releves: releves, periode: .jour, fin: Self.minutes(50))
        #expect(c.liens.map(\.id) == [CourbesNoeud.cleParent])
        #expect(c.liens.first?.points.map(\.valeur) == [3, 3, 2])
        #expect(c.parents == [ChangementParent(date: Self.minutes(30), parent: Self.a1)])
        #expect(c.signal.isEmpty)
        #expect(!c.estVide)
        #expect(CourbesNoeud(cle: "A0000000000000FF", releves: releves, periode: .jour, fin: Self.minutes(50)).estVide)
    }

    /// Les changements de parent de la sonde, sur la courbe du signal d'un routeur.
    @Test func parentsDeLaSonde() {
        let releves = [Self.releve(0), Self.releve(15), Self.releve(30, parentSonde: Self.a1), Self.releve(45, parentSonde: Self.a1)]
        let c = CourbesNoeud(cle: Self.a0, releves: releves, periode: .jour, fin: Self.minutes(50))
        #expect(c.parentsSonde == [ChangementParent(date: Self.minutes(30), parent: Self.a1)])
    }

    /// 7 j : la moyenne de chaque pas de 30 min ; un trou de plus de trois pas ouvre un troncon.
    /// 24 h : chaque releve ; un trou de plus de 20 min ouvre un troncon. Hors periode : rien.
    @Test func pasEtTroncons() {
        let semaine = [0.0, 5, 10, 15, 20, 25].enumerated().map { Self.releve($1, lqi: $0 < 3 ? 200 : 120) }
            + [Self.releve(210, lqi: 200)]
        let c = CourbesNoeud(cle: Self.a0, releves: semaine, periode: .semaine, fin: Self.minutes(240))
        #expect(c.courbe(Self.a1)?.points == [PointCourbe(date: Self.minutes(0), valeur: 2.5, troncon: 0, lqi: 160),
                                              PointCourbe(date: Self.minutes(210), valeur: 3, troncon: 1, lqi: 200)],
                "la moyenne du pas, LQI compris")
        let jour = [Self.releve(0), Self.releve(5), Self.releve(30), Self.releve(35)]
        let d = CourbesNoeud(cle: Self.a0, releves: jour, periode: .jour, fin: Self.minutes(40))
        #expect(d.signal.map(\.troncon) == [0, 0, 1, 1])
        let tard = CourbesNoeud(cle: Self.a0, releves: jour, periode: .jour, fin: Self.minutes(20 + 24 * 60))
        #expect(tard.signal.map(\.date) == [Self.minutes(30), Self.minutes(35)], "24 h avant la fin")
    }

    /// Bornes de la periode (les deux comprises : un releve plus recent que la fiche, qui est a la
    /// minute, n'en fait pas partie), seuils des troncons (20 min pile ne coupent pas, 20 min et 1 s
    /// coupent ; trois pas ne coupent pas, quatre oui ; chaque trou ouvre un troncon de plus), 30 j.
    @Test func bornesSeuilsEtMois() {
        let r = [Self.releve(0), Self.releve(10), Self.releve(11)]
        #expect(CourbesNoeud(cle: Self.a0, releves: r, periode: .jour, fin: Self.minutes(10)).signal.map(\.date)
                == [Self.minutes(0), Self.minutes(10)], "fin comprise, plus recent exclu")
        #expect(CourbesNoeud(cle: Self.a0, releves: r, periode: .jour, fin: Self.minutes(24 * 60)).signal.map(\.date)
                == [Self.minutes(0), Self.minutes(10), Self.minutes(11)], "debut compris")
        let trous = [Self.releve(0), Self.releve(20), Self.releve(40 + 1.0 / 60), Self.releve(70)]
        #expect(CourbesNoeud(cle: Self.a0, releves: trous, periode: .jour, fin: Self.minutes(80)).signal.map(\.troncon)
                == [0, 0, 1, 2], "seuil de 20 min")
        let pas = [Self.releve(0), Self.releve(90), Self.releve(210)]
        #expect(CourbesNoeud(cle: Self.a0, releves: pas, periode: .semaine, fin: Self.minutes(240)).signal.map(\.troncon)
                == [0, 0, 1], "seuil de trois pas")
        let mois = [Self.releve(0, signal: 180), Self.releve(119, signal: 170), Self.releve(120, signal: 160)]
        let m = CourbesNoeud(cle: Self.a0, releves: mois, periode: .mois, fin: Self.minutes(240))
        #expect(m.signal == [PointCourbe(date: Self.minutes(0), valeur: 175, troncon: 0),
                             PointCourbe(date: Self.minutes(120), valeur: 160, troncon: 0)], "pas de 2 h")
        #expect(m.debut == Self.minutes(240).addingTimeInterval(-30 * 24 * 3600), "30 j")
        #expect(CourbesNoeud(cle: Self.a0, releves: mois, periode: .semaine, fin: Self.minutes(240)).debut
                == Self.minutes(240).addingTimeInterval(-7 * 24 * 3600), "7 j")
    }

    /// Un lien sans LQI des deux cotes n'a pas de point (le signal suffit a une fiche) ; un appareil au LQI inconnu n'a
    /// pas de courbe, et ses changements de parent suffisent a sa fiche.
    @Test func sansQualite() {
        let c = CourbesNoeud(cle: Self.a0, releves: [Self.releve(0, lqi: nil).sansLienMesure], periode: .jour,
                             fin: Self.minutes(5))
        #expect(c.courbe(Self.a1) == nil, "pas de point sans qualite")
        #expect(!c.estVide, "le signal suffit")
        let e = CourbesNoeud(cle: Self.b1, releves: [Self.releve(0, lqiEnfant: nil),
                                                     Self.releve(15, parent: Self.a1, lqiEnfant: nil)],
                             periode: .jour, fin: Self.minutes(20))
        #expect(e.liens.isEmpty, "qualite inconnue : pas de courbe")
        #expect(!e.estVide, "le changement de parent suffit")
    }
}

private extension ReleveMaillage {
    /// Le meme releve, son lien sans aucune mesure.
    var sansLienMesure: ReleveMaillage {
        ReleveMaillage(date: date, noeuds: noeuds, liens: liens.map { LienRadio(a: $0.a, b: $0.b) }, parents: parents,
                       signaux: signaux, sonde: sonde)
    }
}
