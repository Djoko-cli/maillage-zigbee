import AppKit
import MaillageCoeur
import SwiftUI

// Haut de la fenetre de la vue par pieces, sans barre de titre (polissage B, section 1 ; maquette du
// bandeau, carte C) : deux capsules de verre sur la ligne des trois boutons de la fenetre, le reseau a
// gauche (`BarreOutils`), la vue a droite (`CommandesVue`) ; entre elles, la bande qui deplace la
// fenetre ; dessous, contre le bord gauche, en plus petit, la tournee, les bandeaux, le fil et la ligne de niveau.

extension EnvironmentValues {
    /// Rendu d'une capture (`CapturesPieces`, par `ImageRenderer`) : ni le verre, ni les vues d'AppKit
    /// n'y sont dessines ; les vues posent a leur place le dessin de la maquette.
    @Entry var capturePieces = false
    /// La periode des courbes de la fiche dans une capture (qui ne rend pas le choix de la periode) ; nil, 24 h.
    @Entry var periodeCapture: PeriodeCourbes?
}

/// Cadre des trois boutons de la fenetre (fermer, reduire, agrandir), dans l'espace de la vue, dont
/// l'origine est le coin haut gauche de la fenetre (le contenu la couvre en entier) : la capsule de
/// gauche commence juste apres eux, et se centre sur leur milieu.
struct CadreFeux: Equatable {
    /// Bord droit du bouton agrandir (pt, depuis le bord gauche) ; 0 : les boutons caches (plein ecran).
    var droite: CGFloat
    /// Milieu des boutons (pt, depuis le haut).
    var milieu: CGFloat

    /// Celui de la fenetre de la vue, mesure sous macOS 27 : sa barre d'outils vide, du style automatique de SwiftUI
    /// (`FenetrePieces`, reverification du 02/10), fait la barre de titre de 52 pt et abaisse les trois boutons de
    /// 14 pt, en x = 19, 42 et 65, de 19 a 33 pt du haut (sans elle : 32 pt, en x = 9, 32 et 55, de 9 a 23 pt).
    /// Avant que la fenetre soit connue, et pour les captures, qui ne rendent pas la fenetre.
    static let defaut = CadreFeux(droite: 79, milieu: 26)

    /// En plein ecran, les boutons se cachent (ils ne paraissent qu'au survol du haut, avec la barre de titre) : la
    /// capsule de gauche prend leur place, contre le bord (`HautPieces.debut`), a la meme hauteur.
    static func pleinEcran(milieu: CGFloat) -> CadreFeux {
        CadreFeux(droite: 0, milieu: milieu)
    }

    init(droite: CGFloat, milieu: CGFloat) {
        self.droite = droite
        self.milieu = milieu
    }

    /// Lu sur la fenetre : les cadres des boutons fermer et agrandir, ramenes au coin haut gauche de la
    /// fenetre ; nil sans ces boutons, ou s'ils sont ailleurs (en plein ecran, dans la fenetre de la barre d'outils).
    @MainActor
    init?(fenetre: NSWindow) {
        guard let fermer = fenetre.standardWindowButton(.closeButton),
              let agrandir = fenetre.standardWindowButton(.zoomButton),
              fermer.window === fenetre, agrandir.window === fenetre else { return nil }
        let f = fermer.convert(fermer.bounds, to: nil)
        let a = agrandir.convert(agrandir.bounds, to: nil)
        self.init(droite: a.maxX, milieu: fenetre.frame.height - f.midY)
    }
}

