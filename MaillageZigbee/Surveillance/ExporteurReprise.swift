import AppKit
import Foundation
import MaillageCoeur
import Observation
import ServiceManagement

/// Ce que dit l'app de son avenir : Maillage Zigbee devient Maillage IoT. L'adresse de telechargement est une
/// constante unique, vide jusqu'a la publication de Maillage IoT 1.0.0 (phase 5 de la fusion) : vide, le bandeau du
/// menu ne propose pas de lien.
enum AnnonceMaillageIoT {
    static let adresseTelechargement = ""

    static var url: URL? {
        adresseTelechargement.isEmpty ? nil : URL(string: adresseTelechargement)
    }
}

/// « Exporter pour Maillage IoT… » : choisit l'emplacement par un panneau d'enregistrement, ecrit le dossier d'export
/// (`ExportReprise`, contrat `ContratExport`), annonce le resultat, et propose de ne plus ouvrir l'app a l'ouverture de
/// session. L'export ne modifie rien dans l'app : il lit son dossier de donnees et ses reglages, jamais le trousseau.
@MainActor
@Observable
final class ExporteurReprise {
    private(set) var enCours = false

    @ObservationIgnored private let ouverture: OuvertureSession
    @ObservationIgnored private let source: URL
    @ObservationIgnored private let defauts: UserDefaults
    @ObservationIgnored private let domaine: String?

    /// `source` : le dossier de donnees de l'app ; `domaine` : le domaine des reglages (celui de l'app par defaut, un
    /// autre pour un essai).
    init(ouverture: OuvertureSession, source: URL = Surveillance.dossierParDefaut, defauts: UserDefaults = .standard,
         domaine: String? = nil) {
        self.ouverture = ouverture
        self.source = source
        self.defauts = defauts
        self.domaine = domaine
    }

    /// La version de l'app, pour le manifeste.
    static var versionApp: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    /// Le nom propose au panneau d'enregistrement : le jour de l'export, pour ne pas remplacer le precedent.
    static func nomParDefaut(date: Date = Date(), calendrier: Calendar = .current) -> String {
        let c = calendrier.dateComponents([.year, .month, .day], from: date)
        let jour = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        return String(localized: "Export Maillage Zigbee") + " " + jour
    }

    /// Proposer de ne plus ouvrir l'app a l'ouverture de session : seulement si elle l'est (deux apps se disputeraient
    /// la sonde USB au demarrage).
    nonisolated static func proposerDeDesactiver(_ etat: SMAppService.Status) -> Bool {
        etat == .enabled
    }

    /// Le bilan, en une ligne.
    nonisolated static func bilan(_ r: ExportReprise.Resultat) -> String {
        let copies = r.manifeste.fichiers.count - 1  // reglages.json n'est pas un fichier de l'app
        return String(localized: "Fichiers copiés : \(copies) · réglages repris : \(r.reglages.valeurs.count) · non repris : \(r.manifeste.fichiersNonRepris.count + r.reglages.nonRepris.count)")
    }

    /// Le message d'un export qui echoue : ce qui s'est passe, en mots, avec le fichier quand il est connu, sans valeur du
    /// reseau.
    nonisolated static func texteErreur(_ e: any Error) -> String {
        switch e {
        case ExportReprise.Erreur.destinationDansLesDonnees:
            return String(localized: "Choisissez un autre emplacement : celui-ci contient les données de l'app, ou en fait partie.")
        case ExportReprise.Erreur.assemblage(let cause):
            return String(localized: "L'export n'a pas pu être assemblé, rien n'a été écrit à l'emplacement choisi (\(texteContrat(cause))).")
        case ExportReprise.Erreur.relecture(let cause):
            return String(localized: "L'export n'a pas passé sa relecture : il n'a pas été écrit, et ce qui se trouvait à l'emplacement choisi n'a pas été touché (\(texteContrat(cause))).")
        case ExportReprise.Erreur.ancienNonRestaure(let dossier):
            return String(localized: "L'export n'a pas passé sa relecture et l'ancien dossier n'a pas pu être remis en place. Il est conservé ici : \(dossier.path)")
        case let cause as ContratExport.Erreur:
            return texteContrat(cause)
        default:
            return e.localizedDescription
        }
    }

