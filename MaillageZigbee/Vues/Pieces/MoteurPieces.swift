import AppKit
import MaillageCoeur
import os
import QuartzCore
import SwiftUI
import simd

/// Ligne de niveau, en haut a gauche de la vue, sous le fil (spec de la vue par pieces, section 6 ; polissage C,
/// section 5.1).
enum LigneNiveau: Equatable {
    case isolee(String)
    case etageIsole(String)
    case pieces
    case routeurs
    case masques(Int)
    case lisibles
}

/// Cible d'un clic droit : le nom ou le disque d'un plateau, par sa cle, ou le fond (spec, section 7 ; polissage C,
/// section 1.3). Jamais un indice : une scene qui s'installe pendant que le menu est ouvert peut ranger autrement ses
/// plateaux.
enum CibleMenu: Equatable {
    case aucune
    case etage(String)
    case fond
}

/// Ce que vise un clic, du plus fort au plus faible (polissage C, section 5.1) : un appareil, une piece (son bloc ou
/// son nom), le nom d'un etage, son disque (en 3D, le plus proche sur le rayon), le fond.
enum CibleClic: Equatable {
    case appareil(String)
    case piece(Int)
    case nomEtage(Int)
    case disque(Int)
    case fond
}

/// Le fil (polissage C, section 5.3) : « Maison », puis l'etage isole, ou l'etage et la piece isolee ; chaque cran
/// au-dessus du dernier mene a son niveau. Une maison d'un seul plateau n'a pas de cran « etage ».
struct Fil: Equatable {
    struct Cran: Equatable {
        var nom: String
        var etage: Int
    }

    var etage: Cran?
    var piece: String?
}

/// Le menu du clic droit sur le nom ou le disque d'un plateau (polissage C, section 1.3) : son nom, en tete ; « Monter
/// d'un etage » et « Descendre d'un etage », actifs pour un etage hors du haut et du bas de la pile ; « Au meme niveau
/// que », les autres niveaux, chacun nomme par son etage principal, celui de la zone coche ; « Hors de la maison » et
/// « Sur son propre niveau », pour une zone a cote.
struct MenuEtage: Equatable {
    /// Un niveau, designe par la cle de son etage principal (`principal`), jamais par son rang, qui perimerait.
    struct Niveau: Equatable {
        var principal: String
        var nom: String
        var coche: Bool
    }

    var nom: String
    var monter: Bool
    var descendre: Bool
    var niveaux: [Niveau]
    var aCote: Bool
    var dehors: Bool
}

/// Le curseur au-dessus de la vue : une main sur ce qui se clique (polissage C, maquette) ; en 3D, une main ouverte
/// tant que ⌥ est tenue, une main fermee pendant ⌥ + glisser (section 6).
enum Curseur: Equatable {
    case fleche
    case main
    case mainOuverte
    case mainFermee
}