/// Suit la fenetre de la vue (reverification du 02/10) : ses trois boutons, que la capsule de gauche suit, et le
/// vrai plein ecran.
/// - Les boutons sont lus a l'arrivee dans la fenetre et a la sortie du plein ecran ; a l'entree, ils se cachent
///   (`CadreFeux.pleinEcran`) : la capsule de gauche prend leur place, contre le bord (decision de Djoko, 02/10). La
///   barre de titre que le survol du haut fait paraitre la couvre le temps du survol.
/// - Le plein ecran : SwiftUI pose a la fenetre d'une app de la barre des menus (`LSUIElement`)
///   `fullScreenAuxiliary` ou `fullScreenNone`, et le bouton vert ne faisait qu'agrandir la fenetre ;
///   `.windowFullScreenBehavior(.enabled)` n'y change rien (essaye dans l'app, en demo). La fenetre recoit
///   `fullScreenPrimary`, et le garde : SwiftUI le defait au lancement, puis a l'entree et a la sortie du plein
///   ecran (releve dans l'app), et la sonde le remet aussitot, en observant `collectionBehavior`.
/// - En plein ecran, la barre d'outils invisible se retire (ronde finale du 02/10) : elle ne sert qu'a abaisser les
///   boutons hors plein ecran, et le survol du haut la faisait descendre en bande claire sur les capsules. SwiftUI la
///   rend visible a chaque mise a jour de la fenetre, quand la capsule change de place par exemple : un observateur
///   (`toolbar.isVisible`) la retire de nouveau tant que la fenetre est en plein ecran. Elle revient a la sortie. La
///   barre de titre que le survol fait paraitre, elle, est sombre, comme la fenetre (`FenetrePieces`,
///   `.preferredColorScheme(.dark)`).
/// - Les boutons lus a la sortie du plein ecran peuvent ne pas etre revenus : la capsule retrouve alors le dernier
///   cadre mesure hors plein ecran (`dernierHorsPleinEcran`), au lieu de rester au bord, sur eux, et une seconde
///   lecture, un peu plus tard, corrige une valeur de passage.
struct SuiviFenetre: NSViewRepresentable {
    let rapporter: (CadreFeux) -> Void

    func makeNSView(context: Context) -> Vue { Vue(rapporter) }
    func updateNSView(_ nsView: Vue, context: Context) {}

    /// Le plein ecran permis a la fenetre, comme fenetre principale : ni `fullScreenAuxiliary`, ni `fullScreenNone`.
    @MainActor
    static func permettrePleinEcran(_ fenetre: NSWindow) {
        var c = fenetre.collectionBehavior
        c.remove([.fullScreenAuxiliary, .fullScreenNone])
        c.insert(.fullScreenPrimary)
        if c != fenetre.collectionBehavior { fenetre.collectionBehavior = c }
    }

    final class Vue: NSView {
        let rapporter: (CadreFeux) -> Void
        /// Le cadre dont la capsule de gauche est a jour (celui du plein ecran, une fois dedans).
        private var feux = CadreFeux.defaut
        /// Le dernier cadre des boutons lu hors plein ecran : celui que la sortie du plein ecran rend a la capsule quand
        /// elle ne peut pas relire les boutons, et dont le milieu sert au plein ecran.
        private var dernierHorsPleinEcran = CadreFeux.defaut
        /// La lecture des boutons de la fenetre ; remplacee par les tests, pour simuler une lecture ratee.
        var lecture: @MainActor (NSWindow) -> CadreFeux? = { CadreFeux(fenetre: $0) }
        private var observation: NSKeyValueObservation?
        private var observationBarre: NSKeyValueObservation?
        /// La fenetre est en plein ecran, ou y entre : sa barre d'outils invisible reste retiree.
        private var enPleinEcran = false
        private weak var derniereFenetre: NSWindow?

        init(_ rapporter: @escaping (CadreFeux) -> Void) {
            self.rapporter = rapporter
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let centre = NotificationCenter.default
            centre.removeObserver(self)
            observation = nil
            observationBarre = nil
            // Une autre fenetre : son etat de plein ecran n'est pas celui de la precedente.
            if window !== derniereFenetre { enPleinEcran = false }
            derniereFenetre = window
            guard let window else { return }
            SuiviFenetre.permettrePleinEcran(window)
            observation = window.observe(\.collectionBehavior) { fenetre, _ in
                MainActor.assumeIsolated { SuiviFenetre.permettrePleinEcran(fenetre) }
            }
            // Quand la capsule change de place, SwiftUI remet la barre d'outils a jour, et la rend visible : en plein
            // ecran, elle se retire de nouveau aussitot.
            observationBarre = window.observe(\.toolbar?.isVisible) { [weak self] fenetre, _ in
                MainActor.assumeIsolated {
                    if self?.enPleinEcran == true, fenetre.toolbar?.isVisible == true { fenetre.toolbar?.isVisible = false }
                }
            }
            centre.addObserver(self, selector: #selector(entreEnPleinEcran), name: NSWindow.willEnterFullScreenNotification,
                               object: window)
            centre.addObserver(self, selector: #selector(sortDuPleinEcran), name: NSWindow.didExitFullScreenNotification,
                               object: window)
            // Une fenetre deja en plein ecran (rouverte ainsi) : la barre d'outils se retire, et la capsule va au bord.
            if window.styleMask.contains(.fullScreen) {
                entreEnPleinEcran()
            } else {
                lireOuRetrouver()
            }
        }

