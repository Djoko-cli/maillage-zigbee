import AppKit
import MaillageCoeur
import SwiftUI
import simd

/// La souris (survol, clics, glisser), la molette, le pincement, et le moniteur des evenements de la fenetre : la
/// molette, ⌥, et Echap, qu'il passe a `sortir` (dans `MoteurPieces+Camera`) (polissage D, section 5 : le moteur en
/// fichiers).
extension MoteurPieces {
    // MARK: Souris et clavier

    /// Noeud sous un point : sa pastille, a 8 points pres, sinon son nom.
    func noeudSous(_ p: CGPoint) -> String? {
        if let n = projetee?.noeud(sous: p, marge: 8) { return n }
        for l in etiquettes where l.vu && l.rect.contains(p) {
            if case .noeud(let id) = l.genre { return id }
        }
        return nil
    }

    /// Survol : le nom de l'appareil en semi-gras ; un disque cliquable s'eclaircit, le nom d'un etage se souligne ; la
    /// main sur ce qui se clique (polissage C, maquette). Rien pendant l'envol : ni clic, ni menu du clic droit.
    func survoler(_ p: CGPoint?, option: Bool = false) {
        curseur = p
        optionTenue = option
        let libre = envol == nil && fondu == nil
        let c = libre ? p.map(cibleClic(en:)) ?? .fond : .fond
        let n: String? = if case .appareil(let id) = c { id } else { nil }
        let disque: Int? = if case .disque(let e) = c, disqueCliquable(e) { e } else { nil }
        let nom: Int? = if case .nomEtage(let e) = c { e } else { nil }
        if n != survol || disque != survolEtage || nom != survolNomEtage {
            survol = n
            survolEtage = disque
            survolNomEtage = nom
            reveiller()
        }
        surCliquable = switch c {
        case .appareil, .piece: true
        case .nomEtage(let e): etageCliquable(e, disque: false)
        case .disque(let e): disqueCliquable(e)
        case .fond: false
        }
        majCurseur()
        let cible = libre ? p.map(cible(en:)) ?? .aucune : .aucune
        if cible != cibleMenu { cibleMenu = cible }
    }

    /// ⌥ pressee ou relachee, le pointeur immobile (le moniteur des touches).
    func changerOption(_ option: Bool) {
        guard option != optionTenue else { return }
        optionTenue = option
        majCurseur()
    }

    /// Le curseur (polissage C, section 6) : une main fermee pendant ⌥ + glisser ; une main ouverte tant que ⌥ est
    /// tenue au-dessus de la vue en 3D ; sinon, une main sur ce qui se clique.
    private func majCurseur() {
        let forme: Curseur
        if case .ecran? = geste {
            forme = .mainFermee
        } else if optionTenue && curseur != nil && troisD && t == 1 && envol == nil && fondu == nil {
            forme = .mainOuverte
        } else {
            forme = surCliquable ? .main : .fleche
        }
        if forme != curseurForme { curseurForme = forme }
    }

    /// Ce que vise un clic en `p`, du plus fort au plus faible (polissage C, section 5.1).
    func cibleClic(en p: CGPoint) -> CibleClic {
        if let n = noeudSous(p) { return .appareil(n) }
        if let i = pieceSous(p) { return .piece(i) }
        if let e = nomEtageSous(p) { return .nomEtage(e) }
        if let e = disqueSous(p) { return .disque(e) }
        return .fond
    }

    /// Nom d'etage sous un point (`marge` points autour).
    func nomEtageSous(_ p: CGPoint, marge: CGFloat = 0) -> Int? {
        for l in etiquettes where l.vu && l.rect.insetBy(dx: -marge, dy: -marge).contains(p) {
            if case .etage(let e) = l.genre { return e }
        }
        return nil
    }

