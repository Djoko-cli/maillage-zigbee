"""Tests de outils/essai_sonde.py : parcours en largeur d'une tournee et son resume, sur un reseau invente.
Aucun port serie.

  python3 -m unittest discover -s outils/test
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")))
import essai_sonde  # noqa: E402


def entree(court, type_, ieee=None):
    return {"court": court, "ieee": ieee or "A00000000000" + court, "type": type_, "lqi": 200}


# Pont 0000 ; routeurs 1A2B, 3C4D, 5E6F ; appareil final 7A8B (enfant de 3C4D) ; 5E6F muet.
RESEAU = {
    "0000": {"ok": True, "pages": 1, "partielle": False,
             "liste": [entree("1A2B", "routeur"), entree("3C4D", "routeur")]},
    "1A2B": {"ok": True, "pages": 1, "partielle": False,
             "liste": [entree("0000", "coordinateur"), entree("3C4D", "routeur"), entree("5E6F", "routeur")]},
    "3C4D": {"ok": True, "pages": 2, "partielle": True,
             "liste": [entree("0000", "coordinateur"), entree("1A2B", "routeur"), entree("7A8B", "final")]},
    "5E6F": {"ok": False, "erreur": "delai"},
}


class TestTournee(unittest.TestCase):
    def test_parcours_en_largeur(self):
        demandes = []

        def table(cible):
            demandes.append(cible)
            return RESEAU.get(cible)

        resultats = essai_sonde.parcourir(table)
        self.assertEqual(demandes, ["0000", "1A2B", "3C4D", "5E6F"])  # chacun une fois, jamais le final
        self.assertEqual(list(resultats), demandes)

    def test_sans_reponse_du_pont(self):
        self.assertEqual(essai_sonde.parcourir(lambda c: None), {"0000": None})

    def test_resume(self):
        r = essai_sonde.resumer(essai_sonde.parcourir(RESEAU.get), 12.34)
        self.assertEqual(r, {"interroges": 4, "reponses": 3, "partielles": 1, "incoherentes": 0,
                             "erreurs": {"delai": 1}, "pages": 4, "noeuds_vus": 5, "finaux_vus": 1, "entrees": 8,
                             "duree_s": 12.3})

    def test_complete(self):
        self.assertTrue(essai_sonde.complete({"ok": True, "partielle": False, "total": 2, "liste": [1, 2]}))
        self.assertFalse(essai_sonde.complete({"ok": True, "partielle": False, "total": 3, "liste": [1, 2]}))
        self.assertTrue(essai_sonde.complete({"ok": True, "partielle": True, "total": 3, "liste": [1, 2]}))
        self.assertTrue(essai_sonde.complete({"ok": False, "erreur": "delai"}))
        self.assertTrue(essai_sonde.complete(None))

    def test_requete_incomplete_redemandee_une_fois(self):
        class Fausse:
            def __init__(self, reponses):
                self.reponses, self.textes = list(reponses), []

            def commande(self, texte, types, id=None, delai=10.0):
                self.textes.append(texte)
                return dict(self.reponses.pop(0), id=id)

        manque = {"t": "table", "ok": True, "partielle": False, "total": 3, "liste": [1, 2]}
        bonne = {"t": "table", "ok": True, "partielle": False, "total": 3, "liste": [1, 2, 3]}
        essai = essai_sonde.Essai(Fausse([manque, bonne]))
        self.assertEqual(essai.requete("table", "1A2B")["liste"], [1, 2, 3])
        self.assertEqual(len(essai.sonde.textes), 2)
        essai = essai_sonde.Essai(Fausse([manque, manque]))
        self.assertTrue(essai.requete("table", "1A2B")["incoherente"])
        self.assertEqual(len(essai.sonde.textes), 2)

    def test_resume_sans_reponse(self):
        self.assertEqual(essai_sonde.resumer({"0000": None}, 0)["erreurs"], {"sans_reponse": 1})


if __name__ == "__main__":
    unittest.main()