        @objc private func entreEnPleinEcran() {
            enPleinEcran = true
            window?.toolbar?.isVisible = false
            signaler(.pleinEcran(milieu: dernierHorsPleinEcran.milieu))
        }

        @objc private func sortDuPleinEcran() {
            enPleinEcran = false
            window?.toolbar?.isVisible = true
            window?.contentView?.superview?.layoutSubtreeIfNeeded()
            // Les boutons ne sont pas toujours revenus dans la fenetre : une seconde lecture, un peu plus tard,
            // corrige une valeur de passage.
            lireOuRetrouver()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(250))
                self?.lireLesBoutons()
            }
        }

        /// Une lecture qui rate laisserait la capsule sur les boutons, au bord (`feux` est encore celui du plein
        /// ecran, ou celui d'une autre fenetre) : elle retrouve alors le dernier cadre mesure hors plein ecran.
        private func lireOuRetrouver() {
            if !lireLesBoutons(), feux != dernierHorsPleinEcran { signaler(dernierHorsPleinEcran) }
        }

        /// Lit les boutons, hors plein ecran seulement (dedans, ils sont ailleurs) ; faux si la lecture rate.
        @discardableResult
        private func lireLesBoutons() -> Bool {
            guard !enPleinEcran, let window, let c = lecture(window) else { return false }
            dernierHorsPleinEcran = c
            if c != feux { signaler(c) }
            return true
        }

        private func signaler(_ c: CadreFeux) {
            feux = c
            rapporter(c)
        }
    }
}

/// Ce que fait un double-clic sur la bande du haut : celui d'une barre de titre, selon le reglage du Mac
/// (Bureau et Dock, « Double-cliquer sur la barre de titre d'une fenetre pour »), lu dans
/// `AppleActionOnDoubleClick` : « Fill », « Maximize », « Minimize » ou « None ».
enum ActionDoubleClic: Equatable {
    /// Remplir l'ecran ou agrandir (« Fill », « Maximize », et le reglage absent) : `performZoom`.
    /// AppKit n'a pas d'API publique pour remplir ; le zoom d'une fenetre redimensionnable prend l'ecran.
    case agrandir
    case reduire
    case rien

    init(reglage: String?) {
        switch reglage {
        case "Minimize": self = .reduire
        case "None": self = .rien
        default: self = .agrandir
        }
    }

    static let cle = "AppleActionOnDoubleClick"

    /// Celle du Mac, lue a chaque double-clic : un reglage change s'applique tout de suite.
    static var duMac: ActionDoubleClic { ActionDoubleClic(reglage: UserDefaults.standard.string(forKey: cle)) }

    @MainActor
    func appliquer(_ fenetre: NSWindow) {
        switch self {
        case .agrandir: fenetre.performZoom(nil)
        case .reduire: fenetre.performMiniaturize(nil)
        case .rien: break
        }
    }
}

/// Bande vide du haut, entre les deux capsules : la glisser deplace la fenetre ; un double-clic y fait
/// ce que fait un double-clic sur une barre de titre (`ActionDoubleClic`). C'est une vue d'AppKit, posee
/// sur la scene : elle recoit ses clics avant elle, et les gestes de la scene (tourner, deplacer, le
/// double-clic qui recadre) ne s'y appliquent pas. `WindowDragGesture` deplacerait la fenetre, mais
/// sans le double-clic de la barre de titre. Une capture ne la dessine pas.
struct BandeFenetre: View {
    @Environment(\.capturePieces) private var capture

    var body: some View {
        if capture {
            Color.clear
        } else {
            Representation()
        }
    }

    struct Representation: NSViewRepresentable {
        func makeNSView(context: Context) -> Vue { Vue() }
        func updateNSView(_ nsView: Vue, context: Context) {}
    }

