import Foundation
import ServiceManagement
import Testing
@testable import MaillageZigbee

/// Seulement la decision, sur des etats donnes : aucun test n'appelle SMAppService.
@Suite("Ouverture a la connexion : premier lancement")
struct OuvertureSessionTests {
    /// Au premier lancement, l'app s'inscrit sauf si elle l'est deja (active, ou
    /// en attente d'approbation). Le 28/09, au premier lancement reel, le systeme
    /// ne la connaissait pas encore (`.notFound`) et rien n'avait ete inscrit.
    @Test func inscriptionAuPremierLancement() {
        #expect(OuvertureSession.inscrireAuPremierLancement(.notRegistered))
        #expect(OuvertureSession.inscrireAuPremierLancement(.notFound), "le systeme ne connait pas encore l'app")
        #expect(!OuvertureSession.inscrireAuPremierLancement(.enabled), "deja inscrite")
        #expect(!OuvertureSession.inscrireAuPremierLancement(.requiresApproval), "inscrite, en attente d'approbation")
    }
}
