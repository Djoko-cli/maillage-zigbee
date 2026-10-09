import CoreGraphics
import Foundation

/// Niveau du zoom semantique (spec de la vue par pieces, section 6), selon l'echelle k (points par
/// unite a la cible de la camera, divises par 24) : sous 0,42, les pieces seules ; jusqu'a 0,6, les
/// pieces et les routeurs ; au-dela, tous les noms qui tiennent.
public enum NiveauZoom: Int, Hashable, Sendable {
    case pieces = 0, routeurs = 1, tous = 2

    public init(echelle k: Double) {
        self = k < 0.42 ? .pieces : k < 0.6 ? .routeurs : .tous
    }
}

/// Place candidate d'un nom autour de son objet : une direction (dx, dy), un ecart (px), l'indice
/// de son anneau.
public struct Candidat: Hashable, Sendable {
    public let dx, dy: Int
    public let ecart: Double
    public let anneau: Int
}

/// Places candidates : les anneaux 3, 14, 28, 44 et 62 px autour de l'objet, et sur chacun huit
/// directions dans un ordre propre a chaque genre de nom.
public enum Candidats {
    static let directions = [(0, -1), (1, 0), (-1, 0), (0, 1), (1, -1), (-1, -1), (1, 1), (-1, 1)]
    public static let anneaux: [Double] = [3, 14, 28, 44, 62]

    static func ordre(_ ds: [Int]) -> [Candidat] {
        anneaux.enumerated().flatMap { i, a in
            ds.map { Candidat(dx: directions[$0].0, dy: directions[$0].1, ecart: a, anneau: i) }
        }
    }

    /// Droite, gauche, haut, bas, puis les diagonales.
    public static let appareil = ordre([1, 2, 0, 3, 4, 6, 5, 7])
    /// Haut, bas, droite, gauche, puis les diagonales.
    public static let piece = ordre([0, 3, 1, 2, 4, 5, 6, 7])
    /// Haut, bas, droite, gauche.
    public static let etage = ordre([0, 3, 1, 2])
    /// Bas, droite, gauche, haut.
    public static let maison = ordre([3, 1, 2, 0])
}

/// Un nom et son etat de placement, garde d'une image a l'autre (stabilite).
public struct Etiquette: Sendable {
    public enum Genre: Hashable, Sendable {
        case noeud(String)
        case piece(Int)
        case etage(Int)
        case maison
        /// Repere « ailleurs » de la piece isolee, par l'id de l'enfant.
        case ailleurs(String)
    }

    public let genre: Genre
    public let candidats: [Candidat]
    /// Les noms d'etage sont poses meme s'ils chevauchent.
    public let fixe: Bool
    public var prio: Int
    public var voulu = true
    /// Piece estompee : son nom en pale.
    public var pale = false
    /// Survol ou selection : semi-gras.
    public var fort = false
    public var taille: CGSize
    /// Place retenue (indice du candidat) ; -1 : masque.
    public var place = -1
    /// Temps passe a garder l'ancienne place alors qu'une meilleure est libre (s).
    public var envie = 0.0
    public var vu = false
    public var rect = CGRect.zero
    /// Place de l'image precedente (`CGRect.null` si le nom n'etait pas vu).
    public var rectAvant = CGRect.null

    public init(_ genre: Genre, taille: CGSize) {
        self.genre = genre
        self.taille = taille
        switch genre {
        case .noeud:
            candidats = Candidats.appareil
            fixe = false
            prio = 7
        case .piece:
            candidats = Candidats.piece
            fixe = false
            prio = 4
        case .etage:
            candidats = Candidats.etage
            fixe = true
            prio = 1
        case .maison:
            // Apres les noms d'etage, qu'il evite (polissage C, section 2, decision de Djoko du 03/10) : dans une petite
            // vue 3D, il tombait sur le nom de l'etage du haut.
            candidats = Candidats.maison
            fixe = false
            prio = 2
        case .ailleurs:
            candidats = Candidats.appareil
            fixe = false
            prio = 3
        }
    }

    /// Le nom n'a pas bouge depuis l'image precedente : il s'aligne sur les pixels.
    public var immobile: Bool {
        rectAvant.isNull || (abs(rect.minX - rectAvant.minX) < 0.01 && abs(rect.minY - rectAvant.minY) < 0.01)
    }
}

