import Foundation

/// Disposition des pieces dans leurs etages (spec de la vue par pieces, section 4.3) : cartes
/// espacees, tassees de facon organique, puis placees pour que les liens evitent les autres pieces
/// et se croisent peu. Deterministe : memes entrees, meme disposition, sur toutes les machines (le
/// budget compte des coups, pas du temps). Calcul hors du fil principal : il peut prendre une
/// fraction de seconde. Depuis le polissage C (section 4), son cout voit la maison de dessus, niveau par
/// niveau : elle ne depend ni de la fenetre, ni de la disposition 2D des plateaux (grille ou rangee).
public struct DispositionPieces: Hashable, Sendable {
    /// Ecart entre cartes, bande du nom au-dessus d'une carte, marge du plateau, ecart entre plateaux
    /// en 2D (unites).
    public static let gap = 80 / CartesPieces.px
    public static let lab = 28 / CartesPieces.px
    public static let marge = 56 / CartesPieces.px
    public static let esp = 140 / CartesPieces.px
    /// Coups evalues au plus par calcul, tous departs compris.
    public static let budget = 3000
    public static let departs = 6
    public static let toursMax = 25

    /// Centre de chaque piece (x, z) par rapport au centre de son plateau, en unites.
    public var positions: [SIMD2<Double>]
    /// Rayon de chaque plateau, dans l'ordre des etages.
    public var rayons: [Double]
    /// Cout du premier depart, apres son tassement ; cout de la disposition retenue.
    public var coutDepart: Double
    public var cout: Double
    /// Coups evalues.
    public var coups: Int

    /// `fixees` : places gardees des pieces deplacees (indice de piece -> position) ; elles ne bougent
    /// pas et servent d'obstacles. Un depart d'un cout non fini (une entree demesuree) n'est pas
    /// retenu ; sans depart d'un cout fini, la disposition est celle du depart, sans arret du programme.
    public init(scene: ScenePieces, cartes: [CartesPieces.Carte], fixees: [Int: SIMD2<Double>] = [:],
                budget: Int = DispositionPieces.budget) {
        let calcul = Calcul(scene: scene, cartes: cartes, fixees: fixees)
        let n = scene.pieces.count
        guard n > 0, calcul.fixe.contains(false) else {
            let pos = (0..<n).map { fixees[$0] ?? .zero }
            positions = pos
            rayons = (0..<calcul.nbEtages).map { calcul.rayon(pos, $0) }
            coutDepart = calcul.cout(pos)
            cout = coutDepart
            coups = 0
            return
        }
        var joues = 0
        var retenu: [SIMD2<Double>] = []
        var coutRetenu = Double.infinity
        // Meilleur depart dont aucune carte libre ne recouvre une autre carte (voir plus bas).
        var sain: [SIMD2<Double>]?
        var coutSain = Double.infinity
        var depart = 0.0
        var epuise = false
        for essai in 0..<Self.departs where !epuise {
            var pos = calcul.depart(essai, fixees: fixees)
            for e in 0..<calcul.nbEtages { calcul.tasser(&pos, e, tours: 900, facteur: 0.996) }
            var courant = pos
            var c = calcul.cout(courant)
            if essai == 0 { depart = c }
            for _ in 0..<Self.toursMax {
                var mieux: [SIMD2<Double>]?
                var cm = c
                for e in 0..<calcul.nbEtages where !epuise {
                    for coup in calcul.coups(e) {
                        guard joues < budget else {
                            epuise = true
                            break
                        }
                        joues += 1
                        var p = courant
                        calcul.jouer(coup, &p, etage: e)
                        calcul.tasser(&p, e, tours: 200, facteur: 0.998)
                        let cc = calcul.cout(p)
                        if cc < cm - 1e-6 {
                            cm = cc
                            mieux = p
                        }
                    }
                }
                if let m = mieux {
                    courant = m
                    c = cm
                }
                if epuise || mieux == nil { break }
            }
            // Un cout non fini (une entree demesuree) ne se compare pas : ce depart n'est pas retenu.
            guard c.isFinite else { continue }
            if c < coutRetenu {
                coutRetenu = c
                retenu = courant
            }
            if c < coutSain && !calcul.recouvre(courant) {
                coutSain = c
                sain = courant
            }
        }
        // Aucun depart d'un cout fini : la disposition de depart, celle d'avant l'optimisation (la
        // spirale du premier essai, les fixees a leur place), sans degagement.
        guard !retenu.isEmpty else {
            let pos = calcul.depart(0, fixees: fixees)
            positions = pos
            rayons = (0..<calcul.nbEtages).map { calcul.rayon(pos, $0) }
            coutDepart = depart
            cout = calcul.cout(pos)
            coups = joues
            return
        }
        // Avec des pieces fixees, une carte libre peut finir sur une autre carte : le tassement
        // l'attire vers le centre, parmi les fixees, et la separation s'arrete sur un point fixe ou
        // les poussees des fixees voisines s'annulent dans un meme tour ; le cout ne penalise pas un
        // recouvrement. Dans ce cas seulement, on garde le moins couteux du meilleur depart sans
        // recouvrement et de la disposition retenue degagee. Sans recouvrement, rien ne change.
        if calcul.recouvre(retenu) {
            var degage = retenu
            calcul.degager(&degage)
            let coutDegage = calcul.cout(degage)
            if let s = sain, coutSain <= coutDegage {
                retenu = s
                coutRetenu = coutSain
            } else {
                retenu = degage
                coutRetenu = coutDegage
            }
        }
        positions = retenu
        rayons = (0..<calcul.nbEtages).map { calcul.rayon(retenu, $0) }
        coutDepart = depart
        cout = coutRetenu
        coups = joues
    }

