import Foundation
import MaillageCoeur
import SwiftUI
import simd

/// Chaque image du `Canvas`, les marges du cadre, l'avance de l'etat (envol, fondu, isolement, glissements, vols,
/// rotation lente, amortis) et l'horloge (polissage D, section 5 : le moteur en fichiers).
extension MoteurPieces {
    // MARK: Image

    /// Une image du `Canvas` : avance l'etat, projette la scene, place les noms, dessine.
    func image(_ ctx: inout GraphicsContext, taille nouvelle: CGSize, echelle: Double, palette: Palette) {
        // Taille ou marges changees : la vue d'ensemble se recadre, sauf si Djoko a zoome ou isole une piece ; une
        // nouvelle zone visible recalcule la grille (polissage C, sections 3.3 et 3.5).
        taille = nouvelle
        let changee = zoneVisible != zoneGrille
        zoneGrille = zoneVisible
        let now = Self.maintenant()
        let m = margesDuCadre(now)
        let voulu = CGRect(x: 0, y: m.haut, width: nouvelle.width, height: max(1, nouvelle.height - m.haut - m.bas))
        if voulu != cadre {
            cadre = voulu
            if aLaVueDEnsemble && !fige { recadrer() }
        }
        if changee && !fige { zoneChangee() }
        if !fige { avancer(now) }
        guard pret, let scene else { return }
        let parts = scene.pieces.map { fk[$0.id] ?? 0 }
        let etat = EtatAnime(t: t, s: s, fk: parts, focus: focus, survol: survol, selection: selection, se: se,
                             ek: scene.etages.map { ek[$0.id] ?? 0 }, survolEtage: survolEtage, liens: liens,
                             voisins: voisins, noeudsEstompes: noeudsEstompes, liensEstompes: liensEstompes)
        let p = SceneProjetee(scene: scene, cartes: cartes, positions: positions, geometrie: geometrie, etat: etat,
                              orbite: orbite, cadre: cadre, poses: posesAffichees)
        PlacementNoms.regler(&etiquettes, scene: scene, niveau: p.niveau, survol: survol, selection: selection,
                             focus: focus, isolee: estIsolee, fk: parts, s: s, t: t, se: se, voiles: p.voilesEtages,
                             etageIsole: indiceEtageIsole, survolNomEtage: survolNomEtage)
        let ancres: [CGRect?] = etiquettes.map { l in
            switch l.genre {
            case .noeud(let id): p.ancresNoeuds[id]
            case .piece(let i): p.ancresPieces[i]
            case .etage(let i): p.ancresEtages[i]
            case .maison: p.ancreMaison
            case .ailleurs(let id): p.ancresAilleurs[id]
            }
        }
        var obstacles = p.disques.filter { $0.opacite > 0.5 }.map { d in
            CGRect(x: Double(d.centre.x) - d.rayon, y: Double(d.centre.y) - d.rayon, width: 2 * d.rayon,
                   height: 2 * d.rayon)
        }
        obstacles += cadresInterface.values.map { $0.insetBy(dx: -4, dy: -4) }
        traits = PlacementNoms.placer(&etiquettes, ancres: ancres, obstacles: obstacles, cadre: taille, dt: dt)
        projetee = p
        var g = ctx
        g.opacity = opaciteFondu * opaciteMarges
        RenduCanvas.dessiner(&g, ImagePieces(projetee: p, etiquettes: etiquettes, traits: traits, textes: textes,
                                             apparences: apparences, routeurs: routeurs,
                                             teintesPieces: teintes, selection: selection, echelle: echelle),
                             palette: palette, cache: cache)
        let nouvelle = ligne(p.niveau, ancres: ancres)
        if nouvelle != ligneNiveau {
            // Hors du rendu, sauf pour une capture (rendue d'un trait).
            if fige {
                ligneNiveau = nouvelle
            } else {
                Task { @MainActor [weak self] in self?.ligneNiveau = nouvelle }
            }
        }
        if !fige && !doitContinuer(now) { endormir() }
    }

    /// Le dessin des pastilles : celles de la scene, et celles qui s'effacent, de la scene d'avant.
    private var apparences: [String: DessinNoeud.Apparence] {
        let a = entree?.apparences ?? [:]
        return apparencesParties.isEmpty ? a : a.merging(apparencesParties) { x, _ in x }
    }

