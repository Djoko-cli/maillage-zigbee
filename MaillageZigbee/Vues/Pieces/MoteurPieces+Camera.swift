import Foundation
import MaillageCoeur
import simd

/// Les plateaux et la grille, la camera et ce qu'elle regarde, les vols, l'isolement, le retour a la maison et ce
/// que fait Echap (`sortir`) (polissage D, section 5 : le moteur en fichiers).
extension MoteurPieces {
    // MARK: Plateaux

    /// La geometrie d'une scene : les rayons de sa disposition, ses niveaux, et la grille du reglage (en grille, les
    /// colonnes choisies, la rangee en attendant une vraie taille).
    func geometriePour(_ scene: ScenePieces) -> GeometrieMaison {
        GeometrieMaison(rayons: rayons(scene),
                        plateaux: scene.etages.map {
                            GeometrieMaison.Plateau(niveau: $0.niveau, principal: $0.principal, dehors: $0.dehors)
                        },
                        colonnes: politique.colonnesDeLaGeometrie)
    }

    /// Les rayons des plateaux d'une scene, ceux de sa disposition : la grille se choisit sur eux.
    func rayons(_ scene: ScenePieces) -> [Double] {
        scene.etages.map { rayonsCalcules[$0.id] ?? DispositionPieces.marge }
    }

    /// La zone visible ou se choisit la grille (polissage C, section 3.3, decision de Djoko du 03/10) : la vue moins la
    /// marge du haut et celle du bas, la legende ouverte ou repliee, sans la fiche (`basGrille`). La vue d'ensemble y
    /// est toujours la plus grande possible.
    var zoneVisible: CGSize {
        CGSize(width: taille.width, height: taille.height - marges.haut - (basGrille ?? marges.bas))
    }

    /// Pose la geometrie visee : tout de suite, ou en glissant (« Reduire les animations » : tout de suite) depuis la
    /// geometrie de l'image, remise dans l'ordre des plateaux de la scene (`anciens` : celui de l'image). Un
    /// glissement en cours repart de l'image, avec le temps qui lui restait s'il est plus long.
    func viser(_ g: GeometrieMaison, depuis anciens: [String], duree2D: Double, duree3D: Double) {
        let now = Self.maintenant()
        var d2 = reduire ? 0 : duree2D
        var d3 = reduire ? 0 : duree3D
        if let gl = glissementPlateaux, !reduire {
            d2 = max(d2, gl.duree2D - (now - gl.debut))
            d3 = max(d3, gl.duree3D - (now - gl.debut))
        }
        geometrieVisee = g
        let depart = self.depart(geometrie, anciens: anciens, vers: g)
        // Rien ne bouge : pas de glissement (une nouvelle disposition aux memes plateaux).
        guard pret, d2 > 0 || d3 > 0, scene != nil, depart != g || glissementPlateaux != nil else {
            geometrie = g
            glissementPlateaux = nil
            return
        }
        geometrie = depart
        glissementPlateaux = GlissementPlateaux(depart: depart, debut: now, duree2D: d2, duree3D: d3)
        reveiller()
    }

    /// Le depart d'un glissement vers `g`, la geometrie de la scene : la geometrie `image`, remise dans l'ordre des
    /// plateaux de la scene (`anciens` : celui de l'image), chaque plateau a sa place d'avant, retrouvee par sa cle ;
    /// la boite, le pas, la sphere et le cadrage de l'image. Un plateau nouveau part de sa place d'arrivee.
    func depart(_ image: GeometrieMaison, anciens: [String], vers g: GeometrieMaison) -> GeometrieMaison {
        var depart = g
        for (i, c) in (scene?.etages.map(\.id) ?? []).enumerated() {
            guard let j = anciens.firstIndex(of: c), j < image.centres2D.count else { continue }
            depart.centres2D[i] = image.centres2D[j]
            depart.centres3D[i] = image.centres3D[j]
        }
        depart.boite = image.boite
        depart.pasEtage = image.pasEtage
        depart.centreSphere = image.centreSphere
        depart.rayonSphere = image.rayonSphere
        depart.rayonCadre = image.rayonCadre
        return depart
    }

