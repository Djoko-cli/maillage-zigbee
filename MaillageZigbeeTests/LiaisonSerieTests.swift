import Foundation
import Testing
@testable import MaillageZigbee

@Suite("Liaison serie de la sonde")
struct LiaisonSerieTests {
    /// Seuls les /dev/cu.* s'ouvrent : un /dev/tty.* attendrait DCD.
    @Test func cheminCu() {
        #expect(throws: ErreurPort.self) { try PortSerie.ouvrir("/dev/tty.maillage-inexistant") }
        do {
            _ = try PortSerie.ouvrir("/dev/tty.maillage-inexistant")
        } catch {
            #expect("\(error)".contains("/dev/cu.*"))
        }
    }

    /// errno est lu avant le message, que sa construction (`String(localized:)`) peut
    /// changer : un EBUSY reste un EBUSY (port occupe).
    @Test func errnoAvantLeMessage() {
        errno = EBUSY
        let e = PortSerie.erreur({ errno = ENOENT; return "ouverture" }())
        #expect(e.errno == EBUSY)
    }

    /// Un port absent echoue proprement, sans descripteur laisse ouvert.
    @Test func portAbsent() {
        let l = LiaisonSerie(chemin: "/dev/cu.maillage-inexistant")
        #expect(throws: ErreurPort.self) { _ = try l.ouvrir() }
    }

    @Test func ports() {
        let c6 = PortUSB(chemin: "/dev/cu.usbmodem11301", vid: 0x303A, pid: 0x1001, serie: "A0:00:00:00:00:01",
                         produit: "USB JTAG/serial debug unit")
        let ecran = PortUSB(chemin: "/dev/cu.usbmodemECRAN0001", vid: 0x043E, pid: 0x9A39, serie: "ECRAN-FACTICE-01",
                            produit: "LG Monitor Controls")
        #expect(c6.estEspressif)
        #expect(!ecran.estEspressif)
        #expect(c6.libelle == "usbmodem11301 · A0:00:00:00:00:01")
        #expect(PortsUSB.trier([ecran, c6]) == [c6, ecran], "Espressif en tete")
    }
}
