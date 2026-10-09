import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Alertes : routeur disparu, pertes regroupees, le reste")
struct AlertesTests {
    static let t = Date(timeIntervalSince1970: 1_790_000_000)

    static func evenement(_ type: TypeEvenement, _ ieee: String, apres secondes: TimeInterval = 0) -> Evenement {
        Evenement(date: t.addingTimeInterval(secondes), type: type, sujet: Sujet(id: ieee, nom: ieee), details: ["ieee": ieee])
    }

    /// Un routeur disparu est notifie tout de suite, dans sa categorie ; le demarrage et la veille ne le sont pas ; le
    /// reste va aux informations.
    @Test func categories() {
        var a = Alertes()
        let sortie = a.traiter([Self.evenement(.routeurDisparu, "A000000000000010"),
                                Evenement(date: Self.t, type: .surveillanceDemarree),
                                Evenement(date: Self.t, type: .veille, periode: DateInterval(start: Self.t, duration: 60)),
                                Self.evenement(.parentChange, "A000000000000020"),
                                Self.evenement(.sansParent, "A000000000000021")])
        #expect(sortie.map(\.categorie) == [.routeurDisparu, .informations, .informations])
        #expect(CategorieAlerte.routeurDisparu.parDefaut && CategorieAlerte.pertes.parDefaut)
        #expect(!CategorieAlerte.informations.parDefaut)
        #expect(CategorieAlerte.allCases == [.routeurDisparu, .pertes, .informations])
    }

    /// Les pertes d'appareils : une notification groupee a partir de 3 dans une fenetre de 10 min, qui garde son
    /// identifiant quand une perte s'y ajoute ; une perte hors de la fenetre en ouvre une autre.
    @Test func pertesRegroupees() throws {
        var a = Alertes()
        #expect(a.traiter([Self.evenement(.appareilDisparu, "A000000000000020"),
                           Self.evenement(.appareilDisparu, "A000000000000021", apres: 60)]).isEmpty, "2 : pas encore")
        let trois = a.traiter([Self.evenement(.appareilDisparu, "A000000000000022", apres: 120)])
        let groupe = try #require(trois.first)
        #expect(trois.count == 1 && groupe.categorie == .pertes && groupe.evenements.count == 3)
        let quatre = a.traiter([Self.evenement(.appareilDisparu, "A000000000000023", apres: 300)])
        #expect(quatre.first?.identifiant == groupe.identifiant && quatre.first?.evenements.count == 4,
                "la meme notification, remplacee")
        #expect(a.traiter([Self.evenement(.appareilDisparu, "A000000000000024", apres: 1200)]).isEmpty,
                "hors de la fenetre : une autre, seule pour l'instant")
    }
}