    /// Une erreur du contrat en mots (cause et fichier), jamais le nom du cas ni le texte generique du systeme.
    nonisolated static func texteContrat(_ e: ContratExport.Erreur) -> String {
        switch e {
        case .formatInconnu(let n): return String(localized: "le format \(n) du dossier d'export n'est pas connu")
        case .appInconnue(let app): return String(localized: "l'app source « \(affichable(app)) » n'est pas connue")
        case .illisible(let cause): return String(localized: "un fichier d'export est illisible : \(affichable(cause))")
        case .cheminInvalide(let c):
            return String(localized: "le nom « \(affichable(c)) » ne convient pas à un export (chemin absolu, vide, trop long, ou avec un caractère de contrôle)")
        case .lienSymbolique(let c): return String(localized: "« \(affichable(c)) » passe par un lien symbolique, qu'un export n'accepte pas")
        case .empreinteInvalide(let c): return String(localized: "l'empreinte du fichier « \(affichable(c)) » est mal formée")
        case .tailleInvalide(let c): return String(localized: "la taille du fichier « \(affichable(c)) » est invalide")
        case .cheminEnDouble(let c): return String(localized: "deux fichiers portent le même nom, à la casse près : « \(affichable(c)) »")
        case .nomReserve(let c): return String(localized: "le nom « \(affichable(c)) » est réservé à l'export")
        case .valeurInconnue(let cle, let type):
            return String(localized: "le réglage « \(affichable(cle)) » a un type inconnu (\(affichable(type)))")
        case .cleInvalide: return String(localized: "un réglage a une clé vide")
        case .cleEnDouble(let cle): return String(localized: "le réglage « \(affichable(cle)) » apparaît deux fois")
        case .manifesteAbsent: return String(localized: "le manifeste de l'export est absent")
        case .reglagesAbsents: return String(localized: "le manifeste de l'export ne liste pas les réglages")
        case .fichierManquant(let c): return String(localized: "le fichier « \(affichable(c)) » est listé au manifeste mais absent du dossier")
        case .fichierEnTrop(let c): return String(localized: "le fichier « \(affichable(c)) » est dans le dossier mais pas listé au manifeste")
        case .fichierInconnu(let c): return String(localized: "le fichier « \(affichable(c)) » n'est pas un fichier connu de l'app")
        case .tailleFausse(let c): return String(localized: "la taille du fichier « \(affichable(c)) » n'est pas celle du manifeste")
        case .empreinteFausse(let c): return String(localized: "le contenu du fichier « \(affichable(c)) » n'a pas l'empreinte du manifeste")
        case .appDifferente: return String(localized: "les réglages et le manifeste viennent de deux apps différentes")
        }
    }

    /// Un nom lu dans le dossier de l'app, montrable : sans caractere de controle, et coupe s'il est demesure.
    nonisolated private static func affichable(_ nom: String) -> String {
        let propre = String(String.UnicodeScalarView(nom.unicodeScalars.map {
            $0.properties.generalCategory == .control ? "?" : $0
        }))
        return propre.count > 80 ? String(propre.prefix(80)) + "…" : propre
    }

    // MARK: Ecriture

    /// Ecrit l'export dans `destination` (le dossier d'export lui-meme), hors du fil principal. Les reglages sont lus
    /// dans le domaine de l'app, ici, avant le depart.
    func ecrire(vers destination: URL, date: Date = Date()) async throws -> ExportReprise.Resultat {
        let reglages = ContratExport.reglagesPersistants(de: .maillageZigbee, domaine: domaine, defauts: defauts)
        let source = source
        let version = Self.versionApp
        enCours = true
        defer { enCours = false }
        return try await Task.detached {
            try ExportReprise.exporter(depuis: source, app: .maillageZigbee, versionApp: version, reglages: reglages,
                                       vers: destination, date: date)
        }.value
    }

