"""Tests de outils/sonde_usb.py : lignes machine, reponses en plusieurs lignes, commandes. Aucun port serie :
la sonde est une paire de sockets locale, dont l'autre bout (la « carte ») repond depuis un fil d'execution
une fois la commande recue ; le temps de la sonde est simule. Valeurs inventees.

  python3 -m unittest discover -s outils/test
"""
import json
import os
import socket
import sys
import threading
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import sonde_usb  # noqa: E402


def ligne(m):
    return b"\x1e" + json.dumps(m, separators=(",", ":")).encode() + b"\n"


class Horloge:
    """Avance de 0,5 s a chaque lecture : un delai de 10 s dure 20 lectures, et une attente sans donnees
    (select, 0,1 s au plus) ne dure que 2 s reelles."""

    def __init__(self):
        self.t = 1000.0

    def __call__(self):
        self.t += 0.5
        return self.t


class Carte(threading.Thread):
    """L'autre bout : attend la commande attendue, puis envoie ses lignes."""

    def __init__(self, sock, attendu, octets):
        super().__init__(daemon=True)
        self.sock, self.attendu, self.octets = sock, attendu, octets
        self.start()

    def run(self):
        recu = b""
        while self.attendu not in recu:
            morceau = self.sock.recv(1000)
            if not morceau:
                return
            recu += morceau
        self.sock.sendall(self.octets)


class TestCouper(unittest.TestCase):
    def test_lignes_completes_et_reste(self):
        tampon = ligne({"t": "etat", "membre": True}) + b"journal de la carte\n" + b"\x1e{\"t\":\"vo"
        elements, reste = sonde_usb.couper(tampon)
        self.assertEqual(elements, [{"t": "etat", "membre": True}, "journal de la carte"])
        self.assertEqual(reste, b"\x1e{\"t\":\"vo")

    def test_dernier_rs_et_journal_colle(self):
        tampon = b"I (123) zb: debut\x1e{\"t\":\"x\"}\x1e{\"t\":\"bonjour\"}\r\n"
        elements, reste = sonde_usb.couper(tampon)
        self.assertEqual(elements, ["I (123) zb: debut\x1e{\"t\":\"x\"}", {"t": "bonjour"}])
        self.assertEqual(reste, b"")

    def test_ligne_machine_illisible(self):
        elements, _ = sonde_usb.couper(b"\x1e{\"t\":\"etat\"\n\x1e[1,2]\n")
        self.assertEqual(elements, ["{\"t\":\"etat\"", "[1,2]"])

    def test_fusionner(self):
        lignes = [{"t": "table", "id": 7, "liste": [1, 2], "suite": True},
                  {"t": "table", "id": 7, "liste": [3], "suite": False}]
        self.assertEqual(sonde_usb.fusionner(lignes), {"t": "table", "id": 7, "liste": [1, 2, 3]})
        self.assertEqual(sonde_usb.fusionner([{"t": "etat", "membre": False}]), {"t": "etat", "membre": False})
        self.assertIsNone(sonde_usb.fusionner([]))


class TestSonde(unittest.TestCase):
    def setUp(self):
        self.mac, self.carte = socket.socketpair()
        self.mac.setblocking(False)
        self.journal = []
        self.sonde = sonde_usb.Sonde(self.mac.fileno(), lambda s, e: self.journal.append((s, e)), Horloge())

    def tearDown(self):
        self.mac.close()
        self.carte.close()

    def test_table_en_deux_lignes_parmi_d_autres(self):
        Carte(self.carte, b"table 1A2B 7\n",
              ligne({"v": 1, "t": "bonjour", "produit": "sonde-zigbee"})  # bonjour du demarrage : ignore
              + ligne({"v": 1, "t": "table", "id": 6, "ok": False, "erreur": "delai"})  # autre id : ignore
              + ligne({"v": 1, "t": "table", "id": 7, "ok": True, "liste": [{"court": "1A2B"}], "suite": True})
              + b"journal\n"
              + ligne({"v": 1, "t": "table", "id": 7, "ok": True, "liste": [{"court": "3C4D"}], "suite": False})
              + ligne({"v": 1, "t": "etat", "membre": True, "n": 1}))
        m = self.sonde.commande("table 1A2B 7", ("table",), id=7)
        self.assertEqual(m["liste"], [{"court": "1A2B"}, {"court": "3C4D"}])
        self.assertNotIn("suite", m)
        self.assertIn(("envoi", "table 1A2B 7"), self.journal)
        self.assertIn(("recu", "journal"), self.journal)
        # L'etat arrive avec la table est en retard pour la commande suivante : ecarte (mais journalise).
        Carte(self.carte, b"etat\n", ligne({"v": 1, "t": "etat", "membre": True, "n": 2}))
        self.assertEqual(self.sonde.commande("etat", ("etat",))["n"], 2)
        self.assertIn(("recu", {"v": 1, "t": "etat", "membre": True, "n": 1}), self.journal)

    def test_reponse_en_retard_ecartee(self):
        self.carte.sendall(ligne({"v": 1, "t": "etat", "membre": False}))  # reste d'une commande precedente
        Carte(self.carte, b"etat\n", ligne({"v": 1, "t": "etat", "membre": True}))
        self.assertTrue(self.sonde.commande("etat", ("etat",))["membre"])

    def test_erreur_generale(self):
        Carte(self.carte, b"table 1A2 7\n", ligne({"v": 1, "t": "erreur", "erreur": "syntaxe"}))
        self.assertEqual(self.sonde.commande("table 1A2 7", ("table",), id=7)["erreur"], "syntaxe")

    def test_sans_reponse(self):
        self.assertIsNone(self.sonde.commande("etat", ("etat",), delai=2.0))

    def test_port_perdu(self):
        self.carte.close()
        with self.assertRaises(sonde_usb.PortPerdu):
            self.sonde.commande("etat", ("etat",), delai=2.0)

    def test_verifier(self):
        Carte(self.carte, b"bonjour\n", ligne({"v": 1, "t": "bonjour", "produit": "sonde-zigbee", "nom": "SONDE-Z1"}))
        self.assertEqual(self.sonde.verifier()["nom"], "SONDE-Z1")
        Carte(self.carte, b"bonjour\n", ligne({"v": 1, "t": "bonjour", "produit": "sonde-maillage"}))
        with self.assertRaises(ValueError):
            self.sonde.verifier()


if __name__ == "__main__":
    unittest.main()
