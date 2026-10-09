import CoreGraphics
import Foundation
import simd

/// Couleur sRGB, composantes de 0 a 1.
public struct Teinte: Hashable, Sendable {
    public var r, g, b: Double

    public init(r: Double, g: Double, b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    public init(hexa v: UInt32) {
        self.init(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255)
    }

    /// Eclairee comme dans la maquette : la couleur passe en lineaire, y est multipliee par `k`, puis
    /// revient en sRGB.
    public func eclairee(_ k: Double) -> Teinte {
        func lineaire(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        func srgb(_ c: Double) -> Double {
            let c = min(1, max(0, c))
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        return Teinte(r: srgb(lineaire(r) * k), g: srgb(lineaire(g) * k), b: srgb(lineaire(b) * k))
    }
}

/// Etat anime de la vue, pose a chaque image : ce que la projection lit en plus de la scene.
public struct EtatAnime: Hashable, Sendable {
    /// Bascule, adoucie : 0 en 2D, 1 en 3D.
    public var t: Double
    /// Isolement general d'une piece : 0 a 1, lineaire (la projection l'adoucit).
    public var s: Double
    /// Part propre a chaque piece de l'isolement : 0 a 1.
    public var fk: [Double]
    /// Piece isolee (ou qui l'etait, pendant le retour).
    public var focus: Int?
    public var survol: String?
    public var selection: String?
    /// Isolement d'un etage (polissage C, section 5) : 0 a 1, lineaire ; part propre a chaque plateau, de 0 a 1. Une
    /// piece isolee isole aussi son etage, le cran « etage » du fil.
    public var se: Double
    public var ek: [Double]
    /// Disque cliquable sous le pointeur : il s'eclaircit.
    public var survolEtage: Int?
    /// Les liens montres : les chemins vers le pont, ou tous les liens radio.
    public var liens: ModeLiens
    /// En mode « chemins », les voisins entendus d'un noeud selectionne sont montres (vrai) ou masques (faux).
    public var voisins: Bool
    /// Mode focus (etape 5, section 1) : l'estompement de chaque noeud, par identifiant, et de chaque lien, par paire
    /// (`MiseEnAvant.cle`), de 0 (net) a 1 (estompe) ; absent : net.
    public var noeudsEstompes: [String: Double]
    public var liensEstompes: [String: Double]

    public init(t: Double = 0, s: Double = 0, fk: [Double], focus: Int? = nil, survol: String? = nil,
                selection: String? = nil, se: Double = 0, ek: [Double] = [], survolEtage: Int? = nil,
                liens: ModeLiens = .tous, voisins: Bool = true, noeudsEstompes: [String: Double] = [:],
                liensEstompes: [String: Double] = [:]) {
        self.t = t
        self.s = s
        self.fk = fk
        self.focus = focus
        self.survol = survol
        self.selection = selection
        self.se = se
        self.ek = ek
        self.survolEtage = survolEtage
        self.liens = liens
        self.voisins = voisins
        self.noeudsEstompes = noeudsEstompes
        self.liensEstompes = liensEstompes
    }
}

/// Les liens que montre la vue (consigne de l'etape 3 bis, section 3).
public enum ModeLiens: String, Hashable, Sendable, CaseIterable {
    /// Le chemin de chaque routeur vers le pont, et les liens vers un parent ; les voisins entendus d'un noeud
    /// selectionne seulement (et si la vue les montre : `EtatAnime.voisins`).
    case chemins
    /// Tous les liens radio entendus, et les liens vers un parent (l'affichage d'avant les chemins).
    case tous
}

/// Repere « ailleurs » d'un enfant de la piece isolee dont le parent est dans une autre piece.
public struct Ailleurs: Hashable, Sendable {
    public enum Sens: Hashable, Sendable {
        /// Parent au meme niveau (↗), a un niveau en dessous (↓), au-dessus (↑) (polissage C, section 5.2).
        case memeNiveau, dessous, dessus
    }

    public var enfant: String
    public var parent: String
    public var piece: Int
    public var etage: Int
    public var sens: Sens
}

/// Ce que la camera rend au moteur `Canvas` (spec, section 9), en coordonnees de l'ecran : le contrat
/// entre la scene et le moteur. Couches, sans tri de profondeur global : plateaux et equateur, blocs
/// (du plus loin au plus proche, faces tournees vers l'oeil), liens enfant-parent (avec les
/// rattachements et les fils « ailleurs »), liens entre routeurs, pastilles, lisere de la sphere ;
/// puis les traits de rappel et les noms, que le moteur pose avec `PlacementNoms`.
public struct SceneProjetee: Sendable {
    public struct Plateau: Sendable {
        public var etage: Int
        public var polygone: [CGPoint]
        public var contour: [[CGPoint]]
        /// Envoie le disque unite sur l'ellipse du plateau (degrade radial) ; nil si degenere.
        public var disque: CGAffineTransform?
        public var opacite: Double
        public var profondeur: Double
        /// Disque cliquable sous le pointeur : une fois et demie plus clair.
        public var eclaire: Bool
    }

    public struct Equateur: Sendable {
        public var contour: [[CGPoint]]
        public var opacite: Double
        public var profondeur: Double
    }

    public struct Face: Sendable {
        public var points: [CGPoint]
        public var teinte: Teinte
    }

    public struct Bloc: Sendable {
        public var piece: Int
        /// Faces tournees vers l'oeil, eclairees.
        public var faces: [Face]
        public var aretes: [(CGPoint, CGPoint)]
        public var teinte: Teinte
        public var opaciteVerre: Double
        public var opaciteAretes: Double
        public var profondeur: Double
    }

    public struct Lien: Sendable {
        public var a, b: CGPoint
        public var genre: GrapheReseau.Lien.Genre
        public var qualite: Int?
        public var opacite: Double
        public var eclaire: Bool
        /// Chemin suppose, ou lien vers le parent d'avant : en pointilles.
        public var suppose = false
        /// Voisin entendu d'un noeud selectionne, en mode « chemins » : trait fin et estompe.
        public var voisin = false
    }

    /// Opacite d'un voisin entendu, au repos (en mode « chemins », a la selection) : estompe.
    public static let opaciteVoisin = 0.45

    /// Le lien projete : un lien radio, un chemin ou un voisin entendu (couche des routeurs), ou un lien vers un parent
    /// (couche des enfants, plus visible eclaire) ; `poids` : le voile de ses pieces, `fondu` : sa transition.
    static func lien(_ l: GrapheReseau.Lien, trace: Trace, a: CGPoint, b: CGPoint, poids: Double, fondu: Double,
                     eclaire: Bool) -> Lien {
        switch l.genre {
        case .radio, .chemin:
            let base = trace == .voisin ? opaciteVoisin : opaciteLienRadio
            return Lien(a: a, b: b, genre: l.genre, qualite: l.qualite, opacite: base * poids * fondu, eclaire: eclaire,
                        suppose: l.suppose, voisin: trace == .voisin)
        case .parent, .rattachement:
            return Lien(a: a, b: b, genre: l.genre, qualite: l.qualite,
                        opacite: (eclaire ? 0.85 : opaciteLienEnfant * poids) * fondu, eclaire: eclaire,
                        suppose: l.suppose)
        }
    }

    /// Comment un lien se montre dans un mode : nil, cache ; `voisin`, en trait fin et estompe (un voisin entendu du
    /// noeud selectionne, en mode « chemins »).
    public enum Trace: Hashable, Sendable {
        case normal, voisin
    }

    /// Le trace d'un lien : en mode « chemins », les chemins, les liens vers un parent, et les liens radio du noeud
    /// selectionne (en voisins, sauf si `voisins` est faux : ils sont masques) ; en mode « tous », les liens radio et les
    /// liens vers un parent, sans les chemins.
    public static func trace(_ l: GrapheReseau.Lien, mode: ModeLiens, selection: String?,
                             voisins: Bool = true) -> Trace? {
        switch (l.genre, mode) {
        case (.parent, _), (.rattachement, _): .normal
        case (.chemin, .chemins): .normal
        case (.chemin, .tous): nil
        case (.radio, .tous): .normal
        case (.radio, .chemins):
            voisins && selection != nil && (l.de == selection || l.vers == selection) ? .voisin : nil
        }
    }

    public struct Fil: Sendable {
        public var a, b: CGPoint
        public var opacite: Double
    }

    public struct Disque: Sendable {
        public var noeud: String
        public var centre: CGPoint
        public var rayon: Double
        /// Opacite hors du mode focus : elle decide de ce qui se clique, un noeud estompe se clique encore.
        public var opacite: Double
        public var profondeur: Double
        /// Facteur d'opacite du mode focus (`MiseEnAvant.facteur`) : 1 net ; le dessin le multiplie a `opacite`.
        public var focus = 1.0
    }

    public struct Sphere: Sendable {
        /// Envoie le disque unite sur le contour exact de la sphere.
        public var transfo: CGAffineTransform
        public var force: Double
    }

    /// Eclairage des faces de la maquette : ambiante 2,2 et directionnelle 1,6 venant de
    /// (-10, 30, 14), sur un materiau de Lambert, (2,2 + 1,6 n.l) / pi ; faces +x, -x, +y, -y, +z, -z.
    public static let lambert: [Double] = {
        let l = simd_normalize(SIMD3<Double>(-10, 30, 14))
        let normales: [SIMD3<Double>] = [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]
        return normales.map { (2.2 + 1.6 * max(0, simd_dot($0, l))) / .pi }
    }()

    /// Opacite d'un lien entre routeurs, et d'un lien enfant ou de rattachement, au repos et sans voile.
    static let opaciteLienRadio = 0.95
    static let opaciteLienEnfant = 0.28

    static let aretesBloc = [(0, 1), (1, 2), (2, 3), (3, 0), (4, 5), (5, 6), (6, 7), (7, 4),
                             (0, 4), (1, 5), (2, 6), (3, 7)]

    public var plateaux: [Plateau] = []
    /// Voile de chaque plateau dans l'isolement d'un etage : 1 net, 0,15 estompe (polissage C, section 5.1).
    public var voilesEtages: [Double] = []
    public var equateur: Equateur?
    /// Du plus loin au plus proche.
    public var blocs: [Bloc] = []
    public var liensEnfants: [Lien] = []
    public var liensRouteurs: [Lien] = []
    public var fils: [Fil] = []
    /// Du plus loin au plus proche.
    public var disques: [Disque] = []
    public var sphere: Sphere?
    public var niveau: NiveauZoom = .tous
    /// Echelle k du zoom semantique : points par unite a la cible, divises par 24.
    public var echelle = 1.0
    public var ancresNoeuds: [String: CGRect] = [:]
    public var ancresPieces: [Int: CGRect] = [:]
    public var ancresEtages: [Int: CGRect] = [:]
    public var ancreMaison: CGRect?
    public var ancresAilleurs: [String: CGRect] = [:]
    /// Reperes « ailleurs » de la piece isolee.
    public var ailleurs: [Ailleurs] = []
    /// Centre de chaque noeud dans le monde, y compris ceux qui s'effacent (`fantomes`).
    public var centresNoeuds: [String: SIMD3<Double>] = [:]
    /// Noeuds qui s'effacent pendant une transition (polissage D, section 1) : absents de la scene, ils ne se cliquent
    /// pas et n'ont pas de nom.
    public var fantomes: Set<String> = []
    /// Mode focus : le facteur d'opacite des noeuds estompes (et de leurs noms), par identifiant ; absent : 1.
    public var facteursNoeuds: [String: Double] = [:]

    /// Le facteur d'opacite du mode focus d'un noeud et de son nom : 1 net.
    public func facteur(noeud id: String) -> Double { facteursNoeuds[id] ?? 1 }

    public init() {}

    /// Pose la scene a l'etat `etat` et la projette par `orbite` dans `cadre` (la place utile de la
    /// vue). `positions` : centre de chaque piece dans son plateau (celles de la disposition, ou la
    /// piece qu'on glisse). Invariant, tenu par le moteur : `cartes` et `positions` suivent les pieces
    /// de `scene`, et `g.rayons` ses etages, memes effectifs et meme ordre. `poses` : ce qui est en transition
    /// (polissage D, section 1), par cle, qui l'emporte sur la disposition ; ce qui s'efface, absent de la scene, s'y
    /// dessine aussi, a sa derniere place, sans se cliquer.
    public init(scene: ScenePieces, cartes: [CartesPieces.Carte], positions: [SIMD2<Double>],
                geometrie g: GeometrieMaison, etat: EtatAnime, orbite: Orbite, cadre: CGRect,
                poses: PosesScene = PosesScene()) {
        let proj = ProjectionScene(orbite, cadre: cadre)
        let t = etat.t
        let h = GeometrieMaison.hauteurBloc(t)
        let es = CameraScene.rampe(etat.s), fo = 1 - es
        let oeil = orbite.oeil
        // Isolement d'un etage (polissage C, section 5) : les autres plateaux, avec leurs pieces, leurs pastilles et
        // leurs liens, descendent a 15 % ; la sphere s'efface. Une piece isolee laisse les disques a 15 % : on peut
        // cliquer dessus.
        let ee = CameraScene.rampe(etat.se)
        let ve = g.rayons.indices.map { e in
            1 - 0.85 * ee * (1 - CameraScene.rampe(e < etat.ek.count ? etat.ek[e] : 0))
        }
        voilesEtages = ve

        // Plateaux : polygone exact de 128 points ; degrade par l'affine du disque.
        for e in g.rayons.indices {
            let c = g.centrePlateau(e, t), r = g.rayons[e]
            let pts = Self.cercle(c, r, 128)
            guard let poly = proj.polygone(pts) else { continue }
            plateaux.append(Plateau(etage: e, polygone: poly, contour: proj.polyligne(pts, fermee: true),
                                    disque: proj.disque(c, r), opacite: min(ve[e], 1 - 0.85 * es),
                                    profondeur: proj.profondeur(c), eclaire: etat.survolEtage == e))
        }

        // Sphere de la maison : lisere et equateur, pendant l'envol et en 3D.
        let rs = g.rayonSphere * (0.8 + 0.2 * t)
        if 0.18 * t * fo * (1 - ee) > 0.002 {
            equateur = Equateur(contour: proj.polyligne(Self.cercle(g.centreSphere, rs, 192), fermee: true),
                                opacite: 0.18 * t * fo * (1 - ee), profondeur: proj.profondeur(g.centreSphere))
        }
        let force = t * t * fo * (1 - ee)
        if force > 0.002, let m = proj.contourSphere(g.centreSphere, rs) {
            sphere = Sphere(transfo: m, force: force)
        }

        // Pieces : blocs de verre ; noeuds a mi-hauteur de leur bloc en 3D. Une piece ou un noeud en transition prend
        // sa pose ; une piece qui s'efface, absente de la scene, se dessine a sa derniere place (`piece` -1).
        let plateaux = Dictionary(scene.etages.indices.map { (scene.etages[$0].id, $0) },
                                  uniquingKeysWith: { a, _ in a })
        var voiles = [Double](repeating: 1, count: scene.pieces.count)
        var mondes: [String: SIMD3<Double>] = [:]
        var centres = [SIMD3<Double>](repeating: .zero, count: scene.pieces.count)
        var echelles = [Double](repeating: 1, count: scene.pieces.count)
        var apparitions: [String: Double] = [:]
        func bloc(_ i: Int, centre m: SIMD3<Double>, taille: SIMD2<Double>, f: Double, teinte n: Int, vis: Double) {
            let bx = m.x, bz = m.z
            let y0 = m.y + 0.02, y1 = y0 + h
            let x0 = bx - taille.x * f / 2, x1 = bx + taille.x * f / 2
            let z0 = bz - taille.y * f / 2, z1 = bz + taille.y * f / 2
            let centre = SIMD3(bx, (y0 + y1) / 2, bz)
            if i >= 0 { centres[i] = centre }
            let k: [SIMD3<Double>] = [[x0, y0, z0], [x1, y0, z0], [x1, y0, z1], [x0, y0, z1],
                                      [x0, y1, z0], [x1, y1, z0], [x1, y1, z1], [x0, y1, z1]]
            let teinte = Teinte(hexa: ScenePieces.teintes[n % ScenePieces.teintes.count])
            var faces: [Face] = []
            func face(_ q: [Int], _ n: Int) {
                guard let p = proj.polygone(q.map { k[$0] }) else { return }
                faces.append(Face(points: p, teinte: teinte.eclairee(Self.lambert[n])))
            }
            if oeil.x > x1 { face([1, 2, 6, 5], 0) }
            if oeil.x < x0 { face([0, 4, 7, 3], 1) }
            if oeil.y > y1 { face([4, 5, 6, 7], 2) }
            if oeil.y < y0 { face([0, 3, 2, 1], 3) }
            if oeil.z > z1 { face([3, 7, 6, 2], 4) }
            if oeil.z < z0 { face([0, 1, 5, 4], 5) }
            let aretes = Self.aretesBloc.compactMap { proj.segment(k[$0.0], k[$0.1]) }
            blocs.append(Bloc(piece: i, faces: faces, aretes: aretes, teinte: teinte,
                              opaciteVerre: vis * (0.13 + 0.05 * t), opaciteAretes: vis * 0.75,
                              profondeur: proj.profondeur(centre)))
            let coins = k.compactMap { proj.ecran($0) }
            if i >= 0, coins.count == 8 { ancresPieces[i] = Self.boite(coins) }
        }
        // La place d'un noeud dans le monde, la seule : le centre de sa piece, puis sa place dans la carte, a l'echelle
        // `f`, a mi-hauteur du bloc en 3D. Celle d'un noeud en transition, et celle d'un noeud pose.
        func place(_ centre: SIMD3<Double>, _ decalage: SIMD2<Double>, f: Double) -> SIMD3<Double> {
            SIMD3(centre.x + decalage.x * f, centre.y + 0.1 + 0.5 * h * t, centre.z + decalage.y * f)
        }
        func monde(_ n: PosesScene.Noeud, f: Double) -> SIMD3<Double>? {
            guard let c = PosesScene.centre(n.ancres, geometrie: g, plateaux: plateaux, t: t) else { return nil }
            return place(c, n.decalage, f: f)
        }
        // Le rayon d'une pastille, le seul : il suit l'echelle, sans depasser 1,1 fois le rayon naturel, 3 px au moins.
        func rayonPastille(_ naturel: Double, en p: SIMD3<Double>) -> Double {
            min(naturel * 1.1, max(3, naturel * proj.pxParUnite(p) / CartesPieces.px))
        }
        for (i, pc) in scene.pieces.enumerated() where i < cartes.count && i < positions.count {
            let c = g.centrePlateau(pc.etage, t)
            let fe = CameraScene.rampe(i < etat.fk.count ? etat.fk[i] : 0)
            let voile = 1 - es * (1 - fe), f = 1 + 0.3 * fe
            voiles[i] = voile
            echelles[i] = f
            var vis = min(1 - 0.85 * (1 - voile), pc.etage < ve.count ? ve[pc.etage] : 1)
            var m = SIMD3(c.x + positions[i].x, c.y, c.z + positions[i].y)
            var taille = SIMD2(cartes[i].largeur, cartes[i].profondeur)
            if let pose = poses.pieces[pc.id],
               let centre = PosesScene.centre(pose.ancres, geometrie: g, plateaux: plateaux, t: t) {
                m = centre
                taille = pose.taille
                vis *= pose.opacite
            }
            bloc(i, centre: m, taille: taille, f: f, teinte: pc.teinte, vis: vis)
            for (r, id) in pc.noeuds.enumerated() where r < cartes[i].places.count {
                if let n = poses.noeuds[id] {
                    apparitions[id] = n.opacite
                    if let w = monde(n, f: f) {
                        mondes[id] = w
                        continue
                    }
                }
                mondes[id] = place(m, cartes[i].places[r], f: f)
            }
        }
        // Ce qui s'efface est sous le voile de l'isolement, comme ce qui reste (relecture finale, Mineur 2) : celui du
        // plateau de son ancre de plus fort poids, et celui d'une piece hors du focus ; un noeud, celui de la piece
        // qu'il quitte, si elle reste : il part de son opacite affichee, meme de la piece isolee (relecture ciblee de
        // la vague finale, Mineur 1).
        func voileAncres(_ ancres: [PosesScene.Ancre]) -> Double {
            guard let a = ancres.max(by: { $0.poids < $1.poids }), let e = plateaux[a.plateau], e < ve.count else {
                return 1
            }
            return ve[e]
        }
        // Sans transition, pas de noeud qui s'efface : pas d'indice a construire.
        let indicesPieces = poses.noeuds.isEmpty ? [:]
            : Dictionary(scene.pieces.indices.map { (scene.pieces[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
        func pieceRestante(_ n: PosesScene.Noeud) -> Int? {
            n.piece.flatMap { indicesPieces[$0] }.flatMap { $0 < voiles.count ? $0 : nil }
        }
        let presentes = Set(scene.pieces.map(\.id))
        for (k, pose) in poses.pieces.sorted(by: { $0.key < $1.key }) where !presentes.contains(k) {
            guard let centre = PosesScene.centre(pose.ancres, geometrie: g, plateaux: plateaux, t: t) else { continue }
            bloc(-1, centre: centre, taille: pose.taille, f: 1, teinte: pose.teinte,
                 vis: min(1 - 0.85 * es, voileAncres(pose.ancres)) * pose.opacite)
        }
        for (id, n) in poses.noeuds where scene.noeud(id) == nil {
            guard let w = monde(n, f: 1) else { continue }
            mondes[id] = w
            fantomes.insert(id)
        }
        blocs.sort { $0.profondeur > $1.profondeur }
        centresNoeuds = mondes

        // Le voile de l'etage d'une piece.
        func voileEtage(_ piece: Int) -> Double {
            let e = scene.pieces[piece].etage
            return e < ve.count ? ve[e] : 1
        }

        // Pastilles ; en mode focus, celles qui ne sont pas mises en avant s'estompent, avec leur nom.
        for (id, e) in etat.noeudsEstompes where e > 0 { facteursNoeuds[id] = MiseEnAvant.facteur(e) }
        for n in scene.noeuds {
            guard let p = mondes[n.id], let e = proj.ecran(p) else { continue }
            let r = rayonPastille(n.rayon, en: p)
            disques.append(Disque(noeud: n.id, centre: e, rayon: r,
                                  opacite: min(1 - 0.8 * (1 - voiles[n.piece]), voileEtage(n.piece))
                                      * (apparitions[n.id] ?? 1),
                                  profondeur: proj.profondeur(p), focus: facteur(noeud: n.id)))
            ancresNoeuds[n.id] = CGRect(x: Double(e.x) - r, y: Double(e.y) - r, width: 2 * r, height: 2 * r)
        }
        for id in fantomes.sorted() {
            guard let n = poses.noeuds[id], let p = mondes[id], let e = proj.ecran(p) else { continue }
            disques.append(Disque(noeud: id, centre: e, rayon: rayonPastille(n.rayon, en: p),
                                  opacite: min(1 - 0.8 * (pieceRestante(n).map { 1 - voiles[$0] } ?? es),
                                               voileAncres(n.ancres)) * n.opacite,
                                  profondeur: proj.profondeur(p)))
        }
        disques.sort { $0.profondeur > $1.profondeur }

        // Liens : estompes avec leurs pieces ; un lien qui touche l'etage isole reste visible, meme vers un autre
        // etage ; eclaires au survol (ou a la selection) d'un bout ; en mode focus, estompes s'ils ne sont pas mis en
        // avant.
        for l in scene.liens {
            guard let trace = Self.trace(l, mode: etat.liens, selection: etat.selection, voisins: etat.voisins),
                  let a = mondes[l.de], let b = mondes[l.vers], let (pa, pb) = proj.segment(a, b),
                  let na = scene.noeud(l.de), let nb = scene.noeud(l.vers) else { continue }
            let poids = min(1 - 0.85 * (1 - max(voiles[na.piece], voiles[nb.piece])),
                            max(voileEtage(na.piece), voileEtage(nb.piece)))
            let eclaire = [l.de, l.vers].contains { $0 == etat.survol || $0 == etat.selection }
            // Sans transition, pas de cle de lien a construire (relecture finale, Mineur 5).
            var fondu = poses.liens.isEmpty ? 1 : poses.liens[PosesScene.cle(l)]?.opacite ?? 1
            if !etat.liensEstompes.isEmpty, let e = etat.liensEstompes[MiseEnAvant.cle(l)] {
                fondu *= MiseEnAvant.facteur(e)
            }
            let p = Self.lien(l, trace: trace, a: pa, b: pb, poids: poids, fondu: fondu, eclaire: eclaire)
            if p.genre == .parent || p.genre == .rattachement { liensEnfants.append(p) } else { liensRouteurs.append(p) }
        }
        // Les liens qui s'effacent, absents de la scene, entre les places affichees de leurs bouts, sous le voile de
        // leurs bouts, comme ceux qui restent : un bout de la scene, celui de sa piece ; un bout qui s'efface, celui
        // de la piece qu'il quitte si elle reste, sinon d'une piece hors du focus, et celui du plateau de son ancre.
        func voilesBout(_ id: String) -> (piece: Double, etage: Double) {
            if let n = scene.noeud(id) { return (voiles[n.piece], voileEtage(n.piece)) }
            guard let n = poses.noeuds[id] else { return (1 - es, 1) }
            return (pieceRestante(n).map { voiles[$0] } ?? 1 - es, voileAncres(n.ancres))
        }
        let presents = poses.liens.isEmpty ? Set<String>() : Set(scene.liens.map(PosesScene.cle))
        for (k, l) in poses.liens.sorted(by: { $0.key < $1.key }) where !presents.contains(k) {
            guard let trace = Self.trace(l.graphe, mode: etat.liens, selection: etat.selection, voisins: etat.voisins),
                  let a = mondes[l.de], let b = mondes[l.vers], let (pa, pb) = proj.segment(a, b) else { continue }
            let va = voilesBout(l.de), vb = voilesBout(l.vers)
            let poids = min(1 - 0.85 * (1 - max(va.piece, vb.piece)), max(va.etage, vb.etage))
            let p = Self.lien(l.graphe, trace: trace, a: pa, b: pb, poids: poids, fondu: l.opacite, eclaire: false)
            if p.genre == .parent || p.genre == .rattachement { liensEnfants.append(p) } else { liensRouteurs.append(p) }
        }

        // Reperes « ailleurs » de la piece isolee : un fil vers le bord de la piece, du cote du parent.
        if let i = etat.focus, i < scene.pieces.count, i < cartes.count {
            let fe = CameraScene.rampe(i < etat.fk.count ? etat.fk[i] : 0)
            ailleurs = Self.reperes(scene, focus: i)
            for a in ailleurs {
                guard let e = mondes[a.enfant], let pp = mondes[a.parent] else { continue }
                var dir = pp - centres[i]
                dir.y = 0
                dir = simd_length_squared(dir) < 1e-6 ? SIMD3(1, 0, 0) : simd_normalize(dir)
                var m = centres[i] + dir * (max(cartes[i].largeur, cartes[i].profondeur) * echelles[i] / 2 + 2.6)
                m.y = e.y
                if let (pa, pb) = proj.segment(e, m) { fils.append(Fil(a: pa, b: pb, opacite: 0.8 * fe)) }
                if let q = proj.ecran(m) {
                    ancresAilleurs[a.enfant] = CGRect(x: q.x - 3, y: q.y - 3, width: 6, height: 6)
                }
            }
        }

        // Zoom semantique, noms d'etage (au bord du plateau, en haut de l'ecran) et de la maison.
        echelle = proj.pxParUnite(orbite.cible) / CartesPieces.px
        niveau = NiveauZoom(echelle: echelle)
        var hh = orbite.haut
        hh.y = 0
        let hautHorizontal = simd_length_squared(hh) < 1e-8 ? SIMD3<Double>(0, 0, -1) : simd_normalize(hh)
        for e in g.rayons.indices {
            if let p = proj.ecran(g.centrePlateau(e, t) + hautHorizontal * g.rayons[e]) {
                ancresEtages[e] = CGRect(origin: p, size: .zero)
            }
        }
        ancreMaison = proj.ecran(g.centreSphere + orbite.haut * rs).map { CGRect(origin: $0, size: .zero) }
    }

    /// Reperes « ailleurs » d'une piece isolee : ses enfants dont le parent (vu par la sonde) est dans
    /// une autre piece, dans l'ordre de ses lignes ; leur sens compare les niveaux des deux plateaux.
    public static func reperes(_ scene: ScenePieces, focus i: Int) -> [Ailleurs] {
        let pc = scene.pieces[i]
        let ici = scene.etages[pc.etage].niveau
        return pc.noeuds.compactMap { id in
            guard let parent = scene.liens.first(where: { $0.genre == .parent && $0.de == id })?.vers,
                  let np = scene.noeud(parent), np.piece != i else { return nil }
            let ep = scene.pieces[np.piece].etage
            let la = scene.etages[ep].niveau
            return Ailleurs(enfant: id, parent: parent, piece: np.piece, etage: ep,
                            sens: la == ici ? .memeNiveau : la < ici ? .dessous : .dessus)
        }
    }

    /// Piece sous un point de l'ecran : la plus proche dont une face le contient.
    public func piece(sous p: CGPoint) -> Int? {
        blocs.reversed().first { b in b.piece >= 0 && b.faces.contains { Self.contient($0.points, p) } }?.piece
    }

    /// Noeud sous un point de l'ecran : la pastille la plus proche, a `marge` points pres de son bord.
    public func noeud(sous p: CGPoint, marge: Double = 8) -> String? {
        var meilleur: (String, Double)?
        for d in disques where d.opacite > 0.5 && !fantomes.contains(d.noeud) {
            let e = hypot(Double(d.centre.x - p.x), Double(d.centre.y - p.y))
            if e <= d.rayon + marge, e < meilleur?.1 ?? .infinity { meilleur = (d.noeud, e) }
        }
        return meilleur?.0
    }

    /// Point dans un polygone (regle pair-impair).
    public static func contient(_ poly: [CGPoint], _ p: CGPoint) -> Bool {
        var dedans = false
        var j = poly.count - 1
        for i in poly.indices {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { dedans.toggle() }
            j = i
        }
        return dedans
    }

    static func cercle(_ c: SIMD3<Double>, _ r: Double, _ n: Int) -> [SIMD3<Double>] {
        (0..<n).map { i in
            let a = Double(i) / Double(n) * 2 * .pi
            return c + SIMD3(r * cos(a), 0, r * sin(a))
        }
    }

    /// Boite englobante de points de l'ecran.
    public static func boite(_ pts: [CGPoint]) -> CGRect {
        var x0 = CGFloat.infinity, y0 = CGFloat.infinity, x1 = -CGFloat.infinity, y1 = -CGFloat.infinity
        for p in pts {
            x0 = min(x0, p.x)
            y0 = min(y0, p.y)
            x1 = max(x1, p.x)
            y1 = max(y1, p.y)
        }
        return CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }
}
