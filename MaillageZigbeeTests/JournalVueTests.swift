import Foundation
import MaillageCoeur
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Journal : filtre des lignes")
struct JournalVueTests {
    /// Le journal de la demo : le demarrage, la prise du salon disparue (une alerte), le detecteur de l'abri qui change
    /// de parent, la lampe du bureau qui change de chemin ; filtres par famille, par gravite, et recherche dans le sujet
    /// (nom ou adresse longue).
    @Test func filtreDuJournal() {
        let s = NomsSceneTests.surveillanceDemo()
        let lignes = s.lignesJournal
        #expect(FiltreJournal().appliquer(lignes).count == 4)
        #expect(FiltreJournal(famille: .maillage).appliquer(lignes).count == 2)
        #expect(FiltreJournal(famille: .appareils).appliquer(lignes).isEmpty)
        #expect(FiltreJournal(famille: .routeurs).appliquer(lignes).count == 1)
        #expect(FiltreJournal(famille: .surveillance).appliquer(lignes).count == 1)
        #expect(FiltreJournal(graviteMinimale: .alerte).appliquer(lignes).map { $0.evenements.first?.type }
                == [.routeurDisparu])
        #expect(FiltreJournal(recherche: "prise salon").appliquer(lignes).count == 1, "nom d'un routeur")
        #expect(FiltreJournal(recherche: NomsDemo.Ieee.detecteurAbri).appliquer(lignes).count == 1, "adresse longue")
        #expect(FiltreJournal(recherche: "introuvable").appliquer(lignes).isEmpty)
        #expect(FamilleEvenement.surveillance.contient(.veille))
        #expect(!FamilleEvenement.routeurs.contient(.appareilDisparu))
    }

    /// La recherche trouve aussi les noms des parents (« avant » et « apres ») d'une ligne de
    /// changements de parent regroupes, dont le titre ne les cite pas.
    @Test func rechercheDesParentsRegroupes() {
        let t = MaillageDemo.fin
        let change = { (minutes: Double, avant: String, apres: String) in
            Evenement(date: t.addingTimeInterval(minutes * 60), type: .parentChange,
                      sujet: Sujet(id: "A0000000000000B1", nom: "Détecteur abri"), avant: avant, apres: apres,
                      details: ["ieee": "A0000000000000B1"])
        }
        let lignes = Regroupement.lignes([change(0, "Ruban cuisine", "A0000000000000FD"),
                                          change(5, "A0000000000000FD", "Ruban cuisine")])
        #expect(lignes.count == 1 && lignes.first?.evenements.count == 2)
        #expect(FiltreJournal(recherche: "ruban").appliquer(lignes).count == 1, "nom « avant »")
        #expect(FiltreJournal(recherche: "00FD").appliquer(lignes).count == 1, "nom « apres »")
        #expect(FiltreJournal(recherche: "détecteur").appliquer(lignes).count == 1, "sujet, comme avant")
        #expect(FiltreJournal(recherche: "introuvable").appliquer(lignes).isEmpty)
    }

    /// Les evenements du maillage de la sonde ont leur famille, « Maillage », et elle seule.
    @Test func familleMaillage() {
        for t in [TypeEvenement.parentChange, .sansParent] {
            #expect(FamilleEvenement.allCases.filter { $0 != .toutes && $0.contient(t) } == [.maillage], "\(t)")
        }
    }
}
