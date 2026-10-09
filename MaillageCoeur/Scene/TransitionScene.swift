import Foundation
import simd

/// Les poses d'une scene, par cle (polissage D, section 1) : chaque piece (son centre sur son plateau, la taille de sa
/// carte, sa teinte), chaque noeud (le centre de sa piece et sa place dans la carte, le rayon de sa pastille) et chaque
/// lien, avec leur opacite. Une place est une ancre sur un plateau, par la cle du plateau : la geometrie du moment la
/// pose dans le monde, en 2D comme en 3D, pendant que les plateaux glissent ou que la vue bascule. Une pose en route
/// d'un plateau a un autre est la moyenne ponderee de ses ancres ; posee, elle n'en a qu'une, de poids 1.
public struct PosesScene: Hashable, Sendable {
    public struct Ancre: Hashable, Sendable {
        public var plateau: String
        public var place: SIMD2<Double>
        public var poids: Double

        public init(plateau: String, place: SIMD2<Double>, poids: Double = 1) {
            self.plateau = plateau
            self.place = place
            self.poids = poids
        }
    }

    public struct Piece: Hashable, Sendable {
        public var ancres: [Ancre]
        /// Largeur (x) et profondeur (z) de sa carte, en unites.
        public var taille: SIMD2<Double>
        public var teinte: Int
        public var opacite: Double

        public init(ancres: [Ancre], taille: SIMD2<Double>, teinte: Int, opacite: Double = 1) {
            self.ancres = ancres
            self.taille = taille
            self.teinte = teinte
            self.opacite = opacite
        }
    }

    public struct Noeud: Hashable, Sendable {
        /// Le centre de sa piece.
        public var ancres: [Ancre]
        /// Sa place dans la carte de sa piece, par rapport a son centre, en unites.
        public var decalage: SIMD2<Double>
        /// Rayon naturel de sa pastille (px).
        public var rayon: Double
        public var opacite: Double
        /// La cle de sa piece : un noeud qui s'efface garde le voile de la piece qu'il quitte, si elle reste
        /// (relecture ciblee de la vague finale, Mineur 1) ; nil, inconnue.
        public var piece: String?

        public init(ancres: [Ancre], decalage: SIMD2<Double>, rayon: Double, opacite: Double = 1,
                    piece: String? = nil) {
            self.ancres = ancres
            self.decalage = decalage
            self.rayon = rayon
            self.opacite = opacite
            self.piece = piece
        }
    }

    public struct Lien: Hashable, Sendable {
        public var de: String
        public var vers: String
        public var genre: GrapheReseau.Lien.Genre
        public var qualite: Int?
        public var suppose: Bool
        public var opacite: Double

        public init(_ l: GrapheReseau.Lien, opacite: Double = 1) {
            de = l.de
            vers = l.vers
            genre = l.genre
            qualite = l.qualite
            suppose = l.suppose
            self.opacite = opacite
        }

        /// Le lien du graphe qu'il pose.
        public var graphe: GrapheReseau.Lien {
            GrapheReseau.Lien(de: de, vers: vers, genre: genre, qualite: qualite, suppose: suppose)
        }
    }

    public var pieces: [String: Piece] = [:]
    public var noeuds: [String: Noeud] = [:]
    public var liens: [String: Lien] = [:]

    public init() {}

    /// Les poses de `scene` posee : chaque piece a sa place (`positions`), de la taille de sa carte (`cartes`) ; chaque
    /// noeud a sa place dans la carte de sa piece, avec la cle de celle-ci ; chaque lien. Tout est opaque.
    public init(scene: ScenePieces, cartes: [CartesPieces.Carte], positions: [SIMD2<Double>]) {
        for (i, p) in scene.pieces.enumerated()
        where i < cartes.count && i < positions.count && p.etage < scene.etages.count {
            let ancres = [Ancre(plateau: scene.etages[p.etage].id, place: positions[i])]
            pieces[p.id] = Piece(ancres: ancres, taille: SIMD2(cartes[i].largeur, cartes[i].profondeur),
                                 teinte: p.teinte)
            for (r, id) in p.noeuds.enumerated() where r < cartes[i].places.count {
                noeuds[id] = Noeud(ancres: ancres, decalage: cartes[i].places[r], rayon: scene.noeud(id)?.rayon ?? 7,
                                   piece: p.id)
            }
        }
        for l in scene.liens { liens[Self.cle(l)] = Lien(l) }
    }

