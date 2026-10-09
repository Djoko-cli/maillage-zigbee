import AppKit
import MaillageCoeur
import SwiftUI
import UniformTypeIdentifiers

/// Onglets de la fenetre Reglages (`ControleurReglages`), dans la barre d'outils ; le dernier
/// ouvert est garde (demande de Djoko, 30/09 : une seule page etait trop chargee).
enum OngletReglages: String, CaseIterable {
    case general, notifications, pont, maison, sonde, diagnostic
    static let cle = "reglages.onglet"

    /// Libelle de l'onglet, et titre de la fenetre quand il est choisi.
    var titre: String {
        switch self {
        case .general: String(localized: "Général")
        case .notifications: String(localized: "Notifications")
        case .pont: String(localized: "Pont Hue")
        case .maison: String(localized: "Maison")
        case .sonde: String(localized: "Sonde")
        case .diagnostic: String(localized: "Diagnostic")
        }
    }

    /// Symbole SF de l'onglet.
    var symbole: String {
        switch self {
        case .general: "gearshape"
        case .notifications: "bell"
        case .pont: "lightbulb.2"
        case .maison: "house"
        case .sonde: "antenna.radiowaves.left.and.right"
        case .diagnostic: "stethoscope"
        }
    }
}

/// Une page des Reglages, celle d'un onglet : General (ouverture a la connexion, mises a jour, langue, vue par pieces :
/// les etages en 2D), Notifications (par categorie), Pont Hue (`ReglagesPont`), Maison (`ReglagesMaison`), Sonde (port
/// USB, etat), Diagnostic (maillage, capture, journal). La fenetre et ses onglets sont dans `ControleurReglages`.
struct FenetreReglages: View {
    let onglet: OngletReglages
    /// Appele a chaque changement de hauteur de la page : la fenetre la suit (`ControleurReglages`).
    var surHauteur: @MainActor (CGFloat) -> Void = { _ in }
    @Environment(Surveillance.self) private var surveillance
    @Environment(OuvertureSession.self) private var ouverture
    @Environment(NomsPont.self) private var nomsPont
    @Environment(SondeMaillage.self) private var sonde
    @Environment(MisesAJour.self) private var misesAJour
    @AppStorage(Notifications.cle(.routeurDisparu)) private var routeurDisparu = CategorieAlerte.routeurDisparu.parDefaut
    @AppStorage(Notifications.cle(.pertes)) private var pertes = CategorieAlerte.pertes.parDefaut
    @AppStorage(Notifications.cle(.informations)) private var informations = CategorieAlerte.informations.parDefaut
    @AppStorage(FenetrePieces.cleGrille) private var etagesEnGrille = true
    @State private var messageCapture: String?
    @State private var langue = LangueApp.lire()
    @State private var messageLangue: String?

    var body: some View {
        Group {
            switch onglet {
            case .general:
                page {
                    ouvertureALaConnexion
                    sectionMisesAJour
                    choixDeLangue
                    vueParPieces
                }
            case .notifications: page { notifications }
            case .pont: page { pontHue }
            case .maison: page { Section { ReglagesMaison() } }
            case .sonde: page { reglagesSonde }
            case .diagnostic: page { diagnostic }
            }
        }
        .frame(width: 560)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { surHauteur($0) }
        // Collee en haut : pendant que la fenetre change de hauteur, la page ne bouge pas.
        .frame(maxHeight: .infinity, alignment: .top)
        // Etat de l'ouverture a la connexion relu a chaque affichage de l'onglet (Reglages Systeme).
        .onAppear {
            if onglet == .general { ouverture.actualiser() }
        }
    }

