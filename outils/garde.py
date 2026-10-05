#!/usr/bin/env python3
"""Garde des vrais identifiants (spec de la sonde, section 5).

  python3 outils/garde.py

Lit garde.local.txt a la racine du depot (ignore par git) : les vrais identifiants du reseau de Majid, un
par ligne (adresses longues et courtes, PAN, EPID, identifiant du pont, MAC des cartes, noms) ; les lignes
vides et celles qui commencent par « # » sont ignorees. Depuis un worktree git, ou ce fichier ignore n'est
pas, la garde prend celui du depot principal. Echoue (code 1) si l'un des identifiants apparait dans un
fichier suivi par git, sans tenir compte de la casse ni des separateurs « : » et « 0x ». Sans aucun de ces
fichiers, la garde le dit et passe.
"""
import os
import re
import subprocess
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
DEPOT = os.path.normpath(os.path.join(ICI, ".."))


def normaliser(texte):
    return re.sub(r"0x|:", "", texte, flags=re.IGNORECASE).upper()


def lire_identifiants(chemin):
    with open(chemin, encoding="utf-8") as f:
        lignes = [l.strip() for l in f]
    return sorted({normaliser(l) for l in lignes if l and not l.startswith("#")} - {""})


def fichiers_suivis(depot):
    sortie = subprocess.run(["git", "-C", depot, "ls-files", "-z"], capture_output=True, check=True).stdout
    return [f for f in sortie.decode("utf-8").split("\0") if f]


def trouver(depot, identifiants):
    """[(fichier, identifiant)] pour chaque identifiant present dans un fichier suivi."""
    trouves = []
    for f in fichiers_suivis(depot):
        chemin = os.path.join(depot, f)
        if not os.path.isfile(chemin):
            continue
        with open(chemin, "rb") as g:
            texte = normaliser(g.read().decode("utf-8", "replace"))
        trouves += [(f, i) for i in identifiants if i in texte]
    return trouves


def emplacements(depot):
    """garde.local.txt du depot, puis celui du depot principal (depuis un worktree)."""
    places = [os.path.join(depot, "garde.local.txt")]
    r = subprocess.run(["git", "-C", depot, "rev-parse", "--path-format=absolute", "--git-common-dir"],
                       capture_output=True, text=True)
    if r.returncode == 0 and r.stdout.strip():
        places.append(os.path.join(os.path.dirname(r.stdout.strip()), "garde.local.txt"))
    return places


def main(depot=DEPOT):
    chemin = next((p for p in emplacements(depot) if os.path.exists(p)), None)
    if not chemin:
        print("garde : garde.local.txt absent, rien a verifier")
        return 0
    identifiants = lire_identifiants(chemin)
    trouves = trouver(depot, identifiants)
    for f, i in trouves:
        print(f"garde : identifiant reel dans {f} ({i[:2]}...{i[-2:]})")
    if trouves:
        return 1
    print(f"garde : {len(identifiants)} identifiants, aucun dans les fichiers suivis")
    return 0


if __name__ == "__main__":
    sys.exit(main())
