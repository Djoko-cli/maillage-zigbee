import Foundation
import Testing
@testable import MaillageZigbee

@Suite("Langue de l'app")
struct LangueTests {
    @Test func codes() {
        #expect(LangueApp.systeme.codes == nil)
        #expect(LangueApp.francais.codes == ["fr"])
        #expect(LangueApp.anglais.codes == ["en"])
        #expect(LangueApp.depuis(nil) == .systeme)
        #expect(LangueApp.depuis(["fr-FR", "en"]) == .francais)
        #expect(LangueApp.depuis(["en"]) == .anglais)
        #expect(LangueApp.depuis(["de"]) == .systeme, "une langue sans traduction : celle du Mac")
    }

    /// Le choix vit dans le domaine de l'app seulement : "Systeme" retire la cle.
    @Test func lectureEtEcriture() throws {
        let domaine = "maillage-tests-langue"
        let preferences = try #require(UserDefaults(suiteName: domaine))
        defer { preferences.removePersistentDomain(forName: domaine) }
        #expect(LangueApp.lire(preferences, domaine: domaine) == .systeme)
        LangueApp.ecrire(.anglais, preferences)
        #expect(LangueApp.lire(preferences, domaine: domaine) == .anglais)
        LangueApp.ecrire(.francais, preferences)
        #expect(LangueApp.lire(preferences, domaine: domaine) == .francais)
        LangueApp.ecrire(.systeme, preferences)
        #expect(LangueApp.lire(preferences, domaine: domaine) == .systeme)
        #expect(preferences.persistentDomain(forName: domaine)?[LangueApp.cle] == nil)
    }
}