    /// Centre x de chaque plateau en 2D : cote a cote, `esp` entre les bords de deux voisins, la
    /// rangee centree sur x = 0.
    public static func centres2D(rayons: [Double]) -> [Double] {
        guard let r0 = rayons.first, let rn = rayons.last else { return [] }
        var x = [0.0]
        for i in rayons.indices.dropFirst() { x.append(x[i - 1] + rayons[i - 1] + esp + rayons[i]) }
        let milieu = ((x[0] - r0) + (x[x.count - 1] + rn)) / 2
        return x.map { $0 - milieu }
    }

    /// Longueur d'un segment a l'interieur d'un rectangle (decoupage de Liang et Barsky).
    static func dedans(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: Rect) -> Double {
        if max(p.x, q.x) <= r.x0 || min(p.x, q.x) >= r.x1 || max(p.y, q.y) <= r.z0 || min(p.y, q.y) >= r.z1 { return 0 }
        var t0 = 0.0
        var t1 = 1.0
        let d = q - p
        // Une borne du rectangle : faux si le segment est tout entier dehors.
        func borne(_ pp: Double, _ qq: Double) -> Bool {
            if pp == 0 { return qq >= 0 }
            let u = qq / pp
            if pp < 0 {
                if u > t1 { return false }
                if u > t0 { t0 = u }
            } else {
                if u < t0 { return false }
                if u < t1 { t1 = u }
            }
            return true
        }
        guard borne(-d.x, p.x - r.x0), borne(d.x, r.x1 - p.x), borne(-d.y, p.y - r.z0), borne(d.y, r.z1 - p.y) else {
            return 0
        }
        return t1 > t0 ? (t1 - t0) * (d.x * d.x + d.y * d.y).squareRoot() : 0
    }

    static func sens(_ a: SIMD2<Double>, _ b: SIMD2<Double>, _ c: SIMD2<Double>) -> Double {
        let v = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        return v > 0 ? 1 : v < 0 ? -1 : 0
    }

    /// Deux segments se coupent (strictement).
    static func croise(_ p: SIMD2<Double>, _ q: SIMD2<Double>, _ r: SIMD2<Double>, _ w: SIMD2<Double>) -> Bool {
        sens(p, q, r) * sens(p, q, w) < 0 && sens(r, w, p) * sens(r, w, q) < 0
    }

    /// Rectangle d'une carte en 2D, bande du nom comprise (au-dessus : vers -z).
    struct Rect {
        var x0, x1, z0, z1: Double
    }

    /// Donnees du calcul : tailles des cartes, etages, liens entre noeuds places dans leurs cartes.
    struct Calcul {
        enum Coup {
            case symetrie(Int)
            case echange(Int, Int)
        }