    /// Cle d'un lien : ses deux bouts et son genre ; sa qualite peut changer sans en faire un autre.
    public static func cle(_ l: GrapheReseau.Lien) -> String {
        l.de + ">" + l.vers + ">" + l.genre.rawValue
    }

    /// Ces poses, recouvertes par `autres` : la pose affichee d'une scene, celles en transition l'emportant.
    public func recouvertes(par autres: PosesScene) -> PosesScene {
        var r = self
        r.pieces.merge(autres.pieces) { _, b in b }
        r.noeuds.merge(autres.noeuds) { _, b in b }
        r.liens.merge(autres.liens) { _, b in b }
        return r
    }

    /// Ces poses sans ce qui est deja efface (opacite 0) et absent de `arrivee` : cela n'existe plus.
    fileprivate func sansEfface(devant arrivee: PosesScene) -> PosesScene {
        var r = self
        r.pieces = pieces.filter { $0.value.opacite > 0 || arrivee.pieces[$0.key] != nil }
        r.noeuds = noeuds.filter { $0.value.opacite > 0 || arrivee.noeuds[$0.key] != nil }
        r.liens = liens.filter { $0.value.opacite > 0 || arrivee.liens[$0.key] != nil }
        return r
    }

    /// Le centre dans le monde d'ancres, sur la geometrie `g` a l'avancement `t` de la bascule : la moyenne, ponderee,
    /// du centre de chaque plateau plus sa place ; `plateaux` : l'indice de chaque plateau de `g`, par cle. Une ancre
    /// sur un plateau absent ne compte pas ; nil sans aucune.
    public static func centre(_ ancres: [Ancre], geometrie g: GeometrieMaison, plateaux: [String: Int],
                              t: Double) -> SIMD3<Double>? {
        var somme = SIMD3<Double>.zero, poids = 0.0
        for a in ancres {
            guard let e = plateaux[a.plateau], e < g.rayons.count else { continue }
            let c = g.centrePlateau(e, t)
            somme += SIMD3(c.x + a.place.x, c.y, c.z + a.place.y) * a.poids
            poids += a.poids
        }
        return poids > 0 ? somme / poids : nil
    }

    /// Le melange de deux poses d'ancres, a `e` du chemin de `a` a `b` : chaque ancre garde son plateau, son poids
    /// multiplie par 1 - e (celles de `a`) ou par e (celles de `b`) ; deux ancres du meme plateau n'en font qu'une, a
    /// la moyenne ponderee de leurs places. A 0, les ancres de `a` ; a 1, celles de `b`, exactement.
    public static func melange(_ a: [Ancre], _ b: [Ancre], _ e: Double) -> [Ancre] {
        if e <= 0 { return a }
        if e >= 1 { return b }
        var r: [Ancre] = []
        for x in a.map({ Ancre(plateau: $0.plateau, place: $0.place, poids: $0.poids * (1 - e)) })
            + b.map({ Ancre(plateau: $0.plateau, place: $0.place, poids: $0.poids * e) }) where x.poids > 0 {
            if let k = r.firstIndex(where: { $0.plateau == x.plateau }) {
                let w = r[k].poids + x.poids
                r[k].place = (r[k].place * r[k].poids + x.place * x.poids) / w
                r[k].poids = w
            } else {
                r.append(x)
            }
        }
        return r
    }
}

/// Le glissement d'une disposition a l'autre (polissage D, section 1) : de la pose affichee a la pose nouvelle, chaque
/// piece (son centre et sa taille) et chaque noeud (sa place dans le monde) glisse en 0,9 s, en cubique entree-sortie ;
/// un element present d'un seul cote apparait ou s'efface en fondu de 0,3 s, a sa place ; un lien suit ses bouts. Elle
/// ne garde que ce qui change : le reste est pose. Une nouvelle disposition pendant le glissement repart de la pose
/// affichee (`PosesScene.recouvertes`), sans saut. Avec « Reduire les animations », pas de transition : tout est
/// immediat, sans fondu.
public struct TransitionScene: Hashable, Sendable {
    /// Le glissement, celui des changements de niveau de C.
    public static let duree = CameraScene.dureeNiveaux
    /// Les apparitions et les disparitions.
    public static let dureeFondu = 0.3

