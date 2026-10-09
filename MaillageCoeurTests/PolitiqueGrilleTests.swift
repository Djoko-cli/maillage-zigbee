import CoreGraphics
import Foundation
import Testing
@testable import MaillageCoeur

/// La politique de la grille 2D, sortie du moteur (polissage D, section 5) : le reglage, la premiere vraie taille, la
/// demande qui attend la vue d'ensemble 2D, l'hysteresis, les durees. Les rayons et les tailles sont ceux de
/// `CameraSceneTests.hysteresisEtTailleNulle` : quatre plateaux de 12, la rangee a 1820 x 1000, 2 x 2 a 1100 x 760, et
/// 2 x 2 en place qui reste a 1820 x 1000 (a moins de 5 %) mais pas a 2200 x 1000.
@Suite("Scene : politique de la grille")
struct PolitiqueGrilleTests {
    static let r = [12.0, 12, 12, 12]
    static let carree = CGSize(width: 1100, height: 760), pres = CGSize(width: 1820, height: 1000)
    static let large = CGSize(width: 2200, height: 1000)

    /// Les trois demandes (polissage C, section 3.5) : le reglage, 2,6 s sans hysteresis ; le redimensionnement, 0,4 s
    /// avec ; un changement de niveau, 0,4 s sans.
    @Test func durees() {
        #expect(PolitiqueGrille.reglage == PolitiqueGrille.Demande(duree: 2.6, hysteresis: false))
        #expect(PolitiqueGrille.redimensionnement == PolitiqueGrille.Demande(duree: 0.4, hysteresis: true))
        #expect(PolitiqueGrille.niveaux == PolitiqueGrille.Demande(duree: 0.4, hysteresis: false))
    }

    /// Au depart, en grille, sans colonnes : la rangee en attendant une vraie taille. Le reglage ne change que s'il
    /// change ; en rangee, la geometrie n'a pas de colonnes, meme choisies.
    @Test func reglage() {
        var p = PolitiqueGrille()
        #expect(p.grille && p.colonnes == nil && p.attente == nil && p.colonnesDeLaGeometrie == nil && p.sansVraieTaille)
        let meme = p.regler(true)
        #expect(!meme && p.grille)
        let posee = p.premiereZone(rayons: Self.r, zone: Self.carree)
        #expect(posee && p.colonnesDeLaGeometrie == 2)
        let enRangee = p.regler(false)
        #expect(enRangee && !p.grille)
        #expect(p.colonnes == 2 && p.colonnesDeLaGeometrie == nil && !p.sansVraieTaille)
        let encore = p.regler(false)
        #expect(!encore)
        let enGrille = p.regler(true)
        #expect(enGrille && p.colonnesDeLaGeometrie == 2)
        #expect(!PolitiqueGrille(grille: false).sansVraieTaille && PolitiqueGrille(grille: false).colonnesDeLaGeometrie == nil)
    }

    /// La premiere vraie taille (section 3.3) : une taille de 1 pt ou moins, en largeur comme en hauteur, n'en pose
    /// aucune ; la premiere vraie pose ses colonnes, une seule fois ; en rangee, rien.
    @Test func premiereVraieTaille() {
        var p = PolitiqueGrille()
        for zone in [CGSize.zero, CGSize(width: 1, height: 600), CGSize(width: 600, height: 1)] {
            let posee = p.premiereZone(rayons: Self.r, zone: zone)
            #expect(!posee && p.colonnes == nil && p.sansVraieTaille, "\(zone) : rien")
        }
        let deux = p.premiereZone(rayons: Self.r, zone: CGSize(width: 2, height: 2))
        #expect(deux && p.colonnes != nil, "2 pt : une vraie taille")
        var q = PolitiqueGrille()
        let premiere = q.premiereZone(rayons: Self.r, zone: Self.carree)
        #expect(premiere && q.colonnes == 2)
        let seconde = q.premiereZone(rayons: Self.r, zone: Self.pres)
        #expect(!seconde && q.colonnes == 2, "une seule fois")
        var rangee = PolitiqueGrille(grille: false)
        let enRangee = rangee.premiereZone(rayons: Self.r, zone: Self.carree)
        #expect(!enRangee && rangee.colonnes == nil)
    }

