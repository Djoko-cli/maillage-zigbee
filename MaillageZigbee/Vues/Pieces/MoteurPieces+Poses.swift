import Foundation
import MaillageCoeur
import simd

/// Les etats poses a la main, sans horloge, pour les captures et les tests : la bascule, un isolement, le survol,
/// un glissement, l'orbite, le zoom et la taille (polissage D, section 5 : le moteur en fichiers).
extension MoteurPieces {
    // MARK: Etats poses a la main (captures, tests)

    func poserBascule(_ q: Double) {
        t = CameraScene.rampe(q)
        troisD = q > 0
        orbite = CameraScene.canonique(geometrie, aspect: aspect, u: t)
    }

    /// Une piece isolee, au bout de son vol ; `depuisEtage` : ouverte depuis son etage isole (sa provenance).
    func poserIsolement(_ i: Int, depuisEtage: Bool = false) {
        guard let scene, i < scene.pieces.count else { return }
        let etage = scene.etages[scene.pieces[i].etage].id
        isolement = .piece(scene.pieces[i].id, provenance: depuisEtage ? etage : nil)
        focus = i
        isolee = textes.pieces[i]?.nom
        s = 1
        sCible = 1
        fk[scene.pieces[i].id] = 1
        if scene.etages.count > 1 {
            etageEnVue = etage
            se = 1
            seCible = 1
            ek[etage] = 1
        }
        if let e = entree { textes = Self.textes(e, focus: i) }
        construireEtiquettes()
        majFil()
        if let v = volVersPiece(i) { orbite = v.orbite(1, depuis: orbite) }
    }

    /// Un etage isole, au bout de son vol.
    func poserEtageIsole(_ e: Int) {
        guard let scene, scene.etages.count > 1, e < scene.etages.count else { return }
        let cle = scene.etages[e].id
        isolement = .etage(cle)
        etageEnVue = cle
        se = 1
        seCible = 1
        ek[cle] = 1
        majFil()
        orbite = volVersEtage(e).orbite(1, depuis: orbite)
    }

    func poserSurvol(_ id: String?) { survol = id }

    /// Le glissement d'une disposition, pose a `q` (de 0 a 1) de son temps, sans horloge : les poses des pieces et des
    /// noeuds, et les plateaux qui glissent avec eux.
    func poserTransition(_ q: Double) {
        guard let tr = transition else { return }
        posesAffichees = tr.poses(a: tr.debut + q * TransitionScene.duree)
        if let gl = glissementPlateaux { geometrie = geometrie(a: gl.debut + q * max(gl.duree2D, gl.duree3D)) }
    }

    /// Le glissement d'une disposition et celui des plateaux, commences `dt` secondes plus tot (tests) : l'image
    /// suivante les avance d'autant, par l'horloge.
    func reculerTransition(de dt: Double) {
        transition?.debut -= dt
        glissementPlateaux?.debut -= dt
    }

    func poserAzimut(_ decalage: Double) { orbite.azimut += decalage }

    func poserInclinaison(_ i: Double) { orbite.inclinaison = i }

    /// Zoom a l'echelle `k` (points par unite a la cible, divises par 24), vers le point `vers`.
    func poserZoom(echelle k: Double, vers a: SIMD3<Double>?) {
        let k0 = ProjectionScene(orbite, cadre: cadre).pxParUnite(orbite.cible) / CartesPieces.px
        let f = k0 / k
        if let a { orbite.cible = a + (orbite.cible - a) * f }
        orbite.distance *= f
        vueTouchee = true
    }

    /// Pose le cadre sans image, et la grille de cette zone visible, tout de suite (captures, tests).
    func poserTaille(_ nouvelle: CGSize) {
        taille = nouvelle
        zoneGrille = zoneVisible
        margesCadre = marges
        glissement = nil
        cadre = CGRect(x: 0, y: marges.haut, width: nouvelle.width,
                       height: max(1, nouvelle.height - marges.haut - marges.bas))
        guard pret, let scene else { return }
        politique.choisir(rayons: rayons(scene), zone: zoneVisible, enPlace: true)
        glissementPlateaux = nil
        politique.oublierAttente()
        geometrieVisee = geometriePour(scene)
        geometrie = geometrieVisee
        recadrer()
    }
}
