"""Tests de outils/sonde_reseau.py : enveloppe H1 (vecteurs du pont Halo,
benq tools/host_tests/test_h1.cpp), requetes et reponses par le reseau."""
import contextlib
import io
import os
import socket
import stat
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import sonde_reseau as sr  # noqa: E402

PSK = bytes(range(32))
NA = bytes.fromhex("A0A1A2A3A4A5A6A7A8A9AAABACADAEAF")
SALUT = "H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D"
DEFI = "H1 DEFI 1234ABCD 505152535455565758595A5B5C5D5E5F BFF13F71B42243E6017D2807F8E6171F"
KS = "20D6D83D97ED44F2BBF8CE56389BD475CBE2B625CE6CE24768B6B4C1C625012F"
MSG_A = "H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE id=1 json 1"
HDR_C = "H1 1234ABCD 1 347A2E6A129BC822ECFF39BEC910451C "
JSON_C = '{"v":1,"t":"hb","n":7,"ms":1234}'


class H1(unittest.TestCase):
    def test_kid(self):
        self.assertEqual(sr.kid(PSK), "630DCD29")

    def test_salut(self):
        self.assertEqual(sr.salut(PSK, NA), SALUT)

    def test_defi(self):
        self.assertEqual(sr.verifier_defi(DEFI, PSK, NA), ("1234ABCD", "505152535455565758595A5B5C5D5E5F"))
        self.assertIsNone(sr.verifier_defi(DEFI.replace("BFF1", "BFF2"), PSK, NA))

    def test_session(self):
        s = sr.Session(PSK, NA, "505152535455565758595A5B5C5D5E5F", "1234ABCD")
        self.assertEqual(s.ks.hex().upper(), KS)
        self.assertEqual(s.sceller("id=1 json 1"), MSG_A)
        self.assertEqual(s.ouvrir(HDR_C + JSON_C), JSON_C)
        self.assertIsNone(s.ouvrir(HDR_C + JSON_C), "rejeu refuse")

    def test_session_mac_faux(self):
        s = sr.Session(PSK, NA, "505152535455565758595A5B5C5D5E5F", "1234ABCD")
        self.assertIsNone(s.ouvrir(HDR_C.replace("347A", "347B") + JSON_C))


class Charges(unittest.TestCase):
    def test_reponse(self):
        self.assertEqual(sr.couper_rid('12 {"v":1}'), (12, '{"v":1}'))
        self.assertEqual(sr.couper_rid('0 {"v":1,"t":"signal"}'), (0, '{"v":1,"t":"signal"}'))
        self.assertIsNone(sr.couper_rid("x {}"))

    def test_hexa_wifi(self):
        self.assertEqual(sr.ligne_wifi("Mon Wifi", "motdepasse", 7), "wifi 4D6F6E2057696669 6D6F7464657061737365 7")
        self.assertEqual(sr.ligne_wifi("Ouvert", "", 8), "wifi 4F7576657274 - 8")
        self.assertEqual(sr.ligne_wifi("Café", "motdepasse", 1)[:15], "wifi 436166C3A9")
        with self.assertRaises(ValueError):
            sr.ligne_wifi("X", "court", 1)


class Cle(unittest.TestCase):
    def test_ranger_cle_droits_600_meme_si_fichier_existant(self):
        cle = "AB" * 32
        with tempfile.TemporaryDirectory() as dossier:
            chemin = os.path.join(dossier, "cle_reseau.local")
            with open(chemin, "w") as f:
                f.write("ancienne\n")
            os.chmod(chemin, 0o644)
            sr.ranger_cle(cle, chemin)
            self.assertEqual(stat.S_IMODE(os.stat(chemin).st_mode), 0o600)
            with open(chemin) as f:
                self.assertEqual(f.read(), cle + "\n")


class FauxSocket:
    """Socket de test : rend les morceaux donnes, puis un timeout (comme une vraie socket sans donnee)."""

    def __init__(self, morceaux):
        self.morceaux = list(morceaux)
        self.envoye = b""

    def sendall(self, donnees):
        self.envoye += donnees

    def settimeout(self, _):
        pass

    def recv(self, _):
        if not self.morceaux:
            raise socket.timeout("aucune donnee")
        return self.morceaux.pop(0)


def scelle(session, ctr, charge):
    """Ligne H1 telle qu'une sonde la rend (MAC C), pour la session donnee."""
    mac = sr._mac(session.ks, f"C|{session.sid}|{ctr}|".encode() + charge.encode())
    return f"H1 {session.sid} {ctr} {mac} {charge}\n".encode()


def client_de_test(morceaux):
    """Client sans poignee de main (la session est posee directement), sur une FauxSocket."""
    c = sr.Client.__new__(sr.Client)
    c.s = FauxSocket(morceaux)
    c.tampon = b""
    c.session = sr.Session(PSK, NA, "505152535455565758595A5B5C5D5E5F", "1234ABCD")
    c.rid = 0
    return c


class Reseau(unittest.TestCase):
    def test_commande_sans_reponse_finale_leve_timeout(self):
        c = client_de_test([])
        with self.assertRaises(TimeoutError):
            c.commande("table 0000 1", delai=0.2)

    def test_commande_liste_coupee_leve_timeout(self):
        c = client_de_test([])
        c.s = FauxSocket([scelle(c.session, 1, '1 {"v":1,"t":"table","suite":true}')])
        with self.assertRaises(TimeoutError):
            c.commande("table 0000 1", delai=0.2)

    def test_commande_rend_la_reponse_finale(self):
        c = client_de_test([])
        c.s = FauxSocket([scelle(c.session, 1, '1 {"v":1,"t":"etat"}')])
        self.assertEqual(c.commande("etat", delai=0.2), [{"v": 1, "t": "etat"}])

    def test_code_de_sortie_erreur(self):
        self.assertEqual(sr.code_de_sortie([{"t": "erreur", "erreur": "refuse"}]), 1)
        self.assertEqual(sr.code_de_sortie([{"t": "etat"}]), 0)


class SondeFausse:
    def __init__(self, reponse):
        self.reponse = reponse

    def commande(self, texte, types):
        self.texte = texte
        return self.reponse


class Wifi(unittest.TestCase):
    def lancer(self, reponse, tty=True):
        entree = mock.Mock(isatty=mock.Mock(return_value=tty))
        with mock.patch("sys.stdin", entree), \
                mock.patch("builtins.input", return_value="Mon Wifi") as saisie, \
                mock.patch("getpass.getpass", return_value="motdepasse") as secret, \
                mock.patch.object(sr, "_sonde_usb", return_value=SondeFausse(reponse)), \
                contextlib.redirect_stdout(io.StringIO()) as sortie:
            code = sr.cmd_wifi()
        return code, saisie, secret, sortie.getvalue()

    def test_pas_de_reponse_code_1(self):
        self.assertEqual(self.lancer(None)[0], 1)

    def test_erreur_code_1(self):
        self.assertEqual(self.lancer({"t": "erreur", "erreur": "ecriture"})[0], 1)

    def test_configure_code_0(self):
        self.assertEqual(self.lancer({"t": "wifi", "configure": True})[0], 0)

    def test_sans_terminal_refuse_avant_toute_saisie(self):
        code, saisie, secret, texte = self.lancer(None, tty=False)
        self.assertEqual(code, 1)
        saisie.assert_not_called()
        secret.assert_not_called()
        self.assertIn("terminal", texte)


if __name__ == "__main__":
    unittest.main()
