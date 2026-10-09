import AppKit
import MaillageCoeur
import SwiftUI

/// Icone de la barre des menus : orange quand il y a une alerte. Ouvre le
/// graphe au lancement quand on le lui demande (mode demo, premier lancement).
struct IconeBarre: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(\.openWindow) private var openWindow
    let ouvrirGraphe: Bool
    private static var grapheOuvert = false

    var body: some View {
        Image(nsImage: Self.image(alerte: surveillance.alerte))
            .task {
                guard ouvrirGraphe, !Self.grapheOuvert else { return }
                Self.grapheOuvert = true
                openWindow(id: "graphe")
                NSApp.activate()
            }
    }

    /// Le symbole du maillage en haut a gauche, le logo Zigbee en badge de 11 pt dans le coin vide en bas a
    /// droite, detoure de 1,5 pt pour se detacher du maillage. Image modele noire (suit la barre claire ou
    /// sombre) ; orange, non modele, en alerte.
    static func image(alerte: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        guard let maillage = NSImage(systemSymbolName: "point.3.connected.trianglepath.dotted",
                                     accessibilityDescription: "Maillage Zigbee")?.withSymbolConfiguration(config)
        else { return NSImage() }
        let h: CGFloat = 15, l = maillage.size.width * h / maillage.size.height
        let b: CGFloat = 11, lb = b * MarqueZigbee.proportion
        let taille = NSSize(width: l + 0.45 * lb, height: h + 0.25 * b)
        let couleur: NSColor = alerte ? .systemOrange : .black
        let image = NSImage(size: taille, flipped: false) { cadre in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            maillage.draw(in: NSRect(x: 0, y: taille.height - h, width: l, height: h))
            ctx.saveGState()
            ctx.translateBy(x: taille.width - lb, y: b)
            ctx.scaleBy(x: b, y: -b)
            ctx.addPath(MarqueZigbee.trace)
            ctx.setBlendMode(.clear)
            ctx.setLineWidth(3 / b)
            ctx.setLineJoin(.round)
            ctx.drawPath(using: .fillStroke)
            ctx.setBlendMode(.normal)
            ctx.addPath(MarqueZigbee.trace)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setBlendMode(.sourceIn)
            couleur.setFill()
            cadre.fill()
            return true
        }
        image.isTemplate = !alerte
        image.accessibilityDescription = "Maillage Zigbee"
        return image
    }
}

/// Contenu de la barre des menus : etat d'un coup d'oeil, 3 derniers
/// evenements, et les actions.
struct MenuBarre: View {
    @Environment(Surveillance.self) private var surveillance
    @Environment(SondeMaillage.self) private var sonde
    @Environment(NomsPont.self) private var pont
    @Environment(NomsPasseur.self) private var passeur
    @Environment(\.openWindow) private var openWindow
    @Environment(ControleurReglages.self) private var reglages
    @Environment(MisesAJour.self) private var misesAJour
    /// Fenetre du menu, pour le fermer apres « Ouvrir le graphe », « Journal… » et « Reglages… ».
    @State private var fenetreMenu = RefFenetre()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            entete
            Divider()
            ForEach(surveillance.lignesJournal.prefix(3)) { l in
                VStack(alignment: .leading, spacing: 1) {
                    Text(TexteEvenement.titre(l)).font(.callout).lineLimit(2)
                    Text(l.evenements.first.map(TexteEvenement.quand) ?? "").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            // Actions : comme les articles d'un menu natif (texte en couleur primaire, taille standard,
            // surlignees au survol) ; la marge negative aligne leur texte sur le reste du menu.
            VStack(alignment: .leading, spacing: 0) {
                Button("Ouvrir le graphe") { ouvrir("graphe") }
                Button("Journal…") { ouvrir("journal") }
                // Le Passeur lit Maison sans s'activer : le menu peut rester ouvert.
                Button { passeur.rafraichir() } label: {
                    if passeur.releveEnCours { Text("Relevé de Maison en cours…") } else { Text("Rafraîchir depuis Maison") }
                }
                .disabled(passeur.inerte || passeur.releveEnCours)
                Button("Rechercher les mises à jour…") { rechercherMisesAJour() }
                    .disabled(!misesAJour.peutRechercher)
                Button("Réglages…") { ouvrirReglages() }
                Button("Quitter Maillage Zigbee") { NSApp.terminate(nil) }
            }
            .buttonStyle(ActionMenu())
            .padding(.horizontal, -8)
        }
        .padding(14)
        .frame(width: 320, alignment: .leading)
        .background(FenetreHote { fenetreMenu.fenetre = $0 })
    }

