import CoreGraphics
import Foundation
import MaillageCoeur
import SwiftUI
import Testing
@testable import MaillageZigbee

/// Les reperes des graphes de la fiche (`ReperesFiche`) : la zone du survol de leur pointe, leurs textes, et leur
/// presence dans le rendu d'une capture. Sur la demo (valeurs inventees).
@MainActor
@Suite("Reperes de la fiche")
struct ReperesFicheTests {
    typealias I = NomsDemo.Ieee

    static let t0 = MaillageDemo.fin.addingTimeInterval(-6 * 3600)
    /// Un trace de 600 pt a partir de x = 40, y = 10, sur 24 h : 144 s par pt.
    static let cadre = CGRect(x: 40, y: 10, width: 600, height: 140)
    static let debut = MaillageDemo.fin.addingTimeInterval(-86400)
    static let fin = MaillageDemo.fin

    static func date(_ x: CGFloat) -> Date? { debut.addingTimeInterval(Double(x) * 144) }

    static func reperes() -> [RepereCourbe] {
        let c = [ChangementParent(date: debut.addingTimeInterval(100 * 144), parent: I.pont),
                 ChangementParent(date: debut.addingTimeInterval(104 * 144), parent: I.lampadaireSalon),
                 ChangementParent(date: debut.addingTimeInterval(300 * 144), parent: I.pont)]
        return ReperesFiche.regrouper(c, debut: debut, fin: fin, largeur: cadre.width)
    }

