import CoreGraphics
import Foundation
import simd
import Testing
@testable import MaillageCoeur

/// Le glissement d'une disposition a l'autre (polissage D, section 1) : les poses par cle, en route en 0,9 s en
/// cubique entree-sortie, les fondus de 0,3 s, l'interruption sans saut, « Reduire les animations » ; et la scene
/// projetee qui les prend.
@Suite("Scene : transition d'une disposition a l'autre")
struct TransitionSceneTests {
    typealias A = PosesScene.Ancre

    /// Une piece « p », sur le plateau `plateau`, a `x`, de largeur `l`.
    static func piece(_ plateau: String = "a", x: Double, l: Double = 2) -> PosesScene.Piece {
        PosesScene.Piece(ancres: [A(plateau: plateau, place: SIMD2(x, 0))], taille: SIMD2(l, 2), teinte: 3)
    }

    static func noeud(_ plateau: String, x: Double) -> PosesScene.Noeud {
        PosesScene.Noeud(ancres: [A(plateau: plateau, place: SIMD2(x, 0))], decalage: SIMD2(0.5, -0.5), rayon: 7)
    }

    static func lien(_ de: String, _ vers: String) -> GrapheReseau.Lien {
        GrapheReseau.Lien(de: de, vers: vers, genre: .radio, qualite: 2)
    }

    /// Le centre d'une seule ancre posee, sa place sur x.
    static func x(_ p: PosesScene.Piece?) -> Double? {
        guard let p, p.ancres.count == 1 else { return nil }
        return p.ancres[0].place.x
    }

    /// Les poses a 0, au quart, a la moitie et a la fin du temps : 0, 6,25 % (la cubique, et non une droite ni une
    /// autre courbe symetrique), 50 % et 100 % du chemin, la taille de la carte avec ; finie a 0,9 s, pas avant ; a la
    /// fin, exactement l'arrivee. Un noeud, lui, a 6,25 % et a 93,75 % (le sens du melange), sa place dans la carte et
    /// le rayon de sa pastille avec.
    @Test func glissement() throws {
        var d = PosesScene(), a = PosesScene()
        d.pieces["p"] = Self.piece(x: 0, l: 2)
        a.pieces["p"] = Self.piece(x: 10, l: 4)
        d.noeuds["n"] = PosesScene.Noeud(ancres: [A(plateau: "a", place: SIMD2(0, 0))], decalage: .zero, rayon: 7)
        a.noeuds["n"] = PosesScene.Noeud(ancres: [A(plateau: "a", place: SIMD2(8, 4))], decalage: SIMD2(2, -2),
                                         rayon: 11)
        let t = try #require(TransitionScene(de: d, vers: a, a: 100))
        #expect(TransitionScene.duree == 0.9 && TransitionScene.duree == CameraScene.dureeNiveaux)
        #expect(TransitionScene.dureeFondu == 0.3)
        for (instant, e) in [(100.0, 0.0), (100 + 0.225, 0.0625), (100.45, 0.5), (100.675, 0.9375), (100.9, 1.0)] {
            let n = try #require(t.poses(a: instant).noeuds["n"])
            #expect(n.ancres.count == 1 && simd_distance(n.ancres[0].place, SIMD2(8, 4) * e) < 1e-9, "a \(e), sa place")
            #expect(simd_distance(n.decalage, SIMD2(2, -2) * e) < 1e-9, "a \(e), sa place dans la carte")
            #expect(abs(n.rayon - (7 + 4 * e)) < 1e-9, "a \(e), le rayon de sa pastille")
        }
        #expect(Self.x(t.poses(a: 100).pieces["p"]) == 0)
        #expect(abs((Self.x(t.poses(a: 100 + 0.225).pieces["p"]) ?? -1) - 0.625) < 1e-9, "6,25 % au quart du temps")
        #expect(abs((Self.x(t.poses(a: 100.45).pieces["p"]) ?? -1) - 5) < 1e-9)
        #expect(abs((t.poses(a: 100.45).pieces["p"]?.taille.x ?? -1) - 3) < 1e-9)
        #expect(abs((Self.x(t.poses(a: 100.675).pieces["p"]) ?? -1) - 9.375) < 1e-9, "93,75 % aux trois quarts")
        #expect(t.poses(a: 100.9).pieces["p"] == a.pieces["p"] && t.poses(a: 105).pieces["p"] == a.pieces["p"])
        #expect(t.poses(a: 99).pieces["p"] == d.pieces["p"], "avant le debut : le depart")
        #expect(!t.finie(a: 100.89) && t.finie(a: 100.9) && t.finie(a: 101))
    }

