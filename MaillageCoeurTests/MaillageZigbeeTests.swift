import Foundation
import Testing
@testable import MaillageCoeur

@Suite("Maillage Zigbee : modele, qualite des liens, codage")
struct MaillageZigbeeTests {
    typealias I = NomsDemo.Ieee

    /// LQI -> qualite, a un seul endroit : 170 et plus, 3 ; 100 a 169, 2 ; 50 a 99, 1 ; sous 50, 0.
    @Test func qualiteLien() {
        let cas: [(Int, Int)] = [(255, 3), (170, 3), (169, 2), (100, 2), (99, 1), (50, 1), (49, 0), (0, 0)]
        for (lqi, q) in cas {
            #expect(QualiteLien.depuis(lqi: lqi) == q, "LQI \(lqi)")
        }
        #expect(QualiteLien.depuis(lqi: nil) == nil)
    }

    /// La qualite d'un lien radio : la moins bonne des deux mesures connues ; nil sans mesure.
    @Test func qualiteDUnLienRadio() {
        #expect(LienRadio(a: "A", b: "B", lqiA: 200, lqiB: 120).qualite == 2)
        #expect(LienRadio(a: "A", b: "B", lqiA: 40, lqiB: 250).qualite == 0)
        #expect(LienRadio(a: "A", b: "B", lqiA: nil, lqiB: 180).qualite == 3, "un seul sens")
        #expect(LienRadio(a: "A", b: "B").qualite == nil)
        #expect(LienParent(enfant: "E", parent: "P", lqi: 75).qualite == 1)
        #expect(LienParent(enfant: "E", parent: "P").qualite == nil)
    }

    /// Le lien mesure par l'un ou l'autre bout : `a` < `b` toujours ; la mesure va du bon cote.
    @Test func mesureParUnBout() {
        let l1 = LienRadio(mesurePar: "B", de: "A", lqi: 90)
        #expect(l1.a == "A" && l1.b == "B" && l1.lqiA == nil && l1.lqiB == 90)
        let l2 = LienRadio(mesurePar: "A", de: "B", lqi: 200)
        #expect(l2.a == "A" && l2.lqiA == 200 && l2.lqiB == nil)
        #expect(l1.autre(que: "A") == "B" && l1.autre(que: "C") == nil && l1.relie("B"))
    }

    /// Fusion des deux vues d'un meme lien : par sens, la mesure la plus recente ; une mesure datee passe avant une
    /// mesure sans date ; une mesure absente ne remplace rien.
    @Test func fusion() {
        let t0 = Date(timeIntervalSince1970: 1_791_000_000)
        let t1 = t0.addingTimeInterval(900)
        let ancien = LienRadio(a: "A", b: "B", lqiA: 200, lqiB: 180, dateA: t0, dateB: t1)
        let nouveau = LienRadio(a: "A", b: "B", lqiA: 120, lqiB: 90, dateA: t1, dateB: t0)
        let f = ancien.fusionner(nouveau)
        #expect(f.lqiA == 120 && f.dateA == t1, "a : la plus recente, la nouvelle")
        #expect(f.lqiB == 180 && f.dateB == t1, "b : la plus recente, l'ancienne")
        #expect(ancien.fusionner(LienRadio(a: "A", b: "B", lqiA: 60)).lqiA == 200, "datee avant non datee")
        #expect(ancien.fusionner(LienRadio(a: "A", b: "B")).lqiA == 200, "rien ne remplace")
        #expect(LienRadio(a: "A", b: "B", lqiA: 60).fusionner(LienRadio(a: "A", b: "B", lqiA: 70)).lqiA == 70,
                "sans date des deux cotes : la seconde")
        let reunis = MaillageZigbee.reunir([LienRadio(mesurePar: "B", de: "A", lqi: 90),
                                            LienRadio(mesurePar: "A", de: "B", lqi: 200),
                                            LienRadio(mesurePar: "C", de: "A", lqi: 30)])
        #expect(reunis.count == 2 && reunis[0].lqiA == 200 && reunis[0].lqiB == 90 && reunis[1].b == "C")
    }

    /// Ce que le maillage dit d'un noeud : son parent, ses liens, ses enfants, le coordinateur, le parent de la sonde,
    /// et le chemin du pont vers lui par sa table de routage.
    @Test func lecture() throws {
        let m = MaillageDemo.maillage
        #expect(m.coordinateur?.ieee == I.pont)
        #expect(m.parent(de: I.detecteurAbri)?.parent == I.priseTerrasse)
        #expect(m.parentSonde == I.lampeBureau)
        #expect(m.enfants(de: I.rubanCuisine).map(\.enfant) == [I.fuiteBuanderie])
        #expect(m.liens(de: I.pont).count == 4)
        #expect(m.noeud(court: 0x1A2B)?.ieee == I.plafonnierSalon)
        #expect(m.viaPont(vers: I.plafonnierSalon)?.ieee == I.plafonnierSalon, "voisin du pont : direct")
        #expect(m.viaPont(vers: I.ampouleEntree)?.ieee == I.plafonnierSalon)
        #expect(m.viaPont(vers: I.inconnu) == nil, "sans route")
        #expect(m.viaPont(vers: I.interrupteurSalon) == nil, "un appareil final n'a pas de route")
    }

    /// Codage : un maillage relu est le meme.
    @Test func codage() throws {
        let m = MaillageDemo.maillage
        let d = try CodageJSON.encodeur().encode(m)
        #expect(try CodageJSON.decodeur().decode(MaillageZigbee.self, from: d) == m)
        let n = NoeudZigbee(ieee: "A000000000000099", court: nil, type: .inconnu, muet: true)
        #expect(try CodageJSON.decodeur().decode(NoeudZigbee.self, from: CodageJSON.encodeur().encode(n)) == n)
    }
}
