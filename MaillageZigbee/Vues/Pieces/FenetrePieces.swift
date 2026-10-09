import AppKit
import MaillageCoeur
import SwiftUI

/// Fenetre de la vue par pieces (spec de la vue par pieces, sections 1 et 7 ; polissage B, section 1) :
/// sans barre de titre (le style de sa scene, `.hiddenTitleBar`, dans `MaillageZigbeeApp`), la scene occupe
/// toute la fenetre, jusque sous ses trois boutons ; en haut, les deux capsules du bandeau, la bande qui
/// deplace la fenetre, la ligne de la tournee, les bandeaux, le fil et la ligne de niveau (`HautPieces`) ; en bas,
/// la pile : la legende, puis la fiche. Elle reste sombre, comme la maquette, meme quand le Mac est en
/// clair (precision 15 du plan 4b).
struct FenetrePieces: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.accessibilityReduceMotion) private var reduire
    /// Le mode 2D ou 3D, garde d'un lancement a l'autre.
    @AppStorage(FenetrePieces.cleMode) private var troisD = false
    /// Les etages en 2D, en grille (par defaut) ou en rangee (polissage C, section 3.1) : le reglage de Reglages ›
    /// General, garde d'un lancement a l'autre.
    @AppStorage(FenetrePieces.cleGrille) private var etagesEnGrille = true
    /// Le repli de la legende, tel que Djoko l'a laisse (la preference de `LigneDuBas`) : la zone visible de la grille.
    @AppStorage(LegendePieces.cleRepliee) private var legendeRepliee = false
    @State private var moteur: MoteurPieces
    @State private var piecesChoisies: PiecesChoisies
    @State private var aRenommer: NoeudChoisi?
    /// Les trois boutons de la fenetre, lus sur elle (`SuiviFenetre`) : la capsule de gauche commence apres eux.
    @State private var feux = CadreFeux.defaut
    /// Marge du haut de la vue d'ensemble, d'apres la hauteur mesuree du haut de la fenetre.
    @State private var margeHautMesuree = FenetrePieces.margeHautInitiale
    /// Hauteur mesuree de la rangee du bas (la legende), la legende ouverte ; nil, repliee.
    @State private var hauteurLegende: CGFloat?
    /// La derniere hauteur mesuree de la rangee, la legende ouverte : elle decide du repli faute de place, la legende
    /// repliee comprise.
    @State private var legendeOuverteMesuree: CGFloat?
    /// Hauteur mesuree de la pile du bas (la legende, puis la fiche), une fiche ouverte ; nil sans fiche.
    @State private var hauteurPile: CGFloat?
    /// Hauteur mesuree de la fiche ; la derniere reste a sa fermeture, et vaut pour la suivante jusqu'a sa mesure.
    @State private var hauteurFiche: CGFloat?
    /// Hauteur mesuree de la vue.
    @State private var hauteurVue: CGFloat?
    /// Djoko a rouvert, sous une fiche, la legende repliee faute de place : elle reste ouverte jusqu'a la fermeture de
    /// cette fiche. Une ouverture faite sans fiche n'y compte pas : le drapeau tombe a chaque ouverture et a chaque
    /// fermeture de fiche (`onChange` plus bas).
    @State private var legendeRouverte = false

    /// Preference du mode 2D ou 3D.
    static let cleMode = "vuePieces3D"
    /// Preference des liens montres : « chemins » (par defaut) ou « tous » (`ModeLiens`).
    static let cleLiens = "liensMontres"

    /// Les liens montres gardes ; « chemins » sans preference ou pour une valeur inconnue.
    static func modeLiens(_ valeur: String?) -> ModeLiens {
        valeur.flatMap(ModeLiens.init(rawValue:)) ?? .chemins
    }
    /// Preference des voisins entendus a la selection (mode « chemins ») : montres (vrai, par defaut) ou masques.
    static let cleVoisins = "voisinsALaSelection"

    /// Les voisins montres gardes ; montres sans preference ou pour une valeur qui n'est pas un booleen.
    static func voisinsMontres(_ valeur: Any?) -> Bool {
        valeur as? Bool ?? true
    }

    /// L'aide du bouton « Voisins » : ce que le clic fait, ou pourquoi il est grise (mode « tous »).
    static func aideVoisins(montres: Bool, mode: ModeLiens) -> String {
        if mode == .tous { return String(localized: "Sans effet avec « Liens : tous » : tous les liens radio sont montrés") }
        return montres
            ? String(localized: "Voisins entendus montrés à la sélection d'un nœud : cliquer pour les masquer")
            : String(localized: "Voisins entendus masqués à la sélection d'un nœud : cliquer pour les montrer")
    }

    /// Preference des etages en 2D : en grille (vrai, par defaut) ou en rangee.
    static let cleGrille = "etagesEnGrille"
    /// Taille minimale de la fenetre (polissage B, section 3) : avec la fiche et ses courbes, la scene
    /// garde environ 230 pt de haut (88 pour 820 x 560, tri du sous-projet A, n° 11 ; 234 mesures, ligne de niveau
    /// comprise, sur le jeu de l'historique). 820 x 680 pt sous la barre de titre cachee, de 52 pt avec la barre d'outils
    /// invisible : la fenetre ne descend pas sous 820 x 732 pt.
    static let tailleMinimale = CGSize(width: 820, height: 680)
    /// Bord des elements poses sur la vue, et ecart entre eux (pt).
    static let bord: CGFloat = 16
    /// Largeur par defaut de la fenetre (`MaillageZigbeeApp`, `.defaultSize`).
    static let largeurParDefaut: CGFloat = 1100
    static let espacement: CGFloat = 10
    /// Ecart entre le fil et la ligne de niveau, juste dessous (pt).
    static let espacementNiveau: CGFloat = 4

    /// `fichierPlaces` : `positions-pieces.json` (`fichierPlaces(demo:sousTests:)`) ; `fichierPieces` :
    /// `pieces-routeurs.json` (`PiecesChoisies.fichier(demo:sousTests:)`) ; nil : ni lu ni ecrit. `places` : sans
    /// fichier, celles de depart, en memoire (la demo : `NomsDemo.places()`).
    /// `--args -selection <id>` : fiche ouverte au lancement (captures d'ecran).
    init(fichierPlaces: URL?, fichierPieces: URL? = nil, places: PlacesGardees? = nil) {
        _moteur = State(initialValue: MoteurPieces(troisD: UserDefaults.standard.bool(forKey: Self.cleMode),
                                                   fichierPlaces: fichierPlaces,
                                                   selection: UserDefaults.standard.string(forKey: "selection"),
                                                   places: places,
                                                   liens: Self.modeLiens(UserDefaults.standard.string(forKey: Self.cleLiens)),
                                                   voisins: Self.voisinsMontres(UserDefaults.standard.object(forKey: Self.cleVoisins))))
        _piecesChoisies = State(initialValue: PiecesChoisies(fichier: fichierPieces))
    }

    /// Places des pieces, a cote des identites des routeurs ; ni en demo ni sous les tests.
    static func fichierPlaces(demo: Bool, sousTests: Bool) -> URL? {
        demo || sousTests ? nil : Surveillance.dossierParDefaut.appendingPathComponent("positions-pieces.json")
    }

    /// Redessin de la fenetre au debut de chaque minute. « Ancien » (16 min) et « perime » (45 min)
    /// ne dependent que de l'heure (`Surveillance.maintenant`), que rien n'observe : quand la sonde
    /// se tait, aucun evenement ne redessine la vue ; l'etat parait avec une minute de retard au
    /// plus, et le redessin n'a lieu que dans cette fenetre, tant qu'elle est ouverte.
    static let horloge = EveryMinuteTimelineSchedule()

    /// Marge du haut de la vue d'ensemble (pt) : le bas de ce qui est pose en haut de la fenetre, mesure
    /// (`HautPieces` : la ligne des capsules, la place de la tournee tant qu'une sonde est retenue, les
    /// bandeaux presents, le fil, la ligne de niveau, toujours la), puis l'espacement. Elle remplace les valeurs
    /// fixes du plan 4b (precision 21).
    static func margeHaut(bas: CGFloat) -> CGFloat {
        ceil(bas) + espacement
    }

    /// Avant la premiere mesure : la ligne des capsules, l'espacement, le fil, et la ligne de niveau.
    static let margeHautInitiale = margeHaut(bas: 2 * CadreFeux.defaut.milieu + espacement + 16 + espacementNiveau
                                                + RangeeNiveau.hauteur)

    /// Marge du bas de la vue d'ensemble (pt), comme celle du haut : la hauteur mesuree de ce qui est pose en bas, la
    /// pile (de haut en bas, la legende, puis la fiche), le bord et l'espacement ; la vue d'ensemble se cadre
    /// au-dessus de tout cela (decisions de Djoko du 01/10 pour la legende ouverte, du 02/10 pour la fiche, qui
    /// remplacent les 190 et 360 pt fixes de la fiche). Sans rien a garder (nil : la legende repliee, ou sans entree, et
    /// pas de fiche), 30 pt : la legende repliee deborde un peu sur la vue.
    static func margeBas(pile: CGFloat?) -> CGFloat {
        guard let pile else { return 30 }
        return max(30, bord + ceil(pile) + espacement)
    }

    /// Marge du bas de la zone visible ou se choisit la grille (polissage C, section 3.3, decision de Djoko du 03/10) :
    /// celle de la legende telle que Djoko l'a laissee, ouverte ou repliee, sans la fiche, ni le repli de la legende
    /// faute de place sous elle, qui vont et viennent avec elle. `fiche` : une fiche est ouverte ; `repliee` : le repli
    /// garde ; `legende` : la hauteur mesuree de la rangee du bas, ouverte (nil : repliee) ; `legendeOuverte` : sa
    /// derniere mesure, ouverte. Ouvrir ou replier la legende change donc la grille ; ouvrir une fiche, non.
    static func margeBasGrille(fiche: Bool, repliee: Bool, legende: CGFloat?, legendeOuverte: CGFloat?) -> CGFloat {
        margeBas(pile: fiche ? (repliee ? nil : legendeOuverte) : legende)
    }

    /// Hauteur de scene en dessous de laquelle la legende ouverte se replie d'elle-meme sous une fiche (pt) : les
    /// 230 pt environ que la spec de B garde a la scene dans la plus petite fenetre, avec la fiche et ses courbes
    /// (section 3) ; la legende ne la fait pas descendre plus bas. Mesure sur la demo (reverification du 02/10, apres la
    /// ligne de niveau montee sous le fil), dont la marge du haut est de 139 pt : dans la fenetre par defaut (1100 x 760),
    /// la legende ouverte laisse 250 pt a la scene sous la fiche de l'Apple TV 4K, et reste ouverte, comme sous 20 des 31
    /// fiches de la demo (235 pt au moins) ; sous les 11 autres (de 143 a 179 pt), elle n'en laisserait que 183 a 219 :
    /// elle se replie, et la scene retrouve 380 a 416 pt. Dans la plus petite fenetre (820 x 732 pt, soit 680 pt sous la
    /// barre de titre cachee), elle laisserait 184 pt sous la fiche de l'Apple TV 4K et 155 sous la plus haute : elle se
    /// replie, comme sous 30 des 31 fiches, et la scene garde 381 et 352 pt ; sans fiche, elle en garde 344, la legende
    /// ouverte (563, repliee).
    static let sceneMinimale: CGFloat = 230

    /// La legende se replie d'elle-meme sous une fiche ouverte (verification du 02/10) si, ouverte au-dessus d'elle,
    /// elle ne laissait a la scene que moins de `sceneMinimale` pt, dans une vue de `hauteur` pt, sous la marge du
    /// haut. `legende` : la hauteur de sa rangee ouverte, la derniere mesuree ; `fiche` : celle de la fiche ; nil, pas
    /// encore mesurees : elle ne se replie pas. Le repli garde (la preference) n'y est pour rien.
    static func repliDePlace(hauteur: CGFloat, margeHaut: CGFloat, legende: CGFloat?, fiche: CGFloat?) -> Bool {
        guard let legende, let fiche else { return false }
        return hauteur - margeHaut - margeBas(pile: legende + espacement + fiche) < sceneMinimale
    }

    var body: some View {
        let palette = Palette(sombre: true)
        // Redessin chaque minute (`horloge`) : la scene et la fiche lisent l'heure, que rien n'observe. La
        // fiche la recoit (`instant`) : sinon SwiftUI la sauterait, ses entrees n'ayant pas change. La
        // scene est construite une fois par rendu : la legende, la fiche et son menu la lisent.
        TimelineView(Self.horloge) { contexte in
            let entree = surveillance.aUnReseau
                ? EntreeScene(surveillance: surveillance, places: moteur.places, choix: piecesChoisies.choix) : nil
            let fiche = moteur.selection != nil
            // Sous une fiche, la legende se replie d'elle-meme si la place manque, sauf si Djoko l'a rouverte.
            let repliDePlace = fiche && !legendeRouverte && hauteurVue.map {
                Self.repliDePlace(hauteur: $0, margeHaut: margeHautMesuree, legende: legendeOuverteMesuree,
                                  fiche: hauteurFiche)
            } == true
            ZStack {
                RadialGradient(gradient: palette.fond, center: UnitPoint(x: 0.3, y: 0.35), startRadius: 0, endRadius: 900)
                if let entree {
                    VuePieces(moteur: moteur, entree: entree, palette: palette,
                              marges: (margeHautMesuree, Self.margeBas(pile: hauteurPile ?? hauteurLegende)),
                              basGrille: Self.margeBasGrille(fiche: fiche, repliee: legendeRepliee, legende: hauteurLegende,
                                                             legendeOuverte: legendeOuverteMesuree))
                    if !moteur.pret {
                        ProgressView().controlSize(.small)
                    }
                } else {
                    EtatVide()
                }
                // « Ancien » ne depend que de l'heure : lu ici, dans la `TimelineView`, il suit l'horloge.
                HautPieces(moteur: moteur, troisD: $troisD, sansPieces: entree?.scene.sansPiecesMaison == true,
                           ancien: surveillance.maillageAncien, feux: feux) { margeHautMesuree = Self.margeHaut(bas: $0) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: Self.espacement) {
                    Spacer()
                    // La pile du bas, de haut en bas : la legende, puis la fiche ; la legende reste au-dessus d'une
                    // fiche ouverte (verification du 02/10). La fiche glisse depuis le bas a l'ouverture et a la
                    // fermeture, et la legende glisse avec elle. Avec « Reduire les animations », la fiche se fond (sa
                    // transition porte son fondu) et la legende prend sa place d'un coup : aucune animation de
                    // conteneur. D'un noeud a l'autre, le contenu de la fiche change sur place.
                    VStack(alignment: .leading, spacing: Self.espacement) {
                        LigneDuBas(moteur: moteur, entree: entree, repliDePlace: repliDePlace,
                                   rouvrir: { legendeRouverte = true }) { h in
                            hauteurLegende = h
                            if let h { legendeOuverteMesuree = h }
                        }
                        if let selection = moteur.selection {
                            FicheNoeud(id: selection, entree: entree, instant: surveillance.maintenant(a: contexte.date),
                                       aRenommer: $aRenommer, choisir: { moteur.selection = $0 }) {
                                moteur.selection = nil
                            }
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteurFiche = $0 }
                            .obstacle("fiche", moteur)
                            .transition(Apparition.pour(.bottom, reduire: reduire).transitionAnimee)
                        }
                    }
                    // Sa hauteur, une fiche ouverte : la marge du bas (sans fiche, celle de la rangee).
                    .onGeometryChange(for: CGFloat?.self) { fiche ? $0.size.height : nil } action: { hauteurPile = $0 }
                }
                .animation(Apparition.animationDuConteneur(.bottom, reduire: reduire), value: moteur.selection == nil)
                // En bas a gauche : la pile prend toute la largeur, sinon le `ZStack` centre la rangee du bas.
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Self.bord)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteurVue = $0 }
            .coordinateSpace(.named(VuePieces.espace))
            .ignoresSafeArea()
        }
        .frame(minWidth: Self.tailleMinimale.width, minHeight: Self.tailleMinimale.height)
        // De l'air en haut (reverification du 02/10, comme dans Plans) : une barre d'outils vide, sans fond, du style
        // que SwiftUI choisit (automatique). Elle fait la barre de titre de 52 pt et abaisse les trois boutons ; les
        // capsules, posees sur la scene et non dans la barre, se centrent sur eux (`SuiviFenetre`), leur haut a 11 pt du
        // bord. SwiftUI la garde a chaque mise a jour de la fenetre. En plein ecran, elle se retire (`SuiviFenetre`,
        // ronde finale du 02/10), et ne parait de toute facon qu'au survol du haut : sinon, sa fenetre couvrirait les
        // capsules et prendrait leurs clics (releve dans l'app, en demo).
        .toolbar { ToolbarSpacer(.flexible) }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .windowToolbarFullScreenVisibility(.onHover)
        .environment(piecesChoisies)
        .environment(\.colorScheme, .dark)
        // La fenetre reste sombre, quelle que soit l'apparence du Mac : sa barre, ses menus, ses feuilles, et en plein
        // ecran la barre de titre que le survol du haut fait paraitre (ronde finale du 02/10 : sur un Mac en clair, une
        // bande blanche). SwiftUI pose l'apparence de la fenetre a chaque mise a jour : l'apparence sombre posee par
        // AppKit (`appearance`, avant) etait aussitot defaite (releve dans l'app, en demo).
        .preferredColorScheme(.dark)
        // Les trois boutons, que suit la capsule de gauche, et le vrai plein ecran ; hors de la mise a jour de la vue en
        // cours.
        .background(SuiviFenetre { c in Task { @MainActor in feux = c } })
        .sheet(item: $aRenommer) { FeuilleRenommer(id: $0.id) }
        .onChange(of: reduire, initial: true) { _, r in moteur.reduire = r }
        // Le reglage s'applique tout de suite a la vue ouverte.
        .onChange(of: etagesEnGrille, initial: true) { _, g in moteur.reglerGrille(g) }
        // La fiche parait ou se ferme : la legende reprend son repli garde, et un « rouvert » anterieur ne vaut plus.
        .onChange(of: moteur.selection == nil) { _, _ in
            legendeRouverte = false
        }
        .fenetreDeLApp()
    }
}