    /// Les fondus de 0,3 s : ce qui arrive, piece, noeud ou lien, apparait a sa place, de 0 a 1 ; ce qui part s'efface
    /// a sa derniere place, de 1 a 0. Puis la pose reste, jusqu'a la fin du glissement. Avant le debut, rien n'a
    /// bouge : 0 pour ce qui arrive, 1 pour ce qui part.
    @Test func fondus() throws {
        var d = PosesScene(), a = PosesScene()
        d.pieces["part"] = Self.piece(x: 1)
        a.pieces["arrive"] = Self.piece("b", x: 2)
        d.noeuds["n0"] = Self.noeud("a", x: 1)
        a.noeuds["n1"] = Self.noeud("b", x: 2)
        d.liens[PosesScene.cle(Self.lien("n0", "x"))] = PosesScene.Lien(Self.lien("n0", "x"))
        a.liens[PosesScene.cle(Self.lien("n1", "x"))] = PosesScene.Lien(Self.lien("n1", "x"))
        let t = try #require(TransitionScene(de: d, vers: a, a: 0))
        let parti = PosesScene.cle(Self.lien("n0", "x")), venu = PosesScene.cle(Self.lien("n1", "x"))
        for (instant, arrivee) in [(-0.1, 0.0), (0.0, 0.0), (0.075, 0.25), (0.15, 0.5), (0.3, 1.0), (0.6, 1.0)] {
            let p = t.poses(a: instant)
            for o in [p.pieces["arrive"]?.opacite, p.noeuds["n1"]?.opacite, p.liens[venu]?.opacite] {
                #expect(abs((o ?? -1) - arrivee) < 1e-9, "a \(instant) s, ce qui arrive")
            }
            for o in [p.pieces["part"]?.opacite, p.noeuds["n0"]?.opacite, p.liens[parti]?.opacite] {
                #expect(abs((o ?? -1) - (1 - arrivee)) < 1e-9, "a \(instant) s, ce qui part")
            }
            #expect(Self.x(p.pieces["part"]) == 1 && Self.x(p.pieces["arrive"]) == 2, "a sa place")
            #expect(p.noeuds["n0"]?.ancres == d.noeuds["n0"]?.ancres)
            #expect(p.noeuds["n1"]?.ancres == a.noeuds["n1"]?.ancres)
        }
    }

    /// Rien ne change : pas de transition ; un lien deja la, ou la qualite seule change, non plus. « Reduire les
    /// animations » : jamais de transition, tout est immediat. La transition ne garde que ce qui change.
    @Test func ceQuiChange() throws {
        var d = PosesScene()
        d.pieces["p"] = Self.piece(x: 0)
        d.pieces["q"] = Self.piece(x: 5)
        d.liens["l"] = PosesScene.Lien(Self.lien("p", "q"))
        #expect(TransitionScene(de: d, vers: d, a: 0) == nil)
        var a = d
        a.liens["l"]?.qualite = 3
        #expect(TransitionScene(de: d, vers: a, a: 0) == nil, "la qualite d'un lien")
        a.pieces["q"] = Self.piece(x: 6)
        #expect(TransitionScene(de: d, vers: a, a: 0, reduire: true) == nil, "« Reduire les animations »")
        let t = try #require(TransitionScene(de: d, vers: a, a: 0))
        #expect(Set(t.depart.pieces.keys) == ["q"] && Set(t.arrivee.pieces.keys) == ["q"] && t.depart.liens.isEmpty)
        var s = d
        s.pieces["p"]?.opacite = 0.4
        let fondu = try #require(TransitionScene(de: s, vers: d, a: 0), "une opacite en route change aussi")
        #expect(abs((fondu.poses(a: 0.15).pieces["p"]?.opacite ?? -1) - 0.7) < 1e-9)
        #expect(fondu.poses(a: 0.3).pieces["p"]?.opacite == 1)
    }