    /// Hors de la vue d'ensemble 2D, une demande attend, sans rien choisir ; une seconde garde la plus longue duree, dans
    /// les deux ordres, et l'hysteresis seulement si les deux la demandent. A la vue d'ensemble, elle se pose : plus
    /// d'attente, les colonnes de la zone.
    @Test func attente() {
        var p = PolitiqueGrille()
        _ = p.premiereZone(rayons: Self.r, zone: Self.carree)
        let attend = p.demander(PolitiqueGrille.redimensionnement, ensemble2D: false, rayons: Self.r, zone: Self.large)
        #expect(attend == nil && p.attente == PolitiqueGrille.redimensionnement && p.colonnes == 2)
        let attendEncore = p.demander(PolitiqueGrille.reglage, ensemble2D: false, rayons: Self.r, zone: Self.large)
        #expect(attendEncore == nil)
        #expect(p.attente == PolitiqueGrille.Demande(duree: 2.6, hysteresis: false))
        var q = PolitiqueGrille()
        q.attendre(PolitiqueGrille.reglage)
        q.attendre(PolitiqueGrille.redimensionnement)
        #expect(q.attente == PolitiqueGrille.Demande(duree: 2.6, hysteresis: false), "la plus longue, dans l'autre ordre")
        var h = PolitiqueGrille()
        h.attendre(PolitiqueGrille.redimensionnement)
        h.attendre(PolitiqueGrille.Demande(duree: 0.2, hysteresis: true))
        #expect(h.attente == PolitiqueGrille.Demande(duree: 0.4, hysteresis: true), "l'hysteresis, si toutes la demandent")
        let posee = p.demander(PolitiqueGrille.niveaux, ensemble2D: true, rayons: Self.r, zone: Self.large)
        #expect(posee == PolitiqueGrille.Demande(duree: 2.6, hysteresis: false) && p.attente == nil && p.colonnes == 4,
                "la demande posee : celle qui attendait, fusionnee")
        p.attendre(PolitiqueGrille.niveaux)
        p.oublierAttente()
        #expect(p.attente == nil && p.colonnes == 4)
        // Une demande a la vue d'ensemble 2D, une autre en attente (relecture finale, Mineur 9) : elles fusionnent ; le
        // reglage attendait sans hysteresis, le redimensionnement qui la porte ne la remet pas : le choix exact.
        var f = PolitiqueGrille()
        _ = f.premiereZone(rayons: Self.r, zone: Self.carree)
        f.attendre(PolitiqueGrille.reglage)
        let fusion = f.demander(PolitiqueGrille.redimensionnement, ensemble2D: true, rayons: Self.r, zone: Self.pres)
        #expect(fusion == PolitiqueGrille.reglage && f.attente == nil && f.colonnes == 4,
                "sans hysteresis : 4, et non 2 gardee")
        var seule = PolitiqueGrille()
        _ = seule.premiereZone(rayons: Self.r, zone: Self.carree)
        let seulePosee = seule.demander(PolitiqueGrille.redimensionnement, ensemble2D: true, rayons: Self.r,
                                        zone: Self.pres)
        #expect(seulePosee == PolitiqueGrille.redimensionnement && seule.attente == nil && seule.colonnes == 2,
                "seule, elle garde l'hysteresis")
    }

    /// L'hysteresis de 5 % (section 3.3) : 2 x 2 en place reste a 1820 x 1000 avec une demande qui la porte, et pas
    /// sans ; a 2200 x 1000, la rangee l'emporte meme avec. En rangee, rien ne se choisit.
    @Test func hysteresis() {
        func enPlace() -> PolitiqueGrille {
            var p = PolitiqueGrille()
            _ = p.premiereZone(rayons: Self.r, zone: Self.carree)
            return p
        }
        var avec = enPlace()
        avec.poser(PolitiqueGrille.redimensionnement, rayons: Self.r, zone: Self.pres)
        #expect(avec.colonnes == 2)
        var sans = enPlace()
        sans.poser(PolitiqueGrille.niveaux, rayons: Self.r, zone: Self.pres)
        #expect(sans.colonnes == 4)
        var loin = enPlace()
        loin.poser(PolitiqueGrille.redimensionnement, rayons: Self.r, zone: Self.large)
        #expect(loin.colonnes == 4)
        var choix = enPlace()
        choix.choisir(rayons: Self.r, zone: Self.pres, enPlace: true)
        #expect(choix.colonnes == 2)
        choix.choisir(rayons: Self.r, zone: Self.pres, enPlace: false)
        #expect(choix.colonnes == 4)
        choix.choisir(rayons: Self.r, zone: CGSize(width: 600, height: 1), enPlace: false)
        #expect(choix.colonnes == 4, "1 pt de haut : rien ne change")
        var rangee = enPlace()
        _ = rangee.regler(false)
        rangee.poser(PolitiqueGrille.niveaux, rayons: Self.r, zone: Self.pres)
        #expect(rangee.colonnes == 2 && rangee.attente == nil)
    }
}
