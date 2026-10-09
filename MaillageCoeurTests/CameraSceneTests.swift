import CoreGraphics
import Foundation
import simd
import Testing
@testable import MaillageCoeur

@Suite("Scene : camera, envol, zoom")
struct CameraSceneTests {
    /// La maison de la maquette : deux plateaux, dans une fenetre de 1600 x 972.
    static let geometrie = GeometrieMaison(rayons: [15.2, 16.0])
    static let cadre = CGRect(x: 0, y: 0, width: 1600, height: 972)
    static let aspect = 1600.0 / 972

    static func proche(_ a: CGPoint, _ b: CGPoint, _ e: Double = 1e-6) -> Bool {
        abs(a.x - b.x) < e && abs(a.y - b.y) < e
    }

    /// Vue de dessus, a 10 unites, champ de 90 degres : 30 points par unite ; -z monte a l'ecran.
    /// Le point principal est le centre du cadre, meme decale. Derriere l'oeil : rien.
    @Test func projectionDePointsConnus() throws {
        let o = Orbite(cible: .zero, distance: 10, azimut: 0, inclinaison: 0, champ: 90)
        let p = ProjectionScene(o, cadre: CGRect(x: 0, y: 0, width: 800, height: 600))
        #expect(abs(p.focale - 300) < 1e-9)
        #expect(Self.proche(try #require(p.ecran(.zero)), CGPoint(x: 400, y: 300)))
        #expect(Self.proche(try #require(p.ecran(SIMD3(1, 0, 0))), CGPoint(x: 430, y: 300)))
        #expect(Self.proche(try #require(p.ecran(SIMD3(0, 0, -1))), CGPoint(x: 400, y: 270)))
        #expect(abs(p.pxParUnite(.zero) - 30) < 1e-9)
        #expect(p.ecran(SIMD3(0, 20, 0)) == nil)
        let decale = ProjectionScene(o, cadre: CGRect(x: 100, y: 50, width: 800, height: 600))
        #expect(Self.proche(try #require(decale.ecran(.zero)), CGPoint(x: 500, y: 350)))
        let sol = try #require(decale.sol(CGPoint(x: 530, y: 350), hauteur: 0))
        #expect(abs(sol.x - 1) < 1e-9 && abs(sol.z) < 1e-9)
    }

    /// Debut de l'envol : la vue d'ensemble 2D, la boite de cadrage dans le cadre, marges comprises ;
    /// fin : la sphere cadree, au centre, sur environ 2 / 2,4 de la hauteur.
    @Test func debutEtFinDeLEnvol() throws {
        let g = Self.geometrie
        let e = Envol(depuis: CameraScene.canonique(g, aspect: Self.aspect, u: 0), t: 0, vers: 1, geometrie: g,
                      aspect: Self.aspect)
        let (t0, o0) = e.pose(0, geometrie: g, aspect: Self.aspect)
        #expect(t0 == 0 && o0.champ == 2)
        let p0 = ProjectionScene(o0, cadre: Self.cadre)
        let coins = [SIMD3(g.boite.x0, 0, g.boite.z0), SIMD3(g.boite.x1, 0, g.boite.z1)].compactMap { p0.ecran($0) }
        #expect(coins.count == 2)
        let boite = CGRect(x: coins[0].x, y: coins[0].y, width: 0, height: 0).union(CGRect(origin: coins[1], size: .zero))
        #expect(Self.cadre.contains(boite))
        #expect(boite.width / 1600 > 0.9 || boite.height / 972 > 0.85, "la boite remplit le cadre : \(boite)")
        let (t1, o1) = e.pose(1, geometrie: g, aspect: Self.aspect)
        #expect(t1 == 1 && o1 == CameraScene.canonique(g, aspect: Self.aspect, u: 1))
        let m = try #require(ProjectionScene(o1, cadre: Self.cadre).contourSphere(g.centreSphere, g.rayonSphere))
        let ellipse = CGRect(x: -1, y: -1, width: 2, height: 2).applying(m)
        #expect(Self.cadre.contains(ellipse))
        #expect(ellipse.height / 972 > 0.8 && ellipse.height / 972 < 0.9, "\(ellipse)")
        #expect(abs(ellipse.midX - 800) < 1 && abs(ellipse.midY - 486) < 1)
        let (tm, _) = e.pose(0.5, geometrie: g, aspect: Self.aspect)
        #expect(abs(tm - 0.5) < 1e-12, "rampe cubique : la moitie a mi-temps")
    }

