import CoreGraphics
import Foundation
import simd

/// Camera en orbite autour de sa cible (spec de la vue par pieces, section 7) : distance, azimut
/// (autour de y, 0 quand l'oeil est du cote +z), inclinaison depuis la verticale, champ vertical en
/// degres. L'axe y monte.
public struct Orbite: Hashable, Sendable {
    public var cible: SIMD3<Double>
    public var distance: Double
    public var azimut: Double
    public var inclinaison: Double
    public var champ: Double

    public init(cible: SIMD3<Double>, distance: Double, azimut: Double, inclinaison: Double, champ: Double) {
        self.cible = cible
        self.distance = distance
        self.azimut = azimut
        self.inclinaison = inclinaison
        self.champ = champ
    }

    /// De la cible vers l'oeil : l'axe z de la camera (elle regarde vers -z).
    public var arriere: SIMD3<Double> {
        SIMD3(sin(inclinaison) * sin(azimut), cos(inclinaison), sin(inclinaison) * cos(azimut))
    }

    /// Axe x de la camera, defini meme a la verticale.
    public var droite: SIMD3<Double> { SIMD3(cos(azimut), 0, -sin(azimut)) }
    public var haut: SIMD3<Double> { simd_cross(arriere, droite) }
    public var oeil: SIMD3<Double> { cible + arriere * distance }

    /// Place l'oeil et la cible (vol de camera) ; l'azimut reste continu.
    public mutating func placer(oeil: SIMD3<Double>, cible c: SIMD3<Double>) {
        let v = oeil - c
        let d = simd_length(v)
        guard d > 1e-9 else { return }
        cible = c
        distance = d
        inclinaison = acos(min(1, max(-1, v.y / d)))
        if abs(v.x) + abs(v.z) > 1e-9 * d {
            let a = atan2(v.x, v.z)
            azimut = a + 2 * .pi * ((azimut - a) / (2 * .pi)).rounded()
        }
    }

    /// Distance a laquelle un champ vertical de `champ` degres couvre `hauteur` unites.
    public static func distance(pourHauteur hauteur: Double, champ: Double) -> Double {
        hauteur / (2 * tan(champ * .pi / 360))
    }
}

/// Projection d'une image : du monde a la camera par une matrice, puis perspective vers l'ecran
/// (points, origine en haut a gauche). Le cadre est la place utile de la vue : son centre est le
/// point principal, sa hauteur regle la focale. Plan proche a 0,5.
public struct ProjectionScene: Sendable {
    public static let proche = 0.5
    public let vue: simd_double4x4
    /// Points par unite a une profondeur de 1.
    public let focale: Double
    public let centre: CGPoint
    let droite, haut, arriere, oeil: SIMD3<Double>

    public init(_ o: Orbite, cadre: CGRect) {
        let x = o.droite, y = o.haut, z = o.arriere, e = o.oeil
        vue = simd_double4x4(rows: [
            SIMD4(x.x, x.y, x.z, -simd_dot(x, e)),
            SIMD4(y.x, y.y, y.z, -simd_dot(y, e)),
            SIMD4(z.x, z.y, z.z, -simd_dot(z, e)),
            SIMD4(0, 0, 0, 1),
        ])
        focale = Double(cadre.height) / 2 / tan(o.champ * .pi / 360)
        centre = CGPoint(x: cadre.midX, y: cadre.midY)
        droite = x
        haut = y
        arriere = z
        oeil = e
    }

    /// Coordonnees camera : x a droite, y en haut, z vers l'arriere (profondeur = -z).
    public func camera(_ p: SIMD3<Double>) -> SIMD3<Double> {
        let v = vue * SIMD4(p.x, p.y, p.z, 1)
        return SIMD3(v.x, v.y, v.z)
    }

    public func ecran(camera q: SIMD3<Double>) -> CGPoint {
        let d = -q.z
        return CGPoint(x: Double(centre.x) + q.x * focale / d, y: Double(centre.y) - q.y * focale / d)
    }

    /// Point de l'ecran, ou nil s'il est derriere le plan proche.
    public func ecran(_ p: SIMD3<Double>) -> CGPoint? {
        let q = camera(p)
        return -q.z >= Self.proche ? ecran(camera: q) : nil
    }

