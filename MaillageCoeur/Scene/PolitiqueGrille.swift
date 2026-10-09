import CoreGraphics
import Foundation

/// La politique de la grille 2D (polissage C, sections 3.3 et 3.5 ; sortie du moteur au polissage D, section 5) : le
/// reglage (en grille ou en rangee), les colonnes choisies, et une demande qui attend la vue d'ensemble 2D. Une demande
/// porte la duree du glissement de ses plateaux et l'hysteresis : au changement du reglage, 2,6 s sans hysteresis ; au
/// redimensionnement, 0,4 s avec ; apres un changement de niveau, 0,4 s sans (en 3D, les plateaux glissent en 0,9 s).
/// Une taille de 1 pt ou moins ne choisit rien. Le moteur pose la geometrie et cadre la vue ; il appelle ces regles.
public struct PolitiqueGrille: Hashable, Sendable {
    /// Une demande : la duree du glissement des plateaux vers leur nouvelle case, et si la grille en place reste tant
    /// qu'elle est a moins de 5 % du choix.
    public struct Demande: Hashable, Sendable {
        public var duree: Double
        public var hysteresis: Bool

        public init(duree: Double, hysteresis: Bool) {
            self.duree = duree
            self.hysteresis = hysteresis
        }
    }

    /// Le changement du reglage : les plateaux glissent comme l'envol, 2,6 s, sans hysteresis.
    public static let reglage = Demande(duree: CameraScene.dureeEnvol, hysteresis: false)
    /// Une autre zone visible : 0,4 s, avec l'hysteresis.
    public static let redimensionnement = Demande(duree: CameraScene.dureeCases, hysteresis: true)
    /// Un changement de niveau, hors de la vue d'ensemble 2D : 0,4 s, sans hysteresis, a son retour.
    public static let niveaux = Demande(duree: CameraScene.dureeCases, hysteresis: false)

    /// Etages en 2D : en grille (le reglage par defaut), ou en rangee.
    public private(set) var grille: Bool
    /// Colonnes de la grille ; nil : pas encore de vraie taille, la rangee en attendant.
    public private(set) var colonnes: Int?
    /// Une demande qui attend la vue d'ensemble 2D (zoomee, isolee, en 3D, en mouvement).
    public private(set) var attente: Demande?

    public init(grille: Bool = true) {
        self.grille = grille
    }

    /// Les colonnes de la geometrie : en grille, celles choisies (nil, la rangee, avant une vraie taille) ; en rangee,
    /// nil.
    public var colonnesDeLaGeometrie: Int? { grille ? colonnes : nil }

    /// Le reglage ; rend vrai s'il change.
    public mutating func regler(_ g: Bool) -> Bool {
        guard g != grille else { return false }
        grille = g
        return true
    }

    /// Une demande : a la vue d'ensemble 2D (`ensemble2D`), elle se pose tout de suite, fusionnee avec celle qui
    /// attendait encore (`attendre` : la plus longue duree, l'hysteresis si toutes la demandent ; relecture finale,
    /// Mineur 9), et la fonction rend la demande posee (le moteur pose alors la geometrie, ses plateaux glissant en sa
    /// duree) ; sinon elle attend, et la fonction rend nil.
    @discardableResult
    public mutating func demander(_ d: Demande, ensemble2D: Bool, rayons: [Double], zone: CGSize) -> Demande? {
        attendre(d)
        guard ensemble2D, let a = attente else { return nil }
        poser(a, rayons: rayons, zone: zone)
        return a
    }

    /// Une demande attend la vue d'ensemble 2D : avec une autre en attente, la plus longue duree, et l'hysteresis
    /// seulement si toutes la demandent.
    public mutating func attendre(_ d: Demande) {
        attente = Demande(duree: max(attente?.duree ?? 0, d.duree), hysteresis: (attente?.hysteresis ?? true) && d.hysteresis)
    }

    /// Pose une demande : plus d'attente ; en grille, les colonnes de la zone `zone`, la grille en place gardee si la
    /// demande a l'hysteresis.
    public mutating func poser(_ d: Demande, rayons: [Double], zone: CGSize) {
        attente = nil
        choisir(rayons: rayons, zone: zone, enPlace: d.hysteresis)
    }

    /// En grille, les colonnes de la zone `zone` ; `enPlace` : la grille en place reste a moins de 5 % du choix. Une
    /// taille de 1 pt ou moins ne change rien.
    public mutating func choisir(rayons: [Double], zone: CGSize, enPlace: Bool) {
        guard grille, let c = GeometrieMaison.colonnes(rayons: rayons, taille: zone, enPlace: enPlace ? colonnes : nil)
        else { return }
        colonnes = c
    }

    /// En grille, aucune colonne n'est encore choisie : la grille attend une vraie taille.
    public var sansVraieTaille: Bool { grille && colonnes == nil }

    /// La premiere vraie zone (section 3.3) : en grille, avant tout choix, les colonnes de cette zone, sans autre
    /// condition. Rend vrai si elle les pose : le moteur cadre alors la vue d'ensemble ; une taille de 1 pt ou moins
    /// n'en pose aucune.
    public mutating func premiereZone(rayons: [Double], zone: CGSize) -> Bool {
        guard sansVraieTaille, let c = GeometrieMaison.colonnes(rayons: rayons, taille: zone) else { return false }
        colonnes = c
        return true
    }

    /// La demande en attente part : l'envol vers la 2D pose la grille de la zone du moment.
    public mutating func oublierAttente() {
        attente = nil
    }
}