    /// Les poses de depart et d'arrivee, de ce qui change seulement.
    public var depart: PosesScene
    public var arrivee: PosesScene
    public var debut: Double

    /// La transition de `affichee`, la pose affichee de la scene d'avant, a `arrivee`, la nouvelle, depuis l'instant
    /// `debut` ; nil si rien ne change, ou avec « Reduire les animations ».
    public init?(de affichee: PosesScene, vers arrivee: PosesScene, a debut: Double, reduire: Bool = false) {
        guard !reduire else { return nil }
        // Ce qui est deja efface (opacite 0) et absent de l'arrivee n'existe plus : ce n'est pas un changement.
        let affichee = affichee.sansEfface(devant: arrivee)
        var d = PosesScene(), a = PosesScene()
        for k in Set(affichee.pieces.keys).union(arrivee.pieces.keys) where affichee.pieces[k] != arrivee.pieces[k] {
            d.pieces[k] = affichee.pieces[k]
            a.pieces[k] = arrivee.pieces[k]
        }
        for k in Set(affichee.noeuds.keys).union(arrivee.noeuds.keys) where affichee.noeuds[k] != arrivee.noeuds[k] {
            d.noeuds[k] = affichee.noeuds[k]
            a.noeuds[k] = arrivee.noeuds[k]
        }
        for k in Set(affichee.liens.keys).union(arrivee.liens.keys)
        where affichee.liens[k]?.opacite != arrivee.liens[k]?.opacite {
            d.liens[k] = affichee.liens[k]
            a.liens[k] = arrivee.liens[k]
        }
        guard d != PosesScene() || a != PosesScene() else { return nil }
        depart = d
        self.arrivee = a
        self.debut = debut
    }

    /// Le glissement est fini a l'instant `now`.
    public func finie(a now: Double) -> Bool { now - debut >= Self.duree }

    /// Les poses de ce qui change, a l'instant `now` : en route en cubique entree-sortie ; l'opacite en route, en
    /// 0,3 s, vers 1 pour ce qui arrive, vers 0 pour ce qui part, depuis celle du depart (une transition interrompue).
    public func poses(a now: Double) -> PosesScene {
        let e = CameraScene.rampe(min(1, max(0, (now - debut) / Self.duree)))
        let f = min(1, max(0, (now - debut) / Self.dureeFondu))
        func opacite(_ o0: Double?, _ o1: Double?) -> Double {
            let a = o0 ?? 0, b = o1 == nil ? 0 : 1.0
            return a + (b - a) * f
        }
        var r = PosesScene()
        for k in Set(depart.pieces.keys).union(arrivee.pieces.keys) {
            let d = depart.pieces[k], a = arrivee.pieces[k]
            guard var p = a ?? d else { continue }
            if let d, let a {
                p.ancres = PosesScene.melange(d.ancres, a.ancres, e)
                p.taille = d.taille + (a.taille - d.taille) * e
            }
            p.opacite = opacite(d?.opacite, a?.opacite)
            r.pieces[k] = p
        }
        for k in Set(depart.noeuds.keys).union(arrivee.noeuds.keys) {
            let d = depart.noeuds[k], a = arrivee.noeuds[k]
            guard var n = a ?? d else { continue }
            if let d, let a {
                n.ancres = PosesScene.melange(d.ancres, a.ancres, e)
                n.decalage = d.decalage + (a.decalage - d.decalage) * e
                n.rayon = d.rayon + (a.rayon - d.rayon) * e
            }
            n.opacite = opacite(d?.opacite, a?.opacite)
            r.noeuds[k] = n
        }
        for k in Set(depart.liens.keys).union(arrivee.liens.keys) {
            guard var l = arrivee.liens[k] ?? depart.liens[k] else { continue }
            l.opacite = opacite(depart.liens[k]?.opacite, arrivee.liens[k]?.opacite)
            r.liens[k] = l
        }
        return r
    }

    /// Ces pieces et ces noeuds ne glissent plus : poses, a leur place d'arrivee (une piece que Djoko prend pour la
    /// glisser, et ses noeuds).
    public mutating func oublier(pieces: Set<String>, noeuds: Set<String>) {
        for k in pieces {
            depart.pieces[k] = nil
            arrivee.pieces[k] = nil
        }
        for k in noeuds {
            depart.noeuds[k] = nil
            arrivee.noeuds[k] = nil
        }
    }
}