    /// Page d'un onglet : un formulaire groupe, a la hauteur de son contenu. Un formulaire groupe
    /// connait sa hauteur ideale, mais accepte toute hauteur proposee : sans `fixedSize`, il
    /// n'annoncerait pas sa hauteur a la fenetre. Mesure du 30/09 : 121 pt pour 2 lignes, 367 pour 8.
    private func page<Contenu: View>(@ViewBuilder _ contenu: () -> Contenu) -> some View {
        Form { contenu() }
            .formStyle(.grouped)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Onglet Notifications : une categorie par interrupteur.
    private var notifications: some View {
        Section {
            Toggle("Routeur disparu", isOn: $routeurDisparu)
            Toggle("Au moins 3 appareils perdus en 10 min (une notification groupée)", isOn: $pertes)
            Toggle("Autres changements", isOn: $informations)
        }
    }

    /// Onglet General : ouverture a la connexion.
    private var ouvertureALaConnexion: some View {
        Section("Ouverture") {
            Toggle("Ouvrir à la connexion", isOn: Binding(get: { ouverture.active }, set: { ouverture.basculer($0) }))
            if ouverture.approbationRequise {
                Button("Approuver dans Réglages Système…") { ouverture.ouvrirReglagesSysteme() }
            }
            if let e = ouverture.erreur {
                Text(e).foregroundStyle(.red)
            }
        }
    }

    /// Onglet General : les mises a jour (Sparkle), recherche et installation automatiques, cochees par defaut.
    private var sectionMisesAJour: some View {
        Section("Mises à jour") {
            Toggle("Rechercher automatiquement",
                   isOn: Binding(get: { misesAJour.rechercheAuto }, set: { misesAJour.rechercheAuto = $0 }))
            Toggle("Installer automatiquement",
                   isOn: Binding(get: { misesAJour.installationAuto }, set: { misesAJour.installationAuto = $0 }))
                .disabled(!misesAJour.rechercheAuto)
            Button("Rechercher les mises à jour…") { misesAJour.rechercher() }
                .disabled(!misesAJour.peutRechercher)
        }
    }

    /// Onglet General : langue de l'app, appliquee au prochain lancement.
    private var choixDeLangue: some View {
        Section {
            Picker("Langue", selection: $langue) {
                Text("Celle du Mac").tag(LangueApp.systeme)
                Text(verbatim: "Français").tag(LangueApp.francais)
                Text(verbatim: "English").tag(LangueApp.anglais)
            }
            .onChange(of: langue) { _, l in LangueApp.ecrire(l) }
            if langue != LangueApp.auLancement {
                HStack {
                    Text("La langue change au prochain lancement.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Relancer maintenant") {
                        Task {
                            do { try await LangueApp.relancer() } catch { messageLangue = error.localizedDescription }
                        }
                    }
                }
            }
            if let messageLangue {
                Text(messageLangue).foregroundStyle(.red)
            }
        }
    }

    /// Onglet General : la vue par pieces (polissage C, section 3.1) ; les etages en 2D, en grille ou en rangee,
    /// s'appliquent tout de suite a la vue ouverte.
    private var vueParPieces: some View {
        Section("Vue par pièces") {
            Picker("Étages en 2D", selection: $etagesEnGrille) {
                Text("En grille").tag(true)
                Text("En rangée").tag(false)
            }
        }
    }

    /// Onglet Pont Hue (`ReglagesPont`) ; en demo, les noms de la demo, sans pont.
    private var pontHue: some View {
        Section {
            if surveillance.mode == .demo {
                Text("Mode démo : les noms de la démo, pas de pont.").foregroundStyle(.secondary)
                if let n = nomsPont.noms {
                    LabeledContent("Appareils", value: ReglagesPont.texteLecture(n))
                }
            } else {
                ReglagesPont()
            }
        }
    }

    /// Onglet Sonde : port, etat, firmware, releve.
    private var reglagesSonde: some View {
        Section {
            if surveillance.mode == .demo {
                Text("Mode démo : pas de sonde.").foregroundStyle(.secondary)
            } else {
                Picker("Port", selection: Binding(
                    get: { sonde.ports.first { $0.serie != nil && $0.serie == sonde.serie }?.chemin ?? "" },
                    set: { c in if let p = sonde.ports.first(where: { $0.chemin == c }) { sonde.choisir(p) } })) {
                    Text("—").tag("")
                    ForEach(sonde.ports) { p in
                        Text(verbatim: Self.libellePort(p, serieRetenue: sonde.serie, nom: sonde.nom)).tag(p.chemin)
                    }
                }
                LabeledContent("État", value: Self.texteEtatSonde(sonde.etat, nom: sonde.nomEtat))
                if case .connectee(let b) = sonde.etat {
                    LabeledContent("Firmware", value: b.version)
                }
                ReleveSonde()
                if sonde.serie != nil {
                    Button("Oublier la sonde") { Task { await sonde.oublier() } }
                }
                Text("Seul le port choisi est ouvert. Un autre ESP32-C6 branché n'est jamais ouvert : ne le choisissez pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Onglet Diagnostic : dernier maillage, capture et journal.
    private var diagnostic: some View {
        Section {
            LabeledContent("Dernier maillage",
                           value: surveillance.maillageRecu?.formatted(date: .abbreviated, time: .standard) ?? "—")
            if let m = surveillance.maillage {
                LabeledContent("Nœuds", value: Self.texteNoeuds(m))
            }
            if let e = surveillance.erreurJournal {
                LabeledContent("Journal", value: e)
            }
            HStack {
                Button("Enregistrer une capture…") { enregistrerCapture() }
                    .disabled(surveillance.maillage == nil)
                Button("Afficher le journal dans le Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(
                        [Surveillance.dossierParDefaut.appendingPathComponent("Journal")])
                }
                .disabled(surveillance.mode == .demo)
            }
            if let messageCapture {
                Text(messageCapture).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// « 13 routeurs · 8 appareils finaux · 16 liens radio ».
    static func texteNoeuds(_ m: MaillageZigbee) -> String {
        let routeurs = m.noeuds.filter(\.route).count
        return String(localized: "\(routeurs) routeurs · \(m.noeuds.count - routeurs) appareils finaux · \(MaillageZigbee.reunir(m.liens).count) liens radio")
    }

    /// Libelle d'un port dans le choix : la sonde retenue sous son nom seul ; tout autre port,
    /// ou la sonde retenue sans nom connu (firmware 1.0.0), sous son nom de port et son numero
    /// de serie USB (la MAC d'un C6), qui seul distingue la sonde du pont Halo avant la
    /// premiere connexion.
    static func libellePort(_ p: PortUSB, serieRetenue: String?, nom: String?) -> String {
        if let nom, let serie = p.serie, serie == serieRetenue { return nom }
        return p.libelle
    }

    /// Reseau de la sonde (`etat`) : « canal 25 · parent 1A2B (LQI 180) », le parent sous son nom quand il est connu
    /// (`nomParent`, par son adresse longue) ; « hors réseau » si elle n'est pas membre.
    static func texteReseau(_ e: EtatSonde, nomParent: (String) -> String? = { _ in nil }) -> String {
        guard e.membre else { return String(localized: "hors réseau") }
        var parties: [String] = []
        if let c = e.canal { parties.append(String(localized: "canal \(c)")) }
        if let p = e.parent {
            let n = ProtocoleSonde.ieee(p.ieee).flatMap(nomParent) ?? p.court
            parties.append(p.lqi.map { String(localized: "parent \(n) (LQI \($0))") } ?? String(localized: "parent \(n)"))
        } else {
            parties.append(String(localized: "sans parent (rattachement en cours)"))
        }
        return parties.joined(separator: " · ")
    }

    /// Role de la sonde (`etat`) : « membre, appareil final » ; « hors réseau, recherche » ; « suspendue » en plus.
    static func texteRole(_ e: EtatSonde) -> String {
        var parties = [e.membre ? String(localized: "membre") : String(localized: "hors réseau")]
        if e.role == "final" { parties.append(String(localized: "appareil final")) }
        if !e.membre && e.recherche == true { parties.append(String(localized: "cherche un réseau")) }
        if e.suspendue { parties.append(String(localized: "suspendue")) }
        if let n = e.rattachementsEchoues, n > 0 { parties.append(String(localized: "\(n) rattachements échoués")) }
        return parties.joined(separator: ", ")
    }

    /// Derniere tournee : « 1 min 12 s · 36/36 tables · 15/15 routes · 20 routes reportées · 547 pages · 1 muet »
    /// (« passe complémentaire » apres la duree pour une passe des routes reportees ; les tables de voisins lues sur
    /// les demandees, une tournee sur quatre ; les tables de routage des routeurs, et celles remises a la tournee
    /// suivante faute de budget ; les pages envoyees a la sonde ; les routeurs muets), les pauses sur un refus de
    /// cadence, et « incomplète » quand elle l'est.
    static func texteBilan(_ b: BilanTournee, duree: TimeInterval?) -> String {
        var parties: [String] = []
        if let duree { parties.append(TexteTournee.duree(duree)) }
        if b.complementaire { parties.append(String(localized: "passe complémentaire")) }
        if b.avecTables { parties.append(String(localized: "\(b.tablesLues)/\(b.tablesDemandees) tables")) }
        parties.append(String(localized: "\(b.routesRouteursLues)/\(b.routesRouteursDemandees) routes"))
        if b.routesReportees > 0 { parties.append(String(localized: "\(b.routesReportees) routes reportées")) }
        if b.pages > 0 { parties.append(String(localized: "\(b.pages) pages")) }
        if b.pausesCadence > 0 { parties.append(String(localized: "\(b.pausesCadence) pauses de cadence")) }
        if b.muets > 0 { parties.append(String(localized: "\(b.muets) muets")) }
        if b.sansReponse > b.muets { parties.append(String(localized: "\(b.sansReponse - b.muets) sans réponse")) }
        if b.attentes > 0 { parties.append(String(localized: "\(b.attentes) attentes de la sonde")) }
        if b.lacune != nil { parties.append(String(localized: "incomplète")) }
        return parties.joined(separator: " · ")
    }

    /// « Dernier releve » de la sonde : la date et l'heure (la sonde peut rester des jours sans relever).
    static func texteDernierReleve(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .standard)
    }

    /// Etat de la sonde, precede du nom de la sonde retenue quand il la concerne
    /// (« SONDE-01 · connectee ») ; seul pour un autre port choisi ou sans nom connu.
    static func texteEtatSonde(_ e: SondeMaillage.Etat, nom: String?) -> String {
        let texte = switch e {
        case .sansSonde: String(localized: "aucune sonde choisie")
        case .absente: String(localized: "absente (débranchée ?)")
        case .connexion: String(localized: "connexion…")
        case .connectee: String(localized: "connectée")
        case .refusee(let m): String(localized: "refusée : \(m)")
        case .erreur(let m): String(localized: "erreur : \(m)")
        }
        guard let nom else { return texte }
        return String(localized: "\(nom) · \(texte)")
    }

    private func enregistrerCapture() {
        let donnees: Data
        do {
            guard let d = try surveillance.captureJSON() else { return }
            donnees = d
        } catch {
            messageCapture = error.localizedDescription
            return
        }
        let panneau = NSSavePanel()
        panneau.allowedContentTypes = [.json]
        panneau.nameFieldStringValue = "capture-maillage-zigbee.json"
        guard panneau.runModal() == .OK, let url = panneau.url else { return }
        do {
            try donnees.write(to: url, options: .atomic)
            messageCapture = String(localized: "Capture enregistrée : \(url.lastPathComponent)")
        } catch {
            messageCapture = error.localizedDescription
        }
    }
}

/// Releve de la sonde (Reglages › Sonde) : son role, son parent, son canal et sa suspension (`etat` de la sonde),
/// l'avertissement si elle n'est pas sur le reseau du pont, tournee en cours ou derniere tournee (date, duree, tables
/// lues, muets), derniere erreur. Seulement la sonde connectee : debranchee ou pendant une connexion, ces lignes
/// seraient perimees.
struct ReleveSonde: View {
    @Environment(SondeMaillage.self) private var sonde
    @Environment(Surveillance.self) private var surveillance

    var body: some View {
        if case .connectee = sonde.etat {
            if let e = sonde.etatSonde {
                LabeledContent("Rôle", value: FenetreReglages.texteRole(e))
                LabeledContent("Réseau", value: FenetreReglages.texteReseau(e) { ieee in
                    surveillance.noms.nomConnu(ieee: ieee)
                })
                if e.suspendue {
                    Text("Sonde suspendue : pas de relevé.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if let r = surveillance.noms.maison?.reseau, !r.accueille(e) {
                    Text("La sonde n'est pas sur le réseau du pont (canal ou identifiant du réseau différent).")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            if let a = sonde.avancement, let debut = sonde.debutTournee {
                TimelineView(.periodic(from: debut, by: 1)) { contexte in
                    LabeledContent("Tournée", value: TexteTournee.reglages(a, debut: debut, maintenant: contexte.date))
                }
            } else if let d = sonde.derniereTournee {
                LabeledContent("Dernière tournée", value: FenetreReglages.texteDernierReleve(d))
            }
            if sonde.avancement == nil, let b = sonde.bilan {
                LabeledContent("Bilan", value: FenetreReglages.texteBilan(b, duree: sonde.dureeTournee))
            }
            if sonde.avancement == nil, let passe = sonde.passeComplementaire {
                LabeledContent("Prochaine tournée", value: TexteTournee.passeComplementaire(passe))
            }
            if sonde.avancement == nil, let differee = sonde.tourneeDifferee {
                LabeledContent("Prochaine tournée", value: TexteTournee.tourneeDifferee(differee))
            }
            if let e = sonde.erreurTournee {
                Text(e).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