    /// L'envol part de la vue courante, zoomee ou tournee, sans saut, et finit sur la pose canonique.
    @Test func envolSansSaut() {
        let g = Self.geometrie
        var o = CameraScene.canonique(g, aspect: Self.aspect, u: 1)
        o.azimut += 1.3
        o.distance *= 0.6
        o.cible += SIMD3(2, 0, -1)
        let e = Envol(depuis: o, t: 1, vers: 0, geometrie: g, aspect: Self.aspect)
        let (t, debut) = e.pose(0, geometrie: g, aspect: Self.aspect)
        #expect(t == 1)
        #expect(simd_distance(debut.oeil, o.oeil) < 1e-9 && simd_distance(debut.cible, o.cible) < 1e-9)
        #expect(e.pose(1, geometrie: g, aspect: Self.aspect).orbite == CameraScene.canonique(g, aspect: Self.aspect, u: 0))
    }

    /// Le zoom vers le curseur garde le point sous le curseur, a moins de 1e-6 unite, en 2D comme en 3D.
    @Test func zoomVersLeCurseur() throws {
        let g = Self.geometrie
        for u in [0.0, 1.0] {
            let o = CameraScene.canonique(g, aspect: Self.aspect, u: u)
            let curseur = CGPoint(x: 420, y: 610)
            let ancre = try #require(ProjectionScene(o, cadre: Self.cadre).sol(curseur, hauteur: o.cible.y))
            let bornes = CameraScene.bornes(g, aspect: Self.aspect, troisD: u == 1, champ: o.champ)
            let z = CameraScene.zoomer(o, facteur: -0.4, ancre: ancre, bornes: bornes)
            #expect(z.distance < o.distance)
            let apres = try #require(ProjectionScene(z, cadre: Self.cadre).sol(curseur, hauteur: o.cible.y))
            #expect(simd_distance(apres, ancre) < 1e-6, "u = \(u) : \(simd_distance(apres, ancre))")
        }
    }

