import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Journal : changements de parent regroupes")
struct RegroupementParentsTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)

    static func parent(_ minutes: Double, _ noeud: String) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: noeud, nom: noeud),
                  avant: "A", apres: "B")
    }

    /// Changements de parent d'un meme noeud dans une fenetre de 1 h, comptee depuis le premier :
    /// une ligne ; seul dans sa fenetre, il reste une ligne a lui ; un autre noeud a les siennes.
    @Test func uneLigneParNoeudEtParHeure() throws {
        let lignes = Regroupement.lignes([Self.parent(0, "x"), Self.parent(10, "x"), Self.parent(20, "y"),
                                          Self.parent(50, "x"), Self.parent(59, "x"), Self.parent(70, "x")])
        try #require(lignes.map(\.evenements.count) == [1, 4, 1], "la plus recente d'abord : x a 70 min, x, y")
        guard case .parents(let groupe) = lignes[1] else {
            Issue.record("les 4 changements de x dans l'heure regroupes")
            return
        }
        #expect(groupe.map(\.date) == [0.0, 10, 50, 59].map { Self.t0.addingTimeInterval($0 * 60) })
        #expect(lignes[1].date == Self.t0.addingTimeInterval(59 * 60), "date du plus recent")
        #expect(lignes[1].id.hasPrefix("parents-"))
        #expect(lignes[0].evenements.first?.date == Self.t0.addingTimeInterval(70 * 60), "70 min : une autre fenetre")
        #expect(lignes[2].evenements.first?.sujet?.id == "y")
    }

    /// Evenement d'un appareil : `details["ieee"]` le designe, quel que soit l'id de son sujet.
    static func parent(_ minutes: Double, sujet: String, ieee: String?) -> Evenement {
        Evenement(date: t0.addingTimeInterval(minutes * 60), type: .parentChange, sujet: Sujet(id: sujet, nom: sujet),
                  avant: "A", apres: "B", details: ieee.map { ["ieee": $0] } ?? [:])
    }

    /// Avec une adresse longue, elle fait la cle : le meme appareil sous deux ids de sujet est une ligne, deux appareils
    /// sous un meme id de sujet sont deux lignes. Sans elle, l'id du sujet reste la cle.
    @Test func cleParAdresseLongue() {
        let b1 = "A0000000000000B1", b2 = "A0000000000000B2"
        let memeEnfant = Regroupement.lignes([Self.parent(0, sujet: "s1", ieee: b1),
                                              Self.parent(5, sujet: "s2", ieee: b1)])
        #expect(memeEnfant.map(\.evenements.count) == [2])
        let deuxEnfants = Regroupement.lignes([Self.parent(0, sujet: "s1", ieee: b1),
                                               Self.parent(5, sujet: "s1", ieee: b2)])
        #expect(deuxEnfants.map(\.evenements.count) == [1, 1])
        let anciens = Regroupement.lignes([Self.parent(0, sujet: "s1", ieee: nil),
                                           Self.parent(5, sujet: "s1", ieee: nil),
                                           Self.parent(6, sujet: "s2", ieee: nil)])
        #expect(anciens.map(\.evenements.count) == [1, 2], "par id de sujet")
    }

    /// La fenetre est de 1 h pleine : un changement a 59 min 59 s du premier est dans sa ligne, a
    /// 60 min pile il ouvre la suivante (comme les pertes a 10 min).
    @Test func borneExacteDeLHeure() {
        let dedans = Regroupement.lignes([Self.parent(0, "x"), Self.parent(59.98, "x")])
        #expect(dedans.map(\.evenements.count) == [2], "59 min 59 s : meme ligne")
        let pile = Regroupement.lignes([Self.parent(0, "x"), Self.parent(60, "x")])
        #expect(pile.map(\.evenements.count) == [1, 1], "60 min : une autre fenetre")
    }

    /// Les pertes restent regroupees a part, et les autres evenements passent tels quels.
    @Test func pertesInchangees() {
        let perte = { (minutes: Double, id: String) in
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .appareilDisparu, sujet: Sujet(id: id, nom: id))
        }
        let lignes = Regroupement.lignes([perte(0, "a"), Self.parent(1, "x"), perte(2, "b"), Self.parent(3, "x"),
                                          Evenement(date: Self.t0.addingTimeInterval(240), type: .sansParent)])
        #expect(lignes.count == 3)
        #expect(lignes.contains { if case .pertes(let p) = $0 { p.count == 2 } else { false } })
        #expect(lignes.contains { if case .parents(let p) = $0 { p.count == 2 } else { false } })
    }

    /// Les changements de chemin d'un meme routeur dans l'heure : une ligne a eux, sans se meler a ses changements de
    /// parent.
    @Test func cheminsRegroupes() throws {
        func chemin(_ minutes: Double) -> Evenement {
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .cheminChange, sujet: Sujet(id: "x", nom: "x"),
                      avant: "A", apres: "B", details: ["ieee": "x"])
        }
        let lignes = Regroupement.lignes([chemin(0), Self.parent(5, "x"), chemin(20), chemin(40)])
        try #require(lignes.count == 2)
        guard case .chemins(let groupe) = lignes[0] else {
            Issue.record("les 3 changements de chemin regroupes")
            return
        }
        #expect(groupe.count == 3 && lignes[0].id.hasPrefix("chemins-") && lignes[1].evenements.first?.type == .parentChange)
    }

    /// Resume des relais d'une ligne de changements : l'ancien relais du premier, puis le nouveau de chacun, dans l'ordre
    /// des dates et sans doublon ; le dernier relais est le nouveau du dernier changement.
    @Test func resumeDesRelais() {
        func chemin(_ minutes: Double, _ avant: String?, _ apres: String?) -> Evenement {
            Evenement(date: Self.t0.addingTimeInterval(minutes * 60), type: .cheminChange,
                      sujet: Sujet(id: "x", nom: "x"), avant: avant, apres: apres, details: ["ieee": "x"])
        }
        // Trois relais qui reviennent les uns aux autres : leur ordre de premiere apparition, sans doublon.
        let trois = Regroupement.resumeRelais([chemin(0, "A", "B"), chemin(10, "B", "C"), chemin(20, "C", "A"),
                                               chemin(30, "A", "C")])
        #expect(trois.relais == ["A", "B", "C"] && trois.dernier == "C" && !trois.alternent)
        // Deux relais qui alternent.
        let deux = Regroupement.resumeRelais([chemin(0, "A", "B"), chemin(5, "B", "A"), chemin(9, "A", "B"),
                                              chemin(12, "B", "A")])
        #expect(deux.relais == ["A", "B"] && deux.dernier == "A" && deux.alternent)
        // L'ordre des dates prime sur celui des evenements donnes.
        let melange = Regroupement.resumeRelais([chemin(10, "B", "C"), chemin(0, "A", "B")])
        #expect(melange.relais == ["A", "B", "C"] && melange.dernier == "C")
        // Noms absents ou vides ignores ; un seul changement ; aucun.
        let trous = Regroupement.resumeRelais([chemin(0, nil, "B"), chemin(5, "", "")])
        #expect(trous.relais == ["B"] && trous.dernier == nil && !trous.alternent)
        let un = Regroupement.resumeRelais([chemin(0, "A", "B")])
        #expect(un.relais == ["A", "B"] && un.dernier == "B" && un.alternent)
        let rien = Regroupement.resumeRelais([])
        #expect(rien.relais.isEmpty && rien.dernier == nil)
    }
}