extension View {
    /// Cadre de cet element de l'interface, dans l'espace de la vue : les noms de la scene l'evitent ;
    /// retire quand l'element disparait.
    func obstacle(_ cle: String, _ moteur: MoteurPieces) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(VuePieces.espace)) } action: { r in
            moteur.cadresInterface[cle] = r
            moteur.reveiller()
        }
        .onDisappear { moteur.cadresInterface[cle] = nil }
    }
}

/// La scene : un `Canvas` redessine a chaque image pendant un mouvement (`MoteurPieces.anime`), plus
/// du tout au repos ; gestes, molette, clics droits.
struct VuePieces: View {
    let moteur: MoteurPieces
    let entree: EntreeScene
    let palette: Palette
    let marges: (haut: CGFloat, bas: CGFloat)
    /// Marge du bas de la zone visible ou se choisit la grille (`FenetrePieces.margeBasGrille`).
    let basGrille: CGFloat
    @Environment(\.displayScale) private var echelle
    /// Un glisser est en cours. SwiftUI le remet a faux a la fin du geste, meme annule (sans `onEnded`) :
    /// le moteur clot alors un geste qui serait reste ouvert.
    @GestureState private var glisse = false
    /// Un pincement est en cours. Meme chose : un pincement annule n'a pas d'`onEnded`, et le moteur garde alors son
    /// dernier `magnification`, qui arreterait la rotation lente jusqu'au pincement suivant.
    @GestureState private var pince = false