        struct Lien {
            var pa, pb: Int
            var la, lb: SIMD2<Double>
            var na, nb: Int
        }

        let w: [Double]
        let d: [Double]
        let etage: [Int]
        let nbEtages: Int
        /// Niveau de chaque plateau, et de chaque piece (polissage C, section 1).
        let niveauEtage: [Int]
        let niveau: [Int]
        /// Pieces de chaque etage, par aire decroissante.
        let parEtage: [[Int]]
        let fixe: [Bool]
        let lie: [[Bool]]
        let liens: [Lien]

        init(scene: ScenePieces, cartes: [CartesPieces.Carte], fixees: [Int: SIMD2<Double>]) {
            let n = scene.pieces.count
            let largeurs = cartes.map(\.largeur), profondeurs = cartes.map(\.profondeur)
            let aire = (0..<n).map { largeurs[$0] * profondeurs[$0] }
            w = largeurs
            d = profondeurs
            etage = scene.pieces.map(\.etage)
            nbEtages = scene.etages.count
            niveauEtage = scene.etages.map(\.niveau)
            niveau = scene.pieces.map { scene.etages[$0.etage].niveau }
            fixe = (0..<n).map { fixees[$0] != nil }
            parEtage = scene.etages.map { e in e.pieces.sorted { (-aire[$0], $0) < (-aire[$1], $1) } }
            // Place de chaque noeud dans sa carte.
            var place: [String: (piece: Int, local: SIMD2<Double>, indice: Int)] = [:]
            for (i, p) in scene.pieces.enumerated() {
                for (k, id) in p.noeuds.enumerated() {
                    place[id] = (i, k < cartes[i].places.count ? cartes[i].places[k] : .zero, scene.indice(id) ?? 0)
                }
            }
            var liens: [Lien] = []
            var lie = [[Bool]](repeating: [Bool](repeating: false, count: n), count: n)
            // Les chemins vers le pont doublent des liens radio : la disposition ne depend pas des liens montres.
            for l in scene.liens where l.genre != .chemin {
                guard let a = place[l.de], let b = place[l.vers] else { continue }
                liens.append(Lien(pa: a.piece, pb: b.piece, la: a.local, lb: b.local, na: a.indice, nb: b.indice))
                if a.piece != b.piece {
                    lie[a.piece][b.piece] = true
                    lie[b.piece][a.piece] = true
                }
            }
            self.liens = liens
            self.lie = lie
        }

        /// Depart `essai` : les cartes libres de chaque etage, par aire decroissante, sur une spirale
        /// (angle phase + i 2,39996, rayon racine(i + 0,5) 6, phase = essai 1,047) ; les fixees a leur place.
        func depart(_ essai: Int, fixees: [Int: SIMD2<Double>]) -> [SIMD2<Double>] {
            var pos = [SIMD2<Double>](repeating: .zero, count: w.count)
            for liste in parEtage {
                var i = 0
                for p in liste {
                    if let f = fixees[p] {
                        pos[p] = f
                        continue
                    }
                    let a = Double(essai) * 1.047 + Double(i) * 2.39996
                    let r = (Double(i) + 0.5).squareRoot() * 6
                    pos[p] = SIMD2(cos(a) * r, sin(a) * r)
                    i += 1
                }
            }
            return pos
        }

        /// Ecarte deux cartes qui se recouvrent (ecarts `gap` et `lab` compris) sur l'axe ou la
        /// penetration est la plus faible, de moitie chacune (toute pour une carte libre face a une
        /// fixee) ; rapproche de 0,3 % de leur ecart deux cartes reliees par un lien.
        func separer(_ pos: inout [SIMD2<Double>], _ e: Int, attirer: Bool) {
            let liste = parEtage[e]
            for i in liste.indices {
                for j in liste.indices where j > i {
                    let a = liste[i], b = liste[j]
                    if fixe[a] && fixe[b] { continue }
                    let dx = pos[b].x - pos[a].x, dz = pos[b].y - pos[a].y
                    let px = (w[a] + w[b]) / 2 + gap - abs(dx)
                    let pz = (d[a] + d[b]) / 2 + gap + lab - abs(dz)
                    let fa = fixe[a] ? 0.0 : fixe[b] ? 1.0 : 0.5
                    let fb = 1 - fa
                    if px > 0 && pz > 0 {
                        if px < pz {
                            let m = (dx < 0 ? -1.0 : 1.0) * px
                            pos[a].x -= m * fa
                            pos[b].x += m * fb
                        } else {
                            let m = (dz < 0 ? -1.0 : 1.0) * pz
                            pos[a].y -= m * fa
                            pos[b].y += m * fb
                        }
                    } else if attirer && lie[a][b] {
                        let v = SIMD2(dx, dz) * 0.003
                        if !fixe[a] { pos[a] += v }
                        if !fixe[b] { pos[b] -= v }
                    }
                }
            }
        }

