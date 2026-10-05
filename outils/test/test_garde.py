"""Tests de outils/garde.py : un depot git temporaire, des identifiants inventes.

  python3 -m unittest discover -s outils/test
"""
import contextlib
import io
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import garde  # noqa: E402


def depot(fichiers, garde_local=None):
    d = tempfile.mkdtemp()
    subprocess.run(["git", "init", "-q", d], check=True)
    for nom, texte in fichiers.items():
        chemin = os.path.join(d, nom)
        os.makedirs(os.path.dirname(chemin), exist_ok=True)
        with open(chemin, "w") as f:
            f.write(texte)
        subprocess.run(["git", "-C", d, "add", nom], check=True)
    if garde_local is not None:
        with open(os.path.join(d, "garde.local.txt"), "w") as f:
            f.write(garde_local)
    return d


def lancer(d):
    sortie = io.StringIO()
    with contextlib.redirect_stdout(sortie):
        code = garde.main(d)
    return code, sortie.getvalue()


class TestGarde(unittest.TestCase):
    def test_normaliser(self):
        self.assertEqual(garde.normaliser("a0:00:00:00:00:00:00:99"), "A000000000000099")
        self.assertEqual(garde.normaliser("0x1a2b"), "1A2B")
        self.assertEqual(garde.normaliser("0X1A2B"), "1A2B")
        self.assertEqual(garde.normaliser("a0-00-00-00-00-00-00-99"), "A000000000000099")
        self.assertEqual(garde.normaliser("a000 0000 0000 0099"), "A000000000000099")

    def test_lire_identifiants(self):
        d = tempfile.mkdtemp()
        chemin = os.path.join(d, "g.txt")
        with open(chemin, "w") as f:
            f.write("# commentaire\n\nA0:00:00:00:00:00:00:99\n0x9F8E\n9f8e\n")
        self.assertEqual(garde.lire_identifiants(chemin), ["9F8E", "A000000000000099"])

    def test_sans_fichier_local(self):
        code, sortie = lancer(depot({"a.txt": "A000000000000099"}))
        self.assertEqual(code, 0)
        self.assertIn("absent", sortie)

    def test_rien_de_reel(self):
        code, sortie = lancer(depot({"a.txt": "rien ici", "b/c.md": "1A2B"}, "A000000000000099\n9F8E\n"))
        self.assertEqual(code, 0)
        self.assertIn("aucun", sortie)

    def test_identifiants_trouves_quelle_que_soit_la_forme(self):
        d = depot({"a.txt": "adresse a0:00:00:00:00:00:00:99", "b.cpp": "court = 0x9f8e;"},
                  "A000000000000099\n9F8E\n")
        code, sortie = lancer(d)
        self.assertEqual(code, 1)
        self.assertIn("a.txt", sortie)
        self.assertIn("b.cpp", sortie)
        self.assertNotIn("A000000000000099", sortie)  # jamais l'identifiant entier a l'ecran

    def test_separateurs_tirets_et_espaces(self):
        d = depot({"a.txt": "mac A0-00-00-00-00-00-00-99", "b.txt": "mac a000 0000 0000 0099"},
                  "A000000000000099\n")
        code, sortie = lancer(d)
        self.assertEqual(code, 1)
        self.assertIn("a.txt", sortie)
        self.assertIn("b.txt", sortie)

    def test_nom_accentue(self):
        d = depot({"a.md": "La lampe du Salon à côté"}, "Salon à côté\n")
        code, sortie = lancer(d)
        self.assertEqual(code, 1)
        self.assertIn("a.md", sortie)

    def test_depuis_un_worktree(self):
        d = depot({"a.txt": "adresse A000000000000099"}, "A000000000000099\n")
        subprocess.run(["git", "-C", d, "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "x"],
                       check=True)
        arbre = os.path.join(tempfile.mkdtemp(), "arbre")
        subprocess.run(["git", "-C", d, "worktree", "add", "-q", arbre], check=True)
        self.assertFalse(os.path.exists(os.path.join(arbre, "garde.local.txt")))
        code, sortie = lancer(arbre)
        self.assertEqual(code, 1)  # le fichier du depot principal sert
        self.assertIn("a.txt", sortie)

    def test_fichier_non_suivi_ignore(self):
        d = depot({"a.txt": "rien"}, "A000000000000099\n")
        with open(os.path.join(d, "hors.txt"), "w") as f:
            f.write("A000000000000099")
        self.assertEqual(lancer(d)[0], 0)


if __name__ == "__main__":
    unittest.main()
