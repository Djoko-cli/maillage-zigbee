"""Tests de outils/flasher.py : carte reconnue par son numero de serie USB puis par sa MAC, refus d'une
autre carte. Aucune commande n'est lancee : lancer est remplace par un faux qui note les commandes et rend
des sorties inventees.

  python3 -m unittest discover -s outils/test
"""
import contextlib
import io
import os
import subprocess
import sys
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import flasher  # noqa: E402

PORT = "/dev/cu.usbmodemTEST"

# Arbre d'ioreg invente : un concentrateur, la carte (numero de serie = sa MAC) et son port, puis une
# autre carte sur un autre port.
IOREG = """+-o Concentrateur@01100000  <class IOUSBHostDevice, id 0x100000a01, registered>
  | {
  |   "USB Product Name" = "USB2.0 Hub"
  | }
  | +-o USB JTAG_serial debug unit@01130000  <class IOUSBHostDevice, id 0x100000a02, registered>
  |   {
  |     "USB Serial Number" = "A0:00:00:00:00:01"
  |     "USB Product Name" = "USB JTAG_serial debug unit"
  |   }
  |   +-o IOUSBHostInterface@0  <class IOUSBHostInterface, id 0x100000a03, registered>
  |     +-o AppleUSBACMData  <class AppleUSBACMData, id 0x100000a04, registered>
  |       +-o IOSerialBSDClient  <class IOSerialBSDClient, id 0x100000a05, registered>
  |           {
  |             "IOCalloutDevice" = "/dev/cu.usbmodemTEST"
  |           }
  +-o USB JTAG_serial debug unit@01140000  <class IOUSBHostDevice, id 0x100000b02, registered>
    {
      "USB Serial Number" = "A0:00:00:00:00:02"
    }
    +-o IOSerialBSDClient  <class IOSerialBSDClient, id 0x100000b05, registered>
        {
          "IOCalloutDevice" = "/dev/cu.usbmodemAUTRE"
        }
"""

ESPTOOL5 = """esptool v5.4.0
Connected to ESP32-C6 on /dev/cu.usbmodemTEST:
Chip type:          ESP32-C6FH4 (QFN32) (revision v0.2)
MAC:                a0:00:00:ff:fe:00:00:01
BASE MAC:           a0:00:00:00:00:01
MAC_EXT:            ff:fe
Hard resetting via RTS pin...
"""
ESPTOOL4 = """esptool.py v4.8.1
Chip is ESP32-C6 (QFN32) (revision v0.2)
MAC: a0:00:00:00:00:01
Hard resetting via RTS pin...
"""


class Faux:
    def __init__(self, ioreg=IOREG, mac=ESPTOOL5, codes=None):
        self.ioreg, self.mac, self.codes, self.commandes = ioreg, mac, codes or {}, []

    def __call__(self, commande):
        self.commandes.append(commande)
        if commande[0] == "ioreg":
            return subprocess.CompletedProcess(commande, 0, self.ioreg, "")
        if "read-mac" in commande:
            return subprocess.CompletedProcess(commande, 0, self.mac, "")
        etape = " ".join(commande[commande.index("-e") + 2:]).split(" --upload-port")[0] or "build"
        return subprocess.CompletedProcess(commande, self.codes.get(etape, 0), f"{etape} fait\n", "")

    def etapes(self):
        """Ce qui a ete lance, en clair."""
        noms = []
        for c in self.commandes:
            if c[0] == "ioreg":
                noms.append("ioreg")
            elif "read-mac" in c:
                noms.append("read-mac")
            else:
                noms.append(" ".join(c[c.index("-e") + 2:]).split(" --upload-port")[0] or "build")
        return noms


def flasher_avec(faux, mac="A0:00:00:00:00:01", effacer=False, port=PORT):
    with contextlib.redirect_stdout(io.StringIO()):
        return flasher.flasher(port, mac, "sonde", effacer, lancer=faux, dossier="/depot/sonde")