        /// Jeu sous lequel deux cartes ne se recouvrent pas (unites) : les arrondis d'une separation
        /// exacte laissent des recouvrements de l'ordre de 1e-15.
        static let jeu = 1e-6

        /// Les cartes `a` et `b`, centrees en `pa` et `pb`, se recouvrent (ecarts `gap` et `lab`
        /// compris), au-dela du jeu.
        func chevauchent(_ pa: SIMD2<Double>, _ a: Int, _ pb: SIMD2<Double>, _ b: Int) -> Bool {
            let px = (w[a] + w[b]) / 2 + gap - abs(pb.x - pa.x)
            let pz = (d[a] + d[b]) / 2 + gap + lab - abs(pb.y - pa.y)
            return px > Self.jeu && pz > Self.jeu
        }

        /// La carte libre `p` recouvre une autre carte de son etage.
        func coincee(_ pos: [SIMD2<Double>], _ p: Int) -> Bool {
            parEtage[etage[p]].contains { $0 != p && chevauchent(pos[p], p, pos[$0], $0) }
        }

        /// Une carte libre recouvre une autre carte. Deux fixees qui se recouvrent ne comptent pas :
        /// rien ne peut les ecarter.
        func recouvre(_ pos: [SIMD2<Double>]) -> Bool {
            pos.indices.contains { !fixe[$0] && coincee(pos, $0) }
        }

        /// Place la plus proche de `pos[p]` ou la carte `p` ne recouvre aucune autre carte de son
        /// etage. Le bord de la zone interdite est fait des cotes des rectangles elargis des autres
        /// cartes : la place la plus proche a pour x celui de la carte ou celui d'un cote vertical,
        /// pour z celui de la carte ou celui d'un cote horizontal ; il suffit d'essayer ces
        /// combinaisons. Il en existe toujours une libre (a droite de toutes les autres cartes).
        func placeLibre(_ pos: [SIMD2<Double>], _ p: Int) -> SIMD2<Double> {
            let autres = parEtage[etage[p]].filter { $0 != p }
            var xs = [pos[p].x], zs = [pos[p].y]
            for o in autres {
                let hx = (w[p] + w[o]) / 2 + gap, hz = (d[p] + d[o]) / 2 + gap + lab
                xs += [pos[o].x - hx, pos[o].x + hx]
                zs += [pos[o].y - hz, pos[o].y + hz]
            }
            var place = pos[p]
            var dm = Double.infinity
            for x in xs {
                for z in zs {
                    let q = SIMD2(x, z), v = q - pos[p]
                    let dq = v.x * v.x + v.y * v.y
                    if dq < dm && !autres.contains(where: { chevauchent(q, p, pos[$0], $0) }) {
                        dm = dq
                        place = q
                    }
                }
            }
            return place
        }