    // MARK: Interface

    /// Le menu : le panneau d'enregistrement, l'export, l'annonce, puis la proposition de ne plus ouvrir l'app a
    /// l'ouverture de session.
    func exporter() {
        guard !enCours else { return }
        let panneau = NSSavePanel()
        panneau.title = String(localized: "Exporter pour Maillage IoT")
        panneau.message = String(localized: "Choisissez où écrire le dossier d'export. Maillage IoT le lira pour reprendre vos données.")
        panneau.prompt = String(localized: "Exporter")
        panneau.nameFieldStringValue = Self.nomParDefaut()
        panneau.canCreateDirectories = true
        NSApp.activate()
        guard panneau.runModal() == .OK, let destination = panneau.url else { return }
        Task {
            do {
                let resultat = try await ecrire(vers: destination)
                annoncer(resultat)
            } catch {
                echec(error)
            }
        }
    }

    private func annoncer(_ r: ExportReprise.Resultat) {
        ouverture.actualiser()
        let alerte = NSAlert()
        alerte.messageText = String(localized: "Export terminé")
        alerte.informativeText = Self.bilan(r) + "\n\n" + String(localized: "Dossier : \(r.dossier.lastPathComponent)")
        alerte.addButton(withTitle: String(localized: "OK"))
        alerte.addButton(withTitle: String(localized: "Afficher dans le Finder"))
        NSApp.activate()
        if alerte.runModal() == .alertSecondButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([r.dossier])
        }
        proposerDeNePlusOuvrir()
    }

    /// Le retrait de l'ouverture de session a echoue : le systeme a refuse, ou l'app reste inscrite.
    nonisolated static func retraitEchoue(erreur: String?, etat: SMAppService.Status) -> Bool {
        erreur != nil || etat == .enabled
    }

    nonisolated static func texteRetraitEchoue(erreur: String?) -> String {
        let base = String(localized: "Maillage Zigbee s'ouvrira encore à l'ouverture de session. Vous pouvez le retirer dans les Réglages, onglet Général, ou dans les Réglages Système.")
        return erreur.map { base + " (" + $0 + ")" } ?? base
    }

    private func proposerDeNePlusOuvrir() {
        guard Self.proposerDeDesactiver(ouverture.etat) else { return }
        let alerte = NSAlert()
        alerte.messageText = String(localized: "Ne plus ouvrir Maillage Zigbee à l'ouverture de session ?")
        alerte.informativeText = String(localized: "Maillage IoT et Maillage Zigbee se disputeraient la sonde USB au démarrage du Mac. Vous pouvez le rétablir dans les Réglages, onglet Général.")
        alerte.addButton(withTitle: String(localized: "Ne plus ouvrir"))
        alerte.addButton(withTitle: String(localized: "Garder"))
        NSApp.activate()
        if alerte.runModal() == .alertFirstButtonReturn {
            ouverture.basculer(false)
            if Self.retraitEchoue(erreur: ouverture.erreur, etat: ouverture.etat) { retraitRate() }
        }
    }

    private func retraitRate() {
        let alerte = NSAlert()
        alerte.alertStyle = .warning
        alerte.messageText = String(localized: "L'ouverture à la session n'a pas été retirée")
        alerte.informativeText = Self.texteRetraitEchoue(erreur: ouverture.erreur)
        alerte.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alerte.runModal()
    }

    private func echec(_ e: any Error) {
        let alerte = NSAlert()
        alerte.alertStyle = .warning
        alerte.messageText = String(localized: "L'export n'a pas abouti")
        alerte.informativeText = Self.texteErreur(e)
        alerte.addButton(withTitle: String(localized: "OK"))
        NSApp.activate()
        alerte.runModal()
    }
}