    /// Bornes du zoom : 3 unites de hauteur de vue a 3 fois la vue d'ensemble en 2D ; 5 unites de
    /// distance a 2,5 fois la vue d'ensemble en 3D.
    @Test func bornesDuZoom() {
        let g = Self.geometrie
        let o2 = CameraScene.canonique(g, aspect: Self.aspect, u: 0)
        let b2 = CameraScene.bornes(g, aspect: Self.aspect, troisD: false, champ: o2.champ)
        #expect(CameraScene.zoomer(o2, facteur: -20, ancre: nil, bornes: b2).distance
                == Orbite.distance(pourHauteur: 3, champ: 2))
        #expect(CameraScene.zoomer(o2, facteur: 20, ancre: nil, bornes: b2).distance
                == Orbite.distance(pourHauteur: CameraScene.vue2D(g, aspect: Self.aspect) * 3, champ: 2))
        let o3 = CameraScene.canonique(g, aspect: Self.aspect, u: 1)
        let b3 = CameraScene.bornes(g, aspect: Self.aspect, troisD: true, champ: o3.champ)
        #expect(CameraScene.zoomer(o3, facteur: -20, ancre: nil, bornes: b3).distance == 5)
        #expect(abs(CameraScene.zoomer(o3, facteur: 20, ancre: nil, bornes: b3).distance
                    - Orbite.distance(pourHauteur: CameraScene.vue3D(g, aspect: Self.aspect) * 2.5, champ: 40)) < 1e-9)
    }

    /// Vol vers une piece : la cible au centre de la piece, a la hauteur de vue
    /// max(largeur / aspect, profondeur) 1,3 1,8 + 6 ; il part de la camera, sans saut.
    @Test func volVersUnePiece() {
        let o = CameraScene.canonique(Self.geometrie, aspect: Self.aspect, u: 0)
        let centre = SIMD3(-12.0, 0.5, 3.0)
        let v = CameraScene.volVersPiece(o, centre: centre, largeur: 8.75, profondeur: 9.3, aspect: Self.aspect,
                                         troisD: false)
        let debut = v.orbite(0, depuis: o)
        #expect(simd_distance(debut.oeil, o.oeil) < 1e-9 && simd_distance(debut.cible, o.cible) < 1e-9)
        let fin = v.orbite(1, depuis: o)
        #expect(simd_distance(fin.cible, centre) < 1e-9)
        let attendue = Orbite.distance(pourHauteur: max(8.75 / Self.aspect, 9.3) * 1.3 * 1.8 + 6, champ: 2)
        #expect(abs(fin.distance - attendue) < 1e-6)
        #expect(fin.champ == o.champ)
    }

    /// Orbite sans NaN ni infini.
    static func finie(_ o: Orbite) -> Bool {
        [o.cible.x, o.cible.y, o.cible.z, o.distance, o.azimut, o.inclinaison, o.champ].allSatisfy(\.isFinite)
    }

    /// Un aspect nul, negatif, non fini ou minuscule (cadre vide pendant une mise en page) laisse la
    /// camera finie : vue d'ensemble, bornes, zoom, envol et vols, celui vers un etage compris.
    @Test(arguments: [0, -1, Double.nan, Double.infinity, 1e-9])
    func aspectDegenere(_ aspect: Double) {
        let g = Self.geometrie
        for u in [0.0, 1.0] {
            let o = CameraScene.canonique(g, aspect: aspect, u: u)
            #expect(Self.finie(o), "canonique, u = \(u)")
            let b = CameraScene.bornes(g, aspect: aspect, troisD: u == 1, champ: o.champ)
            #expect(b.lowerBound.isFinite && b.upperBound.isFinite, "bornes, u = \(u)")
            #expect(Self.finie(CameraScene.zoomer(o, facteur: -0.4, ancre: SIMD3(3, 0, -2), bornes: b)), "zoom, u = \(u)")
            #expect(Self.finie(CameraScene.zoomer(o, facteur: 0.4, ancre: nil, bornes: b)), "dezoom, u = \(u)")
            let e = Envol(depuis: o, t: u, vers: 1 - u, geometrie: g, aspect: aspect)
            for q in [0.0, 0.5, 1.0] {
                #expect(Self.finie(e.pose(q, geometrie: g, aspect: aspect).orbite), "envol, u = \(u), q = \(q)")
            }
            let piece = CameraScene.volVersPiece(o, centre: SIMD3(-12, 0.5, 3), largeur: 8.75, profondeur: 9.3,
                                                 aspect: aspect, troisD: u == 1)
            let ensemble = CameraScene.volVersEnsemble(o, g, aspect: aspect, u: u, troisD: u == 1)
            let etage = CameraScene.volVersEtage(o, g, etage: 1, aspect: aspect, u: u, troisD: u == 1)
            for q in [0.0, 0.5, 1.0] {
                #expect(Self.finie(piece.orbite(q, depuis: o)), "vol vers une piece, u = \(u), q = \(q)")
                #expect(Self.finie(ensemble.orbite(q, depuis: o)), "vol vers l'ensemble, u = \(u), q = \(q)")
                #expect(Self.finie(etage.orbite(q, depuis: o)), "vol vers un etage, u = \(u), q = \(q)")
            }
        }
    }

    /// Un facteur de zoom non fini laisse la camera inchangee.
    @Test func zoomNonFini() {
        let g = Self.geometrie
        let o = CameraScene.canonique(g, aspect: Self.aspect, u: 0)
        let b = CameraScene.bornes(g, aspect: Self.aspect, troisD: false, champ: o.champ)
        for f in [Double.nan, .infinity, -.infinity] {
            #expect(CameraScene.zoomer(o, facteur: f, ancre: SIMD3(3, 0, -2), bornes: b) == o, "facteur \(f)")
            #expect(CameraScene.zoomer(o, facteur: f, ancre: nil, bornes: b) == o, "facteur \(f)")
        }
    }

    /// ⌥ + glisser (polissage C, section 6) : la cible et l'oeil glissent ensemble, parallelement a l'ecran, sans
    /// tourner ; un point a la profondeur de la cible suit le pointeur a 0,7 fois sa vitesse.
    @Test func deplacerDansLEcran() throws {
        var o = CameraScene.canonique(Self.geometrie, aspect: Self.aspect, u: 1)
        o.azimut += 0.7
        let d = CameraScene.deplacerDansLEcran(o, glisse: CGSize(width: 120, height: -45), cadre: Self.cadre)
        #expect(d.distance == o.distance && d.azimut == o.azimut && d.inclinaison == o.inclinaison && d.champ == o.champ)
        #expect(simd_distance(d.oeil - o.oeil, d.cible - o.cible) < 1e-9, "l'oeil suit la cible")
        #expect(abs(simd_dot(d.cible - o.cible, o.arriere)) < 1e-9, "parallele a l'ecran")
        let avant = try #require(ProjectionScene(o, cadre: Self.cadre).ecran(o.cible))
        let apres = try #require(ProjectionScene(d, cadre: Self.cadre).ecran(o.cible))
        #expect(abs((apres.x - avant.x) - 0.7 * 120) < 1e-6 && abs((apres.y - avant.y) + 0.7 * 45) < 1e-6)
        #expect(CameraScene.vitesseDeplacement == 0.7)
    }

    /// Plus de saut (polissage C, section 6) : apres la rotation lente et ⌥ + glisser, l'envol et les vols partent de
    /// la pose exacte de la camera (oeil, cible, champ), a 1e-6 pres.
    @Test func envolEtVolsDepuisLaPoseExacte() {
        let g = Self.geometrie
        var o = CameraScene.canonique(g, aspect: Self.aspect, u: 1)
        o.azimut -= 2.3
        o = CameraScene.deplacerDansLEcran(o, glisse: CGSize(width: -260, height: 140), cadre: Self.cadre)
        let debut = Envol(depuis: o, t: 1, vers: 0, geometrie: g, aspect: Self.aspect).pose(0, geometrie: g, aspect: Self.aspect)
        #expect(debut.t == 1 && debut.orbite.champ == o.champ)
        #expect(simd_distance(debut.orbite.oeil, o.oeil) < 1e-6 && simd_distance(debut.orbite.cible, o.cible) < 1e-6)
        for v in [CameraScene.volVersEnsemble(o, g, aspect: Self.aspect, u: 1, troisD: true),
                  CameraScene.volVersEtage(o, g, etage: 1, aspect: Self.aspect, u: 1, troisD: true)] {
            let p = v.orbite(0, depuis: o)
            #expect(simd_distance(p.oeil, o.oeil) < 1e-6 && simd_distance(p.cible, o.cible) < 1e-6 && p.champ == o.champ)
        }
    }

    /// Geometrie : plateaux empiles de 1,5 fois le plus grand rayon ; sphere et boite de la spec.
    @Test func geometrie() {
        let g = Self.geometrie
        #expect(g.pasEtage == 24)
        #expect(g.centreSphere == SIMD3(0, (24 + 2.4) / 2, 0))
        #expect(abs(g.rayonSphere - (hypot(16.8, 13.2 + 1.4) + 0.4)) < 1e-12)
        #expect(g.centrePlateau(1, 1) == SIMD3(0, 24, 0))
        #expect(g.centrePlateau(0, 0).x == g.centres2D[0].x)
        #expect(abs(g.boite.z0 - (-16 - 34.0 / 24)) < 1e-12 && g.boite.z1 == 16)
        #expect(GeometrieMaison.hauteurBloc(0) == 0.04 && abs(GeometrieMaison.hauteurBloc(1) - 2.44) < 1e-12)
        // `vers` (polissage C, section 3.5) : le chemin d'une geometrie a l'autre, champ par champ, avec deux avancements
        // distincts : en 2D (`k2`) les centres et la boite, en 3D (`k3`) les centres, le pas, la sphere et le cadrage ; les
        // rayons et les colonnes sont ceux de l'arrivee. Trois etages empiles, en une rangee, puis deux etages et une zone
        // hors de la maison, en une pile : chaque champ change.
        let depart = GeometrieMaison(rayons: [6, 8, 10], plateaux: [.init(niveau: 0), .init(niveau: 1), .init(niveau: 2)],
                                     colonnes: 3)
        let arrivee = GeometrieMaison(rayons: [6, 8, 10], plateaux: [.init(niveau: 0), .init(niveau: 1),
                                                                     .init(niveau: 1, principal: false, dehors: true)],
                                      colonnes: 1)
        #expect(depart.pasEtage != arrivee.pasEtage && depart.centreSphere != arrivee.centreSphere
                && depart.rayonSphere != arrivee.rayonSphere && depart.rayonCadre != arrivee.rayonCadre
                && depart.boite.x0 != arrivee.boite.x0 && depart.boite.x1 != arrivee.boite.x1
                && depart.boite.z0 != arrivee.boite.z0 && depart.boite.z1 != arrivee.boite.z1, "chaque champ change")
        let (k2, k3) = (0.25, 0.75)
        let v = depart.vers(arrivee, k2: k2, k3: k3)
        func m(_ x: Double, _ y: Double, _ k: Double) -> Double { x + (y - x) * k }
        for i in depart.rayons.indices {
            #expect(v.centres2D[i] == depart.centres2D[i] + (arrivee.centres2D[i] - depart.centres2D[i]) * k2, "centre 2D \(i)")
            #expect(v.centres3D[i] == depart.centres3D[i] + (arrivee.centres3D[i] - depart.centres3D[i]) * k3, "centre 3D \(i)")
        }
        let (a, b) = (depart.boite, arrivee.boite)
        #expect(v.boite == GeometrieMaison.Boite(x0: m(a.x0, b.x0, k2), x1: m(a.x1, b.x1, k2), z0: m(a.z0, b.z0, k2),
                                                 z1: m(a.z1, b.z1, k2)), "la boite, en 2D")
        #expect(v.pasEtage == m(depart.pasEtage, arrivee.pasEtage, k3), "le pas des etages, en 3D")
        #expect(v.centreSphere == depart.centreSphere + (arrivee.centreSphere - depart.centreSphere) * k3, "le centre de la sphere")
        #expect(v.rayonSphere == m(depart.rayonSphere, arrivee.rayonSphere, k3), "le rayon de la sphere")
        #expect(v.rayonCadre == m(depart.rayonCadre, arrivee.rayonCadre, k3), "le cadrage")
        #expect(v.rayons == arrivee.rayons && v.colonnes == arrivee.colonnes, "les rayons et les colonnes de l'arrivee")
    }

    /// Avec des etages seulement, en rangee (polissage C, sections 2 et 3.4) : exactement la geometrie du plan 4b,
    /// au bit pres, calculee ici par ses formules ; la vue d'ensemble 3D cadre la sphere.
    @Test(arguments: [[15.2, 16.0], [7.0], [10, 4, 6, 12.5], [9.94, 15.03, 11.39, 15.91, 8.2]])
    func etagesSeulementCommeAvant(_ r: [Double]) {
        let g = GeometrieMaison(rayons: r)
        let x = DispositionPieces.centres2D(rayons: r)
        let rmax = r.max() ?? 1, pas = 1.5 * rmax, yHaut = Double(r.count - 1) * pas
        #expect(g.colonnes == r.count && g.pasEtage == pas)
        #expect(g.centres2D == x.map { SIMD2($0, 0) })
        #expect(g.centres3D == r.indices.map { SIMD3(0, Double($0) * pas, 0) })
        #expect(g.centreSphere == SIMD3(0, (yHaut + GeometrieMaison.hauteurBloc3D) / 2, 0))
        #expect(g.rayonSphere == hypot(rmax + 0.8, (yHaut + GeometrieMaison.hauteurBloc3D) / 2 + 1.4) + 0.4)
        #expect(g.rayonCadre == g.rayonSphere)
        let boite = GeometrieMaison.Boite(x0: x[0] - r[0], x1: x[r.count - 1] + r[r.count - 1],
                                          z0: -rmax - GeometrieMaison.bandeNomsEtages, z1: rmax)
        #expect(g.boite == boite && g.cible2D == SIMD3((boite.x0 + boite.x1) / 2, 0, (boite.z0 + boite.z1) / 2))
        for e in r.indices {
            for u in [0, 0.3, 1.0] {
                let a = SIMD3(x[e], 0, 0), b = SIMD3(0, Double(e) * pas, 0)
                #expect(g.centrePlateau(e, u) == a + (b - a) * u)
            }
        }
        #expect(CameraScene.vue3D(g, aspect: Self.aspect) == 2.4 * g.rayonSphere * max(1, 1 / Self.aspect))
    }

    /// Plateaux de la maison des tests de C : le rez-de-chaussee (10) et ses zones a cote dans la maison (4, 5,
    /// 3), l'etage (12), et des zones hors de la maison au rez-de-chaussee (6, 5) et a l'etage (4, 3, 2).
    static let rayonsC: [Double] = [10, 4, 5, 3, 6, 5, 12, 4, 3, 2]
    static let plateauxC: [GeometrieMaison.Plateau] = [
        .init(niveau: 0), .init(niveau: 0, principal: false), .init(niveau: 0, principal: false),
        .init(niveau: 0, principal: false), .init(niveau: 0, principal: false, dehors: true),
        .init(niveau: 0, principal: false, dehors: true), .init(niveau: 1), .init(niveau: 1, principal: false, dehors: true),
        .init(niveau: 1, principal: false, dehors: true), .init(niveau: 1, principal: false, dehors: true),
    ]

    /// Zones dans la maison (polissage C, section 2) : a la hauteur de leur niveau, z = 0, la premiere a droite
    /// de l'etage principal, la deuxieme a gauche, la troisieme a droite apres la premiere, `esp` entre les bords ;
    /// le pas des niveaux suit le plus grand rayon dans la maison ; la sphere les englobe, centree sur leur boite.
    @Test func zonesDansLaMaison() {
        let g = GeometrieMaison(rayons: Self.rayonsC, plateaux: Self.plateauxC)
        let esp = DispositionPieces.esp
        #expect(g.pasEtage == 18, "1,5 fois 12, les zones hors de la maison n'y comptent pas")
        #expect(g.centres3D[0] == SIMD3(0, 0, 0) && g.centres3D[6] == SIMD3(0, 18, 0))
        #expect(g.centres3D[1] == SIMD3(10 + esp + 4, 0, 0))
        #expect(g.centres3D[2] == SIMD3(-(10 + esp + 5), 0, 0))
        #expect(g.centres3D[3] == SIMD3(10 + esp + 4 + 4 + esp + 3, 0, 0))
        let x0 = -(10 + esp + 5) - 5, x1 = 10 + esp + 4 + 4 + esp + 3 + 3, hh = (18 + GeometrieMaison.hauteurBloc3D) / 2
        #expect(abs(g.centreSphere.x - (x0 + x1) / 2) < 1e-12 && g.centreSphere.y == hh && g.centreSphere.z == 0)
        #expect(abs(g.rayonSphere - (hypot((x1 - x0) / 2 + 0.8, hh + 1.4) + 0.4)) < 1e-12)
        for e in Self.plateauxC.indices where !Self.plateauxC[e].dehors {
            let c = g.centres3D[e], r = Self.rayonsC[e]
            for p in [c + SIMD3(r, 0, 0), c - SIMD3(r, 0, 0), c + SIMD3(0, 0, r), c - SIMD3(0, 0, r),
                      c + SIMD3(r, GeometrieMaison.hauteurBloc3D, 0), c - SIMD3(r, -GeometrieMaison.hauteurBloc3D, 0)] {
                #expect(simd_distance(p, g.centreSphere) < g.rayonSphere, "plateau \(e) dans la sphere")
            }
        }
    }

    /// Zones hors de la maison : a la hauteur de leur niveau, autour de l'axe de la sphere, vers +x, -x, +z, -z,
    /// puis de nouveau +x, plus loin ; hors de la sphere ; le cadrage les couvre (`rayonCadre`), et la vue
    /// d'ensemble 3D les garde dans le cadre sur un tour de rotation lente.
    @Test func zonesHorsDeLaMaison() throws {
        let g = GeometrieMaison(rayons: Self.rayonsC, plateaux: Self.plateauxC)
        let esp = DispositionPieces.esp, c = g.centreSphere, rs = g.rayonSphere
        let attendus: [(Int, SIMD2<Double>, Double)] = [(4, [1, 0], rs + esp + 6), (5, [-1, 0], rs + esp + 5),
                                                        (7, [0, 1], rs + esp + 4), (8, [0, -1], rs + esp + 3),
                                                        (9, [1, 0], rs + esp + 6 + 6 + esp + 2)]
        for (e, d, dist) in attendus {
            let p = g.centres3D[e]
            #expect(abs(p.x - (c.x + d.x * dist)) < 1e-9 && abs(p.z - d.y * dist) < 1e-9, "plateau \(e)")
            #expect(p.y == Double(Self.plateauxC[e].niveau) * g.pasEtage)
            #expect(hypot(p.x - c.x, p.z) - Self.rayonsC[e] > rs, "plateau \(e) hors de la sphere")
        }
        #expect(abs(g.rayonCadre - (rs + esp + 6 + 6 + esp + 2 + 2)) < 1e-9)
        for k in 0..<24 {
            var o = CameraScene.canonique(g, aspect: Self.aspect, u: 1)
            o.azimut += Double(k) / 24 * 2 * .pi
            let proj = ProjectionScene(o, cadre: Self.cadre)
            for e in Self.rayonsC.indices {
                for a in stride(from: 0.0, to: 2 * .pi, by: .pi / 8) {
                    let p = g.centres3D[e] + SIMD3(Self.rayonsC[e] * cos(a), 0, Self.rayonsC[e] * sin(a))
                    let q = try #require(proj.ecran(p))
                    #expect(Self.cadre.contains(q), "plateau \(e), azimut \(k)")
                }
            }
        }
    }

    /// La grille (polissage C, section 3.3) : elle se remplit depuis la rangee du bas, de gauche a droite ; la
    /// rangee du haut, incomplete, est centree ; une colonne a le plus grand diametre de ses plateaux, une rangee
    /// le plus grand des siens plus la bande des noms, `esp` entre les cases ; chaque plateau est centre dans sa
    /// case, bande comprise.
    @Test func grille() {
        let g = GeometrieMaison(rayons: [10, 4, 6, 5, 3], colonnes: 2)
        let esp = DispositionPieces.esp, bande = GeometrieMaison.bandeNomsEtages
        #expect(g.colonnes == 2)
        #expect(abs(g.centres2D[0].x - (-(20 + esp + 10) / 2 + 10)) < 1e-9 && g.centres2D[0].y == 0)
        #expect(abs(g.centres2D[1].x - ((20 + esp + 10) / 2 - 5)) < 1e-9 && g.centres2D[1].y == 0, "en bas, a droite")
        let z1 = -(20.0 / 2 + bande + esp + 12.0 / 2)
        #expect(abs(g.centres2D[2].x - g.centres2D[0].x) < 1e-9 && abs(g.centres2D[2].y - z1) < 1e-9, "au-dessus")
        #expect(abs(g.centres2D[3].x - g.centres2D[1].x) < 1e-9 && abs(g.centres2D[3].y - z1) < 1e-9)
        let z2 = z1 - (12.0 / 2 + bande + esp + 6.0 / 2)
        #expect(abs(g.centres2D[4].x) < 1e-9 && abs(g.centres2D[4].y - z2) < 1e-9, "la rangee du haut, centree")
        #expect(abs(g.boite.x0 + (20 + esp + 10) / 2) < 1e-9 && abs(g.boite.x1 - (20 + esp + 10) / 2) < 1e-9)
        #expect(g.boite.z1 == 10 && abs(g.boite.z0 - (z2 - 3 - bande)) < 1e-9)
    }

    /// Le choix des colonnes (polissage C, section 3.3), sur les rayons de la maison de la maquette de C : 2 x 2
    /// dans une vue carree ou ordinaire (1100 x 760), la rangee dans une vue large (2,4 : 1) ; 3 + 1 en 1440 x 900,
    /// ou 2 x 2 est a plus de 10 % de la plus grande echelle. Sur quatre plateaux de 12, la rangee a 89,4 % de
    /// l'echelle de 2 x 2 reste hors de la bande de 10 % (1790 x 1000) ; a 90,9 %, elle y entre (1820 x 1000, dans
    /// `hysteresisEtTailleNulle`). A moins de 10 %, le moins de cases vides passe avant le moins de rangees : sur
    /// sept plateaux de 12 (700 x 1000), 2 colonnes (4 rangees, 1 case vide) avant 3 colonnes (3 rangees, 2 cases
    /// vides, a 0,3 % de la meme echelle) ; a cases vides egales, le moins de rangees : la rangee avant 2 x 2.
    @Test func choixDesColonnes() {
        let r = [15.91, 11.39, 15.03, 9.94]
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 1100, height: 760)) == 2)
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 760, height: 760)) == 2)
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 1824, height: 760)) == 4)
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 1440, height: 900)) == 3)
        #expect(GeometrieMaison.colonnes(rayons: [12, 12, 12, 12], taille: CGSize(width: 1600, height: 1000)) == 2)
        #expect(GeometrieMaison.colonnes(rayons: [12, 12, 12, 12], taille: CGSize(width: 1900, height: 1000)) == 4)
        // La bande de 10 % : la rangee a 89,4 % de l'echelle de 2 x 2 n'y est pas (a 90,9 %, elle y est : 1820 x 1000,
        // dans `hysteresisEtTailleNulle`).
        #expect(GeometrieMaison.colonnes(rayons: [12, 12, 12, 12], taille: CGSize(width: 1790, height: 1000)) == 2,
                "la rangee a 89,4 %, hors de la bande de 10 %")
        // Sept plateaux : 2 colonnes (4 rangees, 1 case vide) et 3 colonnes (3 rangees, 2 cases vides) sont a 0,3 %
        // l'une de l'autre ; le moins de cases vides l'emporte sur le moins de rangees.
        let sept = Array(repeating: 12.0, count: 7)
        #expect(GeometrieMaison.colonnes(rayons: sept, taille: CGSize(width: 700, height: 1000)) == 2,
                "le moins de cases vides avant le moins de rangees : 2 colonnes, pas 3")
        #expect(GeometrieMaison.colonnes(rayons: [7], taille: CGSize(width: 800, height: 600)) == 1)
    }

    /// Hysteresis (polissage C, section 3.3) : la grille en place reste tant que son echelle est a moins de 5 % de
    /// celle du choix. Une taille de 1 pt ou moins ne choisit rien : la grille en place, ou rien ; la premiere
    /// vraie taille choisit.
    @Test func hysteresisEtTailleNulle() {
        let r = [12.0, 12, 12, 12]
        // Vers 1,8 : la rangee entre dans les 10 % de 2 x 2 et l'emporte (moins de rangees).
        let pres = CGSize(width: 1820, height: 1000)
        #expect(GeometrieMaison.colonnes(rayons: r, taille: pres) == 4)
        #expect(GeometrieMaison.colonnes(rayons: r, taille: pres, enPlace: 2) == 2, "2 x 2 en place, a moins de 5 %")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 2200, height: 1000), enPlace: 2) == 4)
        // La bande de 5 %, des deux cotes : a 2050 x 1000, 2 x 2 en place est a 97,7 % de l'echelle du choix (la
        // rangee) et reste ; a 2150 x 1000, il est a 93,2 % et la rangee l'emporte.
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 2050, height: 1000), enPlace: 2) == 2,
                "2 x 2 en place a 97,7 % du choix : il reste")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 2150, height: 1000), enPlace: 2) == 4,
                "2 x 2 en place a 93,2 % du choix : la rangee l'emporte")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 1, height: 600), enPlace: 2) == 2)
        // Une hauteur de 1 pt, comme une largeur de 1 pt, ne choisit rien.
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 600, height: 1), enPlace: 2) == 2,
                "1 pt de haut : la grille en place")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 600, height: 1)) == nil,
                "1 pt de haut : rien a choisir")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: .zero) == nil, "attendre une vraie taille")
        #expect(GeometrieMaison.colonnes(rayons: r, taille: CGSize(width: 1100, height: 760)) == 2)
    }

    /// La rotation lente (spec de la vue par pieces, section 7 ; polissage D, section 4.2) : en 3D, l'envol fini,
    /// cochee, sans « Reduire les animations », hors d'un geste ; chaque condition l'arrete. L'isolement, non : il
    /// n'entre pas dans la regle.
    @Test func rotationLente() {
        #expect(CameraScene.rotationLente(troisD: true, bascule: 1, cochee: true, reduire: false, geste: false))
        #expect(!CameraScene.rotationLente(troisD: false, bascule: 1, cochee: true, reduire: false, geste: false))
        #expect(!CameraScene.rotationLente(troisD: true, bascule: 0.999, cochee: true, reduire: false, geste: false))
        #expect(!CameraScene.rotationLente(troisD: true, bascule: 1, cochee: false, reduire: false, geste: false))
        #expect(!CameraScene.rotationLente(troisD: true, bascule: 1, cochee: true, reduire: true, geste: false))
        #expect(!CameraScene.rotationLente(troisD: true, bascule: 1, cochee: true, reduire: false, geste: true))
    }

    /// Cadrage d'un etage isole (polissage C, section 5.1) : en 2D, vue de dessus, la cible au centre de sa boite,
    /// bande du nom comprise, la boite dans le cadre ; en 3D, meme azimut et meme inclinaison, la cible au centre
    /// du plateau, a sa hauteur ; la hauteur de vue max((2 r + bande) 1,1 ; 2 r 1,05 / aspect).
    @Test func cadrageDUnEtage() throws {
        let g = GeometrieMaison(rayons: Self.rayonsC, plateaux: Self.plateauxC, colonnes: 4)
        let bande = GeometrieMaison.bandeNomsEtages
        for e in [0, 4, 6] {
            let r = Self.rayonsC[e], vue = max((2 * r + bande) * 1.1, 2 * r * 1.05 / Self.aspect)
            #expect(CameraScene.vueEtage(g, etage: e, aspect: Self.aspect) == vue)
            let o2 = CameraScene.canonique(g, aspect: Self.aspect, u: 0)
            let v2 = CameraScene.volVersEtage(o2, g, etage: e, aspect: Self.aspect, u: 0, troisD: false).orbite(1, depuis: o2)
            let c = g.centres2D[e]
            #expect(simd_distance(v2.cible, SIMD3(c.x, 0, c.y - bande / 2)) < 1e-9)
            #expect(abs(v2.distance - Orbite.distance(pourHauteur: vue, champ: 2)) < 1e-6 && v2.inclinaison < 1e-3)
            let p = ProjectionScene(v2, cadre: Self.cadre)
            for q in [SIMD3(c.x - r, 0, c.y - r - bande), SIMD3(c.x + r, 0, c.y + r)] {
                #expect(Self.cadre.contains(try #require(p.ecran(q))), "etage \(e) dans le cadre")
            }
            var o3 = CameraScene.canonique(g, aspect: Self.aspect, u: 1)
            o3.azimut += 0.4
            let v3 = CameraScene.volVersEtage(o3, g, etage: e, aspect: Self.aspect, u: 1, troisD: true).orbite(1, depuis: o3)
            #expect(simd_distance(v3.cible, g.centres3D[e]) < 1e-9)
            #expect(abs(v3.azimut - o3.azimut) < 1e-9 && abs(v3.inclinaison - o3.inclinaison) < 1e-9)
            #expect(abs(v3.distance - Orbite.distance(pourHauteur: vue, champ: 40)) < 1e-6)
        }
    }
}