    /// Espace de coordonnees de la vue et de ce qui est pose dessus.
    nonisolated static let espace = "pieces"

    /// Le point de la vue (points, depuis son coin haut gauche, comme l'espace de la vue) d'un point de sa fenetre
    /// (`locationInWindow`) ; `vue` : la sonde de la vue, dans AppKit, de sa taille.
    static func point(_ p: CGPoint, dans vue: NSView) -> CGPoint {
        let q = vue.convert(p, from: nil)
        return CGPoint(x: q.x, y: vue.isFlipped ? q.y : vue.bounds.height - q.y)
    }

    /// Le style du pointeur pour un curseur du moteur : le lien (la main), la main ouverte, la main fermee.
    static func style(_ c: Curseur) -> PointerStyle? {
        switch c {
        case .fleche: nil
        case .main: .link
        case .mainOuverte: .grabIdle
        case .mainFermee: .grabActive
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !moteur.anime)) { contexte in
            Canvas { ctx, taille in
                _ = contexte.date
                moteur.marges = marges
                moteur.basGrille = basGrille
                moteur.image(&ctx, taille: taille, echelle: echelle, palette: palette)
            }
        }
        .contentShape(Rectangle())
        // La main sur ce qui se clique ; en 3D, la main ouverte tant que ⌥ est tenue, fermee pendant ⌥ + glisser
        // (polissage C, section 6) : `NSCursor.openHand` et `closedHand`, que posent ces styles de SwiftUI.
        .pointerStyle(VuePieces.style(moteur.curseurForme))
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): moteur.survoler(p, option: NSEvent.modifierFlags.contains(.option))
            case .ended: moteur.survoler(nil)
            }
        }
        // ⌥ est lue au debut du geste : `DragGesture` ne donne ni l'evenement ni ses touches, mais son premier
        // `onChanged` (distance minimale nulle) arrive a l'appui, et le moteur ne lit `option` qu'a l'appui.
        .gesture(DragGesture(minimumDistance: 0)
            .updating($glisse) { _, g, _ in g = true }
            .onChanged { moteur.glisser($0.location, depart: $0.startLocation, option: NSEvent.modifierFlags.contains(.option)) }
            .onEnded { moteur.relacher($0.location) })
        .simultaneousGesture(MagnifyGesture()
            .updating($pince) { _, p, _ in p = true }
            .onChanged { moteur.pincer($0.magnification, en: $0.startLocation) }
            .onEnded { _ in moteur.finPincement() })
        .contextMenu { MenuPieces(moteur: moteur) }
        // Le premier clic agit aussi dans une fenetre inactive (verification du 02/10) : il active la fenetre et
        // isole la piece, ouvre la fiche ou commence un glisser ; sinon AppKit le garde pour activer la fenetre.
        .allowsWindowActivationEvents(true)
        .background(SondeFenetre { v in
            moteur.fenetre = v.window
            moteur.vue = v
        })
        .onChange(of: glisse) { _, g in
            if !g { moteur.abandonnerGeste() }
        }
        .onChange(of: pince) { _, p in
            if !p { moteur.finPincement() }
        }
        .onChange(of: entree, initial: true) { _, e in moteur.recevoir(e) }
        .onAppear { moteur.ecouter() }
        .onDisappear {
            moteur.arreterEcoute()
            // La vue quitte la fenetre pendant un geste : ni `onEnded`, ni peut-etre le changement ci-dessus.
            moteur.abandonnerGeste()
            moteur.finPincement()
        }
    }
}