    public func profondeur(_ p: SIMD3<Double>) -> Double { -camera(p).z }

    /// Points de l'ecran par unite du monde, a la profondeur de `p`.
    public func pxParUnite(_ p: SIMD3<Double>) -> Double { focale / max(0.01, profondeur(p)) }

    /// Polygone plan du monde, coupe par le plan proche (Sutherland-Hodgman) ; nil s'il n'en reste rien.
    public func polygone(_ pts: [SIMD3<Double>]) -> [CGPoint]? {
        let q = pts.map(camera)
        var sortie: [SIMD3<Double>] = []
        sortie.reserveCapacity(q.count + 2)
        for i in q.indices {
            let a = q[i], b = q[(i + 1) % q.count]
            let da = -a.z - Self.proche, db = -b.z - Self.proche
            if da >= 0 { sortie.append(a) }
            if (da >= 0) != (db >= 0) { sortie.append(a + (b - a) * (da / (da - db))) }
        }
        return sortie.count >= 3 ? sortie.map { ecran(camera: $0) } : nil
    }

    /// Segment du monde coupe par le plan proche.
    public func segment(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> (CGPoint, CGPoint)? {
        var qa = camera(a), qb = camera(b)
        let da = -qa.z - Self.proche, db = -qb.z - Self.proche
        if da < 0 && db < 0 { return nil }
        if da < 0 {
            qa += (qb - qa) * (da / (da - db))
        } else if db < 0 {
            qb += (qa - qb) * (db / (db - da))
        }
        return (ecran(camera: qa), ecran(camera: qb))
    }

    /// Ligne brisee (fermee ou non), en morceaux devant le plan proche.
    public func polyligne(_ pts: [SIMD3<Double>], fermee: Bool) -> [[CGPoint]] {
        var morceaux: [[CGPoint]] = []
        var courant: [CGPoint] = []
        let n = fermee ? pts.count : pts.count - 1
        for i in 0..<max(0, n) {
            guard let (a, b) = segment(pts[i], pts[(i + 1) % pts.count]) else {
                if !courant.isEmpty { morceaux.append(courant) }
                courant = []
                continue
            }
            if let f = courant.last, abs(f.x - a.x) + abs(f.y - a.y) < 0.01 {
                courant.append(b)
            } else {
                if !courant.isEmpty { morceaux.append(courant) }
                courant = [a, b]
            }
        }
        if !courant.isEmpty { morceaux.append(courant) }
        return morceaux
    }

    /// Point du plan horizontal y = `hauteur` vise par un point de l'ecran ; nil s'il est derriere l'oeil.
    public func sol(_ point: CGPoint, hauteur h: Double) -> SIMD3<Double>? {
        let dir = droite * ((Double(point.x) - Double(centre.x)) / focale)
            + haut * ((Double(centre.y) - Double(point.y)) / focale) - arriere
        guard abs(dir.y) > 1e-12 else { return nil }
        let s = (h - oeil.y) / dir.y
        return s > 0 ? oeil + dir * s : nil
    }

    /// Affine qui envoie le disque unite sur l'ellipse, projetee, d'un disque horizontal (degrade d'un
    /// plateau) ; nil si un point cardinal est derriere l'oeil ou si l'ellipse est plate.
    public func disque(_ c: SIMD3<Double>, _ r: Double) -> CGAffineTransform? {
        guard let o = ecran(c), let xp = ecran(c + SIMD3(r, 0, 0)), let xm = ecran(c - SIMD3(r, 0, 0)),
              let zp = ecran(c + SIMD3(0, 0, r)), let zm = ecran(c - SIMD3(0, 0, r)) else { return nil }
        let m = CGAffineTransform(a: (xp.x - xm.x) / 2, b: (xp.y - xm.y) / 2, c: (zp.x - zm.x) / 2,
                                  d: (zp.y - zm.y) / 2, tx: o.x, ty: o.y)
        return abs(m.a * m.d - m.b * m.c) > 1e-3 ? m : nil
    }

    /// Contour exact d'une sphere en perspective : l'ellipse ou le cone tangent depuis l'oeil coupe le
    /// plan de l'image (un cercle seulement dans l'axe). Rend l'affine qui envoie le disque unite sur
    /// cette ellipse ; nil si l'oeil est dans la sphere ou trop pres d'elle.
    public func contourSphere(_ c: SIMD3<Double>, _ r: Double) -> CGAffineTransform? {
        let q = camera(c)
        let d = simd_length(q)
        guard d > r * 1.0001, -q.z > Self.proche else { return nil }
        let sinA = r / d, cosA = (1 - sinA * sinA).squareRoot()
        let cosT = -q.z / d, sinT = max(0, 1 - cosT * cosT).squareRoot()
        let den = cosT * cosT - sinA * sinA
        guard den > 1e-4 else { return nil }
        let decalage = focale * sinT * cosT / den, a = focale * sinA * cosA / den, b = focale * sinA / den.squareRoot()
        var u = SIMD2(q.x, -q.y)
        u = simd_length(u) > 1e-9 ? simd_normalize(u) : SIMD2(1, 0)
        return CGAffineTransform(a: u.x * a, b: u.y * a, c: -u.y * b, d: u.x * b,
                                 tx: Double(centre.x) + u.x * decalage, ty: Double(centre.y) + u.y * decalage)
    }
}

/// Geometrie de la maison pour la camera (spec de la vue par pieces, section 4.4, remplacee par le polissage C,
/// sections 2 et 3) : les plateaux en 2D, en grille ou en rangee ; en 3D, les niveaux empiles, les zones a cote
/// dans ou hors de la maison ; la sphere de la maison ; le rayon que cadre la vue d'ensemble 3D ; la boite de
/// cadrage de la 2D. Avec des etages seulement et en rangee, les valeurs du plan 4b, au bit pres.
public struct GeometrieMaison: Hashable, Sendable {
    public static let hauteurBloc3D = 2.4
    /// Bande des noms d'etage au-dessus des plateaux, en 2D (34 px).
    public static let bandeNomsEtages = 34 / CartesPieces.px

