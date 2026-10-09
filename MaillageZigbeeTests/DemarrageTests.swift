import Foundation
import Testing
@testable import MaillageZigbee

@Suite("Demarrage de l'app (tests heberges)")
struct DemarrageTests {
    @Test func identite() {
        #expect(Bundle.main.bundleIdentifier == "fr.djoko.maillage.zigbee")
        #expect(Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? Bool == true, "app de la barre des menus")
        let services = Bundle.main.object(forInfoDictionaryKey: "NSBonjourServices") as? [String]
        #expect(services == ["_hue._tcp"], "le pont Hue, et lui seul")
    }
}