/// Clics droits, un menu natif (polissage C, section 1.3) : sur le nom ou le disque d'un plateau, son nom en tete,
/// grise ; « Monter d'un etage » et « Descendre d'un etage » ; « Au meme niveau que », un sous-menu des autres niveaux,
/// celui de la zone coche ; « Hors de la maison », une case a cocher ; « Sur son propre niveau ». Le plateau et les
/// niveaux y sont designes par leur cle : une scene qui s'installe pendant que le menu est ouvert ne change pas ce qu'un
/// article vise. Ses coches et ses grises suivent la scene la plus recente (`MoteurPieces.menuEtage`, qui lit sa
/// version) : rouvert sur la meme cible apres un choix, le menu en montre l'effet. Sur le fond, « Replacer les pieces
/// automatiquement ».
struct MenuPieces: View {
    let moteur: MoteurPieces

    var body: some View {
        switch moteur.cibleMenu {
        case .etage(let cle):
            if let m = moteur.menuEtage(cle) {
                Button(m.nom) {}
                    .disabled(true)
                Button("Monter d'un étage") { moteur.deplacerEtage(cle, de: 1) }
                    .disabled(!m.monter)
                Button("Descendre d'un étage") { moteur.deplacerEtage(cle, de: -1) }
                    .disabled(!m.descendre)
                Divider()
                Menu("Au même niveau que") {
                    ForEach(m.niveaux, id: \.principal) { n in
                        Toggle(n.nom, isOn: Binding(get: { n.coche },
                                                    set: { _ in moteur.mettreAuNiveau(cle, de: n.principal) }))
                    }
                }
                .disabled(m.niveaux.isEmpty)
                Toggle("Hors de la maison", isOn: Binding(get: { m.dehors }, set: { _ in moteur.basculerDehors(cle) }))
                    .disabled(!m.aCote)
                Button("Sur son propre niveau") { moteur.mettreSurSonNiveau(cle) }
                    .disabled(!m.aCote)
            }
        case .fond:
            Button("Replacer les pièces automatiquement") { moteur.replacerPieces() }
        case .aucune:
            EmptyView()
        }
    }
}

