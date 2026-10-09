import MaillageCoeur
import SwiftUI

/// App de la barre des menus : suit le maillage Zigbee du pont Hue, tient le journal, notifie ; graphe et journal dans
/// leurs fenetres. `--args -demo` : le faux reseau Hue de la demo, sans rien ecrire ni notifier.
@main
struct MaillageZigbeeApp: App {
    @State private var surveillance: Surveillance
    @State private var ouverture: OuvertureSession
    @State private var nomsPont: NomsPont
    @State private var nomsPasseur: NomsPasseur
    @State private var sonde: SondeMaillage
    @State private var reglages: ControleurReglages
    @State private var misesAJour: MisesAJour
    private let notifications = Notifications()
    /// Bonjour `_hue._tcp`, demarre hors demo et hors tests.
    private let decouverte = DecouvertePont()
    private static let demo = CommandLine.arguments.contains("-demo")
    /// Le graphe s'ouvre au lancement en mode demo et au tout premier lancement
    /// (jamais a l'ouverture de session ensuite).
    private let ouvrirGraphe: Bool
    static let clePremierGraphe = "grapheDejaOuvert"

    init() {
        let s = Surveillance(mode: Self.demo ? .demo : .direct, dossier: Self.demo ? nil : Surveillance.dossierParDefaut)
        let o = OuvertureSession()
        // Les noms du pont : ceux de la demo en demo ; inerte sous les tests (ni reseau, ni trousseau, ni fichier) ;
        // sinon le client du pont, son dernier releve garde dans `noms-pont.json`.
        let d = Self.demo ? NomsPont(noms: NomsDemo.maison)
            : Surveillance.sousTests ? NomsPont()
            : NomsPont(dependances: .systeme(cache: Surveillance.dossierParDefaut.appendingPathComponent("noms-pont.json")))
        _surveillance = State(initialValue: s)
        _ouverture = State(initialValue: o)
        _nomsPont = State(initialValue: d)
        // Les noms de Maison : le releve invente de la demo en demo ; inerte sous les tests (jamais de Passeur lance) ;
        // sinon le Passeur, son dernier releve garde dans `releve-maison.json`.
        let np = Self.demo ? NomsPasseur(demo: NomsDemo.releveMaison)
            : Surveillance.sousTests ? NomsPasseur()
            : NomsPasseur(cache: NomsPasseur.fichierCache(dossier: Surveillance.dossierParDefaut),
                          lanceur: NomsPasseur.lancerPasseurDuMac)
        _nomsPasseur = State(initialValue: np)
        // Inerte en demo et sous tests : aucun port ouvert.
        let sm = SondeMaillage(actif: !Self.demo && !Surveillance.sousTests)
        _sonde = State(initialValue: sm)
        // Les mises a jour : ni en demo, ni sous les tests (aucune recherche, aucun reseau), ni dans une
        // compilation de travail.
        let m = MisesAJour(demarrer: MisesAJour.demarrerAuLancement(demo: Self.demo))
        _misesAJour = State(initialValue: m)
        _reglages = State(initialValue: ControleurReglages(surveillance: s, ouverture: o, nomsPont: d,
                                                           nomsPasseur: np, sonde: sm, misesAJour: m))
        let premier = !UserDefaults.standard.bool(forKey: Self.clePremierGraphe)
        ouvrirGraphe = !Surveillance.sousTests && (Self.demo || premier)
        guard !Surveillance.sousTests else { return }
        if !Self.demo {
            UserDefaults.standard.set(true, forKey: Self.clePremierGraphe)
            let n = notifications
            s.surAlertes = { n.presenter($0) }
            n.demanderAutorisation()
            o.proposerAuPremierLancement()
            // Les noms du pont et le releve de Maison vont a la surveillance, qui les reunit (`FusionNoms`).
            d.surNoms = { [weak s] m in s?.nomsPont = m }
            d.surLecture = { [weak s] m in s?.lecturePont(m) }
            np.surReleve = { [weak s] r in s?.releveMaison = r }
            np.demarrer()
            // Au lancement, le Passeur seulement si le releve garde a plus d'un jour.
            np.rafraichirSiAncien()
            let b = decouverte
            b.surPont = { [weak d] p in d?.pontDecouvert(p) }
            b.surRefus = { [weak d] refus in d?.reseauLocalRefuse = refus }
            d.surEchecReseau = { [weak b] in b?.relancer() }
            d.demarrer()
            b.demarrer()
            sm.surMaillage = { [weak s] m, recu in s?.recevoir(m, a: recu) }
            sm.surTournee = { [weak s] enCours in s?.tourneeEnCours = enCours }
            sm.surOubli = { [weak s] in s?.oublierMaillage() }
            sm.demarrer()
        }
        s.demarrer()
        // `--args -demo -captures <dossier>` : images de la vue par pieces, puis l'app quitte.
        if Self.demo, let dossier = UserDefaults.standard.string(forKey: "captures") {
            CapturesPieces.ecrire(dans: dossier, surveillance: s, sonde: sm, nomsPont: d)
            exit(0)
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarre()
                .environment(surveillance)
                .environment(ouverture)
                .environment(nomsPont)
                .environment(nomsPasseur)
                .environment(sonde)
                .environment(reglages)
                .environment(misesAJour)
        } label: {
            IconeBarre(ouvrirGraphe: ouvrirGraphe)
                .environment(surveillance)
        }
        .menuBarExtraStyle(.window)
        // Les Reglages sont une fenetre AppKit (`ControleurReglages`) : Cmd-virgule l'ouvre.
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Rechercher les mises à jour…") { misesAJour.rechercher() }
                    .disabled(!misesAJour.peutRechercher)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Réglages…") { reglages.montrer() }
                    .keyboardShortcut(",")
            }
        }

        // Sans barre de titre (polissage B, section 1) : SwiftUI pose la barre de titre transparente et le titre
        // masque, et les garde a chaque mise a jour de la fenetre ; les trois boutons restent, et le titre reste
        // celui de la fenetre (Mission Control, menu Fenetre).
        Window("Maillage Zigbee", id: "graphe") {
            FenetrePieces(fichierPlaces: FenetrePieces.fichierPlaces(demo: Self.demo, sousTests: Surveillance.sousTests),
                          fichierPieces: PiecesChoisies.fichier(demo: Self.demo, sousTests: Surveillance.sousTests),
                          places: Self.demo ? NomsDemo.places() : nil)
                .environment(surveillance)
                .environment(nomsPont)
                .environment(sonde)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: FenetrePieces.largeurParDefaut, height: 760)
        .defaultLaunchBehavior(.suppressed)

        Window("Journal", id: "journal") {
            FenetreJournal()
                .environment(surveillance)
        }
        .defaultSize(width: 720, height: 560)
        .defaultLaunchBehavior(.suppressed)
    }
}
