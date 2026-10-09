import Foundation
import MaillageCoeur
import SwiftUI

/// La scene et sa disposition, le glissement d'une disposition a l'autre, les noms, les places gardees et le menu du
/// clic droit (polissage D, section 5 : le moteur en fichiers).
extension MoteurPieces {
    // MARK: Scene et disposition

    /// Nouvelle scene : appliquee tout de suite, ou a la fin du mouvement en cours (envol, vol, fondu)
    /// ou du glisser. Si ses etages, ses pieces, ses noeuds ou leurs noms changent, la disposition est
    /// recalculee hors du fil principal ; l'ancienne reste affichee pendant ce temps.
    func recevoir(_ e: EntreeScene) {
        if occupe {
            attente = e
            return
        }
        appliquer(e)
    }

    func appliquer(_ e: EntreeScene) {
        attente = nil
        let cle = e.cleDisposition
        if cle == cleCalculee {
            calcul?.cancel()
            enCalcul = nil
            installer(e)
            return
        }
        // Meme structure que la disposition en calcul : elle vaudra pour cette scene.
        if enCalcul?.cleDisposition == cle {
            enCalcul = e
            return
        }
        calculer(e)
    }

    /// Lance le calcul de la disposition d'une scene, hors du fil principal, avec les places gardees
    /// du moment ; un calcul en cours est abandonne.
    private func calculer(_ e: EntreeScene) {
        calcul?.cancel()
        enCalcul = e
        let cle = e.cleDisposition
        let cartes = cartesPour(e)
        let fixees = places.fixees(e.scene, domicile: e.domicile)
        let scene = e.scene
        calcul = Task { [weak self] in
            let d = await Task.detached(priority: .userInitiated) {
                DispositionPieces(scene: scene, cartes: cartes, fixees: fixees)
            }.value
            guard !Task.isCancelled, let self else { return }
            self.retenir(d, scene: scene, cartes: cartes, cle: cle)
        }
    }

    /// La meme chose, sur le fil principal (captures, tests).
    func installerMaintenant(_ e: EntreeScene) {
        calcul?.cancel()
        let cartes = cartesPour(e)
        let d = DispositionPieces(scene: e.scene, cartes: cartes,
                                  fixees: places.fixees(e.scene, domicile: e.domicile))
        enCalcul = e
        retenir(d, scene: e.scene, cartes: cartes, cle: e.cleDisposition)
    }

    /// Cartes des pieces d'une scene, d'apres les noms mesures des noeuds, avec la place de tous leurs badges possibles
    /// (polissage D, section 2) : un badge qui change ne change pas la carte.
    private func cartesPour(_ e: EntreeScene) -> [CartesPieces.Carte] {
        var largeurs: [String: Double] = [:]
        for n in e.scene.noeuds {
            largeurs[n.id] = mesure.reserve(n.libelle, routeur: n.route, pile: n.pile).width
        }
        return CartesPieces.cartes(e.scene, largeurs: largeurs)
    }