    /// Disque d'un plateau sous un point : en 3D, le plus proche sur le rayon, au point ou il le rencontre.
    func disqueSous(_ p: CGPoint) -> Int? {
        guard let projetee else { return nil }
        let proj = ProjectionScene(orbite, cadre: cadre)
        var meilleur: (etage: Int, profondeur: Double)?
        for pl in projetee.plateaux where pl.etage < geometrie.rayons.count && SceneProjetee.contient(pl.polygone, p) {
            let point = proj.sol(p, hauteur: geometrie.centrePlateau(pl.etage, t).y)
            let d = point.map { proj.profondeur($0) } ?? pl.profondeur
            if d < meilleur?.profondeur ?? .infinity { meilleur = (pl.etage, d) }
        }
        return meilleur?.etage
    }

    /// Un clic sur ce disque fait quelque chose (polissage C, section 5.4) : sauf celui de l'etage isole, entre ses
    /// pieces ; dans une maison d'un seul plateau, seulement depuis une piece isolee, pour remonter.
    func disqueCliquable(_ e: Int) -> Bool {
        etageCliquable(e, disque: true)
    }

    /// La main du pointeur sur le nom ou le disque du plateau `e` : la regle du clic (`Isolement.cliquable`).
    private func etageCliquable(_ e: Int, disque: Bool) -> Bool {
        guard let scene, e < scene.etages.count else { return false }
        return isolement.cliquable(scene.etages[e].id, disque: disque, plusieursPlateaux: scene.etages.count > 1,
                                   pieceIsolee: estIsolee)
    }

    /// Ce que fait un clic sur le nom ou le disque du plateau `e` (`Isolement.clicEtage`).
    private func clicEtage(_ e: Int, disque: Bool) -> Isolement.ClicEtage {
        guard let scene, e < scene.etages.count else { return .rien }
        return isolement.clicEtage(scene.etages[e].id, disque: disque, plusieursPlateaux: scene.etages.count > 1,
                                   pieceIsolee: estIsolee)
    }

    /// Piece sous un point : son nom (le nom et le compte de ses appareils), sinon sa boite, la plus proche
    /// (verification du 02/10 : en 3D, les boites sont petites, et l'on clique volontiers sur le nom). Le nom,
    /// dessine par-dessus les boites, l'emporte sur celle d'une autre piece qu'il recouvre.
    func pieceSous(_ p: CGPoint) -> Int? {
        for l in etiquettes where l.vu && l.rect.contains(p) {
            if case .piece(let i) = l.genre { return i }
        }
        return projetee?.piece(sous: p)
    }

    /// Clic droit (polissage C, section 1.3) : le nom d'un etage, a 2 points pres, ou son disque, hors des pieces et
    /// des appareils, par la cle de son plateau ; le fond, hors de tout cela ; rien sur une piece ou un appareil.
    func cible(en p: CGPoint) -> CibleMenu {
        if let e = nomEtageSous(p, marge: 2) { return cleEtage(e).map(CibleMenu.etage) ?? .aucune }
        if noeudSous(p) != nil || pieceSous(p) != nil { return .aucune }
        if let e = disqueSous(p) { return cleEtage(e).map(CibleMenu.etage) ?? .aucune }
        return .fond
    }