    final class Vue: NSView {
        /// Deplacer la fenetre au glisser ; l'action du double-clic. Remplacees par les tests.
        var glisser: @MainActor (NSWindow, NSEvent) -> Void = { $0.performDrag(with: $1) }
        var doubleCliquer: @MainActor (NSWindow) -> Void = { ActionDoubleClic.duMac.appliquer($0) }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            switch event.clickCount {
            case 1: glisser(window, event)
            case 2: doubleCliquer(window)
            default: break
            }
        }

        /// Comme une barre de titre : le premier clic agit aussi dans une fenetre inactive.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        /// La fenetre est deplacee ici (`performDrag`), et par elle seule.
        override var mouseDownCanMoveWindow: Bool { false }
    }
}

/// Haut de la fenetre, pose sur la scene : la ligne des capsules, centree sur les trois boutons de la
/// fenetre (le reseau juste apres eux, la vue contre le bord droit, la bande entre elles) ; dessous, la
/// colonne de gauche, contre le bord gauche de la fenetre, a la marge de la legende (ronde finale du 02/10) : la
/// ligne de la tournee, pendant une tournee seulement, le bandeau d'une maison sans pieces, le
/// fil, et, juste sous lui, la ligne de niveau avec la pastille d'un releve ancien (`RangeeNiveau`, decision de
/// Djoko du 02/10). Son bas mesure donne la marge du haut de la vue d'ensemble (`surBas`, puis
/// `FenetrePieces.margeHaut`), avec la place d'une ligne de tournee absente tant qu'une sonde est retenue : la
/// scene ne bouge pas quand la ligne parait ou disparait, ni quand la ligne de niveau change de texte.
struct HautPieces: View {
    @Environment(SondeMaillage.self) private var sonde
    @Environment(\.accessibilityReduceMotion) private var reduire
    let moteur: MoteurPieces
    @Binding var troisD: Bool
    /// Le pont ne donne encore aucune piece : le bandeau du pont.
    var sansPieces = false
    /// Le releve de la sonde est ancien : sa pastille est a cote de la ligne de niveau.
    var ancien = false
    var feux = CadreFeux.defaut
    /// Le bas du haut de la fenetre, dans l'espace de la vue, la place d'une ligne de tournee absente comprise.
    var surBas: (CGFloat) -> Void = { _ in }
    /// Hauteur mesuree de la ligne de la tournee (`LigneTournee.gabarit`).
    @State private var hauteurTournee: CGFloat?

    /// Ecart entre le bouton agrandir et la capsule de gauche, et entre la capsule de droite et le bord
    /// de la fenetre (pt) : ceux de la maquette (72 - 59, et 12).
    static let ecartFeux: CGFloat = 13
    static let bordDroit: CGFloat = 12

    /// Debut de la capsule de gauche (pt, depuis le bord gauche) : juste apres les trois boutons ; au bord, a 12 pt
    /// comme la capsule de droite, quand ils sont caches (plein ecran).
    static func debut(_ feux: CadreFeux) -> CGFloat {
        feux.droite > 0 ? feux.droite + ecartFeux : bordDroit
    }