    /// Une disposition calculee pour `scene` : gardee par cles (piece, etage), d'apres cette scene, dont
    /// elle suit les indices (une scene plus recente de meme structure peut ranger ses etages, donc ses
    /// pieces, dans un autre ordre) ; puis posee avec la derniere scene de cette structure, si une scene
    /// d'une autre structure ne l'a pas depassee ; a la fin du mouvement ou du glisser en cours, s'il y
    /// en a un.
    private func retenir(_ d: DispositionPieces, scene: ScenePieces, cartes: [CartesPieces.Carte],
                         cle: EntreeScene.CleDisposition) {
        guard let e = enCalcul, e.cleDisposition == cle else { return }
        placesCalculees = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map {
            (scene.pieces[$0].id, d.positions[$0])
        })
        rayonsCalcules = Dictionary(scene.etages.indices.map { (scene.etages[$0].id, d.rayons[$0]) },
                                    uniquingKeysWith: { a, _ in a })
        cartesCalculees = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map {
            (scene.pieces[$0].id, cartes[$0])
        })
        cleCalculee = cle
        enCalcul = nil
        if occupe {
            if attente == nil { attente = e }
            return
        }
        installer(e)
    }

    /// Pose une scene sur la disposition gardee : positions et rayons retrouves par cles, noms, piece isolee. Une
    /// nouvelle disposition glisse depuis la pose affichee (polissage D, section 1) ; des niveaux changes, ou des
    /// rayons changes sans eux (section 4), redemandent la grille.
    private func installer(_ e: EntreeScene) {
        let scene = e.scene
        let ancienFocus = focus.flatMap { $0 < clesPieces.count ? clesPieces[$0] : nil }
        // Des niveaux changes (le menu du clic droit) : les plateaux glissent vers leur nouvelle place (polissage C,
        // section 1.3) ; a la vue d'ensemble 2D, la grille se recalcule, sinon elle l'attend.
        let anciens = entree?.scene.etages.map(\.id) ?? []
        let niveauxChanges = pret && entree?.scene.niveaux != scene.niveaux
        let ensemble = aLaVueDEnsemble2D
        // Ce que la vue regarde, et ou, a l'image d'avant : sans glissement (« Reduire les animations »), elle le
        // suit d'un coup (plus bas). Une piece ou un etage qu'on quitte n'est plus regarde, meme s'il se relache
        // encore (relecture ciblee de la vague finale, Important 1).
        let regard = cleRegard(piece: ancienFocus)
        let ancre0 = pret ? ancreCamera() : nil
        // La pose affichee de la scene d'avant, et sa pose d'arrivee (polissage D, section 1).
        let avant = entree.map { PosesScene(scene: $0.scene, cartes: cartes, positions: positions) }
        let affichee = avant?.recouvertes(par: posesAffichees)
        let rayonsAvant = entree.map { Self.rayonsParCle($0.scene, geometrieVisee.rayons) }
        let ancienne = entree
        entree = e
        // Un autre ordre des plateaux : le disque et le nom d'etage survoles, des indices, en designeraient
        // d'autres ; le prochain mouvement du pointeur les reprend.
        if scene.etages.map(\.id) != anciens {
            survolEtage = nil
            survolNomEtage = nil
        }
        cartes = scene.pieces.map { cartesCalculees[$0.id] ?? CartesPieces.carte([]) }
        positions = scene.pieces.map { placesCalculees[$0.id] ?? .zero }
        // Une nouvelle disposition glisse (polissage D, section 1) : de la pose affichee a la nouvelle, en 0,9 s ; une
        // disposition qui ne change aucune pose laisse le glissement en cours aller a son terme, sans le relancer :
        // un releve qui ne change que la qualite d'un lien, par exemple. Ce qui change se juge comme dans
        // `TransitionScene` (les pieces, les noeuds, les liens presents). Avec « Reduire les animations », tout de
        // suite.
        let arrivee = PosesScene(scene: scene, cartes: cartes, positions: positions)
        if pret, let affichee, let avant,
           transition == nil || TransitionScene(de: avant, vers: arrivee, a: 0) != nil {
            transition = TransitionScene(de: affichee, vers: arrivee, a: Self.maintenant(), reduire: reduire)
            if let tr = transition {
                posesAffichees = tr.poses(a: tr.debut)
                apparencesParties = (ancienne?.apparences ?? [:]).merging(apparencesParties) { a, _ in a }
            } else {
                posesAffichees = PosesScene()
                apparencesParties = [:]
            }
        }
        // Les rayons changent sans les niveaux : la grille se redemande comme au redimensionnement, par la regle de la
        // politique : a la vue d'ensemble 2D, elle se rechoisit, avec l'hysteresis ; sinon elle attend (polissage D,
        // section 4).
        let rayonsChanges = pret && !niveauxChanges && Self.rayonsParCle(scene, rayons(scene)) != rayonsAvant
        if grille && (!pret || (niveauxChanges && ensemble)) {
            politique.choisir(rayons: rayons(scene), zone: zoneVisible, enPlace: false)
        } else if niveauxChanges {
            politique.attendre(PolitiqueGrille.niveaux)
        } else if rayonsChanges && grille {
            politique.demander(PolitiqueGrille.redimensionnement, ensemble2D: ensemble, rayons: rayons(scene),
                                   zone: zoneVisible)
        }
        let glisse = pret ? TransitionScene.duree : 0
        viser(geometriePour(scene), depuis: anciens, duree2D: niveauxChanges ? CameraScene.dureeCases : glisse,
              duree3D: niveauxChanges ? CameraScene.dureeNiveaux : glisse)
        // Les parts de l'isolement sont gardees par cle (triage A, n° 9) : un releve recu pendant un fondu ne remet pas
        // la piece a pleine taille. L'etage en vue suit ce que vise la vue (polissage C, section 5) : celui de la piece
        // isolee, qui a pu changer de zone. Une piece isolee qui disparait rend la maison, comme avant les etages :
        // l'etage est relache, comme a la bascule, et la vue d'ensemble se recadre (plus bas). Un etage isole qui
        // disparait rend aussi la maison.
        let clesPieces = Set(scene.pieces.map(\.id)), clesEtages = Set(scene.etages.map(\.id))
        fk = fk.filter { clesPieces.contains($0.key) }
        ek = ek.filter { clesEtages.contains($0.key) }
        isolement = isolement.recaler(pieces: clesPieces, etages: clesEtages)
        if let cle = ancienFocus, let i = scene.pieces.firstIndex(where: { $0.id == cle }) {
            focus = i
            if case .piece = isolement, scene.etages.count > 1 { viserEtage(scene.etages[scene.pieces[i].etage].id) }
        } else if focus != nil {
            focus = nil
            s = 0
            sCible = 0
            isolee = nil
            if isolement == .maison {
                etageEnVue = nil
                se = 0
                seCible = 0
                ek = [:]
            }
        }
        if let k = etageEnVue, !clesEtages.contains(k) {
            etageEnVue = nil
            se = 0
            seCible = 0
        }
        textes = Self.textes(e, focus: focus)
        routeurs = Set(scene.noeuds.filter(\.route).map(\.id))
        teintes = Dictionary(uniqueKeysWithValues: scene.pieces.indices.map { ($0, scene.pieces[$0].teinte) })
        construireEtiquettes()
        majFil()
        majMiseEnAvant()
        if !pret {
            pret = true
            orbite = CameraScene.canonique(geometrie, aspect: aspect, u: t)
        } else if !vueTouchee && sansIsolement {
            recadrer()
        } else if let ancre0, transition == nil, glissementPlateaux == nil, !aLaVueDEnsemble,
                  regard == cleRegard(piece: focus.map { scene.pieces[$0].id }) {
            // Rien ne glisse (« Reduire les animations ») : les pieces et les plateaux sont poses tout de suite
            // (polissage D, section 1 ; polissage C, section 1.3). La vue isolee ou zoomee suit ce qu'elle regarde,
            // d'un coup, depuis sa place a l'image d'avant, comme le glissement le lui fait suivre image apres image
            // (`suivre`), sans « Reduire » (relecture finale, Mineur 1). Si elle regarde autre chose (la piece isolee
            // disparue), elle ne bouge pas.
            suivre(depuis: ancre0)
        }
        reveiller()
    }

    /// Les rayons des plateaux de `scene`, par cle : une cle en double garde son premier rayon.
    private static func rayonsParCle(_ scene: ScenePieces, _ rayons: [Double]) -> [String: Double] {
        Dictionary(zip(scene.etages.map(\.id), rayons).map { ($0, $1) }, uniquingKeysWith: { a, _ in a })
    }

    /// Textes des noms : libelles, pieces (nom, compte), etages, maison, reperes « ailleurs ».
    static func textes(_ e: EntreeScene, focus: Int?) -> TextesScene {
        var t = TextesScene()
        t.noeuds = e.libelles
        for (i, p) in e.scene.pieces.enumerated() {
            t.pieces[i] = TextesScene.Piece(nom: LibellesNoeuds.nom(p.nom, libelles: e.libelles),
                                            compte: LibellesNoeuds.compte(p.noeuds.count))
        }
        for (i, et) in e.scene.etages.enumerated() { t.etages[i] = LibellesNoeuds.nom(et.nom) }
        t.maison = String(localized: "⌂ Maison")
        if let f = focus {
            for a in SceneProjetee.reperes(e.scene, focus: f) {
                t.ailleurs[a.enfant] = LibellesNoeuds.ailleurs(a, scene: e.scene, libelles: e.libelles)
            }
        }
        return t
    }

    /// Cle d'un nom, qui ne depend pas des indices de la scene.
    private func cle(_ g: Etiquette.Genre) -> String {
        switch g {
        case .noeud(let id): "n:" + id
        case .piece(let i): "p:" + (i < clesPieces.count ? clesPieces[i] : "")
        case .etage(let i): "e:" + (i < clesEtages.count ? clesEtages[i] : "")
        case .maison: "m"
        case .ailleurs(let id): "a:" + id
        }
    }

    /// Noms de la scene, dans l'ordre de la maquette (appareils, etages, pieces, maison, reperes) ;
    /// chacun garde son etat de placement d'une scene a l'autre.
    func construireEtiquettes() {
        guard let scene else { return }
        var anciennes: [String: Etiquette] = [:]
        for l in etiquettes { anciennes[cle(l.genre)] = l }
        clesPieces = scene.pieces.map(\.id)
        clesEtages = scene.etages.map(\.id)
        var l: [Etiquette] = []
        func ajouter(_ genre: Etiquette.Genre, _ taille: CGSize) {
            var e = Etiquette(genre, taille: taille)
            if let a = anciennes[cle(genre)] {
                e.place = a.place
                e.envie = a.envie
                e.vu = a.vu
                e.rect = a.rect
                e.rectAvant = a.rectAvant
            }
            l.append(e)
        }
        for n in scene.noeuds {
            let libelle = textes.noeuds[n.id] ?? LibellesNoeuds.Libelle(texte: n.id)
            ajouter(.noeud(n.id), mesure.noeud(libelle, routeur: n.route))
        }
        for i in scene.etages.indices { ajouter(.etage(i), mesure.etage(textes.etages[i] ?? "")) }
        for i in scene.pieces.indices {
            let t = textes.pieces[i] ?? TextesScene.Piece(nom: "", compte: "")
            ajouter(.piece(i), mesure.piece(nom: t.nom, compte: t.compte))
        }
        ajouter(.maison, mesure.maison(textes.maison))
        for (id, texte) in textes.ailleurs.sorted(by: { $0.key < $1.key }) {
            ajouter(.ailleurs(id), mesure.ailleurs(texte))
        }
        etiquettes = l
    }

    // MARK: Places gardees et ordre des etages

    private func enregistrer() {
        guard let fichierPlaces else { return }
        do {
            try places.ecrire(dans: fichierPlaces)
        } catch {
            Self.journal.error("places des pieces non ecrites : \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Garde la place d'une piece qu'on vient de glisser : elle est desormais fixee. Un calcul en cours
    /// ne la connait pas : il est relance avec elle (sinon, a sa fin, la piece sauterait a la place
    /// qu'il lui donne). Une place non finie (camera degeneree) n'est pas gardee.
    func garder(_ id: String) {
        guard let e = entree, let i = e.scene.pieces.firstIndex(where: { $0.id == id }), i < positions.count,
              positions[i].x.isFinite, positions[i].y.isFinite else { return }
        let p = e.scene.pieces[i]
        places.garder(positions[i], piece: p.id, etage: e.scene.etages[p.etage].id, domicile: e.domicile)
        placesCalculees[p.id] = positions[i]
        enregistrer()
        if let c = enCalcul { calculer(c) }
    }

    // MARK: Menu du clic droit (polissage C, section 1.3)

    /// La scene la plus recente : celle qui attend la fin d'un mouvement ou d'un geste, sinon celle du calcul en cours,
    /// sinon celle affichee. Apres un choix du menu, elle le porte avant la scene affichee.
    private var sceneRecente: EntreeScene? { attente ?? enCalcul ?? entree }

    /// Le menu du nom ou du disque du plateau `cle`, sur la scene la plus recente : ses coches et ses grises suivent le
    /// dernier choix, meme quand la scene de ce choix attend encore. Il lit la version de cette scene, observee : une
    /// vue qui le montre se refait quand elle change, meme si la cible du clic droit, elle, ne change pas.
    func menuEtage(_ cle: String) -> MenuEtage? {
        _ = versionScene
        guard let scene = sceneRecente?.scene, let niveau = scene.niveaux.niveau(cle) else { return nil }
        let n = scene.niveaux, estPrincipal = n.estPrincipal(cle)
        func nom(_ c: String) -> String {
            scene.etages.firstIndex { $0.id == c }.map { LibellesNoeuds.nom(scene.etages[$0].nom) } ?? c
        }
        let niveaux = n.liste.indices.filter { !(estPrincipal && $0 == niveau) }.map { i in
            MenuEtage.Niveau(principal: n.liste[i][0], nom: nom(n.liste[i][0]), coche: !estPrincipal && i == niveau)
        }
        return MenuEtage(nom: nom(cle), monter: estPrincipal && niveau < n.liste.count - 1,
                         descendre: estPrincipal && niveau > 0, niveaux: niveaux, aCote: !estPrincipal,
                         dehors: n.dehors(cle))
    }

    /// Un choix du menu, calcule sur la scene la plus recente et sur les choix gardes : le nouvel ordre des plateaux et
    /// les nouveaux choix de niveau, gardes ; la scene suivante les prend (`EntreeScene`), et les plateaux glissent
    /// vers leur nouvelle place. Sur la scene affichee, un choix fait pendant que la scene du precedent attend (un vol,
    /// le calcul de sa disposition) defaisait le precedent.
    private func ranger(_ operation: (Niveaux, [String: PlacesGardees.ACote]) -> Rangement?) {
        guard let e = sceneRecente, let r = operation(e.scene.niveaux, places.maison(e.domicile).aCote) else { return }
        places.ranger(r, domicile: e.domicile)
        enregistrer()
    }

    /// La cle du plateau `e` de la scene affichee, celle des noms et de la projection.
    func cleEtage(_ e: Int) -> String? {
        guard let scene, scene.etages.indices.contains(e) else { return nil }
        return scene.etages[e].id
    }

    /// « Monter d'un etage » (+1) ou « Descendre d'un etage » (-1) : le niveau entier de l'etage `cle`, zones a cote
    /// comprises, change de place avec son voisin.
    func deplacerEtage(_ cle: String, de pas: Int) {
        ranger { $0.deplacer(cle, de: pas, choix: $1) }
    }

    /// La meme chose pour le plateau `e` de la scene affichee.
    func deplacerEtage(_ e: Int, de pas: Int) {
        if let cle = cleEtage(e) { deplacerEtage(cle, de: pas) }
    }

    func peutDeplacerEtage(_ e: Int, de pas: Int) -> Bool {
        cleEtage(e).flatMap(menuEtage).map { pas > 0 ? $0.monter : $0.descendre } ?? false
    }

    /// « Au meme niveau que » le niveau de l'etage principal `principal` (sa cle), dans la maison.
    func mettreAuNiveau(_ cle: String, de principal: String) {
        ranger { n, choix in n.niveau(principal).flatMap { n.rejoindre(cle, niveau: $0, choix: choix) } }
    }

    /// « Hors de la maison », coche ou non.
    func basculerDehors(_ cle: String) {
        ranger { $0.basculerDehors(cle, choix: $1) }
    }

    /// « Sur son propre niveau ».
    func mettreSurSonNiveau(_ cle: String) {
        ranger { $0.propreNiveau(cle, choix: $1) }
    }

    /// « Replacer les pieces automatiquement » : oublie les places gardees de la maison (pas l'ordre
    /// des etages) et recalcule la disposition de la scene la plus recente (celle qui attend la fin d'un
    /// mouvement ou d'un geste, sinon celle du calcul en cours, sinon celle affichee) ; l'ancienne reste
    /// affichee pendant ce temps.
    func replacerPieces() {
        guard let e = sceneRecente else { return }
        places.replacer(domicile: e.domicile)
        enregistrer()
        cleCalculee = nil
        enCalcul = nil
        appliquer(e)
    }
}