/// Capsule de droite du haut de la fenetre : les liens montres (chemins ou tous), le bouton des voisins entendus a la
/// selection (grise en mode « tous »), l'interrupteur 2D / 3D, puis
/// « Rotation lente », en 3D seulement (coupee par « Reduire les animations »).
struct CommandesVue: View {
    let moteur: MoteurPieces
    @Binding var troisD: Bool
    /// Les liens montres, gardes d'un lancement a l'autre.
    @AppStorage(FenetrePieces.cleLiens) private var liensGardes = ModeLiens.chemins.rawValue
    /// Les voisins entendus a la selection, gardes d'un lancement a l'autre.
    @AppStorage(FenetrePieces.cleVoisins) private var voisinsGardes = true

    var body: some View {
        HStack(spacing: 5) {
            SelecteurLiens(liens: Binding(get: { moteur.liens }, set: { v in
                moteur.liens = v
                liensGardes = v.rawValue
            }))
            Toggle(isOn: Binding(get: { moteur.voisins }, set: { v in
                moteur.voisins = v
                voisinsGardes = v
            })) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .accessibilityLabel(Text("Voisins à la sélection"))
            }
            .toggleStyle(StyleBasculeCapsule())
            .disabled(moteur.liens == .tous)
            .help(FenetrePieces.aideVoisins(montres: moteur.voisins, mode: moteur.liens))
            SelecteurVue(troisD: Binding(get: { moteur.troisD }, set: { v in
                moteur.basculer(troisD: v)
                troisD = v
            }))
            if moteur.troisD {
                Toggle("Rotation lente", isOn: Binding(get: { moteur.rotation && !moteur.reduire },
                                                       set: { _ in moteur.basculerRotation() }))
                    .toggleStyle(StyleBasculeCapsule())
                    .disabled(moteur.reduire)
                    .help(moteur.reduire ? String(localized: "Coupée par « Réduire les animations »") : "")
            }
        }
    }
}