    /// Le regroupement lit la duree et la largeur du trace ; la pointe se survole dans la zone haute seulement, a moins de
    /// 6 pt du trait, et libere le survol des courbes ailleurs.
    @Test func survolDeLaPointe() {
        let r = Self.reperes()
        #expect(r.map(\.nombre) == [2, 1])
        func sous(x: CGFloat, y: CGFloat) -> Date? {
            // x, y : dans le trace ; l'espace du pointeur le decale de l'origine du cadre.
            ReperesFiche.repereSous(CGPoint(x: Self.cadre.minX + x, y: Self.cadre.minY + y), cadre: Self.cadre, reperes: r,
                                    debut: Self.debut, fin: Self.fin, convertir: Self.date)
        }
        #expect(sous(x: 102, y: 5) == r[0].date)
        #expect(sous(x: 300, y: 19.9) == r[1].date)
        #expect(sous(x: 300, y: 20) == nil, "sous la zone haute : le survol est celui des courbes")
        #expect(sous(x: 102, y: 60) == nil)
        #expect(sous(x: 300 + 5.9, y: 5) == r[1].date && sous(x: 300 + 6.1, y: 5) == nil)
        #expect(sous(x: 200, y: 5) == nil)
        #expect(sous(x: 102, y: -1) == nil, "au-dessus du trace")
        #expect(ReperesFiche.repereSous(CGPoint(x: 142, y: 15), cadre: .zero, reperes: r, debut: Self.debut, fin: Self.fin,
                                        convertir: Self.date) == nil, "cadre sans largeur")
    }

    /// Les textes : « 14:21 → Plan de travail (gauche) » (le jour aussi sur 7 j et 30 j), « ×4 », « et 3 autres »,
    /// « et 1 autre » ; un nom inconnu reste l'adresse.
    @Test func textes() {
        let fr = Locale(identifier: "fr_FR"), utc = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: 1_790_000_000)   // 2026-09-21 14:13:20 UTC
        let ch = ChangementParent(date: d, parent: I.lampadaireSalon)
        let noms = [I.lampadaireSalon: "Plan de travail (gauche)"]
        #expect(ReperesFiche.ligne(ch, noms: noms, periode: .jour, locale: fr, fuseau: utc) == "14:13 → Plan de travail (gauche)")
        #expect(ReperesFiche.ligne(ch, noms: noms, periode: .semaine, locale: fr, fuseau: utc).hasSuffix("14:13 → Plan de travail (gauche)"))
        #expect(ReperesFiche.ligne(ch, noms: noms, periode: .semaine, locale: fr, fuseau: utc).count > "14:13 → Plan de travail (gauche)".count)
        #expect(ReperesFiche.ligne(ch, noms: [:], periode: .jour, locale: fr, fuseau: utc) == "14:13 → " + I.lampadaireSalon)
        #expect(ReperesFiche.texteNombre(RepereCourbe(changements: Array(repeating: ch, count: 4))) == "×4")
        #expect(ReperesFiche.texteAutres(3) == String(localized: "et \(3) autres"))
        #expect(ReperesFiche.texteAutres(1) == String(localized: "et 1 autre"))
        #expect(ReperesFiche.texteAutres(1) != ReperesFiche.texteAutres(2))
    }

    /// Les graphes n'ecrivent plus de texte au-dessus de la courbe et ne gardent aucun trait pointille : la couche des
    /// reperes se rend sans geste (aucun test de survol de fenetre) sur 24 h et sur 7 j, avec les changements de la demo.
    @Test func coucheRendue() throws {
        let c24 = CourbesNoeud(cle: I.lampeBureau, releves: MaillageDemo.historique, periode: .jour, fin: MaillageDemo.fin)
        let c7 = CourbesNoeud(cle: I.lampeBureau, releves: MaillageDemo.historique, periode: .semaine, fin: MaillageDemo.fin)
        // Sur 24 h, les dix changements rapproches se fondent deux a deux ; sur 7 j (le trace est plus large que 600 pt), en un seul.
        let jour = ReperesFiche.regrouper(c24.chemins, debut: c24.debut, fin: c24.fin, largeur: 700)
        let semaine = ReperesFiche.regrouper(c7.chemins, debut: c7.debut, fin: c7.fin, largeur: 700)
        #expect(jour.count > semaine.count && semaine.first?.nombre == 10)
        for (c, periode) in [(c24, PeriodeCourbes.jour), (c7, .semaine)] {
            let vue = GrapheQualite(courbes: c.liens, debut: c.debut, fin: c.fin, reperes: CourbesFiche.reperes(c),
                                    titre: CourbesFiche.titreQualite(c), cles: c.prioritaires, noms: [:],
                                    nomCourbe: { $0 }, periode: periode, enAvant: .constant(nil))
                .frame(width: 800, height: 260)
                .environment(\.capturePieces, true)
            let rendu = ImageRenderer(content: vue)
            #expect(rendu.cgImage != nil)
        }
    }

    /// Le graphe de qualite est generique : il se rend avec des courbes, des reperes et des noms de n'importe quel
    /// protocole, sans `CourbesNoeud` (reprise par Maillage Thread).
    @Test func grapheSansCourbesNoeud() {
        let fin = MaillageDemo.fin, debut = fin.addingTimeInterval(-PeriodeCourbes.jour.duree)
        let points = (0..<4).map { PointCourbe(date: debut.addingTimeInterval(Double($0) * 3600), valeur: Double($0 % 4), troncon: 0) }
        let vue = GrapheQualite(courbes: [CourbeLien(id: "x", points: points)], debut: debut, fin: fin,
                                reperes: [ChangementParent(date: debut.addingTimeInterval(7200), parent: "p")],
                                titre: "Qualité", cles: ["x"], noms: ["p": "Parent"], nomCourbe: { _ in "Courbe" },
                                periode: .jour, enAvant: .constant("x"))
            .frame(width: 800, height: 260)
            .environment(\.capturePieces, true)
        #expect(ImageRenderer(content: vue).cgImage != nil)
        let survol = GrapheQualite.releves([CourbeLien(id: "x", points: points)], cles: ["x"], enAvant: nil,
                                           heure: points[2].date, periode: .jour)
        #expect(survol.map(\.cle) == ["x"] && survol.first?.point.valeur == 2)
    }
}