    /// La place d'un plateau dans les niveaux (`ScenePieces.Etage`) : son niveau (0 en bas), etage principal ou
    /// zone a cote, hors de la maison.
    public struct Plateau: Hashable, Sendable {
        public var niveau: Int
        public var principal: Bool
        public var dehors: Bool

        public init(niveau: Int, principal: Bool = true, dehors: Bool = false) {
            self.niveau = niveau
            self.principal = principal
            self.dehors = dehors
        }
    }

    public var rayons: [Double]
    /// Centre de chaque plateau en 2D (x, z), et en 3D.
    public var centres2D: [SIMD2<Double>]
    public var centres3D: [SIMD3<Double>]
    /// Colonnes de la grille 2D : de 1 au nombre de plateaux, la rangee.
    public var colonnes: Int
    /// Pas entre deux niveaux en 3D : 1,5 fois le plus grand rayon des plateaux dans la maison.
    public var pasEtage: Double
    public var centreSphere: SIMD3<Double>
    public var rayonSphere: Double
    /// Le rayon que cadre la vue d'ensemble 3D : le plus grand de la sphere et des distances a son axe des
    /// bords exterieurs des zones hors de la maison.
    public var rayonCadre: Double
    public var boite: Boite

    public struct Boite: Hashable, Sendable {
        public var x0, x1, z0, z1: Double
    }

    /// Le centre de la boite de cadrage de la 2D.
    public var cible2D: SIMD3<Double> { SIMD3((boite.x0 + boite.x1) / 2, 0, (boite.z0 + boite.z1) / 2) }

