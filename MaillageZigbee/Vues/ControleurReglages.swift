import AppKit
import SwiftUI

/// Fenetre Reglages, faite en AppKit comme les reglages classiques de macOS (demande de Djoko,
/// 30/09, sur le modele de Screens Connect) :
/// - les onglets sont dans la barre d'outils ;
/// - le titre de la fenetre est celui de l'onglet ;
/// - la hauteur s'ajuste d'un onglet a l'autre.
///
/// Les onglets sont ceux de `NSTabViewController` en style barre d'outils. La hauteur, elle, est
/// animee ici (`OngletsReglages.ajuster`) : le redimensionnement natif, par `preferredContentSize`,
/// saute d'une hauteur a l'autre (essai et retour de Djoko, 30/09). La scene `Settings` de SwiftUI,
/// que cette fenetre remplace, faisait scintiller la barre des onglets a chaque changement.
@MainActor
@Observable
final class ControleurReglages {
    @ObservationIgnored private let surveillance: Surveillance
    @ObservationIgnored private let ouverture: OuvertureSession
    @ObservationIgnored private let nomsPont: NomsPont
    @ObservationIgnored private let nomsPasseur: NomsPasseur
    @ObservationIgnored private let sonde: SondeMaillage
    @ObservationIgnored private let misesAJour: MisesAJour
    /// Creee a la premiere ouverture, puis gardee : elle rouvre sur le meme onglet.
    @ObservationIgnored private var fenetre: NSWindow?

    init(surveillance: Surveillance, ouverture: OuvertureSession, nomsPont: NomsPont, nomsPasseur: NomsPasseur,
         sonde: SondeMaillage, misesAJour: MisesAJour) {
        self.surveillance = surveillance
        self.ouverture = ouverture
        self.nomsPont = nomsPont
        self.nomsPasseur = nomsPasseur
        self.sonde = sonde
        self.misesAJour = misesAJour
    }

    /// Montre la fenetre au premier plan. Elle devient la fenetre active : le menu de la barre
    /// se ferme, comme apres le graphe ou le journal.
    func montrer() {
        let f = fenetre ?? creerFenetre()
        fenetre = f
        f.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func creerFenetre() -> NSWindow {
        let onglets = OngletsReglages()
        onglets.tabStyle = .toolbar
        for o in OngletReglages.allCases {
            // Contenu change (sonde branchee, erreur affichee…) : la fenetre suit, si la page est visible.
            let page = FenetreReglages(onglet: o, surHauteur: { [weak onglets] _ in onglets?.contenuChange(de: o) })
                .environment(surveillance)
                .environment(ouverture)
                .environment(nomsPont)
                .environment(nomsPasseur)
                .environment(sonde)
                .environment(misesAJour)
            // Sans `sizingOptions` : la page n'annonce pas de taille preferee, sinon le redimensionnement
            // natif, sans animation, prendrait le pas sur `ajuster`.
            let hote = NSHostingController(rootView: page)
            hote.title = o.titre
            let item = NSTabViewItem(viewController: hote)
            item.label = o.titre
            item.image = NSImage(systemSymbolName: o.symbole, accessibilityDescription: o.titre)
            item.identifier = o.rawValue
            onglets.addTabViewItem(item)
        }
        let garde = UserDefaults.standard.string(forKey: OngletReglages.cle).flatMap(OngletReglages.init(rawValue:))
        onglets.selectedTabViewItemIndex = OngletReglages.allCases.firstIndex(of: garde ?? .general) ?? 0
        let f = NSWindow(contentViewController: onglets)
        f.styleMask = [.titled, .closable, .miniaturizable]
        f.toolbarStyle = .preference
        f.isReleasedWhenClosed = false
        onglets.ajuster(animer: false)
        f.center()
        return f
    }
}

/// Onglets des Reglages : garde le dernier onglet ouvert (`OngletReglages.cle`), et donne a la
/// fenetre la taille de la page choisie, en l'animant, bord du haut fixe, comme les reglages
/// classiques de macOS.
final class OngletsReglages: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        if let id = tabViewItem?.identifier as? String {
            UserDefaults.standard.set(id, forKey: OngletReglages.cle)
        }
        ajuster(animer: view.window?.isVisible == true)
    }

    /// L'onglet choisi, ou nil si le choix n'en est pas un.
    var ongletCourant: OngletReglages? {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex) else { return nil }
        return (tabViewItems[selectedTabViewItemIndex].identifier as? String).flatMap(OngletReglages.init(rawValue:))
    }

    /// La page de cet onglet a change de hauteur : la fenetre suit, si c'est la page visible.
    func contenuChange(de onglet: OngletReglages) {
        guard tabViewItems.indices.contains(selectedTabViewItemIndex),
              tabViewItems[selectedTabViewItemIndex].identifier as? String == onglet.rawValue else { return }
        ajuster(animer: view.window?.isVisible == true)
    }

    /// Donne a la fenetre la taille ideale de la page choisie (sa `fittingSize` : la page est
    /// collee en haut et peut s'etirer, mais sa taille ideale est celle de son contenu). Le bord
    /// du haut ne bouge pas ; l'animation prend la duree standard de macOS pour ce changement.
    func ajuster(animer: Bool) {
        guard let fenetre = view.window, tabViewItems.indices.contains(selectedTabViewItemIndex),
              let page = tabViewItems[selectedTabViewItemIndex].viewController else { return }
        let voulu = page.view.fittingSize
        let actuel = fenetre.contentLayoutRect.size
        guard voulu.height > 0, voulu.width > 0,
              abs(voulu.height - actuel.height) > 0.5 || abs(voulu.width - actuel.width) > 0.5 else { return }
        var cadre = fenetre.frame
        cadre.origin.y -= voulu.height - actuel.height
        cadre.size.height += voulu.height - actuel.height
        cadre.size.width += voulu.width - actuel.width
        if animer {
            NSAnimationContext.runAnimationGroup { contexte in
                contexte.duration = fenetre.animationResizeTime(cadre)
                fenetre.animator().setFrame(cadre, display: true)
            }
        } else {
            fenetre.setFrame(cadre, display: true)
        }
    }
}