    /// Marges du cadre a l'instant `now` : les marges visees, ou en route vers elles quand elles changent, pendant
    /// 0,3 s, ou 0,45 s quand la legende s'ouvre ou se replie (`legendeBasculee`) ; avec « Reduire les animations »,
    /// par un fondu de cette duree (la scene s'efface, les marges sautent a mi-chemin, la scene revient :
    /// `opaciteMarges`) ; tout de suite avant la premiere disposition et pour une capture.
    func margesDuCadre(_ now: Double) -> (haut: CGFloat, bas: CGFloat) {
        let actuelles = margesCadre ?? marges
        let visees = glissement?.arrivee ?? actuelles
        if marges.haut != visees.haut || marges.bas != visees.bas {
            if pret, !fige, margesCadre != nil {
                glissement = GlissementMarges(depart: actuelles, arrivee: marges, debut: now,
                                              duree: dureeAnnoncee ?? Apparition.duree, fondu: reduire)
                // Le glissement demande des images : l'horloge repart, hors du rendu.
                if !anime { Task { @MainActor [weak self] in self?.reveiller() } }
            } else {
                glissement = nil
            }
            dureeAnnoncee = nil
        }
        guard let g = glissement else {
            margesCadre = marges
            opaciteMarges = 1
            return marges
        }
        let q = min(1, max(0, (now - g.debut) / g.duree))
        let m: (haut: CGFloat, bas: CGFloat)
        if g.fondu {
            m = q < 0.5 ? g.depart : g.arrivee
            opaciteMarges = abs(1 - 2 * q)
        } else {
            let e = CGFloat(Apparition.courbe(q))
            m = (haut: g.depart.haut + (g.arrivee.haut - g.depart.haut) * e,
                 bas: g.depart.bas + (g.arrivee.bas - g.depart.bas) * e)
        }
        if q >= 1 {
            glissement = nil
            opaciteMarges = 1
        }
        margesCadre = m
        return m
    }

    /// Les marges du cadre sont en route.
    var margesEnRoute: Bool { glissement != nil }

    /// Les marges du cadre sont en route par un fondu (« Reduire les animations »).
    var margesEnFondu: Bool { glissement?.fondu == true }

    /// La legende s'ouvre ou se replie, d'un clic : le recadrage qui l'accompagne (le prochain changement des
    /// marges) prend sa duree, 0,45 s (`Apparition.dureeLegende`), au lieu des 0,3 s de la fiche et des bandeaux.
    func legendeBasculee() {
        dureeAnnoncee = Apparition.dureeLegende
    }

    private func ligne(_ niveau: NiveauZoom, ancres: [CGRect?]) -> LigneNiveau {
        if estIsolee, let nom = isolee { return .isolee(nom) }
        if let e = indiceEtageIsole, let nom = textes.etages[e] { return .etageIsole(nom) }
        switch niveau {
        case .pieces: return .pieces
        case .routeurs: return .routeurs
        case .tous:
            let n = PlacementNoms.masques(etiquettes, ancres: ancres, cadre: taille)
            return n > 0 ? .masques(n) : .lisibles
        }
    }

    private func avancer(_ now: Double) {
        dt = instant.map { min(0.1, max(0, now - $0)) } ?? 0
        instant = now
        let basculait = envol != nil || fondu != nil
        defer { if basculait && envol == nil && fondu == nil { basculeFinie() } }
        if let e = envol {
            let q = min(1, max(0, (now - debutEnvol) / CameraScene.dureeEnvol))
            (t, orbite) = e.pose(q, geometrie: geometrie, aspect: aspect)
            if q >= 1 {
                envol = nil
                t = e.arrivee
            }
        }
        if let f = fondu {
            let q = min(1, max(0, (now - f.debut) / CameraScene.dureeFondu))
            if q >= 0.5 && !f.saute {
                t = f.arrivee
                orbite = f.orbite ?? CameraScene.canonique(geometrie, aspect: aspect, u: t)
                fondu?.saute = true
            }
            opaciteFondu = abs(1 - 2 * q)
            if q >= 1 {
                fondu = nil
                opaciteFondu = 1
            }
        }
        if s != sCible {
            let r = min(1, max(0, (now - sDebut) / CameraScene.dureeVol))
            s = sDepart + (sCible - sDepart) * r
            if r >= 1 {
                s = sCible
                if s == 0 { finirRetour() }
            }
        }
        if se != seCible {
            let r = min(1, max(0, (now - seDebut) / CameraScene.dureeVol))
            se = seDepart + (seCible - seDepart) * r
            if r >= 1 {
                se = seCible
                if se == 0 { etageEnVue = nil }
            }
        }
        // Les parts propres, par cle : celle de la piece isolee et celle de l'etage en vue tendent vers 1.
        if let scene {
            let piece = focus.flatMap { $0 < scene.pieces.count && sCible == 1 ? scene.pieces[$0].id : nil }
            func tendre(_ x: Double?, vers c: Double) -> Double {
                var f = x ?? 0
                f += (c - f) * min(1, dt * 3.5)
                return abs(c - f) < 1e-3 ? c : f
            }
            for p in scene.pieces { fk[p.id] = tendre(fk[p.id], vers: p.id == piece ? 1 : 0) }
            for e in scene.etages { ek[e.id] = tendre(ek[e.id], vers: e.id == etageEnVue ? 1 : 0) }
        }
        // Le mode focus : ce qui n'est pas mis en avant s'estompe, ou revient, en douceur.
        if focusEnRoute {
            let k = dt * Self.vitesseFocus
            noeudsEstompes = MiseEnAvant.tendre(noeudsEstompes, vers: ciblesFocus.noeuds, k: k)
            liensEstompes = MiseEnAvant.tendre(liensEstompes, vers: ciblesFocus.liens, k: k)
        }
        // Les plateaux et les pieces glissent ; la vue suit ce qu'elle regarde.
        if glissementPlateaux != nil || transition != nil {
            let ancre0 = ancreCamera()
            if glissementPlateaux != nil {
                geometrie = geometrie(a: now)
                if geometrie == geometrieVisee { glissementPlateaux = nil }
            }
            if let tr = transition {
                if tr.finie(a: now) {
                    finirTransition()
                } else {
                    posesAffichees = tr.poses(a: now)
                }
            }
            suivre(depuis: ancre0)
        }
        if let v = vol {
            let q = min(1, max(0, (now - debutVol) / CameraScene.dureeVol))
            orbite = v.orbite(q, depuis: orbite)
            if q >= 1 {
                vol = nil
                viseeVol = nil
            }
        } else if envol == nil && fondu == nil {
            controles()
        }
        // Une grille qui attendait la vue d'ensemble 2D s'y pose.
        if let g = politique.attente, aLaVueDEnsemble2D { poserGrille(g) }
        if !occupe, let e = attente { appliquer(e) }
    }