/// Placement glouton des noms, dans l'espace de l'ecran (spec, section 6).
public enum PlacementNoms {
    /// Temps pendant lequel une meilleure place doit rester libre avant qu'un nom la rejoigne (s).
    public static let patience = 0.5
    /// Marge des noms au bord du cadre, et jeu entre deux rectangles (px).
    public static let bord: CGFloat = 4
    public static let jeu: CGFloat = 2

    /// Trait de rappel d'un nom ecarte de son objet : de l'objet au nom.
    public struct Trait: Hashable, Sendable {
        public var depart: CGPoint
        public var arrivee: CGPoint
    }

    /// Rectangle d'un nom de taille `taille` pose au candidat `c` autour de l'ancre `a` ; une
    /// diagonale se place a 0,7 fois l'anneau.
    public static func rect(_ taille: CGSize, _ a: CGRect, _ c: Candidat) -> CGRect {
        let m = c.dx != 0 && c.dy != 0 ? c.ecart * 0.7 : c.ecart
        let w = taille.width, h = taille.height
        let x = c.dx > 0 ? a.maxX + m : c.dx < 0 ? a.minX - m - w : a.midX - w / 2
        let y = c.dy > 0 ? a.maxY + m : c.dy < 0 ? a.minY - m - h : a.midY - h / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    /// Deux rectangles a moins de `jeu` l'un de l'autre.
    public static func chevauche(_ r: CGRect, _ q: CGRect) -> Bool {
        r.minX - jeu < q.maxX && q.minX - jeu < r.maxX && r.minY - jeu < q.maxY && q.minY - jeu < r.maxY
    }

    public static func dansCadre(_ r: CGRect, _ t: CGSize) -> Bool {
        r.minX >= bord && r.minY >= bord && r.maxX <= t.width - bord && r.maxY <= t.height - bord
    }

    /// Pose les noms par priorite croissante (puis dans leur ordre) : chacun prend la premiere place
    /// candidate dans le cadre qui ne chevauche ni un nom deja pose, ni un obstacle (pastilles,
    /// interface) ; un nom d'etage (`fixe`) est pose meme s'il chevauche. Un nom garde sa place tant
    /// qu'elle reste libre, et ne rejoint une meilleure qu'apres l'avoir trouvee libre `patience`
    /// secondes ; sans place, il est masque. Rend le trait de rappel de chaque nom pose des le
    /// deuxieme anneau. `ancres` : l'objet de chaque nom, a l'ecran (nil : pas a l'ecran) ; `dt` :
    /// temps depuis l'image precedente.
    public static func placer(_ etiquettes: inout [Etiquette], ancres: [CGRect?], obstacles: [CGRect], cadre: CGSize,
                              dt: Double) -> [Trait] {
        var pris = obstacles
        var traits: [Trait] = []
        let ordre = etiquettes.indices.sorted { (etiquettes[$0].prio, $0) < (etiquettes[$1].prio, $1) }
        for j in ordre {
            var l = etiquettes[j]
            defer { etiquettes[j] = l }
            guard l.voulu, j < ancres.count, let a = ancres[j] else {
                l.vu = false
                l.place = -1
                l.envie = 0
                continue
            }
            func libre(_ k: Int) -> CGRect? {
                let r = rect(l.taille, a, l.candidats[k])
                return dansCadre(r, cadre) && (l.fixe || !pris.contains { chevauche(r, $0) }) ? r : nil
            }
            var k = -1
            var r = CGRect.zero
            for c in l.candidats.indices {
                if let q = libre(c) {
                    k = c
                    r = q
                    break
                }
            }
            guard k >= 0 else {
                l.vu = false
                l.place = -1
                l.envie = 0
                continue
            }
            if l.place >= 0 && l.place != k, let q = libre(l.place), l.envie + dt < patience {
                l.envie += max(dt, 1e-3)
                k = l.place
                r = q
            } else {
                l.envie = 0
            }
            l.place = k
            l.rectAvant = l.vu ? l.rect : .null
            l.vu = true
            l.rect = r
            pris.append(r)
            if l.candidats[k].anneau > 0 {
                let px = min(max(r.midX, a.minX), a.maxX), py = min(max(r.midY, a.minY), a.maxY)
                traits.append(Trait(depart: CGPoint(x: px, y: py),
                                    arrivee: CGPoint(x: min(max(px, r.minX), r.maxX), y: min(max(py, r.minY), r.maxY))))
            }
        }
        return traits
    }

    /// Zoom semantique et priorites (spec, section 6 ; polissage C, section 5) : noms voulus, priorites, pales et
    /// forts, selon le niveau du zoom, le survol, la selection et l'isolement. `focus` : la piece en vue (isolee, ou
    /// qui l'etait, pendant le retour) ; `isolee` : une piece est visee ; `fk` : part propre a chaque piece de
    /// l'isolement ; `s` : isolement general (0 a 1) ; `t` : bascule (0 : 2D, 1 : 3D) ; `se` : isolement d'un
    /// etage ; `voiles` : le voile de chaque plateau (`SceneProjetee.voilesEtages`) ; `etageIsole` : l'etage vise ;
    /// `survolNomEtage` : le nom d'etage sous le pointeur, souligne.
    ///
    /// Les noms des appareils suivent l'etat d'arrivee (triage A, n° 8) : une piece visee, les siens ; sinon, selon le
    /// zoom, ceux de la maison, ou de l'etage vise seulement. Celui de l'appareil survole ou choisi est toujours voulu.
    /// Les noms d'etage restent voulus, pales et cliquables pendant un isolement.
    public static func regler(_ etiquettes: inout [Etiquette], scene: ScenePieces, niveau: NiveauZoom,
                              survol: String?, selection: String?, focus: Int?, isolee: Bool, fk: [Double],
                              s: Double, t: Double, se: Double = 0, voiles: [Double] = [], etageIsole: Int? = nil,
                              survolNomEtage: Int? = nil) {
        let fo = 1 - CameraScene.rampe(s)
        func voile(_ e: Int) -> Double { e < voiles.count ? voiles[e] : 1 }
        for j in etiquettes.indices {
            switch etiquettes[j].genre {
            case .noeud(let id):
                guard let n = scene.noeud(id) else {
                    etiquettes[j].voulu = false
                    continue
                }
                let part = n.piece < fk.count ? fk[n.piece] : 0
                let vise = survol == id || selection == id
                let arrivee = etageIsole.map { $0 == scene.pieces[n.piece].etage } ?? true
                etiquettes[j].voulu = vise
                    || (isolee ? part > 0.6 : arrivee && (niveau == .tous || (niveau == .routeurs && n.route)))
                etiquettes[j].prio = vise ? 2 : n.chef ? 5 : n.route ? 6 : 7
                etiquettes[j].fort = vise
            case .piece(let i):
                let pale = (focus != nil && (i < fk.count ? fk[i] : 0) < 0.5 && s > 0.3)
                    || (i < scene.pieces.count && voile(scene.pieces[i].etage) < 0.6)
                etiquettes[j].voulu = true
                etiquettes[j].pale = pale
                etiquettes[j].prio = pale ? 8 : 4
            case .etage(let e):
                etiquettes[j].voulu = true
                etiquettes[j].pale = voile(e) < 0.6 || (focus != nil && s > 0.3)
                etiquettes[j].fort = survolNomEtage == e
            case .maison:
                etiquettes[j].voulu = fo > 0.5 && CameraScene.rampe(se) < 0.5 && t > 0.4
            case .ailleurs:
                etiquettes[j].voulu = focus.map { $0 < fk.count && fk[$0] > 0.6 } ?? false
            }
        }
    }

    /// Noms d'appareils voulus mais masques faute de place : leur objet est dans le cadre (un appareil
    /// hors de la vue, apres un zoom, ne compte pas).
    public static func masques(_ etiquettes: [Etiquette], ancres: [CGRect?], cadre: CGSize) -> Int {
        let vue = CGRect(origin: .zero, size: cadre)
        return etiquettes.indices.count { j in
            guard case .noeud = etiquettes[j].genre, etiquettes[j].voulu, !etiquettes[j].vu,
                  j < ancres.count, let a = ancres[j] else { return false }
            return vue.intersects(a)
        }
    }
}
