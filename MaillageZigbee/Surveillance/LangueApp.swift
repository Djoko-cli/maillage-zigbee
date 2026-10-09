import AppKit
import Foundation

/// Langue de l'app : celle du Mac, ou imposee. Le choix est la cle
/// `AppleLanguages` du domaine de l'app (la meme que Reglages Systeme >
/// Langue et region > Applications), lue par macOS au lancement : il faut
/// relancer l'app pour qu'il s'applique.
enum LangueApp: String, CaseIterable, Identifiable {
    case systeme, francais, anglais

    static let cle = "AppleLanguages"

    var id: String { rawValue }

    /// Valeur de la cle (nil : pas de cle, la langue du Mac).
    var codes: [String]? {
        switch self {
        case .systeme: nil
        case .francais: ["fr"]
        case .anglais: ["en"]
        }
    }

    /// Choix correspondant a une valeur de la cle ; une langue sans traduction : celle du Mac.
    static func depuis(_ codes: [String]?) -> LangueApp {
        switch codes?.first?.prefix(2) {
        case "fr"?: .francais
        case "en"?: .anglais
        default: .systeme
        }
    }

    /// Choix enregistre dans le domaine de l'app seulement (pas le domaine global du Mac).
    static func lire(_ preferences: UserDefaults = .standard,
                     domaine: String = Bundle.main.bundleIdentifier ?? "") -> LangueApp {
        depuis(preferences.persistentDomain(forName: domaine)?[cle] as? [String])
    }

    static func ecrire(_ langue: LangueApp, _ preferences: UserDefaults = .standard) {
        if let c = langue.codes {
            preferences.set(c, forKey: cle)
        } else {
            preferences.removeObject(forKey: cle)
        }
    }

    /// Choix en vigueur depuis le lancement de l'app.
    static let auLancement = lire()

    /// Ouvre une nouvelle instance de l'app, puis quitte celle-ci.
    @MainActor
    static func relancer() async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
        NSApp.terminate(nil)
    }
}
