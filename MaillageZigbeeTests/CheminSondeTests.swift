import Security
import Testing
@testable import MaillageZigbee

@Suite("Chemin de la sonde : USB ou reseau")
struct CheminSondeTests {
    @Test func automatique() {
        #expect(CheminSonde.choisir(.automatique, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminSonde.choisir(.automatique, branchee: true, cleConnue: false, annoncee: false) == .usb)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: true, annoncee: false) == nil)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: false, annoncee: true) == nil)
    }

    @Test func usbSeulement() {
        #expect(CheminSonde.choisir(.usb, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminSonde.choisir(.usb, branchee: false, cleConnue: true, annoncee: true) == nil)
    }

    @Test func reseauSeulement() {
        #expect(CheminSonde.choisir(.reseau, branchee: true, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminSonde.choisir(.reseau, branchee: true, cleConnue: false, annoncee: true) == nil)
        #expect(CheminSonde.choisir(.reseau, branchee: false, cleConnue: true, annoncee: false) == nil)
    }

    /// La cle de la sonde dans le trousseau (spec sonde Wi-Fi, 4.3, constat 9 de la relecture finale) : libelle
    /// « sonde Maillage Zigbee », avec l'adresse longue et l'empreinte, et l'empreinte en commentaire. Lu sans toucher
    /// au trousseau. Le pont garde son libelle.
    @Test func etiquetteDuTrousseau() {
        let cle = "62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D"  // empreinte 91CB5C39
        let t = CheminSonde.trousseau()
        #expect(t.service == CheminSonde.serviceTrousseau)
        let v = t.valeurs(identifiant: "A000000000000001", cle: cle)
        #expect(v[kSecAttrLabel as String] as? String == "sonde Maillage Zigbee A000000000000001 (clé 91CB5C39)")
        #expect(v[kSecAttrComment as String] as? String == "91CB5C39")
        let pont = TrousseauSysteme().valeurs(identifiant: "ABCDEF", cle: "cle")
        #expect(pont[kSecAttrLabel as String] as? String == "Maillage Zigbee - pont Hue ABCDEF")
        #expect(pont[kSecAttrComment as String] == nil)
    }

    @Test func reglageLu() {
        #expect(ReglageChemin(rawValue: "automatique") == .automatique)
        #expect(ReglageChemin(rawValue: "inconnu") == nil)
    }
}