    @ViewBuilder
    private var entete: some View {
        let alerte = surveillance.alerte
        HStack(spacing: 8) {
            if surveillance.resume == nil {
                Image(systemName: "antenna.radiowaves.left.and.right.slash").foregroundStyle(.secondary)
            } else {
                Image(systemName: alerte ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(alerte ? .orange : .green)
            }
            Text(titre).font(.headline)
        }
        if let r = surveillance.resume {
            Text("Routeurs : \(r.routeurs) · appareils : \(r.appareils) · injoignables : \(r.injoignables)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        if surveillance.mode == .demo {
            Text("Mode démo : faux réseau Hue").font(.caption).foregroundStyle(.secondary)
        } else if let t = Self.ligneSonde(sonde.etat, nom: sonde.nomEtat, derniere: sonde.derniereTournee,
                                          avancement: sonde.avancement, maintenant: Date(),
                                          passe: sonde.passeComplementaire, differee: sonde.tourneeDifferee) {
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
        if surveillance.mode != .demo, let t = Self.lignePont(pont.etat, lie: pont.lie) {
            Text(t).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Ligne du pont, quand il n'est pas lie et lu : introuvable, non lie, ou en erreur.
    static func lignePont(_ e: NomsPont.Etat, lie: Bool) -> String? {
        switch e {
        case .lie: nil
        case .introuvable: String(localized: "Pont Hue introuvable")
        case .erreur where lie: String(localized: "Pont Hue : erreur (voir les Réglages)")
        case .trouve, .aLier, .liaisonEnCours, .erreur: String(localized: "Pont Hue non lié")
        }
    }

    /// Ligne de la sonde, sous le nom donne (celui de la sonde retenue quand l'etat la concerne,
    /// `SondeMaillage.nomEtat`), sinon « Sonde » ; pendant une tournee, son etape et son
    /// compteur, hors tournee la passe complementaire programmee (`passe`) ou la tournee differee faute de budget (`differee`). Rien tant qu'aucune sonde n'est choisie.
    static func ligneSonde(_ e: SondeMaillage.Etat, nom: String?, derniere: Date?, avancement: AvancementTournee?,
                           maintenant: Date, passe: Date? = nil, differee: SondeMaillage.TourneeDifferee? = nil) -> String? {
        let n = SondeMaillage.nomAffiche(nom)
        switch e {
        case .sansSonde: return nil
        case .absente: return String(localized: "\(n) : absente")
        case .connexion: return String(localized: "\(n) : connexion…")
        case .connectee:
            if let avancement { return TexteTournee.menu(avancement, nom: n) }
            if let passe { return TexteTournee.menuPasse(passe, nom: n) }
            if let differee { return TexteTournee.menuDifferee(differee, nom: n) }
            guard let d = derniere else { return String(localized: "\(n) : connectée") }
            return String(localized: "\(n) : connectée · relevé \(FicheNoeud.relatif(d, maintenant))")
        case .refusee, .erreur: return String(localized: "\(n) : erreur (voir les Réglages)")
        }
    }

    private var titre: String {
        Self.titre(resume: surveillance.resume, alerte: surveillance.alerte)
    }

    /// Titre du menu : en attente tant qu'il n'y a rien a montrer, sinon l'alerte de l'heure, ou le reseau normal.
    static func titre(resume: ResumeReseau?, alerte: Bool) -> String {
        guard resume != nil else { return String(localized: "En attente du maillage de la sonde…") }
        return alerte ? String(localized: "Alerte dans l'heure") : String(localized: "Réseau Zigbee normal")
    }

    private func ouvrir(_ id: String) {
        Self.ouvrir(id, par: { openWindow(id: $0); NSApp.activate() }, menu: fenetreMenu.fenetre)
    }

    /// Ouvre la fenetre `id` de l'app (« graphe », « journal ») par `ouvrirFenetre`, puis ferme le menu `menu`, comme
    /// apres « Reglages… » : la fenetre ouverte ne prend pas toujours la main (l'app inactive, l'activation est
    /// cooperative), et le menu restait ouvert (vu par Djoko le 02/10, apres « Ouvrir le graphe »).
    static func ouvrir(_ id: String, par ouvrirFenetre: (String) -> Void, menu: NSWindow?) {
        ouvrirFenetre(id)
        menu?.close()
    }

    /// Le menu se ferme quand une autre fenetre de l'app prend la main. La fenetre des reglages ne
    /// la prend pas toujours : l'app inactive, le menu la garde (vu par Djoko le 30/09, le menu
    /// restait ouvert). On ferme donc le menu nous-memes, apres avoir montre les reglages.
    private func ouvrirReglages() {
        reglages.montrer()
        fenetreMenu.fenetre?.close()
    }

    /// La fenetre de Sparkle prend la place du menu, comme celle des reglages.
    private func rechercherMisesAJour() {
        misesAJour.rechercher()
        fenetreMenu.fenetre?.close()
    }
}

/// Fenetre du menu de la barre, retenue sans la garder en vie.
@MainActor
final class RefFenetre {
    weak var fenetre: NSWindow?
}

/// Donne la fenetre qui porte la vue, des qu'elle y est posee.
private struct FenetreHote: NSViewRepresentable {
    let surFenetre: (NSWindow?) -> Void

    func makeNSView(context: Context) -> Vue { Vue(surFenetre: surFenetre) }
    func updateNSView(_ nsView: Vue, context: Context) {}

    final class Vue: NSView {
        let surFenetre: (NSWindow?) -> Void

        init(surFenetre: @escaping (NSWindow?) -> Void) {
            self.surFenetre = surFenetre
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            surFenetre(window)
        }
    }
}

/// Action du menu de la barre, a la maniere d'un article de menu natif : texte en couleur
/// primaire et en taille standard, sur toute la largeur, surligne a la couleur d'accent au survol.
private struct ActionMenu: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LigneAction(configuration: configuration)
    }

    private struct LigneAction: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var active
        @State private var survol = false

        var body: some View {
            let surligne = survol && active
            configuration.label
                .font(.body)
                .foregroundStyle(surligne ? AnyShapeStyle(Color.white) : AnyShapeStyle(active ? .primary : .secondary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 5).fill(surligne ? Color.accentColor : .clear))
                .contentShape(Rectangle())
                .onHover { survol = $0 }
                .opacity(configuration.isPressed ? 0.85 : 1)
        }
    }
}