        /// Dernier recours, quand la separation laisse une carte libre sur une autre : tant qu'une
        /// carte libre en recouvre une autre, celle qui a le moins a bouger va a sa place libre la
        /// plus proche (les fixees ne bougent jamais). Chaque deplacement ote tous les recouvrements
        /// de la carte deplacee sans en creer : le nombre de paires qui se recouvrent baisse a chaque
        /// tour, et le plafond de tours n'est jamais atteint. Il ne reste a la fin que les
        /// recouvrements entre fixees, sans solution. Un etage sans fixee est ensuite recentre.
        func degager(_ pos: inout [SIMD2<Double>]) {
            for e in 0..<nbEtages {
                let liste = parEtage[e]
                var bouge = false
                for _ in 0..<(liste.count * liste.count) {
                    var choix: (piece: Int, place: SIMD2<Double>, distance: Double)?
                    for p in liste where !fixe[p] && coincee(pos, p) {
                        let q = placeLibre(pos, p), v = q - pos[p]
                        let dq = v.x * v.x + v.y * v.y
                        if dq < choix?.distance ?? .infinity { choix = (p, q, dq) }
                    }
                    guard let c = choix else { break }
                    pos[c.piece] = c.place
                    bouge = true
                }
                if bouge && !liste.contains(where: { fixe[$0] }) { recentrer(&pos, e) }
            }
        }

        /// Recentre les cartes d'un etage sur leur boite, bande des noms comprise.
        func recentrer(_ pos: inout [SIMD2<Double>], _ e: Int) {
            var x0 = Double.infinity, x1 = -Double.infinity, z0 = Double.infinity, z1 = -Double.infinity
            for p in parEtage[e] {
                x0 = min(x0, pos[p].x - w[p] / 2)
                x1 = max(x1, pos[p].x + w[p] / 2)
                z0 = min(z0, pos[p].y - d[p] / 2 - lab)
                z1 = max(z1, pos[p].y + d[p] / 2)
            }
            let c = SIMD2((x0 + x1) / 2, (z0 + z1) / 2)
            for p in parEtage[e] { pos[p] -= c }
        }

        /// `tours` de separation, chacun suivi d'une homothetie de `facteur` vers le centre ; puis 60
        /// de separation seule ; puis le recentrage (sauf si l'etage a une carte fixee).
        func tasser(_ pos: inout [SIMD2<Double>], _ e: Int, tours: Int, facteur: Double) {
            let libres = parEtage[e].filter { !fixe[$0] }
            for _ in 0..<tours {
                separer(&pos, e, attirer: true)
                for p in libres { pos[p] *= facteur }
            }
            for _ in 0..<60 { separer(&pos, e, attirer: false) }
            if libres.count == parEtage[e].count { recentrer(&pos, e) }
        }

        /// Plus grande distance du centre a un coin de carte (bande du nom comprise), plus la marge.
        func rayon(_ pos: [SIMD2<Double>], _ e: Int) -> Double {
            var r = 0.0
            for p in parEtage[e] {
                let x = abs(pos[p].x) + w[p] / 2
                let z = max(abs(pos[p].y - d[p] / 2 - lab), abs(pos[p].y + d[p] / 2))
                r = max(r, (x * x + z * z).squareRoot())
            }
            return r + marge
        }

        /// Coups d'un etage : les 7 symetries du carre appliquees aux cartes libres, puis l'echange
        /// de chaque paire de cartes libres.
        func coups(_ e: Int) -> [Coup] {
            let libres = parEtage[e].filter { !fixe[$0] }
            guard !libres.isEmpty else { return [] }
            var c = (1...7).map { Coup.symetrie($0) }
            for i in libres.indices {
                for j in libres.indices where j > i { c.append(.echange(libres[i], libres[j])) }
            }
            return c
        }

        func jouer(_ coup: Coup, _ pos: inout [SIMD2<Double>], etage e: Int) {
            switch coup {
            case .symetrie(let o):
                for p in parEtage[e] where !fixe[p] {
                    let v = pos[p]
                    switch o {
                    case 1: pos[p] = SIMD2(-v.y, v.x)
                    case 2: pos[p] = SIMD2(-v.x, -v.y)
                    case 3: pos[p] = SIMD2(v.y, -v.x)
                    case 4: pos[p] = SIMD2(-v.x, v.y)
                    case 5: pos[p] = SIMD2(v.y, v.x)
                    case 6: pos[p] = SIMD2(v.x, -v.y)
                    default: pos[p] = SIMD2(-v.y, -v.x)
                    }
                }
            case .echange(let a, let b):
                pos.swapAt(a, b)
            }
        }