    /// Une nouvelle disposition pendant un glissement repart de la pose affichee, sans saut : a l'instant de
    /// l'interruption, les poses de la nouvelle transition sont celles qui etaient affichees, places et opacites, y
    /// compris ce qui apparaissait encore et ce qui s'effacait ; puis elles vont a la nouvelle arrivee. Pour une
    /// piece, un noeud (dont un qui change de plateau, a deux ancres, jamais plus que de plateaux) et un lien.
    @Test func interruption() throws {
        var p0 = PosesScene(), p1 = PosesScene(), p2 = PosesScene()
        p0.pieces["p"] = Self.piece(x: 0)
        p0.pieces["part"] = Self.piece(x: 3)
        p1.pieces["p"] = Self.piece(x: 10)
        p1.pieces["arrive"] = Self.piece(x: 7)
        p2.pieces["p"] = Self.piece(x: -10)
        p2.pieces["arrive"] = Self.piece(x: 7)
        p0.noeuds["n"] = Self.noeud("a", x: 0)
        p1.noeuds["n"] = Self.noeud("b", x: 4)
        p2.noeuds["n"] = Self.noeud("b", x: -4)
        p1.noeuds["nouveau"] = Self.noeud("b", x: 2)
        p2.noeuds["nouveau"] = Self.noeud("b", x: 2)
        let parti = PosesScene.cle(Self.lien("n", "x")), venu = PosesScene.cle(Self.lien("nouveau", "x"))
        p0.liens[parti] = PosesScene.Lien(Self.lien("n", "x"))
        p1.liens[venu] = PosesScene.Lien(Self.lien("nouveau", "x"))
        p2.liens[venu] = PosesScene.Lien(Self.lien("nouveau", "x"))
        let t1 = try #require(TransitionScene(de: p0, vers: p1, a: 0))
        let affichee = p1.recouvertes(par: t1.poses(a: 0.1))
        let t2 = try #require(TransitionScene(de: affichee, vers: p2, a: 0.1))
        let avant = t1.poses(a: 0.1), apres = t2.poses(a: 0.1)
        for k in ["p", "part", "arrive"] {
            #expect(apres.pieces[k] == avant.pieces[k], "\(k) : pas de saut")
        }
        #expect(abs((avant.pieces["arrive"]?.opacite ?? -1) - 1.0 / 3) < 1e-9 && (Self.x(avant.pieces["p"]) ?? 0) > 0)
        for k in ["n", "nouveau"] {
            #expect(apres.noeuds[k] == avant.noeuds[k], "noeud \(k) : pas de saut")
        }
        for k in [parti, venu] {
            #expect(apres.liens[k] == avant.liens[k], "lien \(k) : pas de saut")
        }
        #expect(avant.noeuds["n"]?.ancres.map(\.plateau) == ["a", "b"], "en route d'un plateau a l'autre")
        #expect(abs((avant.noeuds["nouveau"]?.opacite ?? -1) - 1.0 / 3) < 1e-9)
        #expect(abs((avant.liens[venu]?.opacite ?? -1) - 1.0 / 3) < 1e-9)
        #expect(abs((avant.liens[parti]?.opacite ?? -1) - 2.0 / 3) < 1e-9)
        for instant in [0.1, 0.3, 0.5, 0.8, 1.0] {
            let ancres = try #require(t2.poses(a: instant).noeuds["n"]).ancres
            #expect(ancres.count <= 2 && Set(ancres.map(\.plateau)).count == ancres.count,
                    "jamais plus d'ancres que de plateaux")
        }
        #expect(t2.poses(a: 1).noeuds["n"] == p2.noeuds["n"] && t2.poses(a: 0.4).liens[venu]?.opacite == 1)
        #expect(t2.poses(a: 0.4).liens[parti]?.opacite == 0, "le lien qui s'effacait finit de s'effacer")
        #expect(t2.poses(a: 1).pieces["p"] == p2.pieces["p"] && t2.poses(a: 0.4).pieces["arrive"]?.opacite == 1)
        #expect(t2.poses(a: 0.4).pieces["part"]?.opacite == 0, "ce qui s'effacait finit de s'effacer")
        #expect(p1.recouvertes(par: PosesScene()) == p1)
    }

    /// Ce qui est deja efface (opacite 0) et absent de l'arrivee n'existe plus : une disposition identique qui arrive
    /// apres 0,3 s ne cree pas de transition, alors que pendant le fondu, ce qui s'efface encore en cree une.
    @Test func unEffaceNEstPlusUnChangement() throws {
        var d = PosesScene()
        d.pieces["q"] = Self.piece(x: 5)
        let a = d
        d.pieces["part"] = Self.piece(x: 1)
        d.noeuds["n"] = Self.noeud("a", x: 1)
        d.liens["l"] = PosesScene.Lien(Self.lien("n", "x"))
        let t = try #require(TransitionScene(de: d, vers: a, a: 0))
        let pendant = a.recouvertes(par: t.poses(a: 0.1))
        #expect(pendant.pieces["part"]?.opacite ?? 0 > 0, "il s'efface encore")
        #expect(TransitionScene(de: pendant, vers: a, a: 0.1) != nil)
        let efface = a.recouvertes(par: t.poses(a: 0.5))
        #expect(efface.pieces["part"]?.opacite == 0 && efface.noeuds["n"]?.opacite == 0)
        #expect(efface.liens["l"]?.opacite == 0)
        #expect(TransitionScene(de: efface, vers: a, a: 0.5) == nil, "plus rien ne change")
    }

    /// Les bornes de ce qui n'existe plus (relecture finale, Mineur 6) : efface (opacite 0) mais present a l'arrivee,
    /// un element revient, en fondu, depuis sa derniere place ; presque efface (1e-9) et absent de l'arrivee, il
    /// s'efface encore : c'est un changement.
    @Test func bornesDeLEfface() throws {
        var d = PosesScene(), a = PosesScene()
        d.pieces["p"] = Self.piece(x: 1)
        d.pieces["p"]?.opacite = 0
        a.pieces["p"] = Self.piece(x: 5)
        d.noeuds["n"] = Self.noeud("a", x: 1)
        d.noeuds["n"]?.opacite = 0
        a.noeuds["n"] = Self.noeud("a", x: 5)
        let t = try #require(TransitionScene(de: d, vers: a, a: 0), "il revient : un changement")
        let mi = t.poses(a: 0.45)
        #expect(Self.x(mi.pieces["p"]) == 3 && mi.pieces["p"]?.opacite == 1, "la piece, depuis sa derniere place")
        #expect(mi.noeuds["n"]?.ancres.map(\.place.x) == [3] && mi.noeuds["n"]?.opacite == 1, "le noeud aussi")
        #expect(t.poses(a: 0).pieces["p"]?.opacite == 0 && t.poses(a: 0).noeuds["n"]?.opacite == 0, "en fondu")
        var q = PosesScene()
        q.pieces["q"] = Self.piece(x: 5)
        for genre in ["piece", "noeud", "lien"] {
            var presque = q
            switch genre {
            case "piece": presque.pieces["part"] = PosesScene.Piece(ancres: [A(plateau: "a", place: .zero)],
                                                                   taille: SIMD2(2, 2), teinte: 3, opacite: 1e-9)
            case "noeud": presque.noeuds["n"] = PosesScene.Noeud(ancres: [A(plateau: "a", place: .zero)],
                                                                 decalage: .zero, rayon: 7, opacite: 1e-9)
            default: presque.liens["l"] = PosesScene.Lien(Self.lien("n", "x"), opacite: 1e-9)
            }
            #expect(TransitionScene(de: presque, vers: q, a: 0) != nil, "\(genre) a 1e-9 : il s'efface encore")
        }
    }

    /// Un noeud qui change de plateau va en ligne droite, d'un etage a l'autre, en 2D comme en 3D : ses ancres,
    /// melangees, donnent a chaque instant le point du segment entre ses deux places dans le monde.
    @Test(arguments: [0.0, 1.0]) func dUnPlateauALAutre(t: Double) throws {
        let g = GeometrieMaison(rayons: [5, 4])
        let plateaux = ["a": 0, "b": 1]
        let da = [A(plateau: "a", place: SIMD2(1, -2))], ab = [A(plateau: "b", place: SIMD2(-1, 3))]
        let w0 = try #require(PosesScene.centre(da, geometrie: g, plateaux: plateaux, t: t))
        let w1 = try #require(PosesScene.centre(ab, geometrie: g, plateaux: plateaux, t: t))
        #expect(simd_distance(w0, w1) > 4)
        if t == 1 { #expect(w1.y - w0.y > 4, "d'un etage a l'autre") }
        for e in [0.25, 0.5, 0.75] {
            let m = try #require(PosesScene.centre(PosesScene.melange(da, ab, e), geometrie: g, plateaux: plateaux,
                                                   t: t))
            #expect(simd_distance(m, w0 + (w1 - w0) * e) < 1e-9, "a \(e) du chemin, sur le segment")
        }
    }

    /// Le melange : a 0 et a 1, exactement les ancres d'un cote ; deux ancres du meme plateau n'en font qu'une, a la
    /// moyenne ponderee ; une ancre sur un plateau absent ne compte pas, et sans aucune, pas de centre.
    @Test func melange() throws {
        let a = [A(plateau: "a", place: SIMD2(0, 0))], b = [A(plateau: "a", place: SIMD2(8, 4))]
        #expect(PosesScene.melange(a, b, 0) == a && PosesScene.melange(a, b, 1) == b)
        let m = PosesScene.melange(a, b, 0.25)
        #expect(m.count == 1 && m[0].plateau == "a" && abs(m[0].poids - 1) < 1e-12)
        #expect(simd_distance(m[0].place, SIMD2(2, 1)) < 1e-12)
        let deux = PosesScene.melange(a, [A(plateau: "b", place: SIMD2(8, 4))], 0.25)
        #expect(deux.map(\.plateau) == ["a", "b"])
        #expect(abs(deux[0].poids - 0.75) < 1e-12 && abs(deux[1].poids - 0.25) < 1e-12)
        let g = GeometrieMaison(rayons: [5, 4])
        let seul = PosesScene.centre(deux, geometrie: g, plateaux: ["a": 0], t: 0)
        let centreA = try #require(PosesScene.centre(a, geometrie: g, plateaux: ["a": 0], t: 0))
        #expect(simd_distance(try #require(seul), centreA) < 1e-12, "le plateau absent ne compte pas")
        #expect(PosesScene.centre(deux, geometrie: g, plateaux: [:], t: 0) == nil)
        let c = PosesScene.centre(a, geometrie: g, plateaux: ["a": 1], t: 0)
        #expect(c == SIMD3(g.centres2D[1].x, 0, g.centres2D[1].y), "l'ancre suit son plateau, par sa cle")
    }

    /// Une piece qu'on prend pour la glisser, et ses noeuds : ils ne glissent plus.
    @Test func oublier() throws {
        var d = PosesScene(), a = PosesScene()
        d.pieces["p"] = Self.piece(x: 0)
        a.pieces["p"] = Self.piece(x: 4)
        d.noeuds["n"] = Self.noeud("a", x: 0)
        a.noeuds["n"] = Self.noeud("a", x: 4)
        d.pieces["q"] = Self.piece(x: 1)
        a.pieces["q"] = Self.piece(x: 2)
        var t = try #require(TransitionScene(de: d, vers: a, a: 0))
        t.oublier(pieces: ["p"], noeuds: ["n"])
        let p = t.poses(a: 0.45)
        #expect(p.pieces["p"] == nil && p.noeuds["n"] == nil && p.pieces["q"] != nil)
    }

    /// Les poses d'une scene posee : chaque piece a sa place, sur son plateau, de la taille de sa carte, opaque ;
    /// chaque noeud a sa place dans sa carte ; chaque lien.
    @Test func posesDUneScene() throws {
        let (s, c, d, _) = try SceneProjeteeTests.scene()
        let p = PosesScene(scene: s, cartes: c, positions: d.positions)
        #expect(p.pieces.count == s.pieces.count && p.noeuds.count == s.noeuds.count && p.liens.count == s.liens.count)
        let bureau = try SceneProjeteeTests.indice(s, "Bureau")
        let pose = try #require(p.pieces["piece:Bureau"])
        #expect(pose.ancres == [A(plateau: "zone:Étage", place: d.positions[bureau])] && pose.opacite == 1)
        #expect(pose.taille == SIMD2(c[bureau].largeur, c[bureau].profondeur) && pose.teinte == s.pieces[bureau].teinte)
        let r = try #require(s.pieces[bureau].noeuds.firstIndex(of: "E000000000000003"))
        let n = try #require(p.noeuds["E000000000000003"])
        #expect(n.ancres == pose.ancres && n.decalage == c[bureau].places[r] && n.rayon == 7)
    }

    /// La scene projetee prend les poses : posee, une pose ne change rien, au bit pres ; une piece et un noeud en route
    /// sont a leur pose ; un noeud qui change de piece, et d'etage, en ligne droite ; l'opacite d'un fondu.
    @Test func sceneProjeteeEnRoute() throws {
        let (s, c, d, g) = try SceneProjeteeTests.scene()
        let e = EtatAnime(t: 1, fk: Array(repeating: 0, count: s.pieces.count))
        let o = CameraScene.canonique(g, aspect: 1.5, u: 1)
        func projeter(_ poses: PosesScene, scene: ScenePieces? = nil,
                      positions: [SIMD2<Double>]? = nil) -> SceneProjetee {
            SceneProjetee(scene: scene ?? s, cartes: c, positions: positions ?? d.positions, geometrie: g, etat: e,
                          orbite: o, cadre: SceneProjeteeTests.cadre, poses: poses)
        }
        let sans = projeter(PosesScene()), posee = projeter(PosesScene(scene: s, cartes: c, positions: d.positions))
        #expect(posee.centresNoeuds == sans.centresNoeuds && posee.ancresPieces == sans.ancresPieces)
        #expect(posee.disques.map(\.opacite) == sans.disques.map(\.opacite) && posee.fantomes.isEmpty)
        // Le bureau glisse de 2 sur x, ses noeuds avec lui ; E...03 passe au salon, a mi-chemin.
        let bureau = try SceneProjeteeTests.indice(s, "Bureau"), salon = try SceneProjeteeTests.indice(s, "Salon")
        let arrivee = PosesScene(scene: s, cartes: c, positions: d.positions)
        var depart = arrivee
        depart.pieces["piece:Bureau"]?.ancres[0].place.x -= 2
        depart.noeuds["E000000000000003"] = PosesScene.Noeud(
            ancres: [A(plateau: "zone:Rez-de-chaussée", place: d.positions[salon])], decalage: .zero, rayon: 7)
        let t = try #require(TransitionScene(de: depart, vers: arrivee, a: 0))
        let mi = projeter(t.poses(a: 0.45))
        let ici = try #require(sans.ancresPieces[bureau]), la = try #require(mi.ancresPieces[bureau])
        #expect(ici != la, "le bureau, en route")
        let w0 = SIMD3(g.centrePlateau(0, 1).x + d.positions[salon].x,
                       g.centrePlateau(0, 1).y + 0.1 + GeometrieMaison.hauteurBloc(1) / 2,
                       g.centrePlateau(0, 1).z + d.positions[salon].y)
        let w1 = try #require(sans.centresNoeuds["E000000000000003"])
        let w = try #require(mi.centresNoeuds["E000000000000003"])
        #expect(simd_distance(w, (w0 + w1) / 2) < 1e-9 && w1.y - w0.y > 4, "d'un etage a l'autre, en ligne droite")
        let wQuart = try #require(projeter(t.poses(a: 0.225)).centresNoeuds["E000000000000003"])
        #expect(simd_distance(wQuart, w0 + (w1 - w0) / 16) < 1e-9, "a 6,25 % du chemin, du cote du depart")
        let e02 = try #require(mi.centresNoeuds["E000000000000002"])
        let e02Posee = try #require(sans.centresNoeuds["E000000000000002"])
        #expect(abs((e02Posee.x - e02.x) - 1) < 1e-9 && abs(e02Posee.z - e02.z) < 1e-9,
                "le bureau, a mi-chemin, 1 unite avant sa place ; un noeud du bureau suit sa piece")
        // Un fondu : la pastille et le bloc a l'opacite de la pose ; les liens aussi.
        var f = PosesScene()
        f.pieces["piece:Salon"] = arrivee.pieces["piece:Salon"]
        f.pieces["piece:Salon"]?.opacite = 0.5
        f.noeuds["HomePod"] = arrivee.noeuds["HomePod"]
        f.noeuds["HomePod"]?.opacite = 0.25
        let radio = try #require(s.liens.first { $0.genre == .radio })
        f.liens[PosesScene.cle(radio)] = PosesScene.Lien(radio, opacite: 0.5)
        for l in s.liens where l.genre != .radio { f.liens[PosesScene.cle(l)] = PosesScene.Lien(l, opacite: 0.5) }
        let fondu = projeter(f)
        let blocSalon = try #require(fondu.blocs.first { $0.piece == salon })
        let blocSans = try #require(sans.blocs.first { $0.piece == salon })
        #expect(abs(blocSalon.opaciteVerre - blocSans.opaciteVerre * 0.5) < 1e-12)
        #expect(abs(blocSalon.opaciteAretes - 0.375) < 1e-12)
        #expect(fondu.disques.first { $0.noeud == "HomePod" }?.opacite == 0.25)
        #expect(fondu.liensRouteurs.contains { abs($0.opacite - 0.475) < 1e-12 })
        #expect(fondu.liensRouteurs.count == sans.liensRouteurs.count)
        // Les liens enfants et de rattachement, de meme : la moitie de leur opacite, 0,28 posee.
        #expect(sans.liensEnfants.count == 3 && fondu.liensEnfants.count == 3)
        #expect(sans.liensEnfants.allSatisfy { abs($0.opacite - 0.28) < 1e-12 })
        #expect(sans.liensRouteurs.allSatisfy { abs($0.opacite - 0.95) < 1e-12 })
        #expect(Set(fondu.liensEnfants.map(\.genre)) == [.parent, .rattachement])
        #expect(fondu.liensEnfants.allSatisfy { abs($0.opacite - 0.14) < 1e-12 })
    }

    /// La place d'un noeud, posee ou en route, est la meme, a une bascule et a un isolement a mi-chemin (t et fk
    /// strictement entre 0 et 1) : le centre de sa piece, plus sa place dans la carte a l'echelle 1 + 0,3 fk, a
    /// mi-hauteur du bloc (0,1 + h t / 2) ; ecrite ici en clair, et non par la formule du code.
    @Test func placeDUnNoeudALEtatIntermediaire() throws {
        let (s, c, d, g) = try SceneProjeteeTests.scene()
        let t = 0.4, fk = 0.5
        let e = EtatAnime(t: t, fk: Array(repeating: fk, count: s.pieces.count))
        let o = CameraScene.canonique(g, aspect: 1.5, u: t)
        func projeter(_ poses: PosesScene) -> SceneProjetee {
            SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o,
                          cadre: SceneProjeteeTests.cadre, poses: poses)
        }
        let sans = projeter(PosesScene()), posee = projeter(PosesScene(scene: s, cartes: c, positions: d.positions))
        let bureau = try SceneProjeteeTests.indice(s, "Bureau")
        let r = try #require(s.pieces[bureau].noeuds.firstIndex(of: "E000000000000003"))
        let carte = c[bureau].places[r], centre = g.centrePlateau(s.pieces[bureau].etage, t)
        let f = 1 + 0.3 * CameraScene.rampe(fk), h = GeometrieMaison.hauteurBloc(t)
        #expect(simd_length(carte) > 0.1, "une place decalee, que l'echelle deplace")
        let attendu = SIMD3(centre.x + d.positions[bureau].x + carte.x * f, centre.y + 0.1 + h * t / 2,
                            centre.z + d.positions[bureau].y + carte.y * f)
        for (nom, p) in [("sans pose", sans), ("posee", posee)] {
            let w = try #require(p.centresNoeuds["E000000000000003"])
            #expect(simd_distance(w, attendu) < 1e-9, "\(nom) : a sa place")
        }
        // Un noeud en route, a l'instant de son depart : il est la ou serait le noeud pose.
        var depart = PosesScene(scene: s, cartes: c, positions: d.positions)
        depart.noeuds["E000000000000003"]?.decalage += SIMD2(1, 1)
        let posees = PosesScene(scene: s, cartes: c, positions: d.positions)
        let transition = try #require(TransitionScene(de: depart, vers: posees, a: 0))
        let milieu = try #require(projeter(transition.poses(a: 0.45)).centresNoeuds["E000000000000003"])
        #expect(simd_distance(milieu, attendu + SIMD3(0.5 * f, 0, 0.5 * f)) < 1e-9, "a mi-chemin, a l'echelle f")
    }

    /// Ce qui s'efface sous le voile d'un isolement (relecture finale, Mineur 2) : sur le plateau estompe d'un etage
    /// isole, une piece, ses pastilles et leurs liens qui partent sont estompes comme ce qui reste, a 15 % de leur
    /// fondu ; sous une piece isolee, comme une piece hors du focus : le bloc et les liens a 15 %, les pastilles a
    /// 20 %, exactement, et non moins (relecture ciblee de la vague finale, Mineur 2). Des pastilles qui quittent la
    /// piece isolee elle-meme, et leurs liens, gardent son voile : elles partent de leur opacite affichee (Mineur 1 de
    /// la meme relecture). Sans isolement, le fondu seul.
    @Test func ceQuiSEffaceSousLeVoile() throws {
        let (s, c, d, g) = try SceneProjeteeTests.scene()
        #expect(s.etages.map(\.id) == ["zone:Rez-de-chaussée", "zone:Étage"])
        let o = CameraScene.canonique(g, aspect: 1.5, u: 0)
        // Sur l'etage : une piece, deux pastilles, un lien radio entre elles, un lien enfant vers E...03 (le bureau).
        var f = PosesScene()
        f.pieces["piece:Garage"] = PosesScene.Piece(ancres: [A(plateau: "zone:Étage", place: .zero)],
                                                    taille: SIMD2(3, 3), teinte: 2, opacite: 0.6)
        for (id, x) in [("E000000000000009", 1.0), ("E00000000000000A", -1.0)] {
            f.noeuds[id] = PosesScene.Noeud(ancres: [A(plateau: "zone:Étage", place: SIMD2(x, 0))], decalage: .zero,
                                            rayon: 7, opacite: 0.8)
        }
        let radio = GrapheReseau.Lien(de: "E000000000000009", vers: "E00000000000000A", genre: .radio, qualite: 1)
        let enfant = GrapheReseau.Lien(de: "E00000000000000A", vers: "E000000000000003", genre: .parent, qualite: nil)
        f.liens[PosesScene.cle(radio)] = PosesScene.Lien(radio, opacite: 0.4)
        f.liens[PosesScene.cle(enfant)] = PosesScene.Lien(enfant, opacite: 0.4)
        /// Le facteur de chacun, sur son fondu : le bloc, les deux pastilles, le lien radio, le lien enfant.
        func facteurs(_ e: EtatAnime, _ f: PosesScene) throws -> [Double] {
            let sans = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o,
                                     cadre: SceneProjeteeTests.cadre)
            let p = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o,
                                  cadre: SceneProjeteeTests.cadre, poses: f)
            let bloc = try #require(p.blocs.first { $0.piece == -1 })
            let disques = p.disques.filter { p.fantomes.contains($0.noeud) }
            #expect(disques.count == 2)
            let r = try #require(p.liensRouteurs.dropFirst(sans.liensRouteurs.count).first)
            let l = try #require(p.liensEnfants.dropFirst(sans.liensEnfants.count).first)
            return [bloc.opaciteAretes / (0.75 * 0.6)] + disques.map { $0.opacite / 0.8 }
                + [r.opacite / (0.95 * 0.4), l.opacite / (0.28 * 0.4)]
        }
        func egaux(_ a: [Double], _ b: [Double]) -> Bool {
            a.count == b.count && zip(a, b).allSatisfy { abs($0 - $1) < 1e-12 }
        }
        let n = s.pieces.count
        let libre = try facteurs(EtatAnime(t: 0, fk: Array(repeating: 0, count: n)), f)
        #expect(egaux(libre, [1, 1, 1, 1, 1]), "sans isolement, le fondu seul : \(libre)")
        let etage = try facteurs(EtatAnime(t: 0, fk: Array(repeating: 0, count: n), se: 1, ek: [1, 0]), f)
        #expect(egaux(etage, [0.15, 0.15, 0.15, 0.15, 0.15]), "l'etage isole est l'autre : \(etage)")
        let salon = try SceneProjeteeTests.indice(s, "Salon")
        var fk = Array(repeating: 0.0, count: n)
        fk[salon] = 1
        let isole = EtatAnime(t: 0, s: 1, fk: fk, focus: salon)
        let piece = try facteurs(isole, f)
        #expect(egaux(piece, [0.15, 0.2, 0.2, 0.15, 0.15]), "le salon isole : \(piece)")
        // Les deux pastilles quittent le salon isole lui-meme : son voile, celui de leur opacite affichee ; leurs
        // liens aussi. Le bloc qui part est celui d'une autre piece.
        let posees = PosesScene(scene: s, cartes: c, positions: d.positions)
        #expect(posees.noeuds.allSatisfy { k, p in p.piece == s.noeud(k).map { s.pieces[$0.piece].id } },
                "une pose de noeud porte la cle de sa piece")
        var duSalon = f
        for id in ["E000000000000009", "E00000000000000A"] { duSalon.noeuds[id]?.piece = s.pieces[salon].id }
        let partantes = try facteurs(isole, duSalon)
        #expect(egaux(partantes, [0.15, 1, 1, 1, 1]), "elles quittent le salon isole : \(partantes)")
    }

    /// Ce qui s'efface, absent de la scene, se dessine a sa derniere place, a son opacite : une piece (son bloc, sans
    /// ancre de nom, et qui ne se clique pas), un noeud (sa pastille, sans nom, qui ne se clique pas), un lien entre
    /// les places de ses bouts. Un element sur un plateau absent ne se dessine pas.
    @Test func ceQuiSEfface() throws {
        let (s, c, d, g) = try SceneProjeteeTests.scene()
        let e = EtatAnime(t: 0, fk: Array(repeating: 0, count: s.pieces.count))
        let o = CameraScene.canonique(g, aspect: 1.5, u: 0)
        var f = PosesScene()
        f.pieces["piece:Garage"] = PosesScene.Piece(ancres: [A(plateau: "zone:Étage", place: SIMD2(0, 0))],
                                                    taille: SIMD2(3, 3), teinte: 2, opacite: 0.6)
        f.pieces["piece:Ailleurs"] = PosesScene.Piece(ancres: [A(plateau: "zone:Absente", place: .zero)],
                                                      taille: SIMD2(3, 3), teinte: 2, opacite: 0.6)
        f.noeuds["E000000000000009"] = PosesScene.Noeud(ancres: [A(plateau: "zone:Étage", place: SIMD2(0, 0))],
                                                        decalage: .zero, rayon: 7, opacite: 0.8)
        let parti = GrapheReseau.Lien(de: "E000000000000009", vers: "HomePod", genre: .radio, qualite: 1)
        f.liens[PosesScene.cle(parti)] = PosesScene.Lien(parti, opacite: 0.4)
        let partiEnfant = GrapheReseau.Lien(de: "E000000000000009", vers: "HomePod", genre: .parent, qualite: nil)
        f.liens[PosesScene.cle(partiEnfant)] = PosesScene.Lien(partiEnfant, opacite: 0.4)
        // Un noeud qui s'efface a la place et au rayon d'un noeud pose : meme centre, meme pastille.
        f.noeuds["E000000000000008"] = PosesScene(scene: s, cartes: c, positions: d.positions).noeuds["HomePod"]
        f.noeuds["E000000000000008"]?.opacite = 0.8
        let sans = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o,
                                 cadre: SceneProjeteeTests.cadre)
        let p = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: e, orbite: o,
                              cadre: SceneProjeteeTests.cadre, poses: f)
        let fantome = try #require(p.blocs.first { $0.piece == -1 })
        #expect(p.blocs.count == sans.blocs.count + 1 && abs(fantome.opaciteVerre - 0.6 * 0.13) < 1e-12)
        #expect(p.ancresPieces.count == sans.ancresPieces.count)
        let dessus = SceneProjetee.boite(fantome.faces[0].points)
        #expect(p.piece(sous: CGPoint(x: dessus.midX, y: dessus.midY)) != -1)
        let disque = try #require(p.disques.first { $0.noeud == "E000000000000009" })
        #expect(disque.opacite == 0.8 && p.fantomes.contains("E000000000000009"))
        #expect(p.ancresNoeuds["E000000000000009"] == nil)
        #expect(p.noeud(sous: disque.centre, marge: 0) != "E000000000000009")
        #expect(p.liensRouteurs.count == sans.liensRouteurs.count + 1)
        #expect(p.liensRouteurs.contains { abs($0.opacite - 0.38) < 1e-12 }, "0,95 x 0,4")
        #expect(p.liensEnfants.count == sans.liensEnfants.count + 1)
        #expect(p.liensEnfants.contains { abs($0.opacite - 0.112) < 1e-12 }, "0,28 x 0,4")
        let jumeau = try #require(p.disques.first { $0.noeud == "E000000000000008" })
        let modele = try #require(p.disques.first { $0.noeud == "HomePod" })
        #expect(p.centresNoeuds["E000000000000008"] == p.centresNoeuds["HomePod"] && jumeau.centre == modele.centre)
        #expect(jumeau.rayon == modele.rayon && p.fantomes == ["E000000000000009", "E000000000000008"])
        // Sous le mode focus, un noeud qui s'efface s'estompe comme les autres (relecture de Maillage Thread).
        #expect(jumeau.focus == 1 && disque.focus == 1)
        let estompes = EtatAnime(t: 0, fk: Array(repeating: 0, count: s.pieces.count),
                                 noeudsEstompes: ["E000000000000009": 1, "E000000000000008": 0.5])
        let q = SceneProjetee(scene: s, cartes: c, positions: d.positions, geometrie: g, etat: estompes, orbite: o,
                              cadre: SceneProjeteeTests.cadre, poses: f)
        let flou = try #require(q.disques.first { $0.noeud == "E000000000000009" })
        let flou2 = try #require(q.disques.first { $0.noeud == "E000000000000008" })
        #expect(flou.focus == MiseEnAvant.opaciteEstompee && flou2.focus == MiseEnAvant.facteur(0.5))
        #expect(flou.opacite == disque.opacite, "le focus ne change pas l'opacite du fondu")
    }
}