/// Moteur de la vue par pieces (spec, sections 4 a 7) : la scene recue et sa disposition, calculee
/// hors du fil principal ; la camera et ses animations (envol, vols, isolement, rotation lente,
/// amortis) ; les gestes ; les places gardees ; et chaque image du `Canvas`. SwiftUI n'observe que ce
/// que les vues autour lisent (mode, rotation, horloge, piece isolee, selection, ligne de niveau,
/// menu, places) : le reste change a chaque image sans relancer leur corps.
///
/// Ce fichier porte les types de la vue, l'etat et les proprietes calculees ; le reste est reparti en extensions,
/// par responsabilite (polissage D, section 5) : `MoteurPieces+Scene` (scene, disposition, places gardees, menu du
/// clic droit), `+Camera` (plateaux et grille, camera, vols, isolement, Echap), `+Image` (chaque image, l'avance de
/// l'etat, l'horloge), `+Gestes` (souris, molette, pincement, moniteur des evenements) et `+Poses` (etats poses a la
/// main). Ces extensions ecrivent l'etat, qui n'est donc plus `private(set)` : Swift n'en a pas entre fichiers. L'etat
/// qui etait `private(set)` avant ce decoupage, hors de ces six fichiers, on le lit seulement ; le compilateur ne le
/// garde plus, cette regle le remplace. La vue pose le reste, comme avant : `selection`, `reduire`, `marges`,
/// `basGrille`, `fenetre` et `vue` ; les captures de demo posent aussi `fige` (`CapturesPieces`).
@MainActor
@Observable
final class MoteurPieces {
    /// Mode vise : 3D ou 2D (l'envol peut etre en cours).
    var troisD: Bool
    var rotation = true
    /// Horloge en marche : seulement pendant un mouvement, et 0,6 s apres.
    var anime = true
    /// Nom de la piece isolee ; nil sinon.
    var isolee: String?
    /// Ce que montre la vue, et sa provenance (polissage C, section 5) ; le fil qui le dit.
    var isolement = Isolement.maison
    var fil = Fil()
    var curseurForme = Curseur.fleche
    /// Le noeud choisi, dont la fiche est ouverte : le graphe passe en mode focus (`majMiseEnAvant`).
    var selection: String? {
        didSet { if selection != oldValue { majMiseEnAvant() } }
    }
    /// Les liens montres : les chemins vers le pont (par defaut), ou tous les liens radio (le bouton « Liens » du haut).
    var liens = ModeLiens.chemins {
        didSet {
            if liens != oldValue {
                majMiseEnAvant()
                reveiller()
            }
        }
    }
    /// En mode « chemins », les voisins entendus d'un noeud selectionne sont montres (par defaut) ou masques (le
    /// bouton « Voisins » du haut). Sans effet en mode « tous ».
    var voisins = true {
        didSet {
            if voisins != oldValue {
                majMiseEnAvant()
                reveiller()
            }
        }
    }
    var ligneNiveau = LigneNiveau.lisibles
    var cibleMenu = CibleMenu.aucune
    /// Version de la scene la plus recente (`sceneRecente`), observee : elle change avec elle, a chaque scene
    /// recue, en calcul ou posee. Le menu du clic droit la lit (`menuEtage`) : rouvert sur la meme cible apres un
    /// choix, il suit la scene de ce choix, que SwiftUI ne voit pas (relecture finale, Important 1).
    private(set) var versionScene = 0
    var places: PlacesGardees
    /// La premiere disposition est calculee.
    var pret = false
    /// « Reduire les animations » (accessibilite de macOS).
    var reduire = false {
        didSet { reveiller() }
    }

    nonisolated static let journal = Logger(subsystem: "fr.djoko.maillage.zigbee", category: "pieces")

    // MARK: Etat non observe