        /// Rectangles des cartes et extremites des liens dans la vue de reference du cout (polissage C, section 4) :
        /// la maison vue de dessus, niveau par niveau. Chaque niveau est une rangee : son etage principal en x = 0,
        /// puis ses zones a cote, a sa droite, `esp` entre les bords ; les niveaux sont superposes. Les plateaux d'un
        /// niveau se suivent dans la scene, l'etage principal d'abord.
        func vueReference(_ pos: [SIMD2<Double>]) -> (rayons: [Double], rects: [Rect], segments: [(SIMD2<Double>, SIMD2<Double>)]) {
            let rayons = (0..<nbEtages).map { rayon(pos, $0) }
            var cx = [Double](repeating: 0, count: nbEtages)
            for e in cx.indices.dropFirst() where niveauEtage[e] == niveauEtage[e - 1] {
                cx[e] = cx[e - 1] + rayons[e - 1] + DispositionPieces.esp + rayons[e]
            }
            let rects = pos.indices.map { i in
                let x = cx[etage[i]] + pos[i].x, z = pos[i].y
                return Rect(x0: x - w[i] / 2, x1: x + w[i] / 2, z0: z - d[i] / 2 - lab, z1: z + d[i] / 2)
            }
            let segments = liens.map { l in
                (SIMD2(cx[etage[l.pa]], 0) + pos[l.pa] + l.la, SIMD2(cx[etage[l.pb]], 0) + pos[l.pb] + l.lb)
            }
            return (rayons, rects, segments)
        }

        /// Cout d'une disposition, dans la vue de reference (polissage C, section 4) : la somme des rayons des
        /// plateaux ; pour chaque lien dont les deux bouts sont au meme niveau, 0,3 fois sa longueur, et 6 + 4 fois
        /// la longueur traversee pour chaque carte de ce niveau autre que celles de ses bouts qu'il traverse ; 5 par
        /// croisement de deux liens du meme niveau sans bout commun ; pour chaque lien entre deux niveaux, 0,1 fois
        /// son ecart horizontal. Pour une maison d'un seul plateau, le cout du plan 4b, au bit pres.
        func cout(_ pos: [SIMD2<Double>]) -> Double {
            let v = vueReference(pos)
            var c = v.rayons.reduce(0, +)
            for (k, l) in liens.enumerated() {
                let (p, q) = v.segments[k]
                guard niveau[l.pa] == niveau[l.pb] else {
                    let h = p - q
                    c += 0.1 * (h.x * h.x + h.y * h.y).squareRoot()
                    continue
                }
                let dl = q - p
                c += 0.3 * (dl.x * dl.x + dl.y * dl.y).squareRoot()
                for (r, rect) in v.rects.enumerated() where r != l.pa && r != l.pb && niveau[r] == niveau[l.pa] {
                    let t = DispositionPieces.dedans(p, q, rect)
                    if t > 0 { c += 6 + 4 * t }
                }
            }
            for i in liens.indices where niveau[liens[i].pa] == niveau[liens[i].pb] {
                let s = liens[i], (p, q) = v.segments[i]
                for j in liens.indices where j > i {
                    let t = liens[j]
                    if niveau[t.pa] != niveau[s.pa] || niveau[t.pb] != niveau[s.pa] { continue }
                    if s.na == t.na || s.na == t.nb || s.nb == t.na || s.nb == t.nb { continue }
                    let (r, u) = v.segments[j]
                    if max(p.x, q.x) < min(r.x, u.x) || max(r.x, u.x) < min(p.x, q.x)
                        || max(p.y, q.y) < min(r.y, u.y) || max(r.y, u.y) < min(p.y, q.y) { continue }
                    if DispositionPieces.croise(p, q, r, u) { c += 5 }
                }
            }
            return c
        }

        /// Liens d'un niveau qui passent sur une carte de ce niveau autre que celles de leurs bouts, dans la vue
        /// de reference (tests).
        func traversees(_ pos: [SIMD2<Double>]) -> Int {
            let v = vueReference(pos)
            var n = 0
            for (k, l) in liens.enumerated() where niveau[l.pa] == niveau[l.pb] {
                let (p, q) = v.segments[k]
                for (r, rect) in v.rects.enumerated() where r != l.pa && r != l.pb && niveau[r] == niveau[l.pa]
                    && DispositionPieces.dedans(p, q, rect) > 0 {
                    n += 1
                }
            }
            return n
        }
    }
}
