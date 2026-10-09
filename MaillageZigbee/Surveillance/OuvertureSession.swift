import Foundation
import Observation
import ServiceManagement

/// Ouverture a la connexion (SMAppService) : inscrite une fois au premier
/// lancement, puis a la main dans le menu et les reglages. L'etat est relu a
/// chaque apparition du menu et des reglages : une approbation ou un retrait
/// faits dans Reglages Systeme s'y voient.
@MainActor
@Observable
final class OuvertureSession {
    private(set) var etat: SMAppService.Status = SMAppService.mainApp.status
    private(set) var erreur: String?

    static let clePremierLancement = "ouvertureSessionProposee"

    var active: Bool { etat == .enabled }
    var approbationRequise: Bool { etat == .requiresApproval }

    func basculer(_ oui: Bool) {
        do {
            if oui {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            erreur = nil
        } catch {
            erreur = error.localizedDescription
        }
        actualiser()
    }

    /// Relit l'etat aupres du systeme.
    func actualiser() {
        etat = SMAppService.mainApp.status
    }

    /// Au premier lancement : ouvrir a la connexion (choix de la spec), une seule fois.
    func proposerAuPremierLancement(preferences: UserDefaults = .standard) {
        guard !preferences.bool(forKey: Self.clePremierLancement) else { return }
        preferences.set(true, forKey: Self.clePremierLancement)
        if Self.inscrireAuPremierLancement(etat) { basculer(true) }
    }

    /// Inscrire l'app au premier lancement ? Oui, sauf si elle l'est deja (active,
    /// ou en attente d'approbation) : `.notRegistered`, et aussi `.notFound`, l'etat
    /// d'une app que le systeme ne connait pas encore (le 28/09, au premier lancement).
    nonisolated static func inscrireAuPremierLancement(_ etat: SMAppService.Status) -> Bool {
        etat != .enabled && etat != .requiresApproval
    }

    func ouvrirReglagesSysteme() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