    /// `rayons` : ceux des plateaux, dans l'ordre de la scene (niveau par niveau) ; `plateaux` : leur place dans
    /// les niveaux (nil : un etage par plateau) ; `colonnes` : celles de la grille 2D (nil : la rangee).
    public init(rayons: [Double], plateaux: [Plateau]? = nil, colonnes: Int? = nil) {
        let r = rayons.isEmpty ? [DispositionPieces.marge] : rayons
        let p = plateaux.flatMap { $0.count == r.count ? $0 : nil } ?? r.indices.map { Plateau(niveau: $0) }
        self.rayons = r
        self.colonnes = max(1, min(r.count, colonnes ?? r.count))
        (centres2D, boite) = Self.grille(r, colonnes: self.colonnes)
        // La pile : les etages sur l'axe, au pas de 1,5 fois le plus grand rayon dans la maison.
        let dans = r.indices.filter { !p[$0].dehors }
        let rmax = dans.map { r[$0] }.max() ?? 1
        let pas = 1.5 * rmax
        let niveaux = (p.map(\.niveau).max() ?? 0) + 1
        let hh = (Double(niveaux - 1) * pas + Self.hauteurBloc3D) / 2
        var c3 = r.indices.map { SIMD3(0, Double(p[$0].niveau) * pas, 0) }
        // Les zones a cote dans la maison : la premiere a droite (+x) de l'etage principal, la deuxieme a
        // gauche (-x), puis en alternant, de plus en plus loin, `esp` entre les bords.
        for n in 0..<niveaux {
            guard let e0 = r.indices.first(where: { p[$0].niveau == n && p[$0].principal }) else { continue }
            var bord = [r[e0], r[e0]]
            for (k, e) in r.indices.filter({ p[$0].niveau == n && !p[$0].principal && !p[$0].dehors }).enumerated() {
                let cote = k % 2, x = bord[cote] + DispositionPieces.esp + r[e]
                c3[e].x = cote == 0 ? x : -x
                bord[cote] = x + r[e]
            }
        }
        // La sphere englobe les plateaux dans la maison.
        let x0 = dans.map { c3[$0].x - r[$0] }.min() ?? -1, x1 = dans.map { c3[$0].x + r[$0] }.max() ?? 1
        let centre = SIMD3((x0 + x1) / 2, hh, 0), rs = hypot((x1 - x0) / 2 + 0.8, hh + 1.4) + 0.4
        // Hors de la maison : autour de l'axe de la sphere, vers +x, -x, +z, -z, puis de nouveau, la premiere a
        // R + esp + r de l'axe, mesure a plat, la suivante plus loin, `esp` entre les bords.
        let directions: [SIMD2<Double>] = [[1, 0], [-1, 0], [0, 1], [0, -1]]
        var loin = [Double](repeating: rs, count: 4)
        var cadre = rs
        for (k, e) in r.indices.filter({ p[$0].dehors }).enumerated() {
            let d = k % 4, dist = loin[d] + DispositionPieces.esp + r[e]
            c3[e].x = centre.x + directions[d].x * dist
            c3[e].z = directions[d].y * dist
            loin[d] = dist + r[e]
            cadre = max(cadre, loin[d])
        }
        pasEtage = pas
        centres3D = c3
        centreSphere = centre
        rayonSphere = rs
        rayonCadre = cadre
    }

    /// La grille 2D (polissage C, section 3.3) : elle se remplit depuis la rangee du bas (vers +z), de gauche a
    /// droite ; la rangee du haut, incomplete, est centree. Une colonne a la largeur du plus grand diametre de ses
    /// plateaux ; une rangee, la hauteur du plus grand des siens, plus la bande des noms d'etage, au-dessus ;
    /// `esp` entre les cases ; chaque plateau est centre dans sa case, bande comprise. La rangee du bas est en
    /// z = 0, et une rangee est centree sur x = 0 comme la rangee du plan 4b (`DispositionPieces.centres2D`).
    static func grille(_ r: [Double], colonnes c: Int) -> (centres: [SIMD2<Double>], boite: Boite) {
        let rangees = stride(from: 0, to: r.count, by: c).map { Array($0..<min($0 + c, r.count)) }
        let d = r.map { 2 * $0 }
        let larg = (0..<c).map { k in rangees.map { k < $0.count ? d[$0[k]] : 0 }.max() ?? 0 }
        let dmax = rangees.map { $0.map { d[$0] }.max() ?? 0 }
        var centres = [SIMD2<Double>](repeating: .zero, count: r.count)
        var z = 0.0, x0 = Double.infinity, x1 = -Double.infinity
        for (i, rangee) in rangees.enumerated() {
            if i > 0 { z = z - dmax[i - 1] / 2 - bandeNomsEtages - DispositionPieces.esp - dmax[i] / 2 }
            let x = DispositionPieces.centres2D(rayons: rangee.indices.map { larg[$0] / 2 })
            for (k, e) in rangee.enumerated() { centres[e] = SIMD2(x[k], z) }
            x0 = min(x0, x[0] - larg[0] / 2)
            x1 = max(x1, x[rangee.count - 1] + larg[rangee.count - 1] / 2)
        }
        return (centres, Boite(x0: x0, x1: x1, z0: z - dmax[rangees.count - 1] / 2 - bandeNomsEtages, z1: dmax[0] / 2))
    }