    /// La rotation lente tourne (`CameraScene.rotationLente`), une piece ou un etage isoles compris (polissage D,
    /// section 4.2), sauf pendant un geste : un glisser (⌥ compris), le zoom de la molette en route, un pincement.
    private var rotationLente: Bool {
        CameraScene.rotationLente(troisD: troisD, bascule: t, cochee: rotation, reduire: reduire,
                                  geste: geste != nil || zoomEnAttente != 0 || dernierPincement != 1)
    }

    /// L'envol ou son fondu fini : le survol, le menu du clic droit et le curseur reprennent sous le pointeur immobile
    /// (polissage D, section 4), hors du rendu.
    private func basculeFinie() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.survoler(self.curseur, option: self.optionTenue)
        }
    }

    /// Rotation lente, rotation amortie, zoom amorti ; rien pendant ⌥ + glisser : ce qui attend reprend au relachement.
    private func controles() {
        guard !deplaceDansLEcran else { return }
        if rotationLente {
            orbite.azimut -= 2 * .pi / CameraScene.dureeTour * dt
        }
        if rotationEnAttente != .zero {
            let pas = rotationEnAttente * (1 - pow(0.95, 60 * dt))
            orbite.azimut += pas.x
            orbite.inclinaison = min(1.45, max(0.15, orbite.inclinaison + pas.y))
            rotationEnAttente -= pas
            if simd_length(rotationEnAttente) < 1e-5 { rotationEnAttente = .zero }
        }
        if zoomEnAttente != 0 {
            var pas = zoomEnAttente * (1 - exp(-dt * 16))
            if abs(zoomEnAttente) < 0.002 { pas = zoomEnAttente }
            let bornes = CameraScene.bornes(geometrie, aspect: aspect, troisD: t == 1, champ: orbite.champ)
            orbite = CameraScene.zoomer(orbite, facteur: pas, ancre: ancreZoom, bornes: bornes)
            zoomEnAttente -= pas
            if orbite.distance <= bornes.lowerBound || orbite.distance >= bornes.upperBound { zoomEnAttente = 0 }
        }
    }

    /// Fin du glissement d'une disposition : tout est pose.
    private func finirTransition() {
        transition = nil
        posesAffichees = PosesScene()
        apparencesParties = [:]
    }

    /// Vitesse de l'estompement du mode focus : la part du chemin faite par seconde (les deux tiers en 0,2 s, presque
    /// tout en 0,8 s).
    static let vitesseFocus = 5.0

    // MARK: Horloge

    func doitContinuer(_ now: Double) -> Bool {
        // Une scene qui attend la fin d'un glisser s'applique au relachement : pas d'image pour elle.
        if enMouvement || s != sCible || margesEnRoute || glissementPlateaux != nil || transition != nil
            || (attente != nil && geste == nil) {
            return true
        }
        if se != seCible || fk.values.contains(where: { $0 != 0 && $0 != 1 })
            || ek.values.contains(where: { $0 != 0 && $0 != 1 }) || focusEnRoute {
            return true
        }
        if rotationLente { return true }
        if zoomEnAttente != 0 || rotationEnAttente != .zero || (geste != nil && bouge) { return true }
        if now - derniereActivite < 0.6 { return true }
        return etiquettes.contains { $0.envie > 0 }
    }

    /// Arrete l'horloge apres l'image (pas pendant le rendu).
    private func endormir() {
        guard anime else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.doitContinuer(Self.maintenant()) else { return }
            self.anime = false
        }
    }

    func reveiller() {
        derniereActivite = Self.maintenant()
        if !anime {
            // Pas de temps nul a la premiere image : sinon le zoom amorti ferait un bond.
            instant = nil
            anime = true
        }
    }
}