    @ObservationIgnored let fichierPlaces: URL?
    /// Scene affichee, posee sur sa disposition.
    @ObservationIgnored var entree: EntreeScene? {
        didSet { versionScene &+= 1 }
    }
    /// Scene recue pendant un mouvement ou un glisser : appliquee a sa fin.
    @ObservationIgnored var attente: EntreeScene? {
        didSet { versionScene &+= 1 }
    }
    /// Scene dont la disposition se calcule : `entree` reste affichee jusqu'a la fin du calcul.
    @ObservationIgnored var enCalcul: EntreeScene? {
        didSet { versionScene &+= 1 }
    }
    @ObservationIgnored var calcul: Task<Void, Never>?
    @ObservationIgnored var cleCalculee: EntreeScene.CleDisposition?
    @ObservationIgnored var placesCalculees: [String: SIMD2<Double>] = [:]
    @ObservationIgnored var rayonsCalcules: [String: Double] = [:]
    @ObservationIgnored var cartesCalculees: [String: CartesPieces.Carte] = [:]
    @ObservationIgnored var cartes: [CartesPieces.Carte] = []
    @ObservationIgnored var positions: [SIMD2<Double>] = []
    /// La geometrie de l'image ; elle rejoint la geometrie visee (`geometrieVisee`) quand les plateaux glissent.
    @ObservationIgnored var geometrie = GeometrieMaison(rayons: [])
    /// La geometrie de la scene, avec les rayons de sa disposition et la grille du reglage.
    @ObservationIgnored var geometrieVisee = GeometrieMaison(rayons: [])
    @ObservationIgnored var glissementPlateaux: GlissementPlateaux?
    /// Le glissement d'une disposition a l'autre (polissage D, section 1) : les pieces, les noeuds et les liens qui
    /// changent, de leur pose affichee a leur nouvelle pose ; nil au repos.
    @ObservationIgnored var transition: TransitionScene?
    /// Les poses de l'image, de ce qui est en transition : la scene projetee les prend, la camera les suit.
    @ObservationIgnored var posesAffichees = PosesScene()
    /// Le dessin des pastilles qui s'effacent, absentes de la scene : celui de la scene d'avant.
    @ObservationIgnored var apparencesParties: [String: DessinNoeud.Apparence] = [:]
    /// La politique de la grille 2D (polissage C, section 3 ; dans le coeur depuis le polissage D, section 5) : le
    /// reglage « Etages en 2D », pose par la fenetre, les colonnes choisies, une demande qui attend la vue d'ensemble
    /// 2D (`aLaVueDEnsemble2D`).
    @ObservationIgnored var politique = PolitiqueGrille()
    var grille: Bool { politique.grille }
    var colonnes: Int? { politique.colonnes }
    var grilleEnAttente: GrilleEnAttente? { politique.attente }
    /// Ce que vise le vol en cours : son arrivee suit les plateaux qui glissent.
    @ObservationIgnored var viseeVol: Visee?
    @ObservationIgnored var orbite = Orbite(cible: .zero, distance: 1000, azimut: 0, inclinaison: 0.0001, champ: 2)
    @ObservationIgnored var taille = CGSize.zero
    /// Marges du haut (le haut de la fenetre, mesure) et du bas (la pile du bas, mesuree : la legende et la ligne
    /// de niveau, puis la fiche), posees par la vue : la place utile de la vue d'ensemble. Le cadre les rejoint en
    /// 0,3 s, sur la courbe de la fiche qui glisse (`Apparition`) : la vue se releve avec elle, au-dessus de la pile,
    /// ou descend sous un bandeau ; en 0,45 s quand la legende s'ouvre ou se replie (`legendeBasculee`) ; avec
    /// « Reduire les animations », par un fondu.
    @ObservationIgnored var marges: (haut: CGFloat, bas: CGFloat) = (0, 0)
    /// Marge du bas de la zone visible ou se choisit la grille (polissage C, section 3.3) : celle de la legende,
    /// ouverte ou repliee, sans la fiche, qui va et vient (`FenetrePieces.margeBasGrille`) ; nil : celle du cadre.
    @ObservationIgnored var basGrille: CGFloat?
    /// La zone visible de la derniere image : une autre recalcule la grille.
    @ObservationIgnored var zoneGrille = CGSize.zero
    /// Marges du cadre, et leur glissement en cours vers `marges`.
    @ObservationIgnored var margesCadre: (haut: CGFloat, bas: CGFloat)?
    @ObservationIgnored var glissement: GlissementMarges?
    /// Duree du prochain glissement des marges : celle de la legende, qui vient de s'ouvrir ou de se replier
    /// (`legendeBasculee`) ; nil, celle de la fiche et des bandeaux.
    @ObservationIgnored var dureeAnnoncee: Double?
    /// Opacite de la scene pendant le fondu des marges (« Reduire les animations ») ; 1 sinon.
    @ObservationIgnored var opaciteMarges = 1.0
    @ObservationIgnored var cadre = CGRect(x: 0, y: 0, width: 1, height: 1)
    /// Bascule adoucie : 0 en 2D, 1 en 3D.
    @ObservationIgnored var t: Double
    @ObservationIgnored var envol: Envol?
    @ObservationIgnored var debutEnvol = 0.0
    /// « Reduire les animations » : l'envol, et le retour a la vue d'ensemble par double-clic, sont un
    /// fondu ; la camera saute a mi-chemin.
    @ObservationIgnored var fondu: Fondu?
    @ObservationIgnored var opaciteFondu = 1.0
    /// Isolement : `s` general, `fk` propre a chaque piece.
    @ObservationIgnored var s = 0.0
    @ObservationIgnored var sCible = 0.0
    @ObservationIgnored var sDepart = 0.0
    @ObservationIgnored var sDebut = 0.0
    @ObservationIgnored var focus: Int?
    /// Part propre a chaque piece de l'isolement, gardee par cle (triage A, n° 9).
    @ObservationIgnored var fk: [String: Double] = [:]
    /// Isolement d'un etage (polissage C, section 5) : `se` general, `ek` propre a chaque plateau, par cle ; l'etage
    /// en vue (isole, celui de la piece isolee, ou qui l'etait, pendant le retour).
    @ObservationIgnored var se = 0.0
    @ObservationIgnored var seCible = 0.0
    @ObservationIgnored var seDepart = 0.0
    @ObservationIgnored var seDebut = 0.0
    @ObservationIgnored var ek: [String: Double] = [:]
    @ObservationIgnored var etageEnVue: String?
    /// Disque cliquable et nom d'etage sous le pointeur.
    @ObservationIgnored var survolEtage: Int?
    @ObservationIgnored var survolNomEtage: Int?
    @ObservationIgnored var vol: Vol?
    @ObservationIgnored var debutVol = 0.0
    @ObservationIgnored var survol: String?
    @ObservationIgnored var curseur: CGPoint?
    @ObservationIgnored var zoomEnAttente = 0.0
    @ObservationIgnored var ancreZoom: SIMD3<Double>?
    @ObservationIgnored var dernierPincement = 1.0
    @ObservationIgnored var rotationEnAttente = SIMD2<Double>.zero
    @ObservationIgnored var geste: Geste?
    /// Point de depart du geste en cours : un glisser qui part d'ailleurs en commence un autre.
    @ObservationIgnored var departGeste = CGPoint.zero
    @ObservationIgnored var bouge = false
    /// Le dernier geste, qui avait bouge, a ete clos par `abandonnerGeste` : si son relachement arrive
    /// encore (SwiftUI peut remettre l'etat du geste a zero avant d'appeler `onEnded`), ce n'est pas un
    /// clic.
    @ObservationIgnored var abandonApresGlisser = false
    @ObservationIgnored var precedent = CGPoint.zero
    @ObservationIgnored var derniereActivite = 0.0
    @ObservationIgnored var instant: Double?
    @ObservationIgnored var dt = 0.0
    /// Djoko a zoome ou deplace la vue : un redimensionnement ne la recadre plus.
    @ObservationIgnored var vueTouchee = false
    @ObservationIgnored var etiquettes: [Etiquette] = []
    @ObservationIgnored var textes = TextesScene()
    /// Noeuds routeurs (leur nom en 12 points) et teinte de chaque piece, pour le dessin.
    @ObservationIgnored var routeurs: Set<String> = []
    @ObservationIgnored var teintes: [Int: Int] = [:]
    @ObservationIgnored var projetee: SceneProjetee?
    @ObservationIgnored var traits: [PlacementNoms.Trait] = []
    /// Cles des pieces et des etages de la scene des noms : un nom garde son etat d'une scene a l'autre.
    @ObservationIgnored var clesPieces: [String] = []
    @ObservationIgnored var clesEtages: [String] = []
    @ObservationIgnored let cache = CacheTextes()
    @ObservationIgnored let mesure = MesureNoms()
    /// Ce qui est pose sur la vue (barre, fil, ligne de niveau, legende, fiche), par element : les noms
    /// l'evitent.
    @ObservationIgnored var cadresInterface: [String: CGRect] = [:]
    /// Fenetre de la vue : la molette et Echap ne valent que pour elle. La vue, dans AppKit : le point de la molette.
    @ObservationIgnored weak var fenetre: NSWindow?
    @ObservationIgnored weak var vue: NSView?
    @ObservationIgnored var moniteur: Any?
    /// Captures : l'etat est pose a la main, l'horloge n'avance pas.
    @ObservationIgnored var fige = false
    /// Mode focus (etape 5, section 1) : ce qui reste net autour du noeud choisi (nil : pas de focus), l'estompement
    /// vise de chaque noeud et de chaque lien, et celui de l'image, qui le rejoint en douceur (`avancer`).
    @ObservationIgnored var miseEnAvant: MiseEnAvant?
    @ObservationIgnored var ciblesFocus: (noeuds: [String: Double], liens: [String: Double]) = ([:], [:])
    @ObservationIgnored var noeudsEstompes: [String: Double] = [:]
    @ObservationIgnored var liensEstompes: [String: Double] = [:]

