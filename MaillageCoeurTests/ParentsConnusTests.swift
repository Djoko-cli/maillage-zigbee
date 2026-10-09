import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Dernier parent connu d'un appareil final : 24 h en pointilles")
struct ParentsConnusTests {
    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let pont = "A0000000000000A0"
    static let r1 = "A0000000000000A1"
    static let r2 = "A0000000000000A2"
    static let sonde = "A0000000000000FE"
    /// Le bouton endormi (adresse courte 3C4D, `ecoute` faux) et un autre appareil final.
    static let bouton = "A0000000000000B1"
    static let capteur = "A0000000000000B2"

    /// Le maillage a `minutes` : le pont et deux routeurs, la sonde sous R1 ; `enfants` : appareil final -> routeur
    /// (l'appareil est un noeud, au recepteur eteint, et lit sous ce parent a la date de la tournee) ; `tables` : date
    /// des tables dont viennent ces liens (par defaut, la tournee).
    static func maillage(_ minutes: Double, enfants: [String: String] = [:], routeurs: [String] = [r1, r2],
                         tables: Date? = nil) -> MaillageZigbee {
        let date = t0.addingTimeInterval(minutes * 60)
        let lecture = tables ?? date
        var noeuds = [NoeudZigbee(ieee: pont, court: 0, type: .coordinateur)]
        noeuds += routeurs.enumerated().map { NoeudZigbee(ieee: $1, court: UInt16(0x1000 + $0), type: .routeur) }
        noeuds += enfants.keys.sorted().map { NoeudZigbee(ieee: $0, court: $0 == bouton ? 0x3C4D : 0x3C4E, type: .final,
                                                            ecoute: false) }
        noeuds.append(NoeudZigbee(ieee: sonde, court: 0x3C4F, type: .final, ecoute: true))
        var parents = enfants.sorted { $0.key < $1.key }
            .map { LienParent(enfant: $0.key, parent: $0.value, lqi: 150, date: lecture) }
        parents.append(LienParent(enfant: sonde, parent: r1, lqi: 200, date: date))
        return MaillageZigbee(date: date, noeuds: noeuds.sorted { $0.ieee < $1.ieee }, parents: parents, sonde: sonde,
                              dateTables: lecture)
    }

    /// Un appareil final absent des dernieres tables garde son parent d'avant, 40 min apres : un lien « d'avant » de la
    /// date de sa table, le noeud (appareil final endormi, adresse courte) qui manquait, et rien d'autre de change.
    @Test func parentGardeQuaranteMinutes() throws {
        var p = ParentsConnus()
        p.retenir(Self.maillage(0, enfants: [Self.bouton: Self.r1]))
        let suivant = Self.maillage(40)
        p.retenir(suivant)
        let m = p.completer(suivant)
        let lien = try #require(m.parent(de: Self.bouton))
        #expect(lien.dAvant && lien.parent == Self.r1 && lien.date == Self.t0 && lien.lqi == 150)
        let n = try #require(m.noeud(Self.bouton))
        #expect(n.type == .final && n.court == 0x3C4D && n.ecoute == false && n.endormi, "son role reste appareil final")
        #expect(m.prochainSaut(de: Self.bouton) == Self.r1)
        #expect(m.parents.map(\.enfant) == [Self.bouton, Self.sonde] && m.noeuds.map(\.ieee) == m.noeuds.map(\.ieee).sorted())
        #expect(m.parent(de: Self.sonde)?.dAvant == false, "la sonde garde son lien lu")
        #expect(m.liens == suivant.liens && m.chemins == suivant.chemins && m.date == suivant.date)
        // Le graphe trace ce lien en pointilles (« suppose ») ; un lien lu ne l'est pas.
        let g = GrapheReseau(maillage: m, appareils: [])
        #expect(g.liens.filter { $0.genre == .parent }.map(\.suppose) == [true, false])
        #expect(g.parent(de: Self.bouton) == Self.r1)
        // Rien a ajouter si on le refait.
        #expect(p.completer(m) == m)
    }

    /// 24 h pile, c'est encore le parent d'avant ; au-dela, l'appareil n'a plus de parent ni de noeud : le comportement
    /// d'avant.
    @Test func parentPerduApresVingtQuatreHeures() {
        var p = ParentsConnus()
        p.retenir(Self.maillage(0, enfants: [Self.bouton: Self.r1]))
        let limite = Self.maillage(24 * 60)
        #expect(p.completer(limite).parent(de: Self.bouton)?.dAvant == true)
        let apres = Self.maillage(24 * 60 + 1)
        #expect(p.completer(apres) == apres, "plus de parent, et plus de noeud")
        #expect(p.completer(apres).noeud(Self.bouton) == nil)
        // Les 24 h comptent depuis la table qui l'a lu, pas depuis la derniere tournee ni depuis le releve.
        var q = ParentsConnus()
        q.retenir(Self.maillage(60, enfants: [Self.bouton: Self.r1], tables: Self.t0))
        #expect(q.completer(Self.maillage(24 * 60)).parent(de: Self.bouton)?.dAvant == true)
        #expect(q.completer(Self.maillage(24 * 60 + 1)).parent(de: Self.bouton) == nil)
    }