    /// Un glisser, a chaque deplacement du pointeur ; `option` : ⌥ tenue, lue a l'appui seulement (polissage C,
    /// section 6) : en 3D, la vue glisse alors dans le plan de l'ecran, depuis le fond, un disque ou une piece, qui ne
    /// bouge pas ; un vol en cours s'arrete, et pendant le geste la camera n'obeit qu'au pointeur
    /// (`deplaceDansLEcran`). Relacher ⌥ en route ne change rien. En 2D, ⌥ ne change rien.
    func glisser(_ p: CGPoint, depart d: CGPoint, option: Bool = false) {
        // Un geste reste d'un glisser annule (sans relachement), et celui-ci part d'ailleurs : il est clos.
        if geste != nil, d != departGeste { terminerGeste() }
        if geste == nil {
            bouge = false
            abandonApresGlisser = false
            precedent = d
            departGeste = d
            if option && troisD && t == 1 && envol == nil && fondu == nil {
                vol = nil
                viseeVol = nil
                geste = .ecran(orbite)
            } else if !estIsolee, !enMouvement, let scene, let i = projetee?.piece(sous: d), i < scene.pieces.count,
                      indiceEtageIsole.map({ $0 == scene.pieces[i].etage }) ?? true {
                // Les pieces de l'etage isole se glissent ; celles des autres etages se cliquent seulement. Une piece
                // en route vers sa place n'y est posee qu'au premier vrai mouvement (`prendrePiece`) : un simple clic
                // ne la fait pas sauter. Sans centre (un indice hors des positions), elle reste de cote : le geste est
                // celui du fond.
                if let h = centrePiece(i)?.y {
                    geste = .piece(scene.pieces[i].id, hauteur: h)
                } else {
                    geste = .fond
                }
            } else {
                geste = .fond
            }
            majCurseur()
        }
        if !bouge && hypot(p.x - d.x, p.y - d.y) < 5 { return }
        if !bouge {
            bouge = true
            if case .piece(let id, _)? = geste { geste = prendrePiece(id) }
        }
        defer { precedent = p }
        guard !enMouvement, let geste else { return }
        let proj = ProjectionScene(orbite, cadre: cadre)
        switch geste {
        case .ecran(let o):
            orbite = CameraScene.deplacerDansLEcran(o, glisse: CGSize(width: p.x - d.x, height: p.y - d.y),
                                                    cadre: cadre)
            vueTouchee = true
        case .piece(let id, let h):
            guard let scene, let i = scene.pieces.firstIndex(where: { $0.id == id }), i < positions.count,
                  i < cartes.count, scene.pieces[i].etage < geometrie.rayons.count,
                  let a = proj.sol(precedent, hauteur: h), let b = proj.sol(p, hauteur: h) else { return }
            var pos = positions[i] + SIMD2(b.x - a.x, b.z - a.z)
            let demiDiagonale = 0.5 * hypot(cartes[i].largeur, cartes[i].profondeur)
            let r = max(0, geometrie.rayons[scene.pieces[i].etage] - demiDiagonale)
            if simd_length(pos) > r { pos = simd_length(pos) > 0 ? simd_normalize(pos) * r : .zero }
            positions[i] = pos
        case .fond:
            if t == 0 {
                if let a = proj.sol(precedent, hauteur: orbite.cible.y), let b = proj.sol(p, hauteur: orbite.cible.y) {
                    orbite.cible += a - b
                    vueTouchee = true
                }
            } else {
                let h = max(1, Double(taille.height))
                rotationEnAttente.x -= 2 * .pi * Double(p.x - precedent.x) / h
                rotationEnAttente.y -= 2 * .pi * Double(p.y - precedent.y) / h
            }
        }
        reveiller()
    }

    /// Une piece prise, au premier vrai mouvement du glisser (relecture finale, Mineur 3) : en route vers sa place,
    /// elle y est posee, avec ses noeuds ; elle suit alors le pointeur depuis sa place, a sa hauteur, lue une fois
    /// posee. Sans centre, le geste devient celui du fond.
    private func prendrePiece(_ id: String) -> Geste {
        guard let scene, let i = scene.pieces.firstIndex(where: { $0.id == id }) else { return .fond }
        if transition != nil {
            transition?.oublier(pieces: [id], noeuds: Set(scene.pieces[i].noeuds))
            if let tr = transition { posesAffichees = tr.poses(a: Self.maintenant()) }
        }
        return centrePiece(i).map { .piece(id, hauteur: $0.y) } ?? .fond
    }