    /// Le nombre de colonnes de la grille (polissage C, section 3.3) pour une vue de `taille` points. L'echelle
    /// d'une grille est min(largeur / sa largeur, hauteur / sa hauteur) ; parmi les grilles a moins de 10 % de la
    /// plus grande echelle, celle qui a le moins de cases vides, puis le moins de rangees. `enPlace` : la grille en
    /// place, qui reste tant que son echelle est a moins de 5 % de celle du choix (au redimensionnement). Une
    /// taille de 1 pt ou moins ne choisit rien : la grille en place, ou nil, attendre une vraie taille.
    public static func colonnes(rayons: [Double], taille: CGSize, enPlace: Int? = nil) -> Int? {
        let n = rayons.count
        guard n > 0, taille.width > 1, taille.height > 1 else { return enPlace }
        let candidats = (1...n).map { c -> (c: Int, echelle: Double, vides: Int, rangees: Int) in
            let b = grille(rayons, colonnes: c).boite
            let rangees = (n + c - 1) / c
            return (c, min(Double(taille.width) / (b.x1 - b.x0), Double(taille.height) / (b.z1 - b.z0)),
                    c * rangees - n, rangees)
        }
        let meilleure = candidats.map(\.echelle).max() ?? 0
        guard let choix = candidats.filter({ $0.echelle >= 0.9 * meilleure })
            .min(by: { ($0.vides, $0.rangees) < ($1.vides, $1.rangees) }) else { return enPlace }
        if let e = enPlace, let g = candidats.first(where: { $0.c == e }), g.echelle >= 0.95 * choix.echelle { return e }
        return choix.c
    }

    /// Centre du plateau `e` a l'avancement `u` de la bascule (0 : 2D, 1 : 3D).
    public func centrePlateau(_ e: Int, _ u: Double) -> SIMD3<Double> {
        let a = SIMD3(centres2D[e].x, 0, centres2D[e].y), b = centres3D[e]
        return a + (b - a) * u
    }

    /// La geometrie en route de celle-ci, au depart, vers `b`, qui a les memes plateaux dans le meme ordre
    /// (polissage C, sections 1.3 et 3.5) : en 2D a l'avancement `k2` (les centres et la boite), en 3D a `k3`
    /// (les centres, le pas, la sphere et le cadrage) ; les rayons et les colonnes sont ceux de `b`.
    public func vers(_ b: GeometrieMaison, k2: Double, k3: Double) -> GeometrieMaison {
        func m(_ x: Double, _ y: Double, _ k: Double) -> Double { x + (y - x) * k }
        var g = b
        for i in g.rayons.indices where i < centres2D.count {
            g.centres2D[i] = centres2D[i] + (b.centres2D[i] - centres2D[i]) * k2
            g.centres3D[i] = centres3D[i] + (b.centres3D[i] - centres3D[i]) * k3
        }
        g.boite = Boite(x0: m(boite.x0, b.boite.x0, k2), x1: m(boite.x1, b.boite.x1, k2), z0: m(boite.z0, b.boite.z0, k2),
                        z1: m(boite.z1, b.boite.z1, k2))
        g.pasEtage = m(pasEtage, b.pasEtage, k3)
        g.centreSphere = centreSphere + (b.centreSphere - centreSphere) * k3
        g.rayonSphere = m(rayonSphere, b.rayonSphere, k3)
        g.rayonCadre = m(rayonCadre, b.rayonCadre, k3)
        return g
    }