    /// La geometrie de l'image a l'instant `now` : en route vers la geometrie visee, ou elle.
    func geometrie(a now: Double) -> GeometrieMaison {
        guard let gl = glissementPlateaux else { return geometrieVisee }
        let q2 = gl.duree2D > 0 ? min(1, max(0, (now - gl.debut) / gl.duree2D)) : 1
        let q3 = gl.duree3D > 0 ? min(1, max(0, (now - gl.debut) / gl.duree3D)) : 1
        if q2 >= 1 && q3 >= 1 { return geometrieVisee }
        return gl.depart.vers(geometrieVisee, k2: CameraScene.rampe(q2), k3: CameraScene.rampe(q3))
    }

    /// Le reglage « Etages en 2D » (polissage C, section 3.1) : en grille ou en rangee. Il s'applique tout de suite a
    /// la vue ouverte, les plateaux glissant comme l'envol, en 2,6 s ; zoomee, isolee ou en 3D, au retour a la vue
    /// d'ensemble 2D.
    func reglerGrille(_ g: Bool) {
        guard politique.regler(g), pret else { return }
        demanderGrille(PolitiqueGrille.reglage)
    }

    /// La zone visible a change (polissage C, sections 3.3 et 3.5) : la taille de la vue, ou ses marges sans la fiche
    /// (la legende ouverte ou repliee, un bandeau). La premiere vraie zone pose la grille et cadre la vue d'ensemble,
    /// sans autre condition ; ensuite, la grille se recalcule a la vue d'ensemble 2D, avec l'hysteresis, et les
    /// plateaux glissent en 0,4 s ; zoomee, isolee ou en 3D, elle attend.
    func zoneChangee() {
        guard pret, let scene else { return }
        if politique.sansVraieTaille {
            guard politique.premiereZone(rayons: rayons(scene), zone: zoneVisible) else { return }
            viser(geometriePour(scene), depuis: scene.etages.map(\.id), duree2D: 0, duree3D: 0)
            vueTouchee = false
            orbite = CameraScene.canonique(geometrie, aspect: aspect, u: t)
            return
        }
        demanderGrille(PolitiqueGrille.redimensionnement)
    }

    /// Une grille voulue : posee a la vue d'ensemble 2D, avec celle qui attendait encore, ses plateaux glissant en la
    /// duree de la demande posee ; sinon elle attend (`PolitiqueGrille`).
    private func demanderGrille(_ d: PolitiqueGrille.Demande) {
        guard let scene else { return }
        if let posee = politique.demander(d, ensemble2D: aLaVueDEnsemble2D, rayons: rayons(scene), zone: zoneVisible) {
            poserGeometrie(posee.duree)
        }
    }

    /// Pose la grille d'une demande, puis sa geometrie.
    func poserGrille(_ d: PolitiqueGrille.Demande) {
        guard let scene else { return }
        politique.poser(d, rayons: rayons(scene), zone: zoneVisible)
        poserGeometrie(d.duree)
    }

    /// La geometrie de la grille choisie : ses plateaux glissent en `duree`.
    private func poserGeometrie(_ duree: Double) {
        guard let scene else { return }
        let g = geometriePour(scene)
        guard g != geometrieVisee else { return }
        viser(g, depuis: scene.etages.map(\.id), duree2D: duree, duree3D: 0)
        if glissementPlateaux == nil && aLaVueDEnsemble { recadrer() }   // posee tout de suite : cadree tout de suite
    }

    /// Ce que la vue regarde : la piece isolee, l'etage isole (ou celui de la piece isolee), ou la cible de la vue
    /// d'ensemble ; dans la geometrie de l'image, ou dans `g`. Une piece ou un etage qu'on quitte, encore en train de
    /// se relacher, ne sont plus regardes : la vue regarde deja ce vers quoi elle remonte (relecture ciblee de la vague
    /// finale, Important 1).
    func ancreCamera(dans g: GeometrieMaison? = nil) -> SIMD3<Double> {
        let g = g ?? geometrie
        if let i = focus, sCible == 1, let c = centrePiece(i, dans: g) { return c }
        if let k = etageEnVue, seCible == 1, let e = scene?.etages.firstIndex(where: { $0.id == k }) {
            return g.centrePlateau(e, t)
        }
        return g.cible2D + (g.centreSphere - g.cible2D) * t
    }

    /// La cle de ce que la vue regarde, comme `ancreCamera` : `p:` et la cle de la piece isolee, ou `e:` et celle de
    /// l'etage en vue ; nil, la vue d'ensemble. `piece` : la cle de la piece de `focus`.
    func cleRegard(piece: String?) -> String? {
        if sCible == 1, let piece { return "p:" + piece }
        if seCible == 1, let k = etageEnVue { return "e:" + k }
        return nil
    }

