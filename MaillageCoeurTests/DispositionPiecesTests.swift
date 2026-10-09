import Foundation
import simd
import Testing
@testable import MaillageCoeur

@Suite("Scene : disposition des pieces")
struct DispositionPiecesTests {
    /// Paires de cartes d'un meme etage qui se recouvrent, ecarts `gap` et `lab` compris (a 1e-6 pres).
    static func recouvrements(_ s: ScenePieces, _ c: [CartesPieces.Carte], _ d: DispositionPieces) -> [String] {
        var r: [String] = []
        for e in s.etages {
            for (k, a) in e.pieces.enumerated() {
                for b in e.pieces[(k + 1)...] {
                    let dx = d.positions[b].x - d.positions[a].x, dz = d.positions[b].y - d.positions[a].y
                    let px = (c[a].largeur + c[b].largeur) / 2 + DispositionPieces.gap - abs(dx)
                    let pz = (c[a].profondeur + c[b].profondeur) / 2 + DispositionPieces.gap + DispositionPieces.lab - abs(dz)
                    if px > 1e-6 && pz > 1e-6 { r.append("\(s.pieces[a].id) / \(s.pieces[b].id)") }
                }
            }
        }
        return r
    }

    /// Maison inventee : 8 pieces, 30 appareils, 4 routeurs ; aucun recouvrement, chaque carte dans son
    /// plateau, et le cout retenu au plus celui du depart.
    @Test func aucunRecouvrement() {
        let (s, c) = MaisonInventee.scene(pieces: 8, appareils: 30, routeurs: 4)
        let d = DispositionPieces(scene: s, cartes: c)
        #expect(Self.recouvrements(s, c, d) == [])
        #expect(d.rayons.count == s.etages.count)
        for (i, p) in s.pieces.enumerated() {
            let coin = SIMD2(abs(d.positions[i].x) + c[i].largeur / 2, abs(d.positions[i].y) + c[i].profondeur / 2)
            #expect((coin.x * coin.x + coin.y * coin.y).squareRoot() <= d.rayons[p.etage], "\(p.id) dans son plateau")
        }
        #expect(d.cout <= d.coutDepart)
        #expect(d.coups > 0 && d.coups <= DispositionPieces.budget)
    }

    /// Memes entrees, meme disposition.
    @Test func deterministe() {
        let (s, c) = MaisonInventee.scene(pieces: 6, appareils: 20, routeurs: 3)
        let a = DispositionPieces(scene: s, cartes: c)
        let b = DispositionPieces(scene: s, cartes: c)
        #expect(a == b)
    }

    /// Une piece fixee ne bouge pas, et sert d'obstacle : les autres se placent sans la recouvrir, ni
    /// se recouvrir entre elles. Tout fixe : aucune optimisation.
    @Test func pieceFixee() {
        let (s, c) = MaisonInventee.scene(pieces: 6, appareils: 20, routeurs: 3)
        let place = SIMD2(4.5, -3.0)
        let d = DispositionPieces(scene: s, cartes: c, fixees: [0: place])
        #expect(d.positions[0] == place)
        #expect(Self.recouvrements(s, c, d) == [])
        let toutes = Dictionary(uniqueKeysWithValues: d.positions.enumerated().map { ($0, $1) })
        let figee = DispositionPieces(scene: s, cartes: c, fixees: toutes)
        #expect(figee.positions == d.positions)
        #expect(figee.coups == 0)
    }

    /// Pieces fixees d'un tirage : piece `i` fixee au tirage `k` pour `pourcent` %, par un hachage
    /// entier deterministe (aucun hasard).
    static func fixee(_ i: Int, tirage k: Int, pourcent: Int) -> Bool {
        var h = UInt32(truncatingIfNeeded: i &* 73 &+ k &* 1009 &+ 17)
        h ^= h >> 13
        h = h &* 0x5bd1e995
        h ^= h >> 15
        return Int(h % 100) < pourcent
    }