    /// Un parent lu dans les tables l'emporte, et change le dernier parent connu ; un parent d'avant n'en rafraichit
    /// pas la date.
    @Test func parentLuPrime() throws {
        var p = ParentsConnus()
        p.retenir(Self.maillage(0, enfants: [Self.bouton: Self.r1]))
        let lu = Self.maillage(60, enfants: [Self.bouton: Self.r2])
        p.retenir(lu)
        #expect(p.completer(lu) == lu, "rien d'ajoute : ses tables le donnent")
        let absent = Self.maillage(120)
        p.retenir(absent)
        let m = p.completer(absent)
        #expect(m.parent(de: Self.bouton)?.parent == Self.r2 && m.parent(de: Self.bouton)?.date == lu.date)
        // Retenir un maillage deja complete ne rajeunit pas le parent d'avant.
        p.retenir(m)
        let tard = Self.maillage(24 * 60 + 61)
        #expect(p.completer(tard).parent(de: Self.bouton) == nil, "24 h depuis la derniere table qui l'a lu")
    }

    /// Pas de parent d'avant : pour la sonde, pour un routeur, quand le parent n'est plus dans le maillage, ni avec une
    /// cle provisoire.
    @Test func casSansParentDAvant() {
        var p = ParentsConnus()
        var avant = Self.maillage(0, enfants: [Self.bouton: Self.r1, Self.capteur: Self.r2])
        avant.parents.append(LienParent(enfant: "~3C50", parent: Self.r1, lqi: 100, date: avant.date))
        p.retenir(avant)
        #expect(p.enfants == [Self.bouton, Self.capteur], "ni la sonde ni une cle provisoire")
        // R2 est parti du maillage : son enfant n'a plus de parent connu.
        let sansR2 = Self.maillage(30, routeurs: [Self.r1])
        let m = p.completer(sansR2)
        #expect(m.parent(de: Self.bouton)?.dAvant == true && m.parent(de: Self.capteur) == nil)
        // Devenu routeur : il n'est plus un appareil final.
        var routeur = Self.maillage(30)
        routeur.noeuds.append(NoeudZigbee(ieee: Self.bouton, court: 0x3C4D, type: .routeur))
        #expect(p.completer(routeur).parent(de: Self.bouton) == nil)
        // La sonde detachee ne se complete pas.
        var detachee = Self.maillage(30)
        detachee.parents.removeAll { $0.enfant == Self.sonde }
        #expect(p.completer(detachee).parent(de: Self.sonde) == nil)
    }

    /// Un noeud deja la, sans parent (liste par une table sans relation « enfant ») : il garde son role et gagne son
    /// parent d'avant, et son `ecoute` s'il n'en avait pas.
    @Test func noeudDejaLa() throws {
        var p = ParentsConnus()
        p.retenir(Self.maillage(0, enfants: [Self.bouton: Self.r1]))
        var m = Self.maillage(30)
        m.noeuds.append(NoeudZigbee(ieee: Self.bouton, court: 0x3C4D, type: .inconnu))
        m.noeuds.sort { $0.ieee < $1.ieee }
        let r = p.completer(m)
        #expect(r.noeuds.filter { $0.ieee == Self.bouton }.count == 1)
        #expect(r.noeud(Self.bouton)?.type == .final && r.noeud(Self.bouton)?.ecoute == false)
        #expect(r.parent(de: Self.bouton)?.dAvant == true)
    }

    /// Le releve de l'historique ne garde ni le parent d'avant ni le noeud qu'il a fait ajouter : l'historique ne le
    /// rendrait jamais perime ; on le retrouve pourtant au lancement dans les releves d'avant, a leur date.
    @Test func historique() throws {
        var p = ParentsConnus()
        let avant = Self.maillage(0, enfants: [Self.bouton: Self.r1])
        p.retenir(avant)
        let m = p.completer(Self.maillage(40))
        let r = ReleveMaillage(m)
        #expect(r.parents.map(\.enfant) == [Self.sonde] && !r.noeuds.contains { $0.ieee == Self.bouton })
        #expect(ReleveMaillage(avant).parents.map(\.enfant) == [Self.bouton, Self.sonde])
        // Au lancement : le dernier releve qui le portait, a sa date (ici 90 min avant le maillage).
        var lancement = ParentsConnus()
        lancement.retenir(ReleveMaillage(Self.maillage(-120, enfants: [Self.bouton: Self.capteur])))
        lancement.retenir(ReleveMaillage(Self.maillage(-90, enfants: [Self.bouton: Self.r1])))
        let relu = lancement.completer(Self.maillage(0))
        let lien = try #require(relu.parent(de: Self.bouton))
        #expect(lien.parent == Self.r1 && lien.dAvant && lien.date == Self.t0.addingTimeInterval(-90 * 60))
        #expect(relu.noeud(Self.bouton)?.type == .final && relu.noeud(Self.bouton)?.court == nil)
        // Un releve de plus de 24 h ne tient pas lieu de parent.
        var ancien = ParentsConnus()
        ancien.retenir(ReleveMaillage(Self.maillage(-25 * 60, enfants: [Self.bouton: Self.r1])))
        #expect(ancien.completer(Self.maillage(0)).parent(de: Self.bouton) == nil)
        // Un releve ne remplace pas ce que la session sait de l'appareil (adresse courte, ecoute) pour le meme parent.
        var session = ParentsConnus()
        session.retenir(Self.maillage(-30, enfants: [Self.bouton: Self.r1]))
        session.retenir(ReleveMaillage(Self.maillage(-20, enfants: [Self.bouton: Self.r1])))
        #expect(session.completer(Self.maillage(0)).noeud(Self.bouton)?.court == 0x3C4D)
        // Et un releve plus ancien ne remplace pas un parent plus recent.
        session.retenir(ReleveMaillage(Self.maillage(-50, enfants: [Self.bouton: Self.r2])))
        #expect(session.completer(Self.maillage(0)).parent(de: Self.bouton)?.parent == Self.r1)
    }