    var body: some View {
        let tournee = LigneTournee.place(serie: sonde.serie, debut: sonde.debutTournee)
        // Hors tournee, une sonde retenue : la marge du haut compte la ligne absente et son espacement.
        let reserve = tournee == .comptee ? (hauteurTournee ?? 0) + FenetrePieces.espacement : 0
        VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
            // Chaque capsule garde la largeur de son contenu (`fixedSize`) : la bande vide prend la place qui
            // reste. Sans cela, les trois se la partagent et la capsule du reseau tronque ses boutons.
            HStack(spacing: 0) {
                BarreOutils()
                    .capsuleDeVerre()
                    .fixedSize()
                BandeFenetre()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                CommandesVue(moteur: moteur, troisD: $troisD)
                    .capsuleDeVerre()
                    .fixedSize()
            }
            .frame(height: 2 * feux.milieu)
            .obstacle("ligne", moteur)
            .padding(.leading, Self.debut(feux))
            // Un bandeau qui parait glisse depuis le haut, et repart de meme ; ce qui est dessous descend
            // avec lui. Avec « Reduire les animations », le bandeau se fond (sa transition porte son fondu)
            // et le fil prend sa place d'un coup : aucune animation de conteneur. La ligne de la tournee fait
            // de meme ; la pastille d'un releve ancien, qui ne change rien a la place de la ligne de niveau, se
            // fond sur la meme animation de conteneur (aucune avec le reglage).
            VStack(alignment: .leading, spacing: FenetrePieces.espacementNiveau) {
                VStack(alignment: .leading, spacing: FenetrePieces.espacement) {
                    if tournee == .montree {
                        LigneTournee()
                            .transition(apparition.transitionAnimee)
                    }
                    if sansPieces {
                        BandeauSansPieces()
                            .transition(apparition.transitionAnimee)
                    }
                    FilPieces(moteur: moteur)
                }
                .obstacle("colonne", moteur)
                RangeeNiveau(moteur: moteur, ancien: ancien)
            }
            .animation(Apparition.animationDuConteneur(.top, reduire: reduire), value: sansPieces)
            .animation(Apparition.animationDuConteneur(.top, reduire: reduire), value: tournee == .montree)
            .animation(Apparition.animationDuConteneur(.top, reduire: reduire), value: ancien)
            .background(alignment: .topLeading) {
                if tournee != .aucune {
                    LigneTournee.gabarit
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { hauteurTournee = $0 }
                }
            }
            .padding(.leading, FenetrePieces.bord)
        }
        .padding(.trailing, Self.bordDroit)
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(VuePieces.espace)).maxY + reserve } action: {
            surBas($0)
        }
    }

    private var apparition: Apparition { Apparition.pour(.top, reduire: reduire) }
}

/// Bouton d'une capsule du haut (maquette du bandeau, `.b`) : texte de 11 pt (10 sous la capsule) blanc
/// a 0,92, marges de 3 x 9 pt, pastille blanche a 0,10 (0,20 enfoncee) au filet de 0,5 pt blanc a 0,16 ;
/// `allume` : la pastille blanche a 0,28 et le texte blanc, comme le segment choisi de 2D / 3D.
struct StyleBoutonCapsule: ButtonStyle {
    var taille: CGFloat = 11
    var allume = false

    func makeBody(configuration: Configuration) -> some View {
        Corps(etiquette: configuration.label, enfonce: configuration.isPressed, taille: taille, allume: allume)
    }

    private struct Corps<Etiquette: View>: View {
        @Environment(\.isEnabled) private var actif
        let etiquette: Etiquette
        let enfonce: Bool
        let taille: CGFloat
        let allume: Bool

        var body: some View {
            etiquette
                .font(.system(size: taille))
                .foregroundStyle(Color.white.opacity(allume ? 1 : 0.92))
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(allume ? 0.28 : enfonce ? 0.2 : 0.1)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
                .contentShape(Capsule())
                .opacity(actif ? 1 : 0.45)
        }
    }
}

/// Bouton a deux etats d'une capsule du haut (« Rotation lente ») : celui de `StyleBoutonCapsule`,
/// allume quand il est actif.
struct StyleBasculeCapsule: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
        }
        .buttonStyle(StyleBoutonCapsule(allume: configuration.isOn))
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// Interrupteur 2D / 3D (maquette du bandeau, `.seg`) : deux segments de 11 pt blancs a 0,8, marges de
/// 3 x 10 pt, dans une pastille blanche a 0,08 au filet de 0,5 pt blanc a 0,16 ; le segment choisi sur
/// une pastille blanche a 0,28, en blanc. Pour VoiceOver, un choix « Vue » a deux segments.
struct SelecteurVue: View {
    @Binding var troisD: Bool