    /// Dernier clic sur le fond (instant, point) : un second, assez pres et assez tot, est un double-clic.
    @ObservationIgnored var clicFond: (instant: Double, point: CGPoint)?

    enum Geste {
        case fond
        /// Une piece qu'on glisse (son identifiant, jamais un indice qui perimerait), sur le plan
        /// horizontal y = `hauteur`.
        case piece(String, hauteur: Double)
        /// ⌥ + glisser en 3D : la vue glisse dans le plan de l'ecran, depuis l'orbite de l'appui.
        case ecran(Orbite)
    }

    /// ⌥ est tenue (le survol et le moniteur des touches la suivent) ; ce que le pointeur vise est cliquable.
    @ObservationIgnored var optionTenue = false
    @ObservationIgnored var surCliquable = false

    /// ⌥ + glisser en cours : la camera n'obeit qu'au pointeur. La maquette coupe alors ses controles : l'inertie de
    /// rotation et le zoom amorti attendent, la molette et le pincement sont ignores ; au relachement, tout
    /// reprend.
    var deplaceDansLEcran: Bool {
        if case .ecran? = geste { true } else { false }
    }

    /// Glissement des marges du cadre, de `depart` a `arrivee`, depuis `debut`, en `duree` ; `fondu` : avec
    /// « Reduire les animations », un fondu par le fond, les marges sautant a mi-chemin.
    struct GlissementMarges {
        var depart: (haut: CGFloat, bas: CGFloat)
        var arrivee: (haut: CGFloat, bas: CGFloat)
        var debut: Double
        var duree: Double
        var fondu: Bool
    }