    /// Hauteur des blocs : 0,04 en 2D, 2,44 en 3D.
    public static func hauteurBloc(_ u: Double) -> Double { 0.04 + hauteurBloc3D * u }
}

/// Camera de la vue (spec, section 7) : vues d'ensemble, envol, vols, zoom vers le curseur, bornes, rotation lente.
public enum CameraScene {
    public static let champ2D = 2.0
    public static let champ3D = 40.0
    public static let inclinaison3D = 0.95
    public static let orbite3D = -0.75
    public static let dureeEnvol = 2.6
    public static let dureeVol = 1.3
    /// Glissement des plateaux vers leur nouvelle case en 2D : au redimensionnement, et apres un changement de
    /// niveau (polissage C, sections 1.3 et 3.5) ; au changement du reglage, celui de l'envol (`dureeEnvol`).
    public static let dureeCases = 0.4
    /// Glissement des plateaux, de la sphere et du cadrage vers leur nouvelle place en 3D, apres un changement de
    /// niveau (polissage C, section 1.3).
    public static let dureeNiveaux = 0.9
    /// « Reduire les animations » : l'envol devient un fondu.
    public static let dureeFondu = 0.3
    /// Rotation lente : un tour en deux minutes.
    public static let dureeTour = 120.0

    /// La rotation lente tourne (spec de la vue par pieces, section 7) : en 3D, l'envol fini (`bascule` a 1), cochee,
    /// sans « Reduire les animations », hors d'un geste (`geste` : un glisser, la molette, un pincement). Elle continue
    /// quand une piece ou un etage est isole (polissage D, section 4.2), autour de la cible de la camera.
    public static func rotationLente(troisD: Bool, bascule: Double, cochee: Bool, reduire: Bool, geste: Bool) -> Bool {
        troisD && bascule == 1 && cochee && !reduire && !geste
    }