    /// Fin d'un glisser, ou clic. Deux clics sur le fond ou sur un disque, a moins de l'intervalle du double-clic
    /// de macOS et de 5 points : le second est un double-clic ; le premier a agi comme un clic simple. Une
    /// scene recue pendant le geste s'applique ensuite, avec la place gardee de la piece glissee.
    func relacher(_ p: CGPoint, a instant: Double = MoteurPieces.maintenant()) {
        let g = geste
        let clic = !bouge && !(g == nil && abandonApresGlisser)
        geste = nil
        bouge = false
        abandonApresGlisser = false
        majCurseur()
        if case .piece(let id, _)? = g, !clic {
            garder(id)
        } else if clic {
            let fond = switch cibleClic(en: p) {
            case .fond, .disque: true
            default: false
            }
            if fond, let c = clicFond, instant - c.instant <= NSEvent.doubleClickInterval,
               hypot(p.x - c.point.x, p.y - c.point.y) <= 5 {
                clicFond = nil
                if envol == nil, fondu == nil { doubleCliquer() }
            } else {
                clicFond = fond ? (instant, p) : nil
                cliquer(p)
            }
        }
        if !occupe, let e = attente { appliquer(e) }
        reveiller()
    }

    /// Geste annule : SwiftUI remet l'etat du geste a zero sans appeler `onEnded` (la vue quitte la
    /// fenetre pendant le geste, ou le geste est interrompu). Il est clos sans clic, la piece glissee
    /// garde sa place, et la scene en attente s'applique. Apres un relachement, plus de geste : rien.
    func abandonnerGeste() {
        guard geste != nil else { return }
        abandonApresGlisser = bouge
        terminerGeste()
        if !occupe, let e = attente { appliquer(e) }
        reveiller()
    }

    /// Clot un geste reste ouvert (glisser annule, sans relachement) : la piece glissee garde sa place,
    /// sans clic. Depuis `glisser`, la scene en attente s'applique a la fin du geste suivant (sinon les
    /// indices de la projection, qui a servi a le commencer, periment) ; depuis `abandonnerGeste`, elle
    /// s'applique tout de suite apres, sauf pendant un mouvement.
    private func terminerGeste() {
        if case .piece(let id, _)? = geste, bouge { garder(id) }
        geste = nil
        bouge = false
        majCurseur()
    }

    /// Clic sans glisser, selon sa cible (polissage C, sections 5.1 et 5.4) : un appareil ou son nom ouvre sa fiche, ou
    /// la ferme s'il est deja choisi (etape 5) ; une piece ou son nom l'isole (en piece isolee, une autre piece y mene,
    /// meme pendant le vol) ; le nom ou le disque d'un etage l'isole ; a cote, la fiche se ferme et la vue remonte d'ou
    /// elle vient. Rien pendant l'envol.
    func cliquer(_ p: CGPoint) {
        guard envol == nil, fondu == nil else { return }
        switch cibleClic(en: p) {
        case .appareil(let n):
            // Un second clic sur le noeud choisi ferme sa fiche, et rend la vue normale (mode focus, etape 5).
            selection = selection == n ? nil : n
        case .piece(let i):
            if !(focus == i && sCible == 1) { isoler(i) }
        case .nomEtage(let e):
            cliquerEtage(e, disque: false)
        case .disque(let e):
            cliquerEtage(e, disque: true)
        case .fond:
            selection = nil
            remonter(clavier: false)
        }
    }

    /// Clic sur le nom ou le disque d'un etage : il l'isole ; son propre disque, l'etage isole, entre les pieces, ne
    /// fait rien. Maison d'un seul plateau : seulement depuis une piece isolee, pour remonter a la maison.
    private func cliquerEtage(_ e: Int, disque: Bool) {
        switch clicEtage(e, disque: disque) {
        case .isoler: allerEtage(e)
        case .maison: versMaison()
        case .rien: break
        }
    }

    /// La molette zoome, sauf pendant un vol et pendant ⌥ + glisser : elle est alors ignoree, non differee. Au-dessus
    /// d'un element pose sur la vue (`p`, dans la vue : la fiche, la legende, la ligne des capsules, la colonne du
    /// haut), elle n'est pas prise (faux) : l'evenement leur revient (polissage D, section 3).
    @discardableResult
    func molette(_ dy: Double, precis: Bool, en p: CGPoint? = nil) -> Bool {
        if let p, surInterface(p) { return false }
        guard !enMouvement, !deplaceDansLEcran else { return true }
        zoomer(precis ? -dy * 0.004 : -dy * 0.08, en: curseur)
        return true
    }