    /// Aucun evenement de journal pendant les 24 h : ni « sans parent » ni « a change de parent ». Au-dela, le comportement
    /// d'avant : deux tournees d'absence, puis « n'a plus de parent » ; son retour ensuite est un « revenu ».
    @Test func journalSilencieuxPendantLeDelai() throws {
        var parents = ParentsConnus()
        var suivi = SuiviMaillage()
        func tourner(_ minutes: Double, parent: Int? = nil) -> [Evenement] {
            let m = SuiviMaillageTests.maillage(minutes, enfants: parent.map { [1: $0] } ?? [:])
            parents.retenir(m)
            return suivi.integrer(parents.completer(m), nom: SuiviMaillageTests.nom)
        }
        // Le bouton B1 sous le routeur 1, puis absent des tables, tournee apres tournee, pendant 24 h.
        #expect(tourner(0, parent: 1).map(\.type) == [.surveillanceDemarree])
        var evenements: [Evenement] = []
        for minutes in stride(from: 15.0, through: 24 * 60, by: 15) { evenements += tourner(minutes) }
        #expect(evenements.isEmpty, "\(evenements.map(\.type))")
        // Plus de parent d'avant : deux tournees d'absence, puis « sans parent ».
        #expect(tourner(24 * 60 + 15).isEmpty)
        let perte = try #require(tourner(24 * 60 + 30).first)
        #expect(perte.type == .sansParent && perte.avant == "A1" && perte.sujet?.id == SuiviMaillageTests.appareil(1))
        #expect(tourner(24 * 60 + 45).isEmpty)
        // Son retour sous un autre parent : « revenu ».
        #expect(tourner(24 * 60 + 60, parent: 2).map(\.type) == [.appareilRevenu])
    }

    /// Un appareil qui change vraiment de parent pendant ce delai le fait savoir : ses tables le donnent sous l'autre.
    @Test func vraiChangementDeParent() throws {
        var parents = ParentsConnus()
        var suivi = SuiviMaillage()
        func tourner(_ m: MaillageZigbee) -> [Evenement] {
            parents.retenir(m)
            return suivi.integrer(parents.completer(m), nom: SuiviMaillageTests.nom)
        }
        _ = tourner(SuiviMaillageTests.maillage(0, enfants: [1: 1]))
        #expect(tourner(SuiviMaillageTests.maillage(15)).isEmpty, "absent : parent d'avant, rien")
        let ev = tourner(SuiviMaillageTests.maillage(30, enfants: [1: 2]))
        #expect(ev.map(\.type) == [.parentChange] && ev.first?.avant == "A1" && ev.first?.apres == "A2")
    }

    /// Le lien d'avant se code et se decode ; un lien lu s'ecrit comme avant (sans la cle) et se lit sans elle.
    @Test func codage() throws {
        let lu = LienParent(enfant: Self.bouton, parent: Self.r1, lqi: 150, date: Self.t0)
        let davant = LienParent(enfant: Self.bouton, parent: Self.r1, lqi: 150, date: Self.t0, dAvant: true)
        let encodeur = CodageJSON.encodeur()
        let json = try String(decoding: encodeur.encode(lu), as: UTF8.self)
        #expect(!json.contains("dAvant"))
        #expect(try CodageJSON.decodeur().decode(LienParent.self, from: Data(json.utf8)) == lu)
        let json2 = try encodeur.encode(davant)
        #expect(try CodageJSON.decodeur().decode(LienParent.self, from: json2) == davant)
        #expect(String(decoding: json2, as: UTF8.self).contains("\"dAvant\":true"))
        // Un maillage ecrit et relu garde son parent d'avant.
        var p = ParentsConnus()
        p.retenir(Self.maillage(0, enfants: [Self.bouton: Self.r1]))
        let m = p.completer(Self.maillage(40))
        #expect(try CodageJSON.decodeur().decode(MaillageZigbee.self, from: encodeur.encode(m)) == m)
    }
}