    /// Centre du bloc d'une piece, dans le monde, dans la geometrie de l'image ou dans `g` : sa pose affichee quand
    /// elle est en route vers une nouvelle disposition (polissage D, section 1), sinon sa place sur son plateau. Nil
    /// pour un indice hors de la scene.
    func centrePiece(_ i: Int, dans g: GeometrieMaison? = nil) -> SIMD3<Double>? {
        guard let scene, i < scene.pieces.count, i < positions.count else { return nil }
        let g = g ?? geometrie
        // En route (polissage D, section 1) : sa pose affichee.
        if let pose = posesAffichees.pieces[scene.pieces[i].id],
           let m = PosesScene.centre(pose.ancres, geometrie: g, plateaux: plateaux(scene), t: t) {
            return SIMD3(m.x, m.y + 0.02 + GeometrieMaison.hauteurBloc(t) / 2, m.z)
        }
        let c = g.centrePlateau(scene.pieces[i].etage, t)
        return SIMD3(c.x + positions[i].x, c.y + 0.02 + GeometrieMaison.hauteurBloc(t) / 2, c.z + positions[i].y)
    }

    /// L'indice de chaque plateau de la scene, par cle.
    private func plateaux(_ scene: ScenePieces) -> [String: Int] {
        Dictionary(scene.etages.indices.map { (scene.etages[$0].id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// Les plateaux glissent : un vol rejoint l'arrivee de ce qu'il vise ; a la vue d'ensemble, elle se recadre ;
    /// sinon, la vue suit ce qu'elle regarde (`ancre0` : sa place a l'image d'avant).
    func suivre(depuis ancre0: SIMD3<Double>) {
        if vol != nil {
            if let v = viseeVol, let fin = volVers(v) {
                vol?.oeil1 = fin.oeil1
                vol?.cible1 = fin.cible1
            }
        } else if envol == nil && fondu == nil {
            if aLaVueDEnsemble {
                recadrer()
            } else {
                orbite.cible += ancreCamera() - ancre0
            }
        }
    }

    /// Le vol vers ce que l'on vise, depuis la camera du moment.
    private func volVers(_ v: Visee) -> Vol? {
        switch v {
        case .ensemble: CameraScene.volVersEnsemble(orbite, geometrie, aspect: aspect, u: t, troisD: t == 1)
        case .piece(let cle): scene?.pieces.firstIndex { $0.id == cle }.flatMap(volVersPiece)
        case .etage(let cle): scene?.etages.firstIndex { $0.id == cle }.map(volVersEtage)
        }
    }

    // MARK: Camera

    /// Cadre la vue d'ensemble a l'avancement courant, en gardant l'orbite en 3D.
    func recadrer() {
        var c = CameraScene.canonique(geometrie, aspect: aspect, u: t)
        if t == 1 {
            c.azimut = orbite.azimut
            c.inclinaison = orbite.inclinaison
        }
        orbite = c
    }

    /// Bascule 2D / 3D : un envol de 2,6 s depuis la vue courante (un fondu de 0,3 s si « Reduire
    /// les animations ») ; une piece isolee est relachee. Pas de menu du clic droit pendant l'envol, meme sous un
    /// pointeur immobile : sa cible tombe, et le survol ne la reprend qu'apres lui.
    func basculer(troisD v: Bool) {
        guard v != troisD else { return }
        troisD = v
        if cibleMenu != .aucune { cibleMenu = .aucune }
        focus = nil
        isolee = nil
        s = 0
        sCible = 0
        fk = [:]
        etageEnVue = nil
        se = 0
        seCible = 0
        ek = [:]
        isolement = .maison
        vol = nil
        zoomEnAttente = 0
        rotationEnAttente = .zero
        vueTouchee = false
        textes = entree.map { Self.textes($0, focus: nil) } ?? textes
        construireEtiquettes()
        majFil()
        // Vers la 2D, l'envol se pose sur la grille de la zone visible du moment (polissage C, section 3.5).
        if !v, let scene {
            politique.oublierAttente()
            politique.choisir(rayons: rayons(scene), zone: zoneVisible, enPlace: false)
            viser(geometriePour(scene), depuis: scene.etages.map(\.id), duree2D: 0, duree3D: 0)
        }
        let arrivee = v ? 1.0 : 0.0
        if reduire {
            fondu = Fondu(debut: Self.maintenant(), arrivee: arrivee)
        } else {
            envol = Envol(depuis: orbite, t: t, vers: arrivee, geometrie: geometrie, aspect: aspect)
            debutEnvol = Self.maintenant()
        }
        reveiller()
    }

    /// Isole une piece : la camera y vole en 1,3 s (tout de suite si « Reduire les animations »), les
    /// autres s'estompent, ses reperes « ailleurs » apparaissent. Son etage est celui du fil : les disques des
    /// autres etages restent a 15 %, cliquables (polissage C, section 5.2). La provenance (section 5.4) : depuis la
    /// maison ou un etage isole, ce que l'on quitte ; d'une piece a une autre, elle reste, sauf vers une piece d'un
    /// autre etage : la maison.
    func isoler(_ i: Int) {
        guard let scene, i < scene.pieces.count, !(focus == i && sCible == 1) else { return }
        let piece = scene.pieces[i], etage = scene.etages[piece.etage].id
        isolement = isolement.isoler(piece: piece.id, etage: etage)
        focus = i
        isolee = textes.pieces[i]?.nom
        if sCible != 1 {
            sDepart = s
            sCible = 1
            sDebut = Self.maintenant()
        }
        if scene.etages.count > 1 { viserEtage(etage) }
        if let e = entree { textes = Self.textes(e, focus: i) }
        construireEtiquettes()
        majFil()
        if let v = volVersPiece(i) { voler(v, visee: .piece(piece.id)) }
    }

    /// Isole un etage (polissage C, section 5.1) : un vol de 1,3 s cadre son plateau, bande de son nom comprise ; les
    /// autres plateaux s'estompent a 15 %, la sphere et « ⌂ Maison » s'effacent ; la rotation lente continue
    /// (polissage D, section 4.2). Une piece isolee est relachee. Rien dans une maison d'un seul plateau, ni pendant
    /// l'envol.
    func allerEtage(_ e: Int) {
        guard let scene, scene.etages.count > 1, e < scene.etages.count, envol == nil, fondu == nil else { return }
        quitterPiece()
        let cle = scene.etages[e].id
        isolement = .etage(cle)
        viserEtage(cle)
        majFil()
        voler(volVersEtage(e), visee: .etage(cle))
    }

    /// Vol vers un etage isole.
    func volVersEtage(_ e: Int) -> Vol {
        CameraScene.volVersEtage(orbite, geometrie, etage: e, aspect: aspect, u: t, troisD: t == 1)
    }

    /// L'etage vise par l'isolement, dans la scene ; nil : la maison ou une piece.
    var indiceEtageIsole: Int? {
        guard case .etage(let cle) = isolement else { return nil }
        return scene?.etages.firstIndex { $0.id == cle }
    }

    /// L'isolement d'etage vise `cle` : son plateau reste net.
    func viserEtage(_ cle: String) {
        etageEnVue = cle
        if seCible != 1 {
            seDepart = se
            seCible = 1
            seDebut = Self.maintenant()
        }
    }

    /// La piece isolee est relachee : son isolement redescend en 1,3 s.
    private func quitterPiece() {
        guard focus != nil, sCible != 0 else { return }
        sDepart = s
        sCible = 0
        sDebut = Self.maintenant()
        isolee = nil
        // Retour lance avant la premiere image de l'isolement : `s` est deja a 0, et l'horloge ne
        // finirait jamais ce retour.
        if s == 0 { finirRetour() }
    }

    /// L'etage isole est relache.
    private func quitterEtage() {
        guard seCible != 0 else { return }
        seDepart = se
        seCible = 0
        seDebut = Self.maintenant()
        if se == 0 { etageEnVue = nil }
    }

    /// Le fil de ce que montre la vue.
    func majFil() {
        var f = Fil()
        if let scene {
            func cran(_ e: Int) -> Fil.Cran { Fil.Cran(nom: textes.etages[e] ?? "", etage: e) }
            switch isolement {
            case .maison:
                break
            case .etage(let cle):
                f.etage = scene.etages.firstIndex { $0.id == cle }.map(cran)
            case .piece(let cle, _):
                if let i = scene.pieces.firstIndex(where: { $0.id == cle }) {
                    f.piece = textes.pieces[i]?.nom
                    if scene.etages.count > 1 { f.etage = cran(scene.pieces[i].etage) }
                }
            }
        }
        if f != fil { fil = f }
    }

    /// Vol vers une piece, a la hauteur de vue de la spec (section 7).
    func volVersPiece(_ i: Int) -> Vol? {
        guard let c = centrePiece(i) else { return nil }
        return CameraScene.volVersPiece(orbite, centre: c, largeur: cartes[i].largeur, profondeur: cartes[i].profondeur,
                                        aspect: aspect, troisD: t == 1)
    }

    /// Retour a la maison (« Maison » dans le fil, double-clic, ou en remontant) : la piece et l'etage isoles sont
    /// relaches, le zoom et le deplacement annules, par un vol de 1,3 s qui part de la pose courante. « Reduire les
    /// animations » : tout de suite, ou par un fondu de 0,3 s (`enFondu`, le double-clic).
    func versMaison(enFondu: Bool = false) {
        guard ecarteDeLaVueDEnsemble else { return }
        quitterPiece()
        quitterEtage()
        isolement = .maison
        majFil()
        vueTouchee = false
        voler(CameraScene.volVersEnsemble(orbite, geometrie, aspect: aspect, u: t, troisD: t == 1), visee: .ensemble,
              enFondu: enFondu)
    }

    /// Echap et le clic a cote remontent d'ou l'on vient (polissage C, section 5.4) : une piece ouverte depuis un etage
    /// isole, a l'etage de la piece ; une autre piece, ou un etage, a la maison. A la maison, Echap ramene une vue
    /// zoomee ou deplacee a la vue d'ensemble (`clavier`) ; le clic a cote ne fait rien. Rien pendant l'envol.
    func remonter(clavier: Bool = true) {
        guard envol == nil, fondu == nil else { return }
        var etageDeLaPiece: String?
        if case .piece(let cle, _) = isolement, let scene, let i = scene.pieces.firstIndex(where: { $0.id == cle }) {
            etageDeLaPiece = scene.etages[scene.pieces[i].etage].id
        }
        switch isolement.remonter(etageDeLaPiece: etageDeLaPiece, plusieursPlateaux: (scene?.etages.count ?? 0) > 1,
                                  clavier: clavier) {
        case .etage(let cle):
            if let e = scene?.etages.firstIndex(where: { $0.id == cle }) { allerEtage(e) }
        case .maison:
            versMaison()
        case .rien:
            break
        }
    }

    /// Echap (polissage D, section 3), dans cet ordre : une fiche ouverte se ferme ; sinon la vue remonte d'un cran ;
    /// sinon, a la vue d'ensemble sans zoom ni fiche, Echap n'est pas pris (faux) : l'evenement suit son chemin. Le
    /// moniteur des evenements (`prendre`, dans `MoteurPieces+Gestes`) l'appelle.
    @discardableResult
    func sortir() -> Bool {
        if selection != nil {
            selection = nil
            return true
        }
        guard envol == nil, fondu == nil, ecarteDeLaVueDEnsemble else { return false }
        remonter(clavier: true)
        return true
    }

    /// Fin du retour d'un isolement : plus de piece isolee, ni de reperes « ailleurs ».
    func finirRetour() {
        focus = nil
        if let e = entree { textes = Self.textes(e, focus: nil) }
        construireEtiquettes()
    }

    /// Double-clic sur le fond ou sur un disque (precision 17 du plan 4b ; polissage C, section 5.4) : retour a la vue
    /// d'ensemble d'un geste, de partout. Le premier clic a deja agi seul ; le second relache ce qui reste isole et
    /// annule le zoom et le deplacement.
    func doubleCliquer() {
        versMaison(enFondu: true)
    }

    private func voler(_ v: Vol, visee: Visee, enFondu: Bool = false) {
        zoomEnAttente = 0
        rotationEnAttente = .zero
        viseeVol = nil
        if reduire && enFondu {
            fondu = Fondu(debut: Self.maintenant(), arrivee: t, orbite: v.orbite(1, depuis: orbite))
            vol = nil
        } else if reduire {
            orbite = v.orbite(1, depuis: orbite)
            vol = nil
        } else {
            vol = v
            viseeVol = visee
            debutVol = Self.maintenant()
        }
        reveiller()
    }

    func basculerRotation() {
        rotation.toggle()
        reveiller()
    }
}