class TestFlasher(unittest.TestCase):
    def test_normaliser_mac(self):
        self.assertEqual(flasher.normaliser_mac("a0:00:00:00:00:01"), "A00000000001")
        self.assertEqual(flasher.normaliser_mac("A0-00-00-00-00-01"), "A00000000001")
        self.assertIsNone(flasher.normaliser_mac("a0:00:00:ff:fe:00:00:01"))  # 8 octets
        self.assertIsNone(flasher.normaliser_mac(""))
        self.assertIsNone(flasher.normaliser_mac(None))

    def test_mac_lue(self):
        self.assertEqual(flasher.mac_lue(ESPTOOL5), "A00000000001")
        self.assertEqual(flasher.mac_lue(ESPTOOL4), "A00000000001")
        self.assertIsNone(flasher.mac_lue("A fatal error occurred: Failed to connect\n"))
        # esptool 5 sans BASE MAC : la ligne MAC de 8 octets ne vaut pas.
        self.assertIsNone(flasher.mac_lue("MAC: a0:00:00:ff:fe:00:00:01\n"))

    def test_ports_par_serie(self):
        self.assertEqual(flasher.ports_par_serie(IOREG), {"/dev/cu.usbmodemTEST": "A0:00:00:00:00:01",
                                                           "/dev/cu.usbmodemAUTRE": "A0:00:00:00:00:02"})
        self.assertEqual(flasher.ports_par_serie(""), {})

    def test_bonne_carte(self):
        faux = Faux()
        self.assertEqual(flasher_avec(faux), 0)
        self.assertEqual(faux.etapes(), ["ioreg", "build", "read-mac", "-t nobuild -t upload"])
        televersement = faux.commandes[-1]
        self.assertEqual(televersement[televersement.index("-d") + 1], "/depot/sonde")
        self.assertEqual(televersement[-2:], ["--upload-port", PORT])

    def test_effacer_d_abord(self):
        faux = Faux()
        self.assertEqual(flasher_avec(faux, effacer=True), 0)
        self.assertEqual(faux.etapes(), ["ioreg", "build", "read-mac", "-t erase", "-t nobuild -t upload"])

    def test_autre_carte_refusee_sans_la_toucher(self):
        faux = Faux()
        self.assertEqual(flasher_avec(faux, port="/dev/cu.usbmodemAUTRE"), 2)
        self.assertEqual(faux.etapes(), ["ioreg"])  # ni compilation, ni esptool : la carte n'est pas touchee

    def test_port_absent_refuse(self):
        faux = Faux()
        self.assertEqual(flasher_avec(faux, port="/dev/cu.usbmodemABSENT"), 2)
        self.assertEqual(faux.etapes(), ["ioreg"])

    def test_mac_differente_au_dernier_moment(self):
        faux = Faux(mac=ESPTOOL5.replace("a0:00:00:00:00:01", "a0:00:00:00:00:02"))
        self.assertEqual(flasher_avec(faux), 2)
        self.assertEqual(faux.etapes(), ["ioreg", "build", "read-mac"])  # rien n'est ecrit

    def test_carte_muette_refusee(self):
        faux = Faux(mac="A fatal error occurred: Failed to connect\n")
        self.assertEqual(flasher_avec(faux), 2)
        self.assertEqual(faux.etapes(), ["ioreg", "build", "read-mac"])

    def test_compilation_en_echec(self):
        faux = Faux(codes={"build": 1})
        self.assertEqual(flasher_avec(faux), 1)
        self.assertEqual(faux.etapes(), ["ioreg", "build"])

    def test_mac_attendue_illisible(self):
        faux = Faux()
        self.assertEqual(flasher_avec(faux, mac="pas une mac"), 2)
        self.assertEqual(faux.commandes, [])

    def test_echec_de_l_effacement_arrete_tout(self):
        faux = Faux(codes={"-t erase": 1})
        self.assertEqual(flasher_avec(faux, effacer=True), 1)
        self.assertEqual(faux.etapes(), ["ioreg", "build", "read-mac", "-t erase"])

    def test_ecoute(self):
        faux = Faux()
        with contextlib.redirect_stdout(io.StringIO()):
            code = flasher.flasher(PORT, "A0:00:00:00:00:01", "ecoute", False, lancer=faux,
                                   dossier="/depot/outils/ecoute/firmware")
        self.assertEqual(code, 0)
        c = faux.commandes[-1]
        self.assertEqual(c[c.index("-d") + 1], "/depot/outils/ecoute/firmware")
        self.assertEqual(c[c.index("-e") + 1], "ecoute")

    def test_variantes_de_verification_refusees(self):
        for env in ("verif", "verif_routeur", "autre"):
            with contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(flasher.main(["--env", env]), 2)


if __name__ == "__main__":
    unittest.main()
