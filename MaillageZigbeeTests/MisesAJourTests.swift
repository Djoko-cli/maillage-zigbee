import Foundation
import Security
import Testing
@testable import MaillageZigbee

/// Les mises a jour (Sparkle 2) : ce que porte l'app, et le moteur jamais demarre sous les tests.
@MainActor
@Suite("Mises a jour : Sparkle")
struct MisesAJourTests {
    /// L'Info.plist : la version, le flux des versions publiees, la cle publique et les reglages de Sparkle.
    @Test func infoPlist() throws {
        let info = try #require(Bundle.main.infoDictionary)
        #expect(info["CFBundleShortVersionString"] as? String == "1.0.0")
        #expect(Int(info["CFBundleVersion"] as? String ?? "") != nil, "un nombre, que compare Sparkle")
        #expect(info["SUFeedURL"] as? String
                == "https://raw.githubusercontent.com/Djoko-cli/maillage-zigbee/main/appcast.xml")
        // La cle publique Ed25519 (project.yml, CLE_MISES_A_JOUR), jamais vide : sans elle, Sparkle refuserait
        // toute mise a jour.
        let cle = try #require(info["SUPublicEDKey"] as? String)
        #expect(cle == "nRIVHOXbEktqGduJ4ukxhjZzlUaiE/yqR3sgbW9Ie6E=")
        #expect(Data(base64Encoded: cle)?.count == 32, "une cle publique Ed25519 de 32 octets : \(cle)")
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info["SUScheduledCheckInterval"] as? Int == 86_400)
        #expect(info["SUAutomaticallyUpdate"] as? Bool == true)
        #expect(info["SUEnableInstallerLauncherService"] as? Bool == true)
    }

    /// Les droits du bac a sable : les deux services de Sparkle, rien de plus (le telechargement passe par
    /// `network.client`).
    @Test func droitsMachLookup() throws {
        let tache = try #require(SecTaskCreateFromSelf(nil))
        let cle = "com.apple.security.temporary-exception.mach-lookup.global-name" as CFString
        let valeur = SecTaskCopyValueForEntitlement(tache, cle, nil) as? [String] ?? []
        // Sous les tests, Xcode ajoute ceux de ses outils (com.apple…) a la compilation Debug.
        #expect(valeur.filter { !$0.hasPrefix("com.apple.") } == ["fr.djoko.maillage.zigbee-spks", "fr.djoko.maillage.zigbee-spki"])
        let bac = SecTaskCopyValueForEntitlement(tache, "com.apple.security.app-sandbox" as CFString, nil) as? Bool
        #expect(bac == true)
        // Le telechargement des mises a jour passe par le reseau de l'app, pas par un service a part.
        let reseau = SecTaskCopyValueForEntitlement(tache, "com.apple.security.network.client" as CFString, nil) as? Bool
        #expect(reseau == true)
    }

    /// La decision de demarrer le moteur : oui dans l'app publiee ordinaire, non en demo, non sous les tests (Xcode
    /// pose `XCTestConfigurationFilePath`), non dans une compilation de travail (numero 1, ou absent). Sans le cas
    /// « oui », une app qui ne cherche jamais passerait.
    @Test func decisionDeDemarrer() {
        #expect(MisesAJour.doitDemarrer(demo: false, numero: "435", environnement: [:]))
        #expect(MisesAJour.doitDemarrer(demo: false, numero: "435", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "1", environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "1", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: nil, environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435", environnement: [:]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435", environnement: ["HOME": "/tmp", "PATH": "/usr/bin"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "435",
                                         environnement: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
        #expect(!MisesAJour.doitDemarrer(demo: false, numero: "435",
                                         environnement: ["HOME": "/tmp", "XCTestConfigurationFilePath": ""]))
        #expect(!MisesAJour.doitDemarrer(demo: true, numero: "435",
                                         environnement: ["XCTestConfigurationFilePath": "/tmp/x.xctestconfiguration"]))
    }

    /// Celle de l'app, creee a son lancement, n'est pas demarree sous les tests : aucune recherche, aucun reseau.
    @Test func moteurArreteSousLesTests() throws {
        #expect(!MisesAJour.demarrerAuLancement(demo: false))
        let m = try #require(MisesAJour.deLApp, "creee au lancement de l'app")
        #expect(!m.demarre)
        #expect(!m.peutRechercher, "un moteur arrete ne recherche pas")
    }
}