    /// Une seule piece libre (nouvelle ou renommee), toutes les autres fixees a une disposition
    /// valide : la libre se place sans recouvrement, et aucune fixee ne bouge. Chaque piece tour a
    /// tour, sur la maison de 8 pieces et sur celle de 20.
    @Test(arguments: [(8, 30, 4), (20, 100, 6)])
    func uneSeuleLibre(_ maison: (Int, Int, Int)) {
        let np = maison.0
        let (s, c) = MaisonInventee.scene(pieces: np, appareils: maison.1, routeurs: maison.2)
        let base = DispositionPieces(scene: s, cartes: c)
        #expect(Self.recouvrements(s, c, base) == [])
        for libre in 0..<np {
            var fixees: [Int: SIMD2<Double>] = [:]
            for i in 0..<np where i != libre { fixees[i] = base.positions[i] }
            let d = DispositionPieces(scene: s, cartes: c, fixees: fixees)
            #expect(Self.recouvrements(s, c, d) == [], "libre \(libre)")
            for (i, p) in fixees { #expect(d.positions[i] == p, "fixee \(i), libre \(libre)") }
        }
    }

    /// Sous-ensembles deterministes de pieces fixees a une disposition valide (10 tirages par
    /// maison) : aucun recouvrement, et aucune fixee ne bouge.
    @Test(arguments: [10, 30, 50, 80])
    func piecesFixees(_ pourcent: Int) {
        for (np, na, nr) in [(8, 30, 4), (12, 50, 4), (20, 100, 6)] {
            let (s, c) = MaisonInventee.scene(pieces: np, appareils: na, routeurs: nr)
            let base = DispositionPieces(scene: s, cartes: c)
            for k in 0..<10 {
                var fixees: [Int: SIMD2<Double>] = [:]
                for i in 0..<np where Self.fixee(i, tirage: k, pourcent: pourcent) { fixees[i] = base.positions[i] }
                if fixees.isEmpty || fixees.count == np { continue }
                let d = DispositionPieces(scene: s, cartes: c, fixees: fixees)
                #expect(Self.recouvrements(s, c, d) == [], "\(np) pieces, tirage \(k)")
                for (i, p) in fixees { #expect(d.positions[i] == p, "\(np) pieces, tirage \(k), fixee \(i)") }
            }
        }
    }

    /// Cas sans solution : deux fixees qui se recouvrent entre elles. Le calcul se termine, les
    /// fixees ne bougent pas, et les libres ne recouvrent aucune carte ; seul reste le recouvrement
    /// des deux fixees.
    @Test func fixeesQuiSeRecouvrent() {
        let (s, c) = MaisonInventee.scene(pieces: 6, appareils: 20, routeurs: 3)
        let a = s.etages[0].pieces[0], b = s.etages[0].pieces[1]
        let fixees = [a: SIMD2(0.0, 0.0), b: SIMD2(0.5, 0.5)]
        let d = DispositionPieces(scene: s, cartes: c, fixees: fixees)
        #expect(Self.recouvrements(s, c, d) == ["\(s.pieces[a].id) / \(s.pieces[b].id)"])
        #expect(d.positions[a] == fixees[a] && d.positions[b] == fixees[b])
    }

    /// Budget : au plus `budget` coups ; le resultat reste sans recouvrement, et au plus le cout du depart.
    @Test func budget() {
        let (s, c) = MaisonInventee.scene(pieces: 8, appareils: 30, routeurs: 4)
        let d = DispositionPieces(scene: s, cartes: c, budget: 40)
        #expect(d.coups == 40)
        #expect(Self.recouvrements(s, c, d) == [])
        #expect(d.cout <= d.coutDepart)
    }

    /// Un cout non fini, venu d'une carte de largeur infinie (une entree que l'app ne donne pas : elle
    /// mesure ses noms) : aucun depart n'est retenu, et la disposition garde son depart, celui d'avant
    /// l'optimisation (la spirale du premier essai), sans arret du programme.
    @Test func coutNonFini() {
        let (s, cartes) = MaisonInventee.scene(pieces: 6, appareils: 20, routeurs: 3)
        var c = cartes
        c[0].largeur = .infinity
        let d = DispositionPieces(scene: s, cartes: c)
        #expect(d.positions == DispositionPieces.Calcul(scene: s, cartes: c, fixees: [:]).depart(0, fixees: [:]))
        #expect(d.rayons.count == s.etages.count)
        #expect(!d.cout.isFinite && !d.coutDepart.isFinite)
    }

    /// Une place fixee demesuree (1e308 : `PlacesGardees.fixees` l'ignore, un autre appelant pourrait la
    /// donner) rend le rayon de son etage infini : le meme repli sur le depart, la fixee a sa place.
    @Test func placeFixeeDemesuree() {
        let (s, c) = MaisonInventee.scene(pieces: 6, appareils: 20, routeurs: 3)
        let fixees = [0: SIMD2(1e308, 0.0)]
        let d = DispositionPieces(scene: s, cartes: c, fixees: fixees)
        #expect(d.positions == DispositionPieces.Calcul(scene: s, cartes: c, fixees: fixees).depart(0, fixees: fixees))
        #expect(d.positions[0] == fixees[0])
        #expect(!d.cout.isFinite)
    }

    /// Plateaux cote a cote en 2D : `esp` entre les bords de deux voisins, la rangee centree sur x = 0.
    @Test func centres2D() {
        let x = DispositionPieces.centres2D(rayons: [10, 4, 6])
        #expect(abs((x[1] - 4) - (x[0] + 10) - DispositionPieces.esp) < 1e-9)
        #expect(abs((x[2] - 6) - (x[1] + 4) - DispositionPieces.esp) < 1e-9)
        #expect(abs((x[0] - 10) + (x[2] + 6)) < 1e-9)
        #expect(DispositionPieces.centres2D(rayons: [7]) == [0])
    }

    /// Temps de calcul, en Release : sur une grande maison inventee (20 pieces, 100 appareils, 6
    /// routeurs de bordure), la disposition tient sous 1 s.
    @Test(.enabled(if: Compilation.optimisee, "mesure en Release (outils/mesurer.sh)"))
    func tempsGrandeMaison() {
        let (s, c) = MaisonInventee.scene(pieces: 20, appareils: 100, routeurs: 6)
        #expect(s.pieces.count == 20 && s.noeuds.count == 106)
        let debut = DispatchTime.now().uptimeNanoseconds
        let d = DispositionPieces(scene: s, cartes: c)
        let secondes = Double(DispatchTime.now().uptimeNanoseconds - debut) / 1e9
        print("mesure : disposition de la grande maison en \(secondes) s, \(d.coups) coups")
        #expect(secondes < 1, "\(secondes) s pour \(d.coups) coups")
        #expect(Self.recouvrements(s, c, d) == [])
    }

    /// Le cout du plan 4b, recopie tel qu'il etait : la vue 2D des etages cote a cote (`centres2D`), tous les
    /// liens, toutes les cartes, tous les croisements.
    static func coutDuPlan4b(_ k: DispositionPieces.Calcul, _ pos: [SIMD2<Double>]) -> Double {
        let rayons = (0..<k.nbEtages).map { k.rayon(pos, $0) }
        let cx = DispositionPieces.centres2D(rayons: rayons)
        let rects = pos.indices.map { i in
            let x = cx[k.etage[i]] + pos[i].x, z = pos[i].y
            return DispositionPieces.Rect(x0: x - k.w[i] / 2, x1: x + k.w[i] / 2, z0: z - k.d[i] / 2 - DispositionPieces.lab,
                                          z1: z + k.d[i] / 2)
        }
        let segments = k.liens.map { l in
            (SIMD2(cx[k.etage[l.pa]], 0) + pos[l.pa] + l.la, SIMD2(cx[k.etage[l.pb]], 0) + pos[l.pb] + l.lb)
        }
        var c = rayons.reduce(0, +)
        for (n, l) in k.liens.enumerated() {
            let (p, q) = segments[n]
            let dl = q - p
            c += 0.3 * (dl.x * dl.x + dl.y * dl.y).squareRoot()
            for (r, rect) in rects.enumerated() where r != l.pa && r != l.pb {
                let t = DispositionPieces.dedans(p, q, rect)
                if t > 0 { c += 6 + 4 * t }
            }
            if k.etage[l.pa] != k.etage[l.pb] {
                let h = (pos[l.pa] + l.la) - (pos[l.pb] + l.lb)
                c += 0.1 * (h.x * h.x + h.y * h.y).squareRoot()
            }
        }
        for i in k.liens.indices {
            let s = k.liens[i], (p, q) = segments[i]
            for j in k.liens.indices where j > i {
                let t = k.liens[j]
                if s.na == t.na || s.na == t.nb || s.nb == t.na || s.nb == t.nb { continue }
                let (r, u) = segments[j]
                if max(p.x, q.x) < min(r.x, u.x) || max(r.x, u.x) < min(p.x, q.x)
                    || max(p.y, q.y) < min(r.y, u.y) || max(r.y, u.y) < min(p.y, q.y) { continue }
                if DispositionPieces.croise(p, q, r, u) { c += 5 }
            }
        }
        return c
    }

    /// Pour une maison d'un seul plateau, le cout de reference (polissage C, section 4) est celui du plan 4b, au
    /// bit pres : au depart de chaque essai, et sur la disposition retenue, qui est donc la meme.
    @Test func coutDUnSeulPlateau() {
        let (s, c) = MaisonInventee.scene(pieces: 8, appareils: 30, routeurs: 4, unSeulPlateau: true)
        #expect(s.etages.count == 1)
        let k = DispositionPieces.Calcul(scene: s, cartes: c, fixees: [:])
        let d = DispositionPieces(scene: s, cartes: c)
        for pos in (0..<DispositionPieces.departs).map({ k.depart($0, fixees: [:]) }) + [d.positions] {
            #expect(k.cout(pos) == Self.coutDuPlan4b(k, pos))
        }
        #expect(d.cout == Self.coutDuPlan4b(k, d.positions))
    }

    /// La vue de reference du cout (polissage C, section 4) : chaque niveau est une rangee, son etage principal en
    /// x = 0, ses zones a cote a droite, l'une apres l'autre, `esp` entre les bords. Un lien entre deux niveaux ne
    /// coute que 0,1 fois son ecart horizontal : ni longueur, ni carte traversee, ni croisement ; un lien du meme
    /// niveau, entre un etage et sa zone a cote, coute 0,3 fois sa longueur dans cette vue. Le niveau de chaque piece
    /// est ecrit a la main ; le decalage de chaque plateau et les extremites des liens sont recalcules a part, sans
    /// `vueReference` : l'attendu ne suit pas une erreur du code juge. Des positions ou un lien du niveau coupe un
    /// lien entre niveaux montrent que ce croisement ne coute rien.
    @Test func vueDeReference() throws {
        let pieces = ["Apple TV": "Salon", "HomePod": "Chambre", "E000000000000002": "Terrasse",
                      "E000000000000003": "Terrasse", "E000000000000004": "Salon", "E000000000000005": "Salon"]
        let zones = [ZoneMaison(nom: "Rez-de-chaussée", pieces: ["Salon"]), ZoneMaison(nom: "Étage", pieces: ["Chambre"]),
                     ZoneMaison(nom: "Jardin", pieces: ["Terrasse"])]
        let s = ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: true), libelles: ScenePiecesTests.libelles,
                            piecesNoeuds: pieces, zones: zones, chefs: ["Apple TV"], piecesMaison: true,
                            aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true)])
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Étage"])
        let c = CartesPieces.cartes(s, largeurs: [:])
        let k = DispositionPieces.Calcul(scene: s, cartes: c, fixees: [:])
        let d = DispositionPieces(scene: s, cartes: c)
        let v = k.vueReference(d.positions)
        let salon = try #require(s.pieces.firstIndex { $0.nom == .maison("Salon") })
        let terrasse = try #require(s.pieces.firstIndex { $0.nom == .maison("Terrasse") })
        let chambre = try #require(s.pieces.firstIndex { $0.nom == .maison("Chambre") })
        // Les niveaux, a la main : le Salon et la Terrasse (dans le Jardin, a cote du Rez-de-chaussee) au niveau 0, la
        // Chambre au-dessus.
        #expect(k.niveauEtage == [0, 0, 1])
        #expect(k.niveau[salon] == 0 && k.niveau[terrasse] == 0 && k.niveau[chambre] == 1)
        let cx = d.rayons[0] + DispositionPieces.esp + d.rayons[1]
        #expect(abs(v.rects[terrasse].x0 - (cx + d.positions[terrasse].x - c[terrasse].largeur / 2)) < 1e-12)
        #expect(abs(v.rects[chambre].x0 - (d.positions[chambre].x - c[chambre].largeur / 2)) < 1e-12, "l'etage, en x = 0")
        // Trois jeux de positions : la disposition ; puis la Chambre posee a la main en (1, 0), ou le lien
        // Terrasse-Salon (du niveau 0) coupe le lien Terrasse-Chambre (entre niveaux) ; puis en (-12, -1), ou celui-ci
        // coupe le lien Salon-Salon (E...05). Ces valeurs sont celles de cette maison : si la taille des cartes ou
        // l'ordre des liens change, les deux `croise` echouent d'abord. Un croisement ne compte qu'entre deux liens du
        // meme niveau : aucun de ceux-la ne compte.
        var coupe = d.positions, coupe2 = d.positions
        coupe[chambre] = SIMD2(1, 0)
        coupe2[chambre] = SIMD2(-12, -1)
        let vc = k.vueReference(coupe), vc2 = k.vueReference(coupe2)
        #expect(DispositionPieces.croise(vc.segments[2].0, vc.segments[2].1, vc.segments[3].0, vc.segments[3].1),
                "liens 2 et 3 : Terrasse-Salon coupe Terrasse-Chambre")
        #expect(DispositionPieces.croise(vc2.segments[3].0, vc2.segments[3].1, vc2.segments[4].0, vc2.segments[4].1),
                "liens 3 et 4 : Terrasse-Chambre coupe Salon-Salon")
        let jeux = [("disposition", d.positions), ("Chambre en (1, 0)", coupe), ("Chambre en (-12, -1)", coupe2)]
        for (nom, pos) in jeux {
            let vue = k.vueReference(pos)
            let rayons = (0..<s.etages.count).map { k.rayon(pos, $0) }
            // Le x de chaque plateau : le Rez-de-chaussee en 0, le Jardin apres lui, l'Etage en 0 (autre niveau).
            let cxs = [0.0, rayons[0] + DispositionPieces.esp + rayons[1], 0.0]
            var attendu = rayons.reduce(0, +)
            for (n, l) in k.liens.enumerated() {
                let p = SIMD2(cxs[k.etage[l.pa]], 0.0) + pos[l.pa] + l.la
                let q = SIMD2(cxs[k.etage[l.pb]], 0.0) + pos[l.pb] + l.lb
                #expect(vue.segments[n].0 == p && vue.segments[n].1 == q, "extremites du lien \(n), \(nom)")
                if k.niveau[l.pa] == k.niveau[l.pb] {
                    attendu += 0.3 * simd_length(q - p)
                    for (r, rect) in vue.rects.enumerated() where r != l.pa && r != l.pb && k.niveau[r] == k.niveau[l.pa] {
                        let t = DispositionPieces.dedans(p, q, rect)
                        if t > 0 { attendu += 6 + 4 * t }
                    }
                } else {
                    attendu += 0.1 * simd_length(p - q)
                }
            }
            #expect(abs(k.cout(pos) - attendu) < 1e-9, "cout, \(nom) : aucun croisement ne compte")
        }
        #expect(k.traversees(d.positions) == 0)
        // Deux zones a cote du meme etage : la seconde vient apres la premiere, et non a sa place. Une quatrieme piece,
        // « Abri » (le noeud E...05 : seul son rectangle sert ici), seule dans la zone « Cabane », a cote du
        // Rez-de-chaussee, apres le Jardin.
        let s2 = ScenePieces(graphe: try ScenePiecesTests.graphe(sonde: true), libelles: ScenePiecesTests.libelles,
                             piecesNoeuds: pieces.merging(["E000000000000005": "Abri"]) { $1 },
                             zones: zones + [ZoneMaison(nom: "Cabane", pieces: ["Abri"])], chefs: ["Apple TV"],
                             piecesMaison: true,
                             aCote: ["zone:Jardin": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée", dehors: true),
                                     "zone:Cabane": PlacesGardees.ACote(etage: "zone:Rez-de-chaussée")])
        #expect(s2.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Jardin", "zone:Cabane", "zone:Étage"])
        let c2 = CartesPieces.cartes(s2, largeurs: [:])
        let d2 = DispositionPieces(scene: s2, cartes: c2)
        let v2 = DispositionPieces.Calcul(scene: s2, cartes: c2, fixees: [:]).vueReference(d2.positions)
        let abri = try #require(s2.pieces.firstIndex { $0.nom == .maison("Abri") })
        let cxJardin = d2.rayons[0] + DispositionPieces.esp + d2.rayons[1]
        let cxCabane = cxJardin + d2.rayons[1] + DispositionPieces.esp + d2.rayons[2]
        #expect(abs(v2.rects[abri].x0 - (cxCabane + d2.positions[abri].x - c2[abri].largeur / 2)) < 1e-12,
                "la Cabane, apres le Jardin")
    }

    /// Longueur traversee (Liang-Barsky) et croisements stricts.
    @Test func geometrie() {
        let r = DispositionPieces.Rect(x0: 0, x1: 2, z0: 0, z1: 1)
        #expect(abs(DispositionPieces.dedans(SIMD2(-1, 0.5), SIMD2(3, 0.5), r) - 2) < 1e-12)
        #expect(DispositionPieces.dedans(SIMD2(-1, 2), SIMD2(3, 2), r) == 0)
        #expect(abs(DispositionPieces.dedans(SIMD2(1, 0.5), SIMD2(1, 3), r) - 0.5) < 1e-12)
        #expect(DispositionPieces.croise(SIMD2(0, 0), SIMD2(2, 2), SIMD2(0, 2), SIMD2(2, 0)))
        #expect(!DispositionPieces.croise(SIMD2(0, 0), SIMD2(1, 1), SIMD2(1, 1), SIMD2(2, 0)), "bout commun")
        #expect(!DispositionPieces.croise(SIMD2(0, 0), SIMD2(1, 0), SIMD2(0, 1), SIMD2(1, 1)))
    }
}