/// Bandeau d'une maison dont le pont n'a encore donne aucune piece (spec de la vue par pieces, section 2.3) : chaque
/// routeur a sa carte, avec ses enfants.
struct BandeauSansPieces: View {
    var body: some View {
        Label("Pas encore de pièces : le pont Hue les donnera", systemImage: "house")
            .piluleDuHaut()
    }
}

/// Fil, dans la colonne de gauche, sous la ligne des capsules (polissage C, section 5.3) : « Maison », puis
/// « › Etage » en etage isole, « › Etage › Salon » en piece isolee (« › Salon » dans une maison d'un seul
/// plateau) ; chaque cran au-dessus du dernier mene a son niveau. Une capture le dessine sans bouton.
struct FilPieces: View {
    @Environment(\.capturePieces) private var capture
    let moteur: MoteurPieces

    var body: some View {
        let fil = moteur.fil
        HStack(spacing: 4) {
            if fil.etage == nil && fil.piece == nil {
                Text("Maison")
            } else {
                lien(Text("Maison")) { moteur.versMaison() }
                if let e = fil.etage {
                    Text(verbatim: "›")
                    if fil.piece != nil {
                        lien(Text(verbatim: e.nom)) { moteur.allerEtage(e.etage) }
                    } else {
                        Text(verbatim: e.nom)
                    }
                }
                if let piece = fil.piece {
                    Text(verbatim: "› " + piece)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.primary.opacity(0.9))
    }

    /// Un cran qui mene a son niveau : un lien ; dans une capture, son texte, de la couleur d'un lien.
    @ViewBuilder
    private func lien(_ texte: Text, action: @escaping () -> Void) -> some View {
        if capture {
            texte.foregroundStyle(.link)
        } else {
            Button(action: action) { texte }
                .buttonStyle(.link)
        }
    }
}

/// Bas a gauche de la fenetre, au-dessus de la fiche quand elle est ouverte : la legende seule (la ligne de niveau
/// et la pastille d'un releve ancien sont montees dans la colonne de gauche du haut, `HautPieces`, decision de Djoko
/// du 02/10). Elle garde le repli de la legende, d'un lancement a l'autre, et donne sa hauteur quand la legende est
/// ouverte (nil, repliee) : la marge du bas de la vue d'ensemble (`FenetrePieces.margeBas`).
struct LigneDuBas: View {
    @Environment(\.accessibilityReduceMotion) private var reduire
    let moteur: MoteurPieces
    let entree: EntreeScene?
    /// Legende repliee ou ouverte, imposee (captures) : la preference n'est alors ni ecrite, ni suivie.
    var legendeForcee: Bool?
    /// Repli faute de place, sous une fiche, dans une fenetre trop basse (`FenetrePieces.repliDePlace`) : la legende
    /// se replie sans toucher a la preference ; l'ouvrir d'un clic le leve (`rouvrir`).
    var repliDePlace = false
    var rouvrir: () -> Void = {}
    /// Hauteur de la ligne, la legende ouverte ; nil, repliee.
    var surHauteurOuverte: (CGFloat?) -> Void = { _ in }
    @AppStorage(LegendePieces.cleRepliee) private var repliee = false

    var body: some View {
        // Des reperes « ailleurs » sont poses dans une piece isolee (lue avec elle : `isolee`).
        let ailleurs = moteur.isolee != nil && !moteur.textes.ailleurs.isEmpty
        let rubriques = entree.map {
            LegendePieces.rubriques(LegendePieces.Lecture($0, ailleurs: ailleurs, mode: moteur.liens,
                                                                 voisins: moteur.voisins))
        } ?? []
        let estRepliee = legendeForcee ?? (repliee || repliDePlace)
        let ouverte = !rubriques.isEmpty && !estRepliee
        HStack(spacing: 0) {
            if !rubriques.isEmpty {
                LegendePieces(rubriques: rubriques, repliee: Binding(get: { estRepliee }, set: { r in
                    guard legendeForcee == nil else { return }
                    // Un clic : le recadrage qui suit prend la duree de la legende ; l'ouvrir leve son repli faute de
                    // place, sans rien ecrire de plus que le choix de Djoko.
                    moteur.legendeBasculee()
                    if !r { rouvrir() }
                    repliee = r
                }))
                .obstacle("legende", moteur)
            }
        }
        // La legende qui s'ouvre ou se replie glisse ; avec « Reduire les animations », elle prend sa place d'un coup.
        .animation(Apparition.animationDuConteneurLegende(reduire: reduire), value: estRepliee)
        .onGeometryChange(for: CGFloat?.self) { ouverte ? $0.size.height : nil } action: { surHauteurOuverte($0) }
    }
}

/// Ligne de niveau, en haut a gauche, dans la colonne, sous le fil : pieces seules, routeurs, noms masques, piece
/// isolee. Une seule ligne, coupee par des points de suspension si elle est trop longue : la colonne ne change pas de
/// hauteur quand elle change de texte, au fil des zooms.
struct LigneNiveauVue: View {
    let ligne: LigneNiveau

    var body: some View {
        Text(Self.texte(ligne))
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.tail)
    }

    static func texte(_ l: LigneNiveau) -> String {
        switch l {
        case .isolee(let nom):
            String(localized: "Pièce isolée : \(nom) · clic sur une autre pièce pour y aller, clic à côté ou Échap pour revenir")
        case .etageIsole(let nom):
            String(localized: "Étage isolé : \(nom) · clic sur une pièce ou un autre étage pour y aller, clic à côté ou Échap pour revenir")
        case .pieces: String(localized: "Vue d'ensemble : les pièces")
        case .routeurs: String(localized: "Mi-distance : les pièces et les routeurs")
        case .masques(1): String(localized: "1 nom masqué faute de place : rapprochez-vous (molette)")
        case .masques(let n): String(localized: "\(n) noms masqués faute de place : rapprochez-vous (molette)")
        case .lisibles: String(localized: "Tous les noms sont lisibles")
        }
    }
}

/// La rangee de la ligne de niveau, dans la colonne de gauche, sous le fil, et la pastille d'un releve de la sonde
/// ancien, a cote d'elle (decision de Djoko du 02/10, qui les avait en bas). Sa hauteur est toujours celle de la
/// pastille, qu'elle soit la ou non : la colonne ne bouge pas, ni la marge du haut de la vue d'ensemble, quand la
/// pastille parait ou repart. La ligne se coupe d'elle-meme si elle est trop longue, la pastille garde sa place.
struct RangeeNiveau: View {
    let moteur: MoteurPieces
    var ancien = false

    /// Hauteur de la rangee (pt) : celle de la pastille, plus haute que la ligne.
    static let hauteur = PastilleAncien.hauteur

    var body: some View {
        HStack(spacing: 8) {
            LigneNiveauVue(ligne: moteur.ligneNiveau)
                .obstacle("niveau", moteur)
            if ancien {
                PastilleAncien()
                    .fixedSize()
                    .obstacle("ancien", moteur)
            }
        }
        .frame(height: Self.hauteur)
    }
}

/// Rapporte la vue, dans AppKit, et la fenetre qui la porte (la molette et Echap ne valent que pour elle).
struct SondeFenetre: NSViewRepresentable {
    let rapporter: (NSView) -> Void

    func makeNSView(context: Context) -> NSView { Sonde(rapporter) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class Sonde: NSView {
        let rapporter: (NSView) -> Void

        init(_ rapporter: @escaping (NSView) -> Void) {
            self.rapporter = rapporter
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            rapporter(self)
        }
    }
}