    var body: some View {
        HStack(spacing: 0) {
            segment("2D", choisi: !troisD) { troisD = false }
            segment("3D", choisi: troisD) { troisD = true }
        }
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        .accessibilityRepresentation {
            Picker("Vue", selection: $troisD) {
                Text("2D").tag(false)
                Text("3D").tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ titre: LocalizedStringKey, choisi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(choisi ? 1 : 0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(choisi ? 0.28 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// « Liens : chemins | tous » (consigne de l'etape 3 bis, section 3) : le chemin de chaque routeur vers le pont, ou
/// tous les liens radio entendus ; dessine comme l'interrupteur 2D / 3D.
struct SelecteurLiens: View {
    @Binding var liens: ModeLiens

    var body: some View {
        HStack(spacing: 4) {
            Text("Liens")
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.7))
                .padding(.leading, 6)
            HStack(spacing: 0) {
                segment("chemins", choisi: liens == .chemins) { liens = .chemins }
                segment("tous", choisi: liens == .tous) { liens = .tous }
            }
            .background(Capsule().fill(Color.white.opacity(0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        }
        .help(liens == .chemins
            ? String(localized: "Les chemins des messages vers le pont ; les voisins entendus d'un nœud à sa sélection")
            : String(localized: "Tous les liens radio entendus"))
        .accessibilityRepresentation {
            Picker("Liens", selection: $liens) {
                Text("chemins").tag(ModeLiens.chemins)
                Text("tous").tag(ModeLiens.tous)
            }
            .pickerStyle(.segmented)
        }
    }

    private func segment(_ titre: LocalizedStringKey, choisi: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titre)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(choisi ? 1 : 0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(choisi ? 0.28 : 0)))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

extension View {
    /// Capsule de verre du haut (maquette du bandeau, `.verre` de la carte C) : 5 pt autour du contenu,
    /// du verre en capsule. Une capture, qui ne rend pas le verre, pose a sa place le fond de la
    /// maquette : rgba(40, 48, 72, 0,38), filet de 0,5 pt blanc a 0,22, ombre noire a 0,35.
    func capsuleDeVerre() -> some View {
        modifier(CapsuleDeVerre())
    }

    /// Ligne de la colonne de gauche, en plus petit (maquette du bandeau, `.pilule`) : texte de 10 pt
    /// blanc a 0,75, marges de 3 x 10 pt, en capsule de verre, teintee pour un bandeau d'alerte. Une
    /// capture pose a sa place le fond de la maquette : rgba(40, 48, 72, 0,32) (ou la teinte), filet de
    /// 0,5 pt blanc a 0,16.
    func piluleDuHaut(teinte: Color? = nil) -> some View {
        modifier(PiluleDuHaut(teinte: teinte))
    }
}

/// Fond du verre dans une capture (capsules, fiche) : celui des maquettes.
let fondVerreCapture = Color(.sRGB, red: 40 / 255, green: 48 / 255, blue: 72 / 255)

private struct CapsuleDeVerre: ViewModifier {
    @Environment(\.capturePieces) private var capture

    func body(content: Content) -> some View {
        let c = content.padding(5)
        if capture {
            c.background(Capsule().fill(fondVerreCapture.opacity(0.38)).shadow(color: .black.opacity(0.35), radius: 9, y: 6))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 0.5))
        } else {
            c.glassEffect(.regular, in: .capsule)
        }
    }
}

private struct PiluleDuHaut: ViewModifier {
    @Environment(\.capturePieces) private var capture
    let teinte: Color?

    func body(content: Content) -> some View {
        let c = content
            .font(.system(size: 10))
            .foregroundStyle(Color.white.opacity(0.75))
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
        if capture {
            c.background(Capsule().fill(teinte ?? fondVerreCapture.opacity(0.32)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        } else {
            c.glassEffect(teinte.map { Glass.regular.tint($0) } ?? .regular, in: .capsule)
        }
    }
}

/// Les trois boutons de la fenetre, dessines dans une capture seulement (qui ne rend pas la fenetre) :
/// a leur place (`CadreFeux.defaut`), aux couleurs de la maquette.
struct FeuxDeCapture: View {
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(Color(.sRGB, red: 0xFF / 255, green: 0x5F / 255, blue: 0x57 / 255))
            Circle().fill(Color(.sRGB, red: 0xFE / 255, green: 0xBC / 255, blue: 0x2E / 255))
            Circle().fill(Color(.sRGB, red: 40.0 / 255, green: 200.0 / 255, blue: 64.0 / 255))
        }
        .frame(width: 3 * 14 + 2 * 9, height: 14)
        .offset(x: CadreFeux.defaut.droite - (3 * 14 + 2 * 9), y: CadreFeux.defaut.milieu - 7)
        .accessibilityHidden(true)
    }
}