    /// Le point `p` de la vue est sur un element pose sur elle.
    func surInterface(_ p: CGPoint) -> Bool {
        cadresInterface.values.contains { $0.contains(p) }
    }

    /// Le pincement zoome de son increment depuis le dernier `m`, sauf pendant un vol et pendant ⌥ + glisser : il est
    /// alors ignore, mais suivi, pour que celui qui continue apres ne saute pas de ce qu'il a fait pendant.
    func pincer(_ m: Double, en p: CGPoint) {
        let l = -log(max(0.05, m) / max(0.05, dernierPincement))
        dernierPincement = m
        guard !enMouvement, !deplaceDansLEcran else { return }
        zoomer(l, en: p)
    }

    /// Fin du pincement (relache, annule, ou la vue fermee) : la rotation lente, arretee pendant le geste, reprend
    /// (polissage D, section 4.2) ; l'horloge, endormie pendant un pincement tenu immobile, se reveille.
    func finPincement() {
        guard dernierPincement != 1 else { return }
        dernierPincement = 1
        reveiller()
    }

    /// Zoom amorti ; en 2D, vers le point sous le curseur.
    private func zoomer(_ l: Double, en p: CGPoint?) {
        ancreZoom = nil
        if t == 0, let p { ancreZoom = ProjectionScene(orbite, cadre: cadre).sol(p, hauteur: orbite.cible.y) }
        zoomEnAttente += l
        vueTouchee = true
        reveiller()
    }

    /// Molette et Echap, dans la fenetre de la vue seulement : un moniteur local (SwiftUI n'a pas
    /// d'evenement de molette brut).
    func ecouter() {
        guard moniteur == nil else { return }
        let genres: NSEvent.EventTypeMask = [.scrollWheel, .keyDown, .flagsChanged]
        moniteur = NSEvent.addLocalMonitorForEvents(matching: genres) { [weak self] e in
            guard let self else { return e }
            let pris = MainActor.assumeIsolated { self.prendre(e) }
            return pris ? nil : e
        }
    }

    /// Un evenement du moniteur, dans la fenetre de la vue seulement : la molette, au-dessus de la scene (pas d'un
    /// element pose sur elle), et Echap, s'il a quelque chose a faire, sont pris (vrai : le moniteur rend nil) ; ⌥
    /// pressee ou relachee met a jour la main ouverte (polissage C, section 6) et continue son chemin, comme tout le
    /// reste.
    func prendre(_ e: NSEvent) -> Bool {
        guard e.window != nil, e.window === fenetre else { return false }
        return prendre(EvenementVue(e))
    }

    /// Ce que le moniteur lit d'un evenement de la fenetre de la vue.
    struct EvenementVue {
        enum Genre {
            /// La molette : son pas, precis (trackpad) ou non, et le point du pointeur dans la fenetre.
            case molette(dy: Double, precis: Bool, position: CGPoint)
            case echap
            /// ⌥ tenue ou non.
            case option(Bool)
            case autre
        }

        var genre: Genre

        init(_ genre: Genre) {
            self.genre = genre
        }

        init(_ e: NSEvent) {
            switch e.type {
            case .scrollWheel:
                genre = .molette(dy: Double(e.scrollingDeltaY), precis: e.hasPreciseScrollingDeltas,
                                 position: e.locationInWindow)
            case .keyDown where e.keyCode == 53:
                genre = .echap
            case .flagsChanged:
                genre = .option(e.modifierFlags.contains(.option))
            default:
                genre = .autre
            }
        }
    }

    /// La meme chose, une fois l'evenement lu.
    func prendre(_ e: EvenementVue) -> Bool {
        switch e.genre {
        case .molette(let dy, let precis, let position):
            return molette(dy, precis: precis, en: vue.map { VuePieces.point(position, dans: $0) })
        case .echap:
            return sortir()
        case .option(let option):
            changerOption(option)
            return false
        case .autre:
            return false
        }
    }

    func arreterEcoute() {
        if let m = moniteur { NSEvent.removeMonitor(m) }
        moniteur = nil
    }
}
