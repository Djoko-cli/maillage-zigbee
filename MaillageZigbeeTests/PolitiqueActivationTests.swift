import AppKit
import Testing
@testable import MaillageZigbee

@MainActor
@Suite("Politique d'activation : pas d'icone dans le Dock sous les tests")
struct PolitiqueActivationTests {
    /// Les fenetres hors ecran des tests ouvrent `ouverte()` : l'hote de test ne doit pas devenir
    /// une app reguliere, sinon le Dock garde une icone fantome apres chaque lancement.
    @Test func sansIconeSousLesTests() {
        PolitiqueActivation.ouverte()
        defer { PolitiqueActivation.fermee() }
        #expect(NSApp.activationPolicy() == .accessory)
    }
}
