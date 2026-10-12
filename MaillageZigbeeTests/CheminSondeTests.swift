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

    @Test func reglageLu() {
        #expect(ReglageChemin(rawValue: "automatique") == .automatique)
        #expect(ReglageChemin(rawValue: "inconnu") == nil)
    }
}