    /// Glissement des plateaux (polissage C, sections 1.3 et 3.5) : de `depart`, la geometrie de l'image a son debut,
    /// remise dans l'ordre des plateaux de la scene, vers la geometrie visee ; en 2D en `duree2D`, en 3D en
    /// `duree3D` (0 : sans glissement), en cubique entree-sortie.
    struct GlissementPlateaux {
        var depart: GeometrieMaison
        var debut: Double
        var duree2D: Double
        var duree3D: Double
    }

    /// Une grille voulue qui attend la vue d'ensemble 2D : la duree du glissement de ses plateaux, et si elle garde
    /// la grille en place tant qu'elle est a moins de 5 % du choix (un redimensionnement).
    typealias GrilleEnAttente = PolitiqueGrille.Demande

    /// Ce que vise un vol : la vue d'ensemble, une piece ou un etage (sa cle).
    enum Visee {
        case ensemble
        case piece(String)
        case etage(String)
    }

    /// Fondu de 0,3 s par le fond (« Reduire les animations ») : la scene s'efface, la camera saute a
    /// mi-chemin, la scene revient.
    struct Fondu {
        var debut: Double
        /// Avancement de la bascule vise : 0 en 2D, 1 en 3D (le meme pour un retour a la vue d'ensemble).
        var arrivee: Double
        /// Camera a mi-chemin : la fin du vol (retour a la vue d'ensemble) ; nil : la vue d'ensemble du
        /// mode vise (bascule).
        var orbite: Orbite?
        var saute = false
    }