    /// Rampe de la maquette : cubique entree-sortie.
    public static func rampe(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    /// Aspect (largeur / hauteur du cadre) sur, a l'entree de chaque fonction qui le recoit. Un cadre
    /// vide pendant une mise en page donne un aspect nul ou non fini, qui rendrait la camera NaN (vue
    /// infinie, puis inf - inf) et l'y laisserait : un aspect non fini, nul ou negatif vaut 1,6, le
    /// repli de l'app pour une hauteur nulle (format d'une fenetre ordinaire) ; les autres sont
    /// bornes de 0,05 a 20, bien au-dela de toute fenetre reelle, ce qui garde les distances finies
    /// (au plus 20 fois la vue d'ensemble ordinaire). Entre 0,05 et 20, l'aspect est rendu tel quel.
    fileprivate static func aspectSur(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0 else { return 1.6 }
        return min(20, max(0.05, aspect))
    }

    /// Hauteur de vue de la vue d'ensemble 2D, centree sur la boite de cadrage.
    public static func vue2D(_ g: GeometrieMaison, aspect: Double) -> Double {
        let aspect = aspectSur(aspect)
        return max((g.boite.z1 - g.boite.z0) * 1.1, (g.boite.x1 - g.boite.x0) * 1.05 / aspect)
    }

    /// Hauteur de vue de la vue d'ensemble 3D, centree sur la sphere : elle cadre la sphere et les zones hors de
    /// la maison (polissage C, section 2).
    public static func vue3D(_ g: GeometrieMaison, aspect: Double) -> Double {
        let aspect = aspectSur(aspect)
        return 2.4 * g.rayonCadre * max(1, 1 / aspect)
    }

    public static func vue(_ g: GeometrieMaison, aspect: Double, u: Double) -> Double {
        let aspect = aspectSur(aspect)
        return vue2D(g, aspect: aspect) + (vue3D(g, aspect: aspect) - vue2D(g, aspect: aspect)) * u
    }

    /// Champ a l'avancement u de la bascule : 2 + 38 u^1,6 degres.
    public static func champ(_ u: Double) -> Double { champ2D + (champ3D - champ2D) * pow(u, 1.6) }

    /// Pose canonique a l'avancement u de la bascule : vue d'ensemble 2D (u = 0), 3D (u = 1).
    public static func canonique(_ g: GeometrieMaison, aspect: Double, u: Double) -> Orbite {
        let aspect = aspectSur(aspect)
        let f = champ(u)
        return Orbite(cible: g.cible2D + (g.centreSphere - g.cible2D) * u,
                      distance: Orbite.distance(pourHauteur: vue(g, aspect: aspect, u: u), champ: f),
                      azimut: orbite3D * u, inclinaison: 0.0001 + inclinaison3D * u, champ: f)
    }

    /// Bornes de la distance : de 3 unites de hauteur de vue a 3 fois la vue d'ensemble en 2D ; de 5
    /// unites a 2,5 fois la vue d'ensemble en 3D.
    public static func bornes(_ g: GeometrieMaison, aspect: Double, troisD: Bool, champ: Double) -> ClosedRange<Double> {
        let aspect = aspectSur(aspect)
        if troisD {
            return 5...max(5, Orbite.distance(pourHauteur: vue3D(g, aspect: aspect) * 2.5, champ: champ))
        }
        let bas = Orbite.distance(pourHauteur: 3, champ: champ)
        return bas...max(bas, Orbite.distance(pourHauteur: vue2D(g, aspect: aspect) * 3, champ: champ))
    }

    /// Zoom d'un pas (`facteur` : log du rapport des distances), borne ; vers `ancre` si elle est donnee
    /// (le point du monde sous le curseur, qui reste sous le curseur). Un facteur non fini laisse la
    /// camera inchangee.
    public static func zoomer(_ o: Orbite, facteur: Double, ancre: SIMD3<Double>?, bornes: ClosedRange<Double>) -> Orbite {
        guard facteur.isFinite else { return o }
        var r = o
        let d = min(bornes.upperBound, max(bornes.lowerBound, o.distance * exp(facteur)))
        if let a = ancre { r.cible = a + (o.cible - a) * (d / o.distance) }
        r.distance = d
        return r
    }

    /// ⌥ + glisser en 3D (polissage C, section 6) : la vue suit le pointeur a 0,7 fois sa vitesse, mesuree a la cible.
    public static let vitesseDeplacement = 0.7

    /// La vue deplacee dans le plan de l'ecran, depuis l'orbite `o` de l'appui, pour un deplacement du pointeur de
    /// `glisse` points (vers la droite et vers le bas) : la cible et l'oeil glissent ensemble, parallelement a
    /// l'ecran, sans tourner ; un point a la profondeur de la cible suit le pointeur a 0,7 fois sa vitesse.
    public static func deplacerDansLEcran(_ o: Orbite, glisse: CGSize, cadre: CGRect) -> Orbite {
        let focale = Double(max(1, cadre.height)) / 2 / tan(o.champ * .pi / 360)
        let k = vitesseDeplacement * o.distance / focale
        var r = o
        r.cible += o.droite * (-Double(glisse.width) * k) + o.haut * (Double(glisse.height) * k)
        return r
    }

    /// Direction de l'oeil pour un vol : celle de la camera en 3D, la verticale en 2D.
    public static func directionVue(_ o: Orbite, troisD: Bool) -> SIMD3<Double> {
        troisD ? o.arriere : simd_normalize(SIMD3(0, 1, 0.0001))
    }

    /// Vol vers une piece isolee : hauteur de vue max(largeur / aspect, profondeur) 1,3 1,8 + 6 unites.
    public static func volVersPiece(_ o: Orbite, centre: SIMD3<Double>, largeur: Double, profondeur: Double,
                                    aspect: Double, troisD: Bool) -> Vol {
        let aspect = aspectSur(aspect)
        let d = Orbite.distance(pourHauteur: max(largeur / aspect, profondeur) * 1.3 * 1.8 + 6, champ: o.champ)
        return Vol(depuis: o, oeil: centre + directionVue(o, troisD: troisD) * d, cible: centre)
    }

    /// Hauteur de vue d'un etage isole (polissage C, section 5.1), bande de son nom comprise :
    /// max((2 r + bande) 1,1 ; 2 r 1,05 / aspect).
    public static func vueEtage(_ g: GeometrieMaison, etage e: Int, aspect: Double) -> Double {
        let aspect = aspectSur(aspect), r = g.rayons[e]
        return max((2 * r + GeometrieMaison.bandeNomsEtages) * 1.1, 2 * r * 1.05 / aspect)
    }

    /// Vol vers un etage isole, a l'avancement u de la bascule (polissage C, section 5.1) : en 2D, vue de dessus,
    /// la cible au centre de sa boite, bande du nom comprise ; en 3D, meme azimut et meme inclinaison, la cible
    /// au centre du plateau, a sa hauteur.
    public static func volVersEtage(_ o: Orbite, _ g: GeometrieMaison, etage e: Int, aspect: Double, u: Double,
                                    troisD: Bool) -> Vol {
        var c = g.centrePlateau(e, u)
        if !troisD { c.z -= GeometrieMaison.bandeNomsEtages / 2 }
        let d = Orbite.distance(pourHauteur: vueEtage(g, etage: e, aspect: aspect), champ: o.champ)
        return Vol(depuis: o, oeil: c + directionVue(o, troisD: troisD) * d, cible: c)
    }

    /// Vol de retour a la vue d'ensemble, a l'avancement u de la bascule.
    public static func volVersEnsemble(_ o: Orbite, _ g: GeometrieMaison, aspect: Double, u: Double, troisD: Bool) -> Vol {
        let aspect = aspectSur(aspect)
        let c = g.cible2D + (g.centreSphere - g.cible2D) * u
        let d = Orbite.distance(pourHauteur: vue(g, aspect: aspect, u: u), champ: o.champ)
        return Vol(depuis: o, oeil: c + directionVue(o, troisD: troisD) * d, cible: c)
    }
}

/// Vol de camera (isolement d'une piece, retour a la maison) : oeil et cible interpoles, en rampe.
public struct Vol: Hashable, Sendable {
    public var oeil0, cible0, oeil1, cible1: SIMD3<Double>

