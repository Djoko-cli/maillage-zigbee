import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Suivi du maillage : routeurs, appareils, parents")
struct SuiviMaillageTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let pont = "A0000000000000A0"
    static let sonde = "A0000000000000FE"

    static func routeur(_ k: Int) -> String { String(format: "A0000000000000A%X", k) }
    static func appareil(_ k: Int) -> String { String(format: "A0000000000000B%X", k) }

    /// Maillage a `minutes` : le pont et les routeurs `routeurs` ; `enfants` : appareil -> son routeur ; la sonde sous
    /// le routeur 1 ; `muets` : routeurs dont la table n'a pas ete lue.
    static func maillage(_ minutes: Double, routeurs: [Int] = [1, 2], enfants: [Int: Int] = [:],
                         muets: Set<Int> = []) -> MaillageZigbee {
        let date = t0.addingTimeInterval(minutes * 60)
        var noeuds = [NoeudZigbee(ieee: pont, court: 0, type: .coordinateur)]
        noeuds += routeurs.map { NoeudZigbee(ieee: routeur($0), type: .routeur, muet: muets.contains($0)) }
        noeuds += enfants.keys.sorted().map { NoeudZigbee(ieee: appareil($0), type: .final) }
        noeuds.append(NoeudZigbee(ieee: sonde, type: .final))
        var parents = enfants.map { LienParent(enfant: appareil($0.key), parent: routeur($0.value), lqi: 180, date: date) }
        parents.append(LienParent(enfant: sonde, parent: routeur(1), lqi: 200, date: date))
        return MaillageZigbee(date: date, noeuds: noeuds, parents: parents, sonde: sonde)
    }

    /// Le nom d'un noeud : « R1 », « B3 » (la fin de son adresse longue).
    static func nom(_ ieee: String) -> String { String(ieee.suffix(2)) }

    static func suivre(_ maillages: [MaillageZigbee]) -> [[Evenement]] {
        var s = SuiviMaillage()
        return maillages.map { s.integrer($0, nom: nom) }
    }

    /// Le premier maillage est un point de depart : le demarrage, avec ses routeurs (hors pont) et ses appareils.
    @Test func pointDeDepart() throws {
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 1, 2: 2])])
        try #require(ev[0].count == 1)
        #expect(ev[0][0].type == .surveillanceDemarree)
        #expect(ev[0][0].details == ["routeurs": "2", "appareils": "3"], "deux appareils et la sonde")
    }

    /// Un routeur qui entre dans le maillage, ou qui en sort ; le pont n'est jamais ni l'un ni l'autre.
    @Test func routeursApparusEtDisparus() {
        let ev = Self.suivre([Self.maillage(0), Self.maillage(15, routeurs: [1, 3]), Self.maillage(30, routeurs: [1, 3])])
        #expect(ev[1].map(\.type) == [.routeurApparu, .routeurDisparu])
        #expect(ev[1].map { $0.sujet?.id } == [Self.routeur(3), Self.routeur(2)])
        #expect(ev[1].allSatisfy { $0.details["ieee"] == $0.sujet?.id && $0.date == Self.t0.addingTimeInterval(900) })
        #expect(ev[1][1].gravite == .alerte)
        #expect(ev[2].isEmpty)
    }

    /// Un appareil sous un autre parent : « a change de parent : A → B », par son adresse longue.
    @Test func changementDeParent() throws {
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 1]), Self.maillage(15, enfants: [1: 2])])
        let e = try #require(ev[1].first)
        #expect(ev[1].count == 1 && e.type == .parentChange)
        #expect(e.sujet == Sujet(id: Self.appareil(1), nom: "B1") && e.avant == "A1" && e.apres == "A2")
        #expect(e.details == ["ieee": Self.appareil(1)])
    }

    /// Un appareil vu pour la premiere fois apres le depart : « nouveau », sous son parent.
    @Test func appareilNouveau() throws {
        let ev = Self.suivre([Self.maillage(0), Self.maillage(15, enfants: [4: 2])])
        let e = try #require(ev[1].first)
        #expect(ev[1].count == 1 && e.type == .appareilNouveau && e.apres == "A2")
    }

    /// Absent de deux tournees de suite : « n'a plus de parent », une seule fois, nommant son dernier parent ; son retour
    /// ensuite : « revenu ».
    @Test func sansParentPuisRevenu() throws {
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 1]), Self.maillage(15), Self.maillage(30),
                              Self.maillage(45), Self.maillage(60, enfants: [1: 2])])
        #expect(ev[1].isEmpty, "une absence : on attend")
        let perte = try #require(ev[2].first)
        #expect(ev[2].count == 1 && perte.type == .sansParent && perte.avant == "A1" && perte.gravite == .attention)
        #expect(ev[3].isEmpty, "une seule fois")
        #expect(ev[4].map(\.type) == [.appareilRevenu] && ev[4].first?.apres == "A2")
    }

    /// Une absence sous un parent muet ne compte pas (on ne sait pas) ; la suivante, parent lu, compte.
    @Test func absenceSousUnParentMuet() {
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 2]), Self.maillage(15, muets: [2]), Self.maillage(30, muets: [2]),
                              Self.maillage(45), Self.maillage(60)])
        #expect(ev[1].isEmpty && ev[2].isEmpty, "parent muet")
        #expect(ev[3].isEmpty, "premiere absence comptee")
        #expect(ev[4].map(\.type) == [.sansParent])
    }

    /// Un maillage incomplet (la sonde a quitte le reseau pendant la tournee) : ni depart de routeur, ni absence ; un
    /// routeur nouveau y apparait quand meme. Le maillage complet suivant compare a tous les routeurs connus.
    @Test func maillageIncomplet() {
        var incomplet = Self.maillage(15, routeurs: [1, 3])
        incomplet.complet = false
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 2]), incomplet, incomplet, Self.maillage(45, routeurs: [1, 3])])
        #expect(ev[1].map(\.type) == [.routeurApparu] && ev[1].first?.sujet?.id == Self.routeur(3))
        #expect(ev[2].isEmpty, "ni routeur disparu, ni absence de l'appareil")
        #expect(ev[3].map(\.type) == [.routeurDisparu], "R2 n'est vu absent qu'une fois la tournee complete")
    }

    /// Un routeur connu seulement par une route (cle provisoire `~7F80`) est au maillage quand ses routes sont relues, et
    /// manque sinon : ni « apparu » ni « disparu », meme dans un maillage complet ; les routeurs connus restent suivis.
    @Test func routeurProvisoireNiApparuNiDisparu() {
        func avecProvisoire(_ m: MaillageZigbee) -> MaillageZigbee {
            var r = m
            r.noeuds.append(NoeudZigbee(ieee: NoeudZigbee.cleProvisoire(court: 0x7F80), court: 0x7F80, type: .routeur))
            return r
        }
        let ev = Self.suivre([Self.maillage(0), avecProvisoire(Self.maillage(15)), Self.maillage(30),
                              avecProvisoire(Self.maillage(45)), Self.maillage(60, routeurs: [1])])
        #expect(ev[1].isEmpty && ev[2].isEmpty && ev[3].isEmpty, "la cle provisoire n'est pas suivie")
        #expect(ev[4].map(\.type) == [.routeurDisparu] && ev[4].first?.sujet?.id == Self.routeur(2))
        // Present des le point de depart, puis absent : rien non plus.
        let depart = Self.suivre([avecProvisoire(Self.maillage(0)), Self.maillage(15)])
        #expect(depart[1].isEmpty)
    }

    /// Une absence sous un parent dont la table n'a pas ete lue (sans reponse une fois) ne compte pas.
    @Test func absenceSousUnParentNonLu() {
        var nonLu = Self.maillage(15)
        if let i = nonLu.noeuds.firstIndex(where: { $0.ieee == Self.routeur(2) }) { nonLu.noeuds[i].tableNonLue = true }
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 2]), nonLu, nonLu, Self.maillage(45)])
        #expect(ev[1].isEmpty && ev[2].isEmpty && ev[3].isEmpty, "une seule absence comptee")
    }

    /// La sonde n'est jamais « sans parent » ; un appareil devenu routeur n'est plus suivi comme appareil.
    @Test func sondeEtAppareilDevenuRouteur() {
        var sansSonde = Self.maillage(15, enfants: [1: 1])
        sansSonde.parents.removeAll { $0.enfant == Self.sonde }
        var devenu = Self.maillage(30, routeurs: [1, 2])
        devenu.noeuds.append(NoeudZigbee(ieee: Self.appareil(1), type: .routeur))
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 1]), sansSonde, Self.maillage(30), devenu, devenu])
        #expect(ev.joined().allSatisfy { $0.sujet?.id != Self.sonde }, "jamais la sonde")
        #expect(!ev.joined().contains { $0.type == .sansParent }, "l'appareil devenu routeur n'est pas perdu")
    }

    /// La veille du Mac : un evenement date de la fin de la veille, avec sa periode.
    @Test func veille() {
        let periode = DateInterval(start: Self.t0, duration: 3600)
        let ev = SuiviMaillage().noterVeille(periode)
        #expect(ev.map(\.type) == [.veille] && ev.first?.periode == periode && ev.first?.date == periode.end)
    }

    /// Les changements de parent repetes d'un meme appareil font une ligne du journal.
    @Test func unAppareilQuiOscilleFaitUneLigne() {
        let ev = Self.suivre([Self.maillage(0, enfants: [1: 1]), Self.maillage(15, enfants: [1: 2]),
                              Self.maillage(30, enfants: [1: 1]), Self.maillage(45, enfants: [1: 2])])
        let lignes = Regroupement.lignes(Array(ev.joined()))
        #expect(lignes.contains { if case .parents(let p) = $0 { p.count == 3 } else { false } })
    }

    /// Les chemins vers le pont : « a change de chemin : A → B » quand un routeur passe par un autre prochain saut lu ;
    /// un chemin suppose n'en donne pas (le dernier lu reste la reference) ; un maillage incomplet non plus.
    @Test func changementDeChemin() throws {
        func avecChemins(_ m: MaillageZigbee, _ chemins: [CheminPont], complet: Bool = true) -> MaillageZigbee {
            var r = m
            r.chemins = chemins
            r.complet = complet
            return r
        }
        let r1 = Self.routeur(1), r2 = Self.routeur(2)
        let ev = Self.suivre([
            avecChemins(Self.maillage(0), [CheminPont(routeur: r1, prochain: Self.pont), CheminPont(routeur: r2, prochain: r1)]),
            avecChemins(Self.maillage(15), [CheminPont(routeur: r1, prochain: Self.pont),
                                            CheminPont(routeur: r2, prochain: Self.pont, actif: false, suppose: true)]),
            avecChemins(Self.maillage(30), [CheminPont(routeur: r1, prochain: r2), CheminPont(routeur: r2, prochain: r1)],
                        complet: false),
            avecChemins(Self.maillage(45), [CheminPont(routeur: r1, prochain: Self.pont), CheminPont(routeur: r2, prochain: Self.pont)]),
        ])
        #expect(ev[1].isEmpty, "un chemin suppose ne change rien")
        #expect(ev[2].isEmpty, "maillage incomplet")
        let e = try #require(ev[3].first)
        #expect(ev[3].count == 1 && e.type == .cheminChange && e.gravite == .info)
        #expect(e.sujet == Sujet(id: r2, nom: "A2") && e.avant == "A1" && e.apres == "A0" && e.details == ["ieee": r2])
    }
}