    /// `troisD` : le mode garde ; `fichierPlaces` : `positions-pieces.json` (nil : ni lu ni ecrit) ; `places` : sans
    /// fichier, les places de depart, en memoire (la demo et son choix de niveau).
    init(troisD: Bool = false, fichierPlaces: URL? = nil, selection: String? = nil,
         places depart: PlacesGardees? = nil, liens: ModeLiens = .chemins, voisins: Bool = true) {
        self.troisD = troisD
        self.liens = liens
        self.voisins = voisins
        t = troisD ? 1 : 0
        self.fichierPlaces = fichierPlaces
        places = fichierPlaces.map(PlacesGardees.lire) ?? depart ?? PlacesGardees()
        self.selection = selection
    }

    /// Ce qui reste net autour du noeud choisi, d'apres la scene affichee (`EntreeScene.miseEnAvant`, la fonction du
    /// protocole) : a chaque selection, scene installee, et changement des liens ou des voisins montres. L'estompement
    /// suit en douceur ; une capture (`fige`) le prend tout de suite.
    func majMiseEnAvant() {
        let m = selection.flatMap { entree?.miseEnAvant(de: $0, voisins: liens == .tous || voisins) }
        miseEnAvant = m
        ciblesFocus = scene.map {
            MiseEnAvant.cibles(m, noeuds: $0.noeuds.map(\.id), liens: $0.liens.map(MiseEnAvant.cle))
        } ?? ([:], [:])
        if fige {
            noeudsEstompes = ciblesFocus.noeuds
            liensEstompes = ciblesFocus.liens
        }
        reveiller()
    }

    /// L'estompement du mode focus est en route vers sa cible.
    var focusEnRoute: Bool { noeudsEstompes != ciblesFocus.noeuds || liensEstompes != ciblesFocus.liens }

    static func maintenant() -> Double { CACurrentMediaTime() }

    var scene: ScenePieces? { entree?.scene }
    var aspect: Double { cadre.height > 0 ? Double(cadre.width / cadre.height) : 1.6 }
    /// Une piece est isolee (et non en train d'etre quittee).
    var estIsolee: Bool { focus != nil && sCible == 1 }
    var enMouvement: Bool { envol != nil || fondu != nil || vol != nil }
    /// La vue est a la vue d'ensemble : ni zoomee, ni deplacee, ni isolee, ni en mouvement.
    var aLaVueDEnsemble: Bool { pret && !ecarteDeLaVueDEnsemble && !enMouvement }
    /// A la vue d'ensemble, en 2D (la bascule a 0) : la ou la grille se choisit ; ailleurs, une demande de grille
    /// attend (`PolitiqueGrille`, polissage C, section 3.5).
    var aLaVueDEnsemble2D: Bool { t == 0 && aLaVueDEnsemble }
    /// Ni piece ni etage isoles, ni en train d'etre quittes.
    var sansIsolement: Bool { isolement == .maison && focus == nil && etageEnVue == nil }
    /// La vue s'ecarte de la vue d'ensemble : une piece ou un etage isoles (ou en train d'etre quittes), ou la vue
    /// zoomee ou deplacee. Le retour a la maison (`versMaison`) et Echap (`sortir`) n'ont rien a faire sinon.
    var ecarteDeLaVueDEnsemble: Bool { !sansIsolement || vueTouchee }
    /// Un mouvement, ou un glisser en cours (spec, sections 5 et 7) : une scene recue attend sa fin.
    var occupe: Bool { enMouvement || geste != nil }
}