    public init(depuis o: Orbite, oeil: SIMD3<Double>, cible: SIMD3<Double>) {
        oeil0 = o.oeil
        cible0 = o.cible
        oeil1 = oeil
        cible1 = cible
    }

    /// Camera a l'avancement q (0 a 1, en temps) du vol.
    public func orbite(_ q: Double, depuis o: Orbite) -> Orbite {
        let e = CameraScene.rampe(min(1, max(0, q)))
        var r = o
        r.placer(oeil: oeil0 + (oeil1 - oeil0) * e, cible: cible0 + (cible1 - cible0) * e)
        return r
    }
}

/// Envol entre la 2D et la 3D (spec, section 7) : 2,6 s en rampe cubique ; il part de la vue
/// courante, zoomee ou tournee, sans saut : l'ecart a la pose canonique s'efface pendant l'envol.
public struct Envol: Hashable, Sendable {
    public var depart: Double
    public var arrivee: Double
    public var ecartCible: SIMD3<Double>
    public var ecartLogDistance: Double
    public var ecartAzimut: Double
    public var ecartInclinaison: Double

    public init(depuis o: Orbite, t: Double, vers arrivee: Double, geometrie g: GeometrieMaison, aspect: Double) {
        let c = CameraScene.canonique(g, aspect: CameraScene.aspectSur(aspect), u: t)
        depart = t
        self.arrivee = arrivee
        ecartCible = o.cible - c.cible
        ecartLogDistance = log(o.distance / c.distance)
        ecartAzimut = remainder(o.azimut - c.azimut, 2 * .pi)
        ecartInclinaison = o.inclinaison - c.inclinaison
    }

    /// Avancement t de la bascule et camera, a l'avancement q (0 a 1, en temps) de l'envol.
    public func pose(_ q: Double, geometrie g: GeometrieMaison, aspect: Double) -> (t: Double, orbite: Orbite) {
        let e = CameraScene.rampe(min(1, max(0, q)))
        let t = depart + (arrivee - depart) * e
        var o = CameraScene.canonique(g, aspect: CameraScene.aspectSur(aspect), u: t)
        let r = 1 - e
        o.cible += ecartCible * r
        o.distance *= exp(ecartLogDistance * r)
        o.azimut += ecartAzimut * r
        o.inclinaison += ecartInclinaison * r
        return (t, o)
    }
}
