# Maillage Zigbee, plan 1 : la sonde : plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** une sonde ESP32-C6 membre du réseau Hue de Majid, qui donne par l'USB la table complète des voisins de n'importe quel routeur et sa propre table de voisins, avec ses outils d'essai, puis l'essai sur la carte avec Majid.

**Architecture :**
- **Le firmware** (`sonde/`, 0.9.0 pendant l'essai, 1.0.0 ensuite) :
  - des modules C++ purs, testés sur le Mac avec ASan et UBSan :
    - commandes de l'USB, lignes JSON et listes découpées, entrées des tables ;
    - pagination d'une table, garde-fou de cadence, liste blanche ;
    - adhésion au réseau, LED ;
  - une colle mince avec la pile Zigbee d'Espressif (`zigbee.cpp`), sans la bibliothèque Zigbee d'Arduino ;
  - une boucle principale (`main.cpp`) qui relie le tout ;
  - quatre variantes de compilation à trancher pendant l'essai, plus deux variantes de vérification avec une clé factice, que l'outil de flash refuse.
- **Les outils** (`outils/`, Python, bibliothèque standard seulement) :
  - la liaison USB sûre ;
  - l'outil d'essai, avec la tournée en largeur et la nuit ;
  - le flash qui vérifie la MAC de la carte ;
  - la garde des vrais identifiants ;
  - le code de l'essai d'écoute du 05/10, versé sans capture.
- **L'essai** (tâche 8, contrôleur et Majid), puis la sonde 1.0.0 d'après ses résultats (tâche 9).

**Tech Stack :**
- **Firmware :** PlatformIO pioarduino `55.03.312-1` (Arduino-ESP32 3.3.12, ESP-IDF 5.5.5, esp-zigbee-lib 1.6.8, esp-zboss-lib 1.6.4), ESP32-C6 SuperMini (flash de 4 Mo).
- **Tests hôte :** clang++ de Xcode, `-std=gnu++17`, ASan et UBSan, `-Werror`.
- **Outils :** Python 3.11, bibliothèque standard seulement, `unittest`.

**Spec :** `docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md`, validée le 05/10/2026, à lire avec ce plan.

**Code validé avant exécution.** Le 05/10, tout le code de ce plan a été écrit, compilé et testé dans une copie du dépôt :
- les six variantes du firmware compilent, sans avertissement avec `-Wall -Wextra` ;
- 9 programmes de tests hôte (1604 vérifications) et 37 tests Python passent ;
- la garde ne trouve aucun des vrais identifiants dans les fichiers suivis.

Le code a ensuite été relu par un agent au modèle le plus fort : concurrence, usage de l'API de la pile, conformité à la spec. Il n'a trouvé aucun défaut critique. Ses six constats importants et ses dix mineurs sont corrigés dans le code ci-dessous, et la spec a été révisée en conséquence le 05/10 (son en-tête les liste).

Les sorties attendues ci-dessous viennent du rejeu de chaque tâche sur une copie neuve, et l'arbre final du rejeu est identique à la copie validée.

Exécuter une tâche, c'est transcrire les fichiers et les blocs donnés, compiler et tester. Si un fichier doit s'écarter du texte donné, l'exécutant le dit dans son rapport, avec la raison.

**Blocs de modification.** Un fichier existant est modifié soit en entier (« fichier entier ci-dessous »), soit par blocs « remplacer … par … ». Chaque texte à remplacer apparaît une seule fois dans le fichier au moment où on l'applique. Les blocs s'appliquent dans l'ordre, au texte exact, espaces compris (outil Edit).

**Faits établis avant ce plan, utiles à l'exécution :**
- **La bibliothèque Zigbee d'Arduino n'est pas utilisée.** Quand un appareil s'annonce, elle envoie d'elle-même des `Match_Desc_req`, ce que la liste blanche interdit. Elle définit aussi son propre `esp_zb_app_signal_handler`. `lib_ignore = Zigbee` l'écarte, et `zigbee.cpp` appelle directement l'API d'Espressif.
- **Rejoindre un pont Hue :**
  - appeler `esp_zb_enable_joining_to_distributed(true)`, puis `esp_zb_secur_TC_standard_distributed_key_set(<clé ZLL>)` ;
  - régler `app_device_version = 1` sur le point d'accès ;
  - donner à la grappe On/Off les attributs `ON_TIME` et `GLOBAL_SCENE_CONTROL`, car le pont envoie « Off with effect ».

  D'autres l'ont constaté avant nous (wejn.org, janvier 2025), avec une lampe routeur. Avec un appareil final, rien n'est encore vérifié : c'est l'essai E1.
- **La pile Zigbee** (en-têtes, et désassemblage de `libesp_zb_api.ed.a` à la relecture) :
  - toute fonction de l'API appelée hors d'un rappel de la pile exige son verrou (`esp_zb_lock_acquire`), un mutex récursif que la tâche Zigbee tient pendant ses rappels ;
  - avant que ce mutex existe, `esp_zb_lock_acquire` rend `false`. Le firmware ne le prend de toute façon pas avant le premier signal (`ESP_ZB_ZDO_SIGNAL_SKIP_STARTUP`), voir `zigbee::prete()` ;
  - **la pile borne elle-même une requête ZDO à 5 s**. À l'échéance, le rappel arrive avec le statut `0x85`, d'où le délai par page de 5000 ms au plus ;
  - les requêtes copient leurs paramètres aussitôt. La liste d'une réponse `Mgmt_Lqi_rsp` n'est valable que pendant le rappel, qui la recopie ;
  - selon la norme BDB, **une recherche lancée par un nœud déjà membre diffuse un `Mgmt_Permit_Joining_req`**, ce qui ouvrirait le réseau Hue pendant 180 s. `zigbee::chercher()` ne la lance jamais quand la pile se dit rattachée ;
  - `esp_zb_set_node_descriptor_power_source` s'appelle après `esp_zb_start` (en-tête) ;
  - `esp_zb_bdb_reset_via_local_action()` quitte le réseau et efface la mémoire Zigbee, sauf le compteur de trames sortant, puis lève `ESP_ZB_ZDO_SIGNAL_LEAVE`. `esp_zb_factory_reset()` efface tout `zb_storage`, compteur compris, et redémarre.
- **Partitions :** `zigbee_zczr.csv` (Arduino-ESP32) a `zb_storage` et `zb_fct` aux mêmes adresses pour les quatre variantes, et une partition d'application de 1,25 Mo. Le firmware en occupe environ 590 Ko en appareil final et 700 Ko en routeur.
- **Port série :** comme pour la sonde Thread, `TIOCEXCL`, puis DTR = RTS = 0 **en un seul** `TIOCMSET`, puis termios brut sans HUPCL. RTS = 1 avec DTR = 0 redémarre le C6.

**Choix faits en écrivant le code (la spec ne les fixe pas) :**
1. **La recherche se limite aux canaux Hue** 11, 15, 20 et 25.
2. **Appareil final :** un message de maintien auprès du parent toutes les 10 s, et le parent l'oublie après 64 minutes de silence. **Routeur de repli :** `max_children = 0`, il n'est jamais le parent de personne.
3. **Le verrou de la pile** se prend en 200 ms au plus pour une commande, en 50 ms pour une page (sinon, au tour suivant), en 1 s au plus pour une action d'adhésion, et sans attendre pour le constat de la pile, fait toutes les 10 s.
4. **Un effet d'identification** demandé par le pont dure 3 s sur la LED. L'attribut Identify Time, lui, dure le temps qu'il annonce.
5. **Couleurs de la LED**, 24/255 au plus par canal comme la sonde Thread :
   - blanc pour l'identification ;
   - bleu pulsé pendant la recherche ;
   - vert pour l'adhésion ;
   - orange (un quart de vert) pour la suspension ;
   - veille (2/255 par canal) pour la lampe Hue allumée.
6. **Les entrées de `routes` et la réponse d'`echecs` ont un format proposé dès maintenant** (sections 2 et 3 de la spec : « fixé après l'essai »). La tâche 9 le garde ou retire les commandes.
7. **Les variantes de vérification** `verif` (appareil final, On/Off) et `verif_routeur` (routeur, lampe variable) se compilent avec une clé factice (`SONDE_CLE_FACTICE`). Les agents compilent ainsi sans jamais toucher à la vraie clé. `outils/flasher.py` ne connaît pas ces variantes et ne peut donc pas les flasher.
8. **Aucun journal sur l'USB** (`CORE_DEBUG_LEVEL=0`, `esp_log_level_set("*", ESP_LOG_NONE)`) : sur le même USB, un journal couperait les lignes machine. Les signaux de la pile arrivent à la place en lignes `signal` (`SONDE_SIGNAUX`).
9. **Les départs :**
   - après `oubli`, la sonde redémarre sans effacement, car la pile a déjà tout effacé sauf le compteur de trames, que des voisins vérifient ;
   - après un départ demandé par le pont, elle efface tout.
10. **File des événements de la pile :** 32 places. Un signal perdu se rattrape par le constat de la pile, toutes les 10 s.

**Écarts à la spec :** aucun. La spec a été révisée le 05/10 en écrivant ce plan (voir son en-tête). Restent à décider après l'essai, à la tâche 9 : la variante par défaut (E1), `routes` (E4), `echecs` (E5) et les lignes `signal`.

## Global Constraints

- **Carte :** ESP32-C6 SuperMini (flash de 4 Mo), branchée **en USB sur le Mac seulement**.
- **Chaîne :** pioarduino `55.03.312-1` (Arduino-ESP32 3.3.12, ESP-IDF 5.5.5, esp-zigbee-lib 1.6.8, esp-zboss-lib 1.6.4). Le firmware se compile dans `sonde/` par `~/.platformio/penv/bin/pio run -e <variante>` (ou `pio` s'il est dans le `PATH`).
- **Protocole :**
  - RS (`0x1E`), JSON compact, fin de ligne ; 4095 octets émis au plus par ligne ;
  - produit `sonde-zigbee` ;
  - délai par page de 500 à 5000 ms, 5000 par défaut ;
  - une cible est toujours l'adresse d'un appareil, jamais une adresse de diffusion (`FFF8` à `FFFF`) ;
  - une seule table à la fois, une seule nouvelle tentative par page, 120 s au plus par table.
- **Garde-fou :** au moins 100 ms entre deux envois, au plus 600 envois par fenêtre glissante de 10 minutes.
- **Liste blanche :**
  - `Mgmt_Lqi_req` (`0x0031`) ;
  - `Mgmt_Rtg_req` (`0x0032`, si `SONDE_ROUTES`) ;
  - `Mgmt_NWK_Update_req` (`0x0038`, si `SONDE_ECHECS`), en balayage d'énergie de durée 0 sur le seul canal courant.

  Rien d'autre, jamais, et toujours vers un seul appareil. Jamais de recherche une fois la sonde rattachée.
- **Code :** identifiants et commentaires en français **sans accents** ; textes des docs et des README avec accents. Les tests hôte compilent avec `-Werror`.
- **Commandes,** depuis la racine du dépôt :
  - `sh outils/tester.sh` lance tout ce qui se teste sans carte : tests hôte du firmware (`sonde/test/lancer.sh`), tests Python (`python3 -m unittest discover -s outils/test`) et garde (`python3 outils/garde.py`) ;
  - `cd sonde && ~/.platformio/penv/bin/pio run -e verif -e verif_routeur` compile le firmware sans la vraie clé.
- **Carte et ports série :** de la tâche 1 à la tâche 7, **aucun agent n'ouvre un port série ni ne flashe** :
  - pas de `pio run -t upload`, `-t erase` ni `pio device monitor`, et pas d'`esptool` ;
  - pas d'`outils/essai_sonde.py`, d'`outils/flasher.py` ni d'`outils/ecoute/capture.py`.

  Le pont Halo, la sonde Thread et la carte témoin de benq sont aussi des C6 branchés au même Mac : en ouvrir un peut le redémarrer. La tâche 8 se fait par le contrôleur, avec Majid.
- **Clé de liaison Hue :** aucun agent ne crée, n'écrit, ne lit ni ne cherche `sonde/cle_hue.local.h` ni la clé elle-même. C'est Majid qui la pose, à la tâche 8. Les agents compilent les variantes `verif*`.
- **Données personnelles :** le dépôt est local, rien n'est poussé.
  - Uniquement des valeurs inventées : adresses longues `A0000000000000xx`, adresses courtes `1A2B`, `3C4D`, `5E6F`, PAN `1234`, MAC `A0:00:00:00:00:01`.
  - Jamais commités : `sonde/cle_hue.local.h`, `outils/sonde.local.json`, `essais/`, `garde.local.txt` (déjà dans `.gitignore`).
  - La garde (`outils/garde.py`) doit passer à chaque tâche.
- **Commits :**
  - un par tâche, message en français sans accents, terminé par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` ;
  - `git add` avec la liste de fichiers de la tâche, **jamais `git add -A` ni `git add .`** ;
  - jamais de push.
- **Interdits pour les agents :**
  - `sudo` ;
  - ouvrir un port série, flasher ou lancer les outils d'essai (voir plus haut) ;
  - toucher à la clé Hue ;
  - écrire quoi que ce soit dans `~/Dev/maillage-thread`, qu'une autre session est en train d'anonymiser.

## Carte des fichiers

| Fichier | Rôle | Tâche |
|---|---|---|
| `outils/garde.py`, `outils/test/test_garde.py` | garde des vrais identifiants (aussi depuis un worktree) | 1 |
| `outils/tester.sh` | tous les tests sans carte | 1, 3 |
| `README.md` | présentation du dépôt, tests, données personnelles | 1 |
| `outils/ecoute/` | code de l'essai d'écoute du 05/10 (firmware, décodeur, capture, analyse), sans capture | 2 |
| `sonde/src/options.h` | `SONDE_ROUTES`, `SONDE_ECHECS` | 3 |
| `sonde/src/commande.{h,cpp}` | lecture des commandes de l'USB | 3 |
| `sonde/src/ligne.{h,cpp}` | lignes machine, listes découpées (`suite`) | 3 |
| `sonde/src/entrees.{h,cpp}` | entrées des tables en JSON, `Mgmt_Rtg_rsp` brute | 3 |
| `sonde/test/verif.h`, `sonde/test/lancer.sh`, `sonde/test/test_*.cpp` | tests hôte | 3, 4, 5 |
| `sonde/src/pagination.h` | pagination d'une table distante | 4 |
| `sonde/src/cadence.{h,cpp}`, `sonde/src/liste_blanche.h` | garde-fou de cadence, liste blanche | 4 |
| `sonde/src/adhesion.{h,cpp}` | adhésion, rattachement, départ | 5 |
| `sonde/src/voyant.h` | LED de la carte | 5 |
| `sonde/src/version.h`, `sonde/src/zigbee.{h,cpp}`, `sonde/src/main.cpp` | firmware : colle Zigbee, boucle principale | 6, 9 |
| `sonde/platformio.ini`, `sonde/cle_hue.exemple.h`, `sonde/README.md` | variantes, modèle de clé, mode d'emploi | 6, 9 |
| `outils/sonde_usb.py`, `outils/essai_sonde.py`, `outils/flasher.py`, leurs tests | liaison USB, essai, flash vérifié | 7 |
| spec de la sonde, section 8 | résultats de l'essai | 8, 9 |

---

### Task 1: Garde des identifiants, lanceur des tests, README

**Files:**
- Create: `outils/garde.py`, `outils/test/test_garde.py`, `outils/tester.sh`, `README.md`

**Interfaces:**
- Consumes : `garde.local.txt` à la racine du dépôt principal (ignoré par git, déjà rempli par le contrôleur le 05/10 avec les identifiants de l'essai d'écoute). Il n'est jamais lu ni affiché par un agent : seule la garde le lit.
- Produces :
  - `python3 outils/garde.py` : code 0 si aucun vrai identifiant n'est dans un fichier suivi, 1 sinon. Elle n'affiche jamais un identifiant entier ;
  - `sh outils/tester.sh` : tests sans carte. Les tâches 3 à 7 y ajoutent les leurs.

- [ ] **Step 1 : écrire les tests de la garde.**

`outils/test/test_garde.py` :

```python
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
```

- [ ] **Step 2 : les lancer, ils échouent.**

Run : `python3 -m unittest discover -s outils/test`

Expected : `ModuleNotFoundError: No module named 'garde'`, et à la fin :

```text
----------------------------------------------------------------------
Ran 1 test in 0.000s
FAILED (errors=1)
```

- [ ] **Step 3 : écrire la garde.**

`outils/garde.py` :

```python
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
            texte = normaliser(g.read().decode("latin-1"))
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
```

- [ ] **Step 4 : les tests passent.**

Run : `python3 -m unittest discover -s outils/test`

Expected, en fin de sortie :

```text
----------------------------------------------------------------------
Ran 7 tests in 0.367s
OK
```

- [ ] **Step 5 : le lanceur et le README.**

`outils/tester.sh` (première version : la tâche 3 y ajoutera les tests hôte du firmware) :

```sh
#!/bin/sh
# Tous les tests sans carte, depuis la racine du depot :
#   sh outils/tester.sh
# 1. tests des outils Python (outils/test) ;
# 2. garde des vrais identifiants (outils/garde.py).
# Aucun port serie n'est ouvert, rien n'est flashe.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
DEPOT=$(cd "$ICI/.." && pwd)
python3 -m unittest discover -s "$ICI/test"
python3 "$ICI/garde.py"
```

`README.md` :

````markdown
# Maillage Zigbee

Voir le maillage Zigbee d'un réseau Philips Hue : quelle lampe parle à
quelle autre, et avec quelle qualité. Le pont Hue ne le dit pas. Une sonde
ESP32-C6, membre du réseau, interroge donc chaque routeur ; une app macOS,
à venir, dessinera le maillage.

Le projet suit Maillage Thread (dépôt voisin) et se fait en quatre
morceaux, chacun avec sa spec, son plan et sa mise en œuvre :

1. **la sonde** (en cours) : `docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md` ;
2. le cœur de l'app : pont Hue, noms et pièces, tournée, graphe, fiche ;
3. le journal et l'historique ;
4. la vue des pièces en 3D.

## Organisation

- `sonde/` : le firmware de la sonde (voir `sonde/README.md`) et ses tests
  hôte (`sonde/test/`).
- `outils/` : l'outil d'essai par l'USB (`essai_sonde.py`), le flash qui
  vérifie la carte (`flasher.py`), la garde des identifiants (`garde.py`),
  leurs tests (`outils/test/`), et le code de l'essai d'écoute passive du
  05/10/2026 (`outils/ecoute/`).
- `docs/superpowers/` : specs et plans.

## Tests

Depuis la racine du dépôt, sans carte :

```sh
sh outils/tester.sh
```

## Données personnelles

Le dépôt ne contient que des valeurs inventées : adresses, PAN, EPID,
identifiant du pont, noms et pièces. Ne sont jamais commités, et
`.gitignore` les exclut :

- `sonde/cle_hue.local.h` : la clé de liaison Hue ;
- `outils/sonde.local.json` : le port et la MAC de la carte ;
- `essais/` : captures et journaux réels ;
- `garde.local.txt` : la liste des vrais identifiants, que `outils/garde.py`
  cherche dans les fichiers suivis à chaque `sh outils/tester.sh`.
````

- [ ] **Step 6 : tout passe.**

Run : `sh outils/tester.sh`

Expected : les 7 tests passent, puis la garde dit `garde : <n> identifiants, aucun dans les fichiers suivis` (66 le 05/10), même depuis un worktree, où elle lit le fichier du dépôt principal.

- [ ] **Step 7 : commit.**

```bash
git add outils/garde.py outils/test/test_garde.py outils/tester.sh README.md
git commit -m "Ajouter la garde des vrais identifiants, le lanceur des tests et le README

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Code de l'essai d'écoute passive (outils/ecoute)

**Files:**
- Create: `outils/ecoute/README.md`, `outils/ecoute/zb.py`, `outils/ecoute/capture.py`, `outils/ecoute/analyse.py`, `outils/ecoute/firmware/platformio.ini`, `outils/ecoute/firmware/src/main.cpp`

**Interfaces:**
- Consumes : rien (code autonome, versé tel quel depuis l'essai du 05/10, nettoyé de ses identifiants réels).
- Produces : le firmware d'écoute (`pio run -d outils/ecoute/firmware`, variante `ecoute`), que `outils/flasher.py --ecoute` flashera (tâche 7). Ses outils `capture.py` et `analyse.py` ne sont lancés par aucun agent.

- [ ] **Step 1 : transcrire les six fichiers.**

`outils/ecoute/README.md` :

````markdown
# Écoute passive 802.15.4 (essai du 05/10/2026)

Le code de l'essai d'écoute passive (spec de la sonde, annexe A), versé tel
quel, **sans aucune capture**. Il servira à la future voie B (écoute sur une
deuxième carte), ou de repli si la sonde ne peut pas rejoindre le pont Hue.

- `firmware/` : un ESP32-C6 en mode promiscuité, qui **n'émet jamais**. Le
  pilote d'ESP-IDF acquitte par défaut toute trame reçue, même en
  promiscuité : le firmware coupe l'acquittement simple et l'acquittement
  amélioré après `esp_ieee802154_enable()`, et le vérifie dans chacune de
  ses lignes d'état (`S <canal> <reçues> <perdues> <ack_tx> <enh_ack>`).
- `zb.py` : décodage des en-têtes MAC, NWK et sécurité NWK (en clair).
- `capture.py` : balayage des canaux 11, 15, 20 et 25, ou écoute d'un canal
  en JSONL.
- `analyse.py` : nœuds, rôles, sauts, rattachements, relais, réémissions,
  temps d'antenne.

## Usage

```sh
python3 outils/flasher.py --ecoute --effacer     # verifie la MAC de la carte avant d'ecrire
python3 outils/ecoute/capture.py balayage --port /dev/cu.usbmodemXXXX
python3 outils/ecoute/capture.py ecoute --port /dev/cu.usbmodemXXXX --canal 25 --duree 900 --sortie essais/ecoute.jsonl
python3 outils/ecoute/analyse.py essais/ecoute.jsonl
```

Les captures contiennent les vrais identifiants du réseau : toujours dans
`essais/` (ignoré par git). `capture.py` demande `pyserial` (celui de
PlatformIO : `~/.platformio/penv/bin/python`).
````

`outils/ecoute/zb.py` :

```python
"""Decodage des en-tetes 802.15.4 (MAC) et Zigbee (NWK, securite NWK).

Essai jetable. Seuls les en-tetes en clair sont lus ; la charge NWK chiffree
n'est pas touchee. Adresses longues rendues en ordre lisible (octet de poids
fort d'abord), courtes en 0xABCD.
"""

import struct

MAC_TYPES = {0: "balise", 1: "donnees", 2: "ack", 3: "commande"}
MAC_CMDS = {1: "assoc_req", 2: "assoc_rsp", 4: "data_req", 7: "beacon_req", 8: "coord_realign"}


def ieee(b):
    return ":".join(f"{x:02X}" for x in reversed(b))


def court(v):
    return f"0x{v:04X}"


def decoder(data):
    """Retourne un dict, ou None si la trame est trop courte."""
    if len(data) < 3:
        return None
    fcf = data[0] | data[1] << 8
    d = {
        "type": MAC_TYPES.get(fcf & 7, f"type{fcf & 7}"),
        "mac_secu": bool(fcf >> 3 & 1),
        "pending": bool(fcf >> 4 & 1),
        "ack_req": bool(fcf >> 5 & 1),
        "version": fcf >> 12 & 3,
        "seq": data[2],
    }
    dam, sam, panc = fcf >> 10 & 3, fcf >> 14 & 3, fcf >> 6 & 1
    i = 3
    try:
        if dam:
            d["pan"] = court(struct.unpack_from("<H", data, i)[0]); i += 2
            if dam == 2:
                d["dst"] = court(struct.unpack_from("<H", data, i)[0]); i += 2
            else:
                d["dst"] = ieee(data[i:i + 8]); i += 8
        if sam:
            if not panc or not dam:
                d["pan_src"] = court(struct.unpack_from("<H", data, i)[0]); i += 2
                d.setdefault("pan", d["pan_src"])
            if sam == 2:
                d["src"] = court(struct.unpack_from("<H", data, i)[0]); i += 2
            else:
                d["src"] = ieee(data[i:i + 8]); i += 8
    except struct.error:
        d["tronquee"] = True
        return d
    charge = data[i:]
    if d["type"] == "commande" and charge:
        d["cmd"] = MAC_CMDS.get(charge[0], f"cmd{charge[0]}")
    elif d["type"] == "balise":
        _balise(charge, d)
    elif d["type"] == "donnees" and not d["mac_secu"] and len(charge) >= 2:
        d["nwk"] = _nwk(charge)
    elif d["type"] == "donnees" and d["mac_secu"]:
        d["classe"] = "thread_ou_secu_mac"
    return d


def _balise(c, d):
    # superframe(2) gts(1) pending(1) puis charge Zigbee
    if len(c) < 4:
        return
    i = 2
    gts = c[i] & 7; i += 1 + (3 * gts + 1 if gts else 0)
    pend = c[i]; i += 1 + 2 * (pend & 7) + 8 * (pend >> 4 & 7)
    z = c[i:]
    if len(z) >= 11 and z[0] == 0:
        d["zigbee_balise"] = {
            "stack": z[1] & 0xF, "proto": z[1] >> 4,
            "routeurs_ok": bool(z[2] >> 2 & 1), "profondeur": z[2] >> 3 & 0xF,
            "ed_ok": bool(z[2] >> 7 & 1), "epid": ieee(z[3:11]),
        }


def _nwk(c):
    fcf = c[0] | c[1] << 8
    n = {"type": fcf & 3, "proto": fcf >> 2 & 0xF}
    if n["proto"] == 3:  # Green Power
        return _gp(c, n)
    if n["type"] == 3:
        n["classe"] = "inter_pan"
        return n
    if n["proto"] != 2:  # 6LoWPAN (MLE de Thread) ou autre
        n["classe"] = "autre"
        return n
    n["classe"] = "zigbee"
    n["cmd"] = n["type"] == 1
    multicast, secu = fcf >> 8 & 1, fcf >> 9 & 1
    route_src, dst64, src64 = fcf >> 10 & 1, fcf >> 11 & 1, fcf >> 12 & 1
    n["secu"] = bool(secu)
    try:
        dst, src = struct.unpack_from("<HH", c, 2)
        n["dst"], n["src"] = court(dst), court(src)
        n["rayon"], n["seq"] = c[6], c[7]
        i = 8
        if dst64:
            n["dst64"] = ieee(c[i:i + 8]); i += 8
        if src64:
            n["src64"] = ieee(c[i:i + 8]); i += 8
        if multicast:
            i += 1
        if route_src:
            nb, idx = c[i], c[i + 1]; i += 2
            n["relais"] = [court(struct.unpack_from("<H", c, i + 2 * k)[0]) for k in range(nb)]
            n["relais_index"] = idx
            i += 2 * nb
        if secu:
            sc = c[i]; i += 1
            n["cle_id"] = sc >> 3 & 3
            ext = sc >> 5 & 1
            n["compteur"] = struct.unpack_from("<I", c, i)[0]; i += 4
            if ext:
                n["secu_src64"] = ieee(c[i:i + 8]); i += 8
            if n["cle_id"] == 1:
                n["cle_seq"] = c[i]; i += 1
        n["charge_len"] = len(c) - i
    except (struct.error, IndexError):
        n["tronquee"] = True
    return n


def _gp(c, n):
    n["classe"] = "green_power"
    i = 1
    ext = c[0] >> 7 & 1
    app = 0
    if ext and len(c) > 1:
        app = c[1] & 7; i += 1
    if app == 0 and len(c) >= i + 4:
        n["gpd_id"] = f"{struct.unpack_from('<I', c, i)[0]:08X}"
    return n
```

`outils/ecoute/capture.py` :

```python
"""Capture de l'essai : balayage des canaux ou ecoute d'un canal.

  python capture.py balayage --port P [--duree 20] [--canaux 11,15,20,25]
  python capture.py ecoute --port P --canal N --duree 900 --sortie f.jsonl

Chaque trame est ecrite en JSONL : t (heure Mac), canal, rssi, lqi, t_us
(horloge de la sonde), hex. Les lignes S (etat) sont gardees a part.
"""

import argparse
import collections
import json
import sys
import time

import serial

import zb


def ouvrir(port):
    s = serial.Serial(port, 115200, timeout=0.2)
    time.sleep(0.3)
    s.reset_input_buffer()
    return s


def lignes(s, fin):
    tampon = b""
    while time.time() < fin:
        tampon += s.read(8192)
        *completes, tampon = tampon.split(b"\n")
        for l in completes:
            yield l.decode("ascii", "replace").strip()


def canal(s, n):
    s.write(f"c {n}\n".encode())
    s.flush()


def trame(l):
    p = l.split(" ")
    if len(p) < 5 or p[0] != "F":
        return None
    return {"t": time.time(), "canal": int(p[1]), "rssi": int(p[2]), "lqi": int(p[3]),
            "t_us": int(p[4]), "hex": p[5] if len(p) > 5 else ""}


def balayage(a):
    s = ouvrir(a.port)
    for n in [int(x) for x in a.canaux.split(",")]:
        canal(s, n)
        time.sleep(0.3)
        s.reset_input_buffer()
        classes, pans, epids, etats = collections.Counter(), collections.Counter(), set(), []
        nb = 0
        for l in lignes(s, time.time() + a.duree):
            if l.startswith("S "):
                etats.append(l)
            f = trame(l)
            if not f:
                continue
            nb += 1
            d = zb.decoder(bytes.fromhex(f["hex"]))
            if not d:
                continue
            if "pan" in d:
                pans[d["pan"]] += 1
            if "nwk" in d:
                classes[d["nwk"]["classe"]] += 1
            elif d.get("classe"):
                classes[d["classe"]] += 1
            else:
                classes["mac_" + d["type"]] += 1
            if "zigbee_balise" in d:
                epids.add(d["zigbee_balise"]["epid"])
        print(f"canal {n}: {nb} trames en {a.duree} s ; PAN {dict(pans.most_common(4))} ; "
              f"classes {dict(classes)} ; EPID {sorted(epids) or '-'}")
        if etats:
            print("   ", etats[-1])
        sys.stdout.flush()


def ecoute(a):
    s = ouvrir(a.port)
    canal(s, a.canal)
    time.sleep(0.3)
    s.reset_input_buffer()
    nb, debut = 0, time.time()
    with open(a.sortie, "w") as sortie, open(a.sortie + ".etats", "w") as etats:
        for l in lignes(s, debut + a.duree):
            if l.startswith("S ") or l.startswith("I "):
                etats.write(f"{time.time():.3f} {l}\n")
                etats.flush()
                continue
            f = trame(l)
            if f:
                sortie.write(json.dumps(f) + "\n")
                nb += 1
                if nb % 500 == 0:
                    sortie.flush()
                    print(f"{nb} trames, {int(time.time() - debut)} s", flush=True)
    print(f"fini : {nb} trames en {int(time.time() - debut)} s -> {a.sortie}")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    sp = p.add_subparsers(dest="mode", required=True)
    b = sp.add_parser("balayage")
    b.add_argument("--port", required=True)
    b.add_argument("--duree", type=float, default=20)
    b.add_argument("--canaux", default="11,15,20,25")
    e = sp.add_parser("ecoute")
    e.add_argument("--port", required=True)
    e.add_argument("--canal", type=int, required=True)
    e.add_argument("--duree", type=float, default=900)
    e.add_argument("--sortie", required=True)
    a = p.parse_args()
    balayage(a) if a.mode == "balayage" else ecoute(a)
```

`outils/ecoute/analyse.py` :

```python
"""Analyse d'une capture de l'essai : ce que l'ecoute passive revele du maillage.

  python3 analyse.py capture.jsonl [--pan 0x1234] [--json resume.json]
"""

import argparse
import collections
import json
import statistics

import zb

OUI = {"00:17:88": "Signify (Hue)"}
DIFFUSIONS = {"0xFFFF", "0xFFFD", "0xFFFC", "0xFFFB"}
FENETRE_ACK_US = 6000


def charger(chemin):
    trames = []
    with open(chemin) as f:
        for l in f:
            t = json.loads(l)
            d = zb.decoder(bytes.fromhex(t["hex"]))
            if d:
                t["d"] = d
                trames.append(t)
    trames.sort(key=lambda t: t["t_us"])
    return trames


def pan_zigbee(trames):
    c = collections.Counter(t["d"].get("pan") for t in trames
                            if t["d"].get("nwk", {}).get("classe") == "zigbee")
    return c.most_common(1)[0][0] if c else None


def analyser(trames, pan):
    noeuds = collections.defaultdict(lambda: {"ieee": collections.Counter(), "rssi": [],
                                              "lqi": [], "emises": 0, "roles": set()})
    sauts = collections.defaultdict(lambda: {"trames": 0, "ack_dem": 0, "ack_vus": 0})
    parents = collections.Counter()
    link_status = collections.defaultdict(list)
    nb_voisins_ls = collections.defaultdict(collections.Counter)
    rayons_m2o = collections.defaultdict(collections.Counter)  # relais -> rayon vu
    derniere = {}  # (src, dst) -> (seq, t_us) pour les reemissions MAC
    routes_src = collections.Counter()
    relayees = collections.Counter()
    gp, inter_pan = collections.Counter(), collections.Counter()
    coherence = collections.Counter()
    nwk_cmd = collections.Counter()
    attente = {}  # seq -> (t_us, saut) des trames qui demandent un ack
    debut, fin = trames[0]["t"], trames[-1]["t"]
    antenne = collections.Counter()  # PAN -> microsecondes d'emission
    for t in trames:
        # preambule+SFD+PHR (6 octets) + PSDU (charge + FCS), 32 us par octet
        antenne[t["d"].get("pan", "ack" if t["d"]["type"] == "ack" else "?")] += \
            (6 + len(t["hex"]) // 2 + 2) * 32

    for t in trames:
        d = t["d"]
        if d["type"] == "ack":
            s = attente.pop(d["seq"], None)
            if s and 0 < t["t_us"] - s[0] < FENETRE_ACK_US:
                sauts[s[1]]["ack_vus"] += 1
            continue
        if d.get("pan") != pan:
            continue
        src, dst = d.get("src"), d.get("dst")
        if src:
            n = noeuds[src]
            n["emises"] += 1
            n["rssi"].append(t["rssi"])
            n["lqi"].append(t["lqi"])
        if d["type"] == "commande":
            if d.get("cmd") == "data_req" and src and dst:
                parents[(src, dst)] += 1
                noeuds[src]["roles"].add("appareil_final")
            continue
        if dst and dst not in DIFFUSIONS:
            noeuds[dst]
        if src and dst and dst not in DIFFUSIONS:
            k = (src, dst)
            prec = derniere.get(k)
            if prec and prec[0] == d["seq"] and t["t_us"] - prec[1] < 200000:
                sauts[k]["reemissions"] = sauts[k].get("reemissions", 0) + 1
                derniere[k] = (d["seq"], t["t_us"])
                continue
            derniere[k] = (d["seq"], t["t_us"])
            sauts[k]["trames"] += 1
            if d["ack_req"]:
                sauts[k]["ack_dem"] += 1
                attente[d["seq"]] = (t["t_us"], k)
        nw = d.get("nwk")
        if not nw:
            continue
        if nw["classe"] == "green_power":
            gp[nw.get("gpd_id", "?")] += 1
            continue
        if nw["classe"] == "inter_pan":
            inter_pan[src or "?"] += 1
            continue
        if nw["classe"] != "zigbee" or nw.get("tronquee"):
            continue
        if "src64" in nw:
            noeuds[nw["src"]]["ieee"][nw["src64"]] += 1
        if "dst64" in nw:
            noeuds[nw["dst"]]["ieee"][nw["dst64"]] += 1
        if "secu_src64" in nw and src:
            noeuds[src]["ieee"][nw["secu_src64"]] += 1
            if "src64" in nw and nw["src"] == src:
                coherence["secu_src64 == src64"] += nw["secu_src64"] == nw["src64"]
                coherence["comparees"] += 1
        if nw["cmd"]:
            nwk_cmd[(nw["dst"], nw["rayon"])] += 1
            if nw["dst"] == "0xFFFC" and nw["src"] == "0x0000" and nw["rayon"] > 1 and src:
                rayons_m2o[src][nw["rayon"]] += 1
            if nw["dst"] == "0xFFFC" and nw["rayon"] == 1 and src == nw["src"]:
                link_status[src].append(t["t"])
                # charge chiffree = id (1) + options (1) + 3 x voisins + MIC (4)
                if "charge_len" in nw:
                    nb_voisins_ls[src][(nw["charge_len"] - 6) / 3] += 1
                noeuds[src]["roles"].add("routeur")
        if nw["src"] != src and src:
            relayees[(src, nw["src"], "diffusion" if nw["dst"] in DIFFUSIONS else "unicast")] += 1
            noeuds[src]["roles"].add("relais")
        if "relais" in nw:
            routes_src[(nw["src"], tuple(nw["relais"]), nw["dst"])] += 1
        noeuds[nw["src"]]  # connu par le NWK meme s'il n'est pas entendu
        if nw["dst"] not in DIFFUSIONS:
            noeuds[nw["dst"]]
    if "0x0000" in noeuds:
        noeuds["0x0000"]["roles"].add("coordinateur (pont)")
    return {
        "duree_s": fin - debut, "noeuds": noeuds, "sauts": sauts, "parents": parents,
        "link_status": link_status, "routes_src": routes_src, "relayees": relayees,
        "gp": gp, "inter_pan": inter_pan, "coherence": coherence, "nwk_cmd": nwk_cmd,
        "antenne": antenne, "nb_voisins_ls": nb_voisins_ls, "rayons_m2o": rayons_m2o,
    }


def ieee_de(n):
    return n["ieee"].most_common(1)[0][0] if n["ieee"] else None


def rapport(r, pan, nb_trames):
    lignes = []
    p = lignes.append
    nds = r["noeuds"]
    entendus = {k: v for k, v in nds.items() if v["emises"]}
    p(f"PAN Zigbee {pan} ; {nb_trames} trames toutes PAN confondues ; {r['duree_s']:.0f} s")
    p(f"Noeuds connus : {len(nds)} ; entendus directement : {len(entendus)} ; "
      f"avec adresse longue : {sum(1 for v in nds.values() if v['ieee'])}")
    p(f"Coherence en-tete de securite / NWK : {dict(r['coherence'])}")
    p("")
    p("NOEUDS (court, longue, fabricant, roles, trames emises, RSSI median/min/max, intervalle des Link Status)")
    for k in sorted(nds, key=lambda k: -nds[k]["emises"]):
        v = nds[k]
        i = ieee_de(v)
        fab = OUI.get(i[:8], i[:8]) if i else "-"
        conflit = " CONFLIT " + str(dict(v["ieee"])) if len(v["ieee"]) > 1 else ""
        rs = (f"{statistics.median(v['rssi']):.0f}/{min(v['rssi'])}/{max(v['rssi'])}"
              if v["rssi"] else "-")
        ls = r["link_status"].get(k, [])
        per = (f"{statistics.median([b - a for a, b in zip(ls, ls[1:])]):.1f} s ({len(ls)})"
               if len(ls) > 2 else (f"({len(ls)})" if ls else "-"))
        rm = r["rayons_m2o"].get(k)
        r0 = 1 + max((x for c in r["rayons_m2o"].values() for x in c), default=0)
        sauts_pont = f" a {r0 - rm.most_common(1)[0][0]} saut(s) du pont" if rm else ""
        nv = r["nb_voisins_ls"].get(k)
        nvs = " voisins declares " + "/".join(f"{x:g}" for x, _ in nv.most_common(3)) if nv else ""
        p(f"  {k}  {i or '?':23}  {fab:14}  {','.join(sorted(v['roles'])) or '-':28} "
          f"{v['emises']:5}  {rs:12}  {per}{nvs}{sauts_pont}{conflit}")
    p("")
    vois = collections.defaultdict(set)
    for (a, b) in r["sauts"]:
        vois[a].add(b); vois[b].add(a)
    for (a, b) in r["parents"]:
        vois[a].add(b); vois[b].add(a)
    p("VOISINS OBSERVES (liens unicast vus dans un sens ou l'autre)")
    for k in sorted(vois, key=lambda k: -len(vois[k])):
        p(f"  {k} ({len(vois[k])}) : {' '.join(sorted(vois[k]))}")
    p("")
    tot = r["duree_s"] * 1e6
    p("TEMPS D'ANTENNE par PAN (% du canal) : " + ", ".join(
        f"{k} {100 * v / tot:.2f} %" for k, v in r["antenne"].most_common()))
    p("")
    p("SAUTS UNICAST observes (emetteur -> recepteur : trames, ack demandes, ack vus, reemissions MAC)")
    for (a, b), v in sorted(r["sauts"].items(), key=lambda kv: -kv[1]["trames"]):
        re = v.get("reemissions", 0)
        taux = f" ({100 * re / (v['trames'] + re):.0f} %)" if re else ""
        p(f"  {a} -> {b} : {v['trames']}, {v['ack_dem']}, {v['ack_vus']}, {re}{taux}")
    p("")
    p("RATTACHEMENTS (data request appareil final -> parent : nombre)")
    for (a, b), c in r["parents"].most_common():
        p(f"  {a} -> {b} : {c}")
    p("")
    p("RELAIS (relais, origine NWK : trames)")
    for (a, b, genre), c in r["relayees"].most_common(40):
        p(f"  {a} relaie pour {b} ({genre}) : {c}")
    p("")
    p("ROUTES SOURCE (origine, relais [du plus proche de la destination au plus proche de l'origine], destination : nombre)")
    for (a, rel, b), c in r["routes_src"].most_common(30):
        p(f"  {a} {list(rel)} {b} : {c}")
    p("")
    p(f"Commandes NWK (destination, rayon) : {dict(r['nwk_cmd'].most_common(10))}")
    p(f"Green Power (identifiants) : {dict(r['gp'])}")
    p(f"Inter-PAN (emetteurs) : {dict(r['inter_pan'])}")
    return "\n".join(lignes)


def resume_json(r):
    return {
        "noeuds": {k: {"ieee": ieee_de(v), "roles": sorted(v["roles"]), "emises": v["emises"],
                       "rssi_median": statistics.median(v["rssi"]) if v["rssi"] else None}
                   for k, v in r["noeuds"].items()},
        "sauts": [{"de": a, "vers": b, **v} for (a, b), v in r["sauts"].items()],
        "parents": [{"enfant": a, "parent": b, "n": c} for (a, b), c in r["parents"].items()],
        "routes_source": [{"origine": a, "relais": list(rel), "destination": b, "n": c}
                          for (a, rel, b), c in r["routes_src"].items()],
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("capture")
    ap.add_argument("--pan")
    ap.add_argument("--json")
    a = ap.parse_args()
    tr = charger(a.capture)
    pan = a.pan or pan_zigbee(tr)
    r = analyser(tr, pan)
    print(rapport(r, pan, len(tr)))
    if a.json:
        with open(a.json, "w") as f:
            json.dump(resume_json(r), f, indent=1)
```

`outils/ecoute/firmware/platformio.ini` :

```ini
; Ecoute passive 802.15.4 (essai du 05/10/2026 ; spec de la sonde, annexe A) :
; un ESP32-C6 en mode promiscuite qui n'emet jamais (acquittements coupes,
; verifies dans chaque ligne d'etat). Meme chaine que la sonde (pioarduino
; 55.03.312-1). Flasher : python3 outils/flasher.py --ecoute (verifie la MAC
; de la carte avant d'ecrire).

[platformio]
default_envs = ecoute

[env:ecoute]
platform = https://github.com/pioarduino/platform-espressif32/releases/download/55.03.312-1/platform-espressif32.zip
framework = arduino
board = esp32-c6-devkitc-1
board_upload.flash_size = 4MB
board_upload.maximum_size = 4194304
board_build.flash_size = 4MB
monitor_speed = 115200
build_flags =
    -DCORE_DEBUG_LEVEL=1
    -DARDUINO_USB_MODE=1
    -DARDUINO_USB_CDC_ON_BOOT=1
```

`outils/ecoute/firmware/src/main.cpp` :

```cpp
// Essai jetable : ecoute passive 802.15.4, sans jamais emettre.
//
// Sortie USB, une ligne par evenement :
//   F <canal> <rssi> <lqi> <t_us> <hex>   trame recue (sans le FCS)
//   S <canal> <recues> <perdues> <ack_tx> <enh_ack>   etat, toutes les 5 s
//   I <texte>                             information
// Entree USB : "c <11..26>" change de canal.
//
// Surete : le pilote acquitte par defaut toute trame qui demande un accuse,
// meme en mode promiscuite. On coupe l'acquittement automatique (simple et
// ameliore) apres esp_ieee802154_enable(), qui remet la PIB a ses defauts,
// et on le verifie dans chaque ligne S. La sonde n'appelle jamais transmit.

#include <Arduino.h>
#include "esp_ieee802154.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

extern "C" {
// Definies dans libieee802154.a, absentes de l'en-tete public.
esp_err_t esp_ieee802154_set_auto_ack_tx(bool enable);
bool esp_ieee802154_get_auto_ack_tx(void);
void ieee802154_pib_set_enhance_ack_tx(bool enable);
bool ieee802154_pib_get_enhance_ack_tx(void);
}

struct Trame {
  uint8_t len;
  uint8_t canal;
  int8_t rssi;
  uint8_t lqi;
  uint64_t t_us;
  uint8_t data[127];
};

static QueueHandle_t s_file;
static volatile uint32_t s_recues = 0;
static volatile uint32_t s_perdues = 0;
static uint8_t s_canal = 11;

static void IRAM_ATTR rx_done(uint8_t *frame, esp_ieee802154_frame_info_t *info) {
  Trame t;
  uint8_t len = frame[0];
  if (len > 127) len = 127;
  t.len = len;
  t.canal = info->channel;
  t.rssi = info->rssi;
  t.lqi = info->lqi;
  t.t_us = info->timestamp;
  memcpy(t.data, frame + 1, len);
  esp_ieee802154_receive_handle_done(frame);
  s_recues++;
  BaseType_t reveil = pdFALSE;
  if (xQueueSendFromISR(s_file, &t, &reveil) != pdTRUE) s_perdues++;
  portYIELD_FROM_ISR(reveil);
}

static void regler_radio() {
  esp_ieee802154_set_auto_ack_tx(false);
  ieee802154_pib_set_enhance_ack_tx(false);
  esp_ieee802154_set_promiscuous(true);
  esp_ieee802154_set_coordinator(false);
  esp_ieee802154_set_rx_when_idle(true);
  esp_ieee802154_set_channel(s_canal);
  esp_ieee802154_receive();
}

static void ecrire_etat() {
  Serial.printf("S %u %lu %lu %d %d\n", s_canal, (unsigned long)s_recues,
                (unsigned long)s_perdues, esp_ieee802154_get_auto_ack_tx() ? 1 : 0,
                ieee802154_pib_get_enhance_ack_tx() ? 1 : 0);
}

void setup() {
  Serial.begin(115200);
  s_file = xQueueCreate(128, sizeof(Trame));
  esp_ieee802154_event_cb_list_t cbs = {};
  cbs.rx_done_cb = rx_done;
  esp_ieee802154_event_callback_list_register(cbs);
  esp_ieee802154_enable();
  regler_radio();
  delay(200);
  Serial.println("I ecoute-802154 essai 0.1");
  ecrire_etat();
}

static char s_ligne[32];
static size_t s_pos = 0;

static void lire_commandes() {
  while (Serial.available()) {
    int c = Serial.read();
    if (c == '\n' || c == '\r') {
      s_ligne[s_pos] = 0;
      if (s_ligne[0] == 'c' && s_ligne[1] == ' ') {
        int n = atoi(s_ligne + 2);
        if (n >= 11 && n <= 26) {
          s_canal = (uint8_t)n;
          regler_radio();
          ecrire_etat();
        } else {
          Serial.println("I canal refuse");
        }
      }
      s_pos = 0;
    } else if (s_pos < sizeof(s_ligne) - 1) {
      s_ligne[s_pos++] = (char)c;
    }
  }
}

void loop() {
  static const char hexa[] = "0123456789ABCDEF";
  static char sortie[300];
  static uint32_t dernier_etat = 0;
  Trame t;
  while (xQueueReceive(s_file, &t, pdMS_TO_TICKS(20)) == pdTRUE) {
    int n = snprintf(sortie, sizeof(sortie), "F %u %d %u %llu ", t.canal, t.rssi, t.lqi,
                     (unsigned long long)t.t_us);
    uint8_t utile = t.len >= 2 ? t.len - 2 : 0;
    for (uint8_t i = 0; i < utile && n < (int)sizeof(sortie) - 3; i++) {
      sortie[n++] = hexa[t.data[i] >> 4];
      sortie[n++] = hexa[t.data[i] & 0xF];
    }
    sortie[n++] = '\n';
    Serial.write((const uint8_t *)sortie, n);
  }
  lire_commandes();
  if (millis() - dernier_etat > 5000) {
    dernier_etat = millis();
    ecrire_etat();
  }
}
```

- [ ] **Step 2 : vérifier sans rien lancer sur une carte.**

Run :

```bash
python3 -m py_compile outils/ecoute/zb.py outils/ecoute/capture.py outils/ecoute/analyse.py
~/.platformio/penv/bin/pio run -d outils/ecoute/firmware
sh outils/tester.sh
```

Expected : aucune sortie pour `py_compile`, `[SUCCESS]` pour la compilation, et une garde qui passe. `__pycache__/` et `.pio/` sont ignorés par git.

- [ ] **Step 3 : commit.**

```bash
git add outils/ecoute/README.md outils/ecoute/zb.py outils/ecoute/capture.py outils/ecoute/analyse.py outils/ecoute/firmware/platformio.ini outils/ecoute/firmware/src/main.cpp
git commit -m "Verser le code de l'essai d'ecoute passive du 05/10, sans capture

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Protocole de la sonde : commandes, lignes, entrées

**Files:**
- Create: `sonde/src/options.h`, `sonde/src/commande.h`, `sonde/src/commande.cpp`, `sonde/src/ligne.h`, `sonde/src/ligne.cpp`, `sonde/src/entrees.h`, `sonde/src/entrees.cpp`, `sonde/test/verif.h`, `sonde/test/lancer.sh`, `sonde/test/test_commande.cpp`, `sonde/test/test_ligne.cpp`, `sonde/test/test_entrees.cpp`
- Modify: `outils/tester.sh` (bloc ci-dessous)

**Interfaces:**
- Consumes : rien.
- Produces (utilisés par les tâches 4 à 6) :
  - `options.h` : `SONDE_ROUTES`, `SONDE_ECHECS`, `SONDE_SIGNAUX` (1 par défaut) ;
  - `commande.h` :
    - `enum class TypeCommande` ;
    - `struct Commande {type, cible, id, delaiMs, nom}` ;
    - `bool nomValide(const char *)`, `bool lireEntier(const char *, uint32_t *)`, `bool lireCourt(const char *, uint16_t *)`, `Commande lireCommande(const char *)` ;
    - `kNomMax` (32), `kDelaiDefautMs` (5000), `kDelaiMinMs` (500), `kDelaiMaxMs` (5000), `kCibleMax` (`0xFFF7`) ;
  - `ligne.h` :
    - `class Ligne` : `debut(type)`, `ajoute(fmt, ...)`, `tient(n)`, `tropLong()`, `fin(&n)`, `kMax` = 4095 ;
    - `class ListeDecoupee(Ligne &, Sortie, ctx)` : `commencer(type, entete)`, `ajouter(objet)`, `terminer()`, `kEnteteMax` = 255 ;
  - `entrees.h` :
    - `struct EntreeVoisin`, `struct VoisinSonde`, `struct EntreeRoute`, `struct PageRoutes`, `kRoutesParPageMax` (16) ;
    - `bool lirePageRoutes(const uint8_t *, size_t, PageRoutes *)`, `void requeteRoutes(uint8_t tsn, uint8_t debut, uint8_t asdu[2])` ;
    - `texteType`, `texteRelation`, `texteEtatRoute`, `texteIeee(ieee, char[17])` ;
    - `size_t jsonEntreeVoisin(const EntreeVoisin &, char *, size_t)`, `jsonVoisinSonde(...)`, `jsonEntreeRoute(...)` ;
  - `sonde/test/lancer.sh` (les tâches 4 et 5 y ajoutent leurs tests) et `sonde/test/verif.h` (`CHECK`, `bilan`).

- [ ] **Step 1 : écrire les tests et leur lanceur.**

`sonde/test/verif.h` :

```cpp
#pragma once
// Verifications des tests hote de la sonde (sh sonde/test/lancer.sh) : chaque
// CHECK compte, un echec s'affiche avec sa ligne, et bilan() rend le code de
// sortie du programme de test.
#include <stdio.h>

static int gChecks = 0, gFails = 0;
#define CHECK(cond, ...)                            \
  do {                                              \
    gChecks++;                                      \
    if (!(cond)) {                                  \
      gFails++;                                     \
      printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
      printf(__VA_ARGS__);                          \
      printf("\n");                                 \
    }                                               \
  } while (0)

static inline int bilan(const char *nom) {
  printf("%s : %d verifications, %d echec(s)\n", nom, gChecks, gFails);
  return gFails ? 1 : 0;
}
```

`sonde/test/lancer.sh` (première version) :

```sh
#!/bin/sh
# Tests hote purs de la sonde, sans carte : chaque module pur de sonde/src a
# son programme de test ici (test_<module>.cpp).
#
#   sh sonde/test/lancer.sh
#
# clang++ de Xcode, ASan et UBSan. Les binaires vont dans un dossier
# temporaire : rien ne reste dans le depot. Les commandes routes et echecs
# sont testees actives (par defaut) puis coupees (SONDE_ROUTES=0,
# SONDE_ECHECS=0), comme apres l'essai si on les retire.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
SRC="$ICI/../src"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
DRAPEAUX="-std=gnu++17 -g -O1 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"
compiler() {
  nom=$1
  shift
  clang++ $DRAPEAUX -I"$SRC" "$@" -o "$TMP/$nom"
}
compiler test_commande "$ICI/test_commande.cpp" "$SRC/commande.cpp"
compiler test_commande_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_commande.cpp" "$SRC/commande.cpp"
compiler test_ligne "$ICI/test_ligne.cpp" "$SRC/ligne.cpp"
compiler test_entrees "$ICI/test_entrees.cpp" "$SRC/entrees.cpp"
"$TMP/test_commande"
"$TMP/test_commande_sans"
"$TMP/test_ligne"
"$TMP/test_entrees"
```

`sonde/test/test_commande.cpp` :

```cpp
// Tests hote de sonde/src/commande.{h,cpp} : lecture des commandes de l'USB.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "commande.h"
#include "verif.h"

static bool est(const char *ligne, TypeCommande t) { return lireCommande(ligne).type == t; }

int main() {
  // Noms
  CHECK(nomValide("SONDE-Z1"), "defaut");
  CHECK(nomValide("a"), "un caractere");
  CHECK(nomValide("Abc_def.1-2"), "permis");
  CHECK(nomValide("12345678901234567890123456789012"), "32 caracteres");
  CHECK(!nomValide("123456789012345678901234567890123"), "33 caracteres");
  CHECK(!nomValide(""), "vide");
  CHECK(!nomValide("a b"), "espace");
  CHECK(!nomValide("a\"b"), "guillemet");
  CHECK(!nomValide("caf\xc3\xa9"), "accent");

  // Entiers
  uint32_t v = 7;
  CHECK(lireEntier("0", &v) && v == 0, "0");
  CHECK(lireEntier("4294967295", &v) && v == 4294967295u, "max");
  v = 7;
  CHECK(!lireEntier("4294967296", &v) && v == 7, "trop grand, v intact");
  CHECK(!lireEntier("", &v) && v == 7, "vide");
  CHECK(!lireEntier("-1", &v) && v == 7, "signe");
  CHECK(!lireEntier("+1", &v) && v == 7, "plus");
  CHECK(!lireEntier("12a", &v) && v == 7, "lettre");
  CHECK(!lireEntier("00000000001", &v) && v == 7, "11 chiffres");

  // Adresses courtes
  uint16_t c = 9;
  CHECK(lireCourt("1A2B", &c) && c == 0x1A2B, "majuscules");
  CHECK(lireCourt("ffff", &c) && c == 0xFFFF, "minuscules");
  CHECK(lireCourt("0000", &c) && c == 0, "pont");
  c = 9;
  CHECK(!lireCourt("1A2", &c) && c == 9, "3 hexa");
  CHECK(!lireCourt("1A2B3", &c) && c == 9, "5 hexa");
  CHECK(!lireCourt("0x1A", &c) && c == 9, "prefixe");
  CHECK(!lireCourt("1G2B", &c) && c == 9, "G");

  // Commandes sans argument
  CHECK(est("bonjour", TypeCommande::kBonjour), "bonjour");
  CHECK(est("  etat  ", TypeCommande::kEtat), "espaces autour");
  CHECK(est("voisins", TypeCommande::kVoisins), "voisins");
  CHECK(est("suspendre", TypeCommande::kSuspendre), "suspendre");
  CHECK(est("reprendre", TypeCommande::kReprendre), "reprendre");
  CHECK(est("oubli", TypeCommande::kOubli), "oubli");
  CHECK(est("etat 1", TypeCommande::kSyntaxe), "argument en trop");
  CHECK(est("Etat", TypeCommande::kInconnue), "casse");
  CHECK(est("diag 0400 0,1 5", TypeCommande::kInconnue), "commande de la sonde Thread");
  CHECK(est("", TypeCommande::kInconnue), "vide");
  CHECK(est("   ", TypeCommande::kInconnue), "blanc");

  // nom
  Commande n = lireCommande("nom SONDE-Z2");
  CHECK(n.type == TypeCommande::kNom && strcmp(n.nom, "SONDE-Z2") == 0, "nom");
  CHECK(est("nom", TypeCommande::kSyntaxe), "nom sans texte");
  CHECK(est("nom a b", TypeCommande::kSyntaxe), "nom avec espace");
  CHECK(est("nom 123456789012345678901234567890123", TypeCommande::kSyntaxe), "nom trop long");

  // table
  Commande t = lireCommande("table 1a2b 7");
  CHECK(t.type == TypeCommande::kTable && t.cible == 0x1A2B && t.id == 7 && t.delaiMs == kDelaiDefautMs, "table");
  t = lireCommande("table FFF7 4294967295 5000");
  CHECK(t.type == TypeCommande::kTable && t.cible == 0xFFF7 && t.id == 4294967295u && t.delaiMs == 5000,
        "bornes hautes");
  t = lireCommande("table   0000   1   500  ");
  CHECK(t.type == TypeCommande::kTable && t.delaiMs == 500, "espaces en trop, delai minimal");
  CHECK(est("table 0000 1 499", TypeCommande::kSyntaxe), "delai trop court");
  CHECK(est("table 0000 1 5001", TypeCommande::kSyntaxe), "delai au-dela de la borne de la pile");
  CHECK(est("table FFF8 1", TypeCommande::kSyntaxe), "diffusion FFF8");
  CHECK(est("table FFFC 1", TypeCommande::kSyntaxe), "diffusion aux routeurs");
  CHECK(est("table FFFD 1", TypeCommande::kSyntaxe), "diffusion aux recepteurs allumes");
  CHECK(est("table ffff 1", TypeCommande::kSyntaxe), "diffusion a tous");
  CHECK(est("table 0000", TypeCommande::kSyntaxe), "sans id");
  CHECK(est("table", TypeCommande::kSyntaxe), "sans cible");
  CHECK(est("table 000 1", TypeCommande::kSyntaxe), "cible courte");
  CHECK(est("table 0000 x", TypeCommande::kSyntaxe), "id non decimal");
  CHECK(est("table 0000 1 5000 9", TypeCommande::kSyntaxe), "argument en trop");
  CHECK(est("table 0000 1 5000 9 9", TypeCommande::kSyntaxe), "deux arguments en trop");

  // routes et echecs : actives par defaut ; coupes (SONDE_ROUTES=0,
  // SONDE_ECHECS=0), ils n'existent pas et repondent « inconnue ».
#if SONDE_ROUTES
  Commande r = lireCommande("routes 3C4D 8 1000");
  CHECK(r.type == TypeCommande::kRoutes && r.cible == 0x3C4D && r.id == 8 && r.delaiMs == 1000, "routes");
  CHECK(est("routes FFFF 8", TypeCommande::kSyntaxe), "routes vers une diffusion");
#else
  CHECK(est("routes 3C4D 8 1000", TypeCommande::kInconnue), "routes coupee");
#endif
#if SONDE_ECHECS
  Commande e = lireCommande("echecs 3C4D 9");
  CHECK(e.type == TypeCommande::kEchecs && e.cible == 0x3C4D && e.id == 9, "echecs");
  CHECK(est("echecs 3C4D", TypeCommande::kSyntaxe), "echecs sans id");
  CHECK(est("echecs FFFD 9", TypeCommande::kSyntaxe), "echecs vers une diffusion");
#else
  CHECK(est("echecs 3C4D 9", TypeCommande::kInconnue), "echecs coupee");
#endif

  // Ligne trop longue
  char longue[300];
  memset(longue, 'a', sizeof(longue) - 1);
  longue[sizeof(longue) - 1] = 0;
  CHECK(est(longue, TypeCommande::kSyntaxe), "ligne de 299 caracteres");

  return bilan("commande");
}
```

`sonde/test/test_ligne.cpp` :

```cpp
// Tests hote de sonde/src/ligne.{h,cpp} : lignes machine et listes decoupees.
// Lancer : sh sonde/test/lancer.sh
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

#include "ligne.h"
#include "verif.h"

static std::vector<std::string> gLignes;
static void sortie(void *, const uint8_t *o, size_t n) { gLignes.emplace_back((const char *)o, n); }

static std::string texte(Ligne &l) {
  size_t n = 0;
  const uint8_t *o = l.fin(&n);
  return std::string((const char *)o, n);
}

// Nombre d'occurrences de motif dans s.
static size_t compte(const std::string &s, const std::string &motif) {
  size_t n = 0;
  for (size_t i = s.find(motif); i != std::string::npos; i = s.find(motif, i + 1)) n++;
  return n;
}

int main() {
  Ligne l;
  l.debut("bonjour");
  l.ajoute(",\"produit\":\"%s\"", "sonde-zigbee");
  CHECK(texte(l) == "\x1E{\"v\":1,\"t\":\"bonjour\",\"produit\":\"sonde-zigbee\"}\n", "ligne simple");

  // Exactement 4095 octets emis : RS + en-tete + remplissage + } + LF.
  l.debut("x");
  const size_t entete = 1 + strlen("{\"v\":1,\"t\":\"x\"");
  std::string plein(Ligne::kMax - 2 - entete, 'a');
  CHECK(l.tient(plein.size()) && !l.tient(plein.size() + 1), "tient a la limite");
  l.ajoute("%s", plein.c_str());
  CHECK(!l.tropLong(), "a la limite");
  std::string t = texte(l);
  CHECK(t.size() == Ligne::kMax && t.back() == '\n' && t[t.size() - 2] == '}', "4095 octets");

  // Un octet de plus : trop longue, remplacee par l'erreur.
  l.debut("x");
  l.ajoute("%s", plein.c_str());
  l.ajoute("b");
  CHECK(l.tropLong(), "debordement vu");
  l.ajoute("c");  // ignore
  CHECK(texte(l) == "\x1E{\"v\":1,\"t\":\"erreur\",\"erreur\":\"ligne trop longue\"}\n", "erreur de debordement");

  // Liste vide.
  ListeDecoupee liste(l, sortie, nullptr);
  gLignes.clear();
  liste.commencer("voisins", "");
  liste.terminer();
  CHECK(gLignes.size() == 1 && gLignes[0] == "\x1E{\"v\":1,\"t\":\"voisins\",\"liste\":[],\"suite\":false}\n",
        "liste vide");

  // Trois objets : une ligne.
  gLignes.clear();
  liste.commencer("table", ",\"id\":7,\"ok\":true");
  liste.ajouter("{\"a\":1}");
  liste.ajouter("{\"a\":2}");
  liste.ajouter("{\"a\":3}");
  liste.terminer();
  CHECK(gLignes.size() == 1 &&
            gLignes[0] == "\x1E{\"v\":1,\"t\":\"table\",\"id\":7,\"ok\":true,\"liste\":[{\"a\":1},{\"a\":2},{\"a\":3}],"
                          "\"suite\":false}\n",
        "trois objets");

  // 100 objets de 150 octets : plusieurs lignes, chacune complete et dans la
  // limite, l'en-tete repris, "suite":true sauf sur la derniere, l'ordre garde.
  gLignes.clear();
  liste.commencer("table", ",\"id\":42,\"cible\":\"1A2B\"");
  for (int i = 0; i < 100; i++) {
    char objet[160];
    snprintf(objet, sizeof(objet), "{\"n\":%03d,\"r\":\"%s\"}", i, std::string(150 - 16, 'r').c_str());
    CHECK(strlen(objet) == 150, "objet de 150 octets");
    liste.ajouter(objet);
  }
  liste.terminer();
  CHECK(gLignes.size() == 4, "4 lignes (%zu)", gLignes.size());
  size_t objets = 0;
  int attendu = 0;
  bool ordre = true;
  for (size_t i = 0; i < gLignes.size(); i++) {
    const std::string &g = gLignes[i];
    const bool derniere = i + 1 == gLignes.size();
    CHECK(g.size() <= Ligne::kMax, "ligne %zu dans la limite (%zu)", i, g.size());
    CHECK(g.rfind("\x1E{\"v\":1,\"t\":\"table\",\"id\":42,\"cible\":\"1A2B\",\"liste\":[", 0) == 0, "en-tete %zu", i);
    const std::string queue = derniere ? "],\"suite\":false}\n" : "],\"suite\":true}\n";
    CHECK(g.size() > queue.size() && g.compare(g.size() - queue.size(), queue.size(), queue) == 0, "queue %zu", i);
    objets += compte(g, "{\"n\":");
    for (size_t p = g.find("{\"n\":"); p != std::string::npos; p = g.find("{\"n\":", p + 1)) {
      ordre = ordre && atoi(g.c_str() + p + 5) == attendu;
      attendu++;
    }
  }
  CHECK(objets == 100 && ordre, "100 objets dans l'ordre");

  return bilan("ligne");
}
```

`sonde/test/test_entrees.cpp` :

```cpp
// Tests hote de sonde/src/entrees.{h,cpp} : textes des champs, objets JSON des
// tables, lecture d'une Mgmt_Rtg_rsp brute. Valeurs inventees.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include <string>

#include "entrees.h"
#include "verif.h"

int main() {
  // Adresse longue : ordre du reseau (poids faible d'abord) -> poids fort d'abord.
  const uint8_t ieee[8] = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA0};
  char t[17];
  texteIeee(ieee, t);
  CHECK(strcmp(t, "A000000000000001") == 0, "ieee (%s)", t);

  CHECK(strcmp(texteType(0), "coordinateur") == 0 && strcmp(texteType(1), "routeur") == 0 &&
            strcmp(texteType(2), "final") == 0 && strcmp(texteType(3), "inconnu") == 0 &&
            strcmp(texteType(9), "inconnu") == 0,
        "types");
  CHECK(strcmp(texteRelation(0), "parent") == 0 && strcmp(texteRelation(1), "enfant") == 0 &&
            strcmp(texteRelation(2), "frere") == 0 && strcmp(texteRelation(3), "aucune") == 0 &&
            strcmp(texteRelation(4), "ancien_enfant") == 0 && strcmp(texteRelation(5), "enfant") == 0 &&
            strcmp(texteRelation(7), "aucune") == 0,
        "relations");
  CHECK(strcmp(texteEtatRoute(0), "active") == 0 && strcmp(texteEtatRoute(1), "decouverte") == 0 &&
            strcmp(texteEtatRoute(2), "echec_decouverte") == 0 && strcmp(texteEtatRoute(3), "inactive") == 0 &&
            strcmp(texteEtatRoute(4), "validation") == 0 && strcmp(texteEtatRoute(6), "inconnu") == 0,
        "etats de route");

  // Entree de Mgmt_Lqi_rsp : l'exemple de la spec (section 2).
  EntreeVoisin e;
  const uint8_t pont[8] = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA0};
  memcpy(e.ieee, pont, 8);
  e.court = 0x0000;
  e.type = 0;
  e.ecoute = 1;
  e.relation = 3;
  e.admission = 0;
  e.profondeur = 0;
  e.lqi = 212;
  char o[256];
  size_t n = jsonEntreeVoisin(e, o, sizeof(o));
  const std::string attendu =
      "{\"court\":\"0000\",\"ieee\":\"A000000000000003\",\"type\":\"coordinateur\",\"relation\":\"aucune\","
      "\"ecoute\":true,\"profondeur\":0,\"admission\":false,\"lqi\":212}";
  CHECK(n == attendu.size() && attendu == o, "entree de table (%s)", o);
  e.ecoute = 2;
  e.admission = 7;
  jsonEntreeVoisin(e, o, sizeof(o));
  CHECK(strstr(o, "\"ecoute\":null") && strstr(o, "\"admission\":null"), "inconnus en null");
  CHECK(jsonEntreeVoisin(e, o, 20) == 0, "sortie trop petite");

  // Voisin de la sonde : l'exemple de la spec.
  VoisinSonde v;
  memcpy(v.ieee, ieee, 8);
  v.ieee[0] = 0x02;
  v.court = 0x1A2B;
  v.type = 1;
  v.relation = 0;
  v.lqi = 180;
  v.rssi = -71;
  v.coutSortant = 1;
  v.age = 0;
  n = jsonVoisinSonde(v, o, sizeof(o));
  const std::string attenduV =
      "{\"court\":\"1A2B\",\"ieee\":\"A000000000000002\",\"type\":\"routeur\",\"relation\":\"parent\",\"lqi\":180,"
      "\"rssi\":-71,\"cout_sortant\":1,\"age\":0}";
  CHECK(n == attenduV.size() && attenduV == o, "voisin de la sonde (%s)", o);

  // Mgmt_Rtg_req.
  uint8_t req[2];
  requeteRoutes(0x81, 6, req);
  CHECK(req[0] == 0x81 && req[1] == 6, "requete de routes");

  // Mgmt_Rtg_rsp : 2 entrees sur un total de 5, depuis l'index 3.
  const uint8_t rsp[] = {0x81, 0x00, 5, 3, 2,
                         0x2B, 0x1A, 0x00, 0x4D, 0x3C,   // 1A2B active, par 3C4D
                         0x6F, 0x5E, 0x3A, 0x00, 0x00};  // 5E6F : etat 2, memoire, plusieurs vers un, enregistrement
  PageRoutes p;
  CHECK(lirePageRoutes(rsp, sizeof(rsp), &p), "page lue");
  CHECK(p.tsn == 0x81 && p.statut == 0 && p.total == 5 && p.debut == 3 && p.nombre == 2, "en-tete de page");
  CHECK(p.entrees[0].destination == 0x1A2B && p.entrees[0].etat == 0 && p.entrees[0].prochain == 0x3C4D &&
            !p.entrees[0].memoireLimitee && !p.entrees[0].plusieursVersUn && !p.entrees[0].enregistrement,
        "premiere route");
  CHECK(p.entrees[1].destination == 0x5E6F && p.entrees[1].etat == 2 && p.entrees[1].memoireLimitee &&
            p.entrees[1].plusieursVersUn && p.entrees[1].enregistrement && p.entrees[1].prochain == 0,
        "seconde route");
  n = jsonEntreeRoute(p.entrees[0], o, sizeof(o));
  const std::string attenduR =
      "{\"destination\":\"1A2B\",\"etat\":\"active\",\"prochain\":\"3C4D\",\"memoire_limitee\":false,"
      "\"plusieurs_vers_un\":false,\"enregistrement\":false}";
  CHECK(n == attenduR.size() && attenduR == o, "route en JSON (%s)", o);

  // Statut d'echec : deux octets suffisent.
  const uint8_t refus[] = {0x82, 0x84};
  CHECK(lirePageRoutes(refus, sizeof(refus), &p) && p.statut == 0x84 && p.nombre == 0, "refus 0x84");
  // Trames abimees.
  CHECK(!lirePageRoutes(rsp, 1, &p), "un octet");
  CHECK(!lirePageRoutes(rsp, 4, &p), "en-tete coupe");
  CHECK(!lirePageRoutes(rsp, sizeof(rsp) - 1, &p), "entree coupee");
  // Plus de 16 entrees annoncees et portees : les 16 premieres gardees.
  uint8_t grande[5 + 5 * 20] = {0x83, 0x00, 40, 0, 20};
  for (int i = 0; i < 20; i++) grande[5 + 5 * i] = (uint8_t)i;
  CHECK(lirePageRoutes(grande, sizeof(grande), &p) && p.nombre == kRoutesParPageMax &&
            p.entrees[15].destination == 15,
        "16 entrees gardees");

  return bilan("entrees");
}
```

- [ ] **Step 2 : les lancer, ils échouent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
clang++: error: no such file or directory: '<depot>/sonde/test/../src/commande.cpp'
```

- [ ] **Step 3 : écrire les modules.**

`sonde/src/options.h` :

```cpp
#pragma once
// Options de compilation de la sonde, posees par platformio.ini (build_flags)
// ou par sonde/test/lancer.sh. Par defaut, les deux commandes de l'essai
// (spec de la sonde, section 4 : E4 et E5) sont actives ; 0 les retire, avec
// leur place dans la liste blanche. Le journal des signaux de la pile est
// actif aussi pendant l'essai ; la tache 9 du plan decide de le garder.
#ifndef SONDE_ROUTES
#define SONDE_ROUTES 1  // commande routes (Mgmt_Rtg_req en trame APS brute)
#endif
#ifndef SONDE_ECHECS
#define SONDE_ECHECS 1  // commande echecs (Mgmt_NWK_Update_req, balayage d'energie)
#endif
#ifndef SONDE_SIGNAUX
#define SONDE_SIGNAUX 1  // lignes « signal » : chaque signal de la pile, pour l'essai
#endif
```

`sonde/src/commande.h` :

```cpp
#pragma once
// ===========================================================================
//  Commandes de l'USB (spec de la sonde, section 2)
//
//  Une ligne, sans sa fin de ligne, devient une Commande. Mots separes par
//  des espaces ; les espaces en trop au debut, a la fin et entre les mots
//  sont ignores. Un premier mot inconnu donne kInconnue ; des arguments mal
//  formes, kSyntaxe.
//
//    bonjour | etat | voisins | suspendre | reprendre | oubli   (sans argument)
//    nom <texte>                                1 a 32 caracteres permis
//    table <cible> <id> [<delai ms>]            cible : 4 hexa ; id : decimal
//    routes <cible> <id> [<delai ms>]           (si SONDE_ROUTES)
//    echecs <cible> <id> [<delai ms>]           (si SONDE_ECHECS)
//
//  Cible : une adresse d'appareil, jamais une adresse de diffusion (FFF8 a
//  FFFF : syntaxe). Delai : de 500 a 5000 ms, 5000 par defaut (par page pour
//  table et routes ; pour la requete unique d'echecs). La pile Zigbee borne
//  elle-meme une requete ZDO a 5 s : au-dela, le delai ne changerait rien.
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_commande.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "options.h"

enum class TypeCommande : uint8_t {
  kBonjour,
  kNom,
  kEtat,
  kVoisins,
  kTable,
  kRoutes,
  kEchecs,
  kSuspendre,
  kReprendre,
  kOubli,
  kInconnue,
  kSyntaxe,
};

static constexpr size_t kNomMax = 32;
static constexpr uint32_t kDelaiDefautMs = 5000;
static constexpr uint32_t kDelaiMinMs = 500;
static constexpr uint32_t kDelaiMaxMs = 5000;
static constexpr uint16_t kCibleMax = 0xFFF7;  // FFF8 a FFFF : diffusions

struct Commande {
  TypeCommande type = TypeCommande::kInconnue;
  uint16_t cible = 0;                // table, routes, echecs
  uint32_t id = 0;                   // table, routes, echecs
  uint32_t delaiMs = kDelaiDefautMs; // table, routes, echecs
  char nom[kNomMax + 1] = {0};       // nom
};

// 1 a 32 caracteres parmi les lettres ASCII, les chiffres, « - », « _ » et
// « . » : rien a echapper dans le JSON.
bool nomValide(const char *s);

// Decimal sans signe, 1 a 10 chiffres, au plus 4 294 967 295. Refuse : v
// intact.
bool lireEntier(const char *s, uint32_t *v);

// Exactement 4 hexa, majuscules ou minuscules. Refuse : v intact.
bool lireCourt(const char *s, uint16_t *v);

Commande lireCommande(const char *ligne);
```

`sonde/src/commande.cpp` :

```cpp
#include "commande.h"

#include <string.h>

bool nomValide(const char *s) {
  const size_t n = strlen(s);
  if (n == 0 || n > kNomMax) return false;
  for (size_t i = 0; i < n; i++) {
    const char c = s[i];
    const bool permis = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
                        c == '_' || c == '.';
    if (!permis) return false;
  }
  return true;
}

bool lireEntier(const char *s, uint32_t *v) {
  const size_t n = strlen(s);
  if (n == 0 || n > 10) return false;
  uint64_t x = 0;
  for (size_t i = 0; i < n; i++) {
    if (s[i] < '0' || s[i] > '9') return false;
    x = x * 10 + (uint64_t)(s[i] - '0');
  }
  if (x > 0xFFFFFFFFull) return false;
  *v = (uint32_t)x;
  return true;
}

bool lireCourt(const char *s, uint16_t *v) {
  if (strlen(s) != 4) return false;
  uint16_t x = 0;
  for (size_t i = 0; i < 4; i++) {
    const char c = s[i];
    uint16_t chiffre;
    if (c >= '0' && c <= '9') chiffre = (uint16_t)(c - '0');
    else if (c >= 'A' && c <= 'F') chiffre = (uint16_t)(c - 'A' + 10);
    else if (c >= 'a' && c <= 'f') chiffre = (uint16_t)(c - 'a' + 10);
    else return false;
    x = (uint16_t)(x * 16 + chiffre);
  }
  *v = x;
  return true;
}

namespace {

constexpr size_t kLigneMax = 255;  // au-dela : syntaxe
constexpr size_t kMotsMax = 5;

// Coupe la copie de la ligne en mots (au plus kMotsMax ; un mot de plus
// compte pour « trop de mots »). Rend le nombre de mots, kMotsMax + 1 s'il y
// en a trop.
size_t couper(char *copie, char *mots[kMotsMax]) {
  size_t n = 0;
  char *p = copie;
  while (*p) {
    while (*p == ' ') p++;
    if (!*p) break;
    if (n == kMotsMax) return kMotsMax + 1;
    mots[n++] = p;
    while (*p && *p != ' ') p++;
    if (*p) *p++ = 0;
  }
  return n;
}

// table, routes et echecs : <cible> <id> [<delai ms>].
Commande cibleIdDelai(TypeCommande type, char *mots[kMotsMax], size_t n) {
  Commande c;
  c.type = TypeCommande::kSyntaxe;
  if (n < 3 || n > 4) return c;
  uint16_t cible;
  uint32_t id;
  uint32_t delai = kDelaiDefautMs;
  if (!lireCourt(mots[1], &cible) || cible > kCibleMax || !lireEntier(mots[2], &id)) return c;
  if (n == 4 && (!lireEntier(mots[3], &delai) || delai < kDelaiMinMs || delai > kDelaiMaxMs)) return c;
  c.type = type;
  c.cible = cible;
  c.id = id;
  c.delaiMs = delai;
  return c;
}

}  // namespace

Commande lireCommande(const char *ligne) {
  Commande c;
  if (strlen(ligne) > kLigneMax) {
    c.type = TypeCommande::kSyntaxe;
    return c;
  }
  char copie[kLigneMax + 1];
  strcpy(copie, ligne);
  char *mots[kMotsMax] = {};
  const size_t n = couper(copie, mots);
  if (n == 0) return c;  // ligne vide : kInconnue (l'appelant n'en envoie pas)
  const char *m = mots[0];

  struct Simple {
    const char *mot;
    TypeCommande type;
  };
  static const Simple kSimples[] = {
      {"bonjour", TypeCommande::kBonjour},     {"etat", TypeCommande::kEtat},
      {"voisins", TypeCommande::kVoisins},     {"suspendre", TypeCommande::kSuspendre},
      {"reprendre", TypeCommande::kReprendre}, {"oubli", TypeCommande::kOubli},
  };
  for (const Simple &s : kSimples) {
    if (strcmp(m, s.mot) == 0) {
      c.type = n == 1 ? s.type : TypeCommande::kSyntaxe;
      return c;
    }
  }
  if (strcmp(m, "nom") == 0) {
    if (n != 2 || !nomValide(mots[1])) {
      c.type = TypeCommande::kSyntaxe;
      return c;
    }
    c.type = TypeCommande::kNom;
    strcpy(c.nom, mots[1]);
    return c;
  }
  if (strcmp(m, "table") == 0) return cibleIdDelai(TypeCommande::kTable, mots, n);
#if SONDE_ROUTES
  if (strcmp(m, "routes") == 0) return cibleIdDelai(TypeCommande::kRoutes, mots, n);
#endif
#if SONDE_ECHECS
  if (strcmp(m, "echecs") == 0) return cibleIdDelai(TypeCommande::kEchecs, mots, n);
#endif
  return c;  // kInconnue
}
```

`sonde/src/ligne.h` :

```cpp
#pragma once
// ===========================================================================
//  Lignes machine de l'USB (spec de la sonde, section 2)
//
//  RS (0x1E), JSON compact en ASCII, fin de ligne : 4095 octets emis au plus,
//  RS et fin de ligne compris. Une ligne qui deborde est remplacee par
//  {"v":1,"t":"erreur","erreur":"ligne trop longue"}.
//
//  ListeDecoupee ecrit une liste d'objets sur une ou plusieurs lignes :
//  chacune reprend le type et l'en-tete, porte "liste":[...] puis
//  "suite":true, sauf la derniere ("suite":false).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_ligne.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

class Ligne {
 public:
  static constexpr size_t kMax = 4095;  // octets emis au plus, RS et LF compris

  // RS puis {"v":1,"t":"<type>"
  void debut(const char *type);
  // Ajoute du texte (printf) ; au-dela de la place, la ligne est trop longue.
  void ajoute(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
  // n octets de plus tiennent-ils, avant le « } » et la fin de ligne ?
  bool tient(size_t n) const;
  bool tropLong() const { return trop_; }
  // Ferme la ligne (« } » et LF) et rend ses octets, valables jusqu'au
  // prochain debut().
  const uint8_t *fin(size_t *n);

 private:
  char buf_[kMax + 1];  // + le 0 final de vsnprintf
  size_t long_ = 0;
  bool trop_ = false;
};

class ListeDecoupee {
 public:
  using Sortie = void (*)(void *ctx, const uint8_t *octets, size_t n);
  static constexpr size_t kEnteteMax = 255;

  ListeDecoupee(Ligne &ligne, Sortie sortie, void *ctx) : ligne_(ligne), sortie_(sortie), ctx_(ctx) {}
  // type : "table", "voisins"... ; entete : champs a reprendre sur chaque
  // ligne, chacun precede de sa virgule (",\"id\":7"), ou "".
  void commencer(const char *type, const char *entete);
  // Un objet JSON complet ("{...}").
  void ajouter(const char *objet);
  // Ferme la derniere ligne, avec "suite":false.
  void terminer();

 private:
  void ouvrir();
  void fermer(bool suite);
  Ligne &ligne_;
  Sortie sortie_;
  void *ctx_;
  const char *type_ = "";
  char entete_[kEnteteMax + 1] = {0};
  bool premier_ = true;  // aucun objet encore sur la ligne en cours
};
```

`sonde/src/ligne.cpp` :

```cpp
#include "ligne.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

// Place a garder pour « } » et la fin de ligne.
static constexpr size_t kFin = 2;
// "],\"suite\":false" : la fermeture d'une ligne de liste.
static constexpr size_t kFermeture = 15;

void Ligne::debut(const char *type) {
  long_ = 0;
  trop_ = false;
  buf_[long_++] = 0x1E;
  ajoute("{\"v\":1,\"t\":\"%s\"", type);
}

void Ligne::ajoute(const char *fmt, ...) {
  if (trop_) return;
  const size_t reste = kMax - kFin - long_;
  va_list ap;
  va_start(ap, fmt);
  const int n = vsnprintf(buf_ + long_, reste + 1, fmt, ap);
  va_end(ap);
  if (n < 0 || (size_t)n > reste) {
    trop_ = true;
    return;
  }
  long_ += (size_t)n;
}

bool Ligne::tient(size_t n) const { return !trop_ && long_ + n <= kMax - kFin; }

const uint8_t *Ligne::fin(size_t *n) {
  if (trop_) {
    debut("erreur");
    ajoute(",\"erreur\":\"ligne trop longue\"");
  }
  buf_[long_++] = '}';
  buf_[long_++] = '\n';
  *n = long_;
  return (const uint8_t *)buf_;
}

void ListeDecoupee::commencer(const char *type, const char *entete) {
  type_ = type;
  snprintf(entete_, sizeof(entete_), "%s", entete);
  ouvrir();
}

void ListeDecoupee::ouvrir() {
  ligne_.debut(type_);
  ligne_.ajoute("%s,\"liste\":[", entete_);
  premier_ = true;
}

void ListeDecoupee::fermer(bool suite) {
  ligne_.ajoute("],\"suite\":%s", suite ? "true" : "false");
  size_t n = 0;
  const uint8_t *octets = ligne_.fin(&n);
  sortie_(ctx_, octets, n);
}

void ListeDecoupee::ajouter(const char *objet) {
  const size_t n = strlen(objet) + (premier_ ? 0 : 1);
  if (!premier_ && !ligne_.tient(n + kFermeture)) {
    fermer(true);
    ouvrir();
  }
  ligne_.ajoute("%s%s", premier_ ? "" : ",", objet);
  premier_ = false;
}

void ListeDecoupee::terminer() { fermer(false); }
```

`sonde/src/entrees.h` :

```cpp
#pragma once
// ===========================================================================
//  Entrees des tables, en champs bruts et en objets JSON (spec de la sonde,
//  section 2)
//
//  - EntreeVoisin : une entree de Mgmt_Lqi_rsp (table des voisins d'un
//    routeur), recopiee de la reponse que la pile Zigbee a decoupee ;
//  - VoisinSonde : une entree de la table des voisins de la sonde
//    (esp_zb_nwk_get_next_neighbor) ;
//  - EntreeRoute et PageRoutes : Mgmt_Rtg_rsp, lue ici dans la trame brute
//    (la pile n'a pas de requete de table de routage : section 4, E4).
//
//  Adresse longue : 8 octets dans l'ordre du reseau (poids faible d'abord),
//  ecrite en 16 hexa majuscules, poids fort d'abord. Adresse courte : 4 hexa
//  majuscules.
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_entrees.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

struct EntreeVoisin {
  uint8_t ieee[8] = {0};
  uint16_t court = 0;
  uint8_t type = 3;       // 0 coordinateur, 1 routeur, 2 final, 3 inconnu
  uint8_t ecoute = 2;     // recepteur allume au repos : 0 non, 1 oui, 2 inconnu
  uint8_t relation = 3;   // 0 parent, 1 enfant, 2 frere, 3 aucune, 4 ancien enfant,
                          // 5 enfant pas encore authentifie
  uint8_t admission = 2;  // accepte des adhesions : 0 non, 1 oui, 2 inconnu
  uint8_t profondeur = 0;
  uint8_t lqi = 0;
};

struct VoisinSonde {
  uint8_t ieee[8] = {0};
  uint16_t court = 0;
  uint8_t type = 3;
  uint8_t relation = 3;
  uint8_t lqi = 0;
  int8_t rssi = 0;
  uint8_t coutSortant = 0;
  uint8_t age = 0;
};

struct EntreeRoute {
  uint16_t destination = 0;
  uint8_t etat = 0;  // 0 active, 1 decouverte, 2 echec de decouverte, 3 inactive, 4 validation
  bool memoireLimitee = false;
  bool plusieursVersUn = false;
  bool enregistrement = false;  // un Route Record doit preceder le prochain envoi
  uint16_t prochain = 0;
};

// Mgmt_Rtg_rsp : tsn, statut, puis (statut 0 seulement) total, index de
// depart, nombre d'entrees et 5 octets par entree.
static constexpr size_t kRoutesParPageMax = 16;
struct PageRoutes {
  uint8_t tsn = 0;
  uint8_t statut = 0;
  uint8_t total = 0;
  uint8_t debut = 0;
  uint8_t nombre = 0;  // entrees gardees (au plus kRoutesParPageMax)
  EntreeRoute entrees[kRoutesParPageMax];
};

// Lit une Mgmt_Rtg_rsp brute ; false si la trame est trop courte ou annonce
// plus d'entrees qu'elle n'en porte. Au-dela de kRoutesParPageMax entrees,
// seules les premieres sont gardees (la page suivante reprendra la).
bool lirePageRoutes(const uint8_t *asdu, size_t n, PageRoutes *p);
// Mgmt_Rtg_req brute : tsn, puis index de depart.
void requeteRoutes(uint8_t tsn, uint8_t debut, uint8_t asdu[2]);

const char *texteType(uint8_t type);
const char *texteRelation(uint8_t relation);
const char *texteEtatRoute(uint8_t etat);
void texteIeee(const uint8_t ieee[8], char sortie[17]);

// Objets JSON ; rendent leur longueur, ou 0 si la sortie est trop petite.
size_t jsonEntreeVoisin(const EntreeVoisin &e, char *sortie, size_t taille);
size_t jsonVoisinSonde(const VoisinSonde &v, char *sortie, size_t taille);
size_t jsonEntreeRoute(const EntreeRoute &r, char *sortie, size_t taille);
```

`sonde/src/entrees.cpp` :

```cpp
#include "entrees.h"

#include <stdio.h>

const char *texteType(uint8_t type) {
  switch (type) {
    case 0: return "coordinateur";
    case 1: return "routeur";
    case 2: return "final";
    default: return "inconnu";
  }
}

// 5 (enfant pas encore authentifie) compte comme un enfant ; les valeurs
// reservees, comme « aucune ».
const char *texteRelation(uint8_t relation) {
  switch (relation) {
    case 0: return "parent";
    case 1: return "enfant";
    case 2: return "frere";
    case 4: return "ancien_enfant";
    case 5: return "enfant";
    default: return "aucune";
  }
}

const char *texteEtatRoute(uint8_t etat) {
  switch (etat) {
    case 0: return "active";
    case 1: return "decouverte";
    case 2: return "echec_decouverte";
    case 3: return "inactive";
    case 4: return "validation";
    default: return "inconnu";
  }
}

void texteIeee(const uint8_t ieee[8], char sortie[17]) {
  static const char kHexa[] = "0123456789ABCDEF";
  for (int i = 0; i < 8; i++) {
    const uint8_t o = ieee[7 - i];
    sortie[2 * i] = kHexa[o >> 4];
    sortie[2 * i + 1] = kHexa[o & 0x0F];
  }
  sortie[16] = 0;
}

static const char *trois(uint8_t v) { return v == 0 ? "false" : v == 1 ? "true" : "null"; }

static size_t borne(int n, size_t taille) { return n < 0 || (size_t)n >= taille ? 0 : (size_t)n; }

size_t jsonEntreeVoisin(const EntreeVoisin &e, char *sortie, size_t taille) {
  char ieee[17];
  texteIeee(e.ieee, ieee);
  const int n = snprintf(sortie, taille,
                         "{\"court\":\"%04X\",\"ieee\":\"%s\",\"type\":\"%s\",\"relation\":\"%s\",\"ecoute\":%s,"
                         "\"profondeur\":%u,\"admission\":%s,\"lqi\":%u}",
                         e.court, ieee, texteType(e.type), texteRelation(e.relation), trois(e.ecoute),
                         e.profondeur, trois(e.admission), e.lqi);
  return borne(n, taille);
}

size_t jsonVoisinSonde(const VoisinSonde &v, char *sortie, size_t taille) {
  char ieee[17];
  texteIeee(v.ieee, ieee);
  const int n = snprintf(sortie, taille,
                         "{\"court\":\"%04X\",\"ieee\":\"%s\",\"type\":\"%s\",\"relation\":\"%s\",\"lqi\":%u,"
                         "\"rssi\":%d,\"cout_sortant\":%u,\"age\":%u}",
                         v.court, ieee, texteType(v.type), texteRelation(v.relation), v.lqi, v.rssi,
                         v.coutSortant, v.age);
  return borne(n, taille);
}

size_t jsonEntreeRoute(const EntreeRoute &r, char *sortie, size_t taille) {
  const int n = snprintf(sortie, taille,
                         "{\"destination\":\"%04X\",\"etat\":\"%s\",\"prochain\":\"%04X\",\"memoire_limitee\":%s,"
                         "\"plusieurs_vers_un\":%s,\"enregistrement\":%s}",
                         r.destination, texteEtatRoute(r.etat), r.prochain, r.memoireLimitee ? "true" : "false",
                         r.plusieursVersUn ? "true" : "false", r.enregistrement ? "true" : "false");
  return borne(n, taille);
}

bool lirePageRoutes(const uint8_t *asdu, size_t n, PageRoutes *p) {
  if (n < 2) return false;
  *p = PageRoutes();
  p->tsn = asdu[0];
  p->statut = asdu[1];
  if (p->statut != 0) return true;
  if (n < 5) return false;
  p->total = asdu[2];
  p->debut = asdu[3];
  const uint8_t annonce = asdu[4];
  if (n < 5 + 5 * (size_t)annonce) return false;
  p->nombre = annonce > kRoutesParPageMax ? (uint8_t)kRoutesParPageMax : annonce;
  for (uint8_t i = 0; i < p->nombre; i++) {
    const uint8_t *o = asdu + 5 + 5 * i;
    EntreeRoute &r = p->entrees[i];
    r.destination = (uint16_t)(o[0] | o[1] << 8);
    r.etat = o[2] & 0x07;
    r.memoireLimitee = (o[2] >> 3) & 1;
    r.plusieursVersUn = (o[2] >> 4) & 1;
    r.enregistrement = (o[2] >> 5) & 1;
    r.prochain = (uint16_t)(o[3] | o[4] << 8);
  }
  return true;
}

void requeteRoutes(uint8_t tsn, uint8_t debut, uint8_t asdu[2]) {
  asdu[0] = tsn;
  asdu[1] = debut;
}
```

- [ ] **Step 4 : les tests passent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
commande : 60 verifications, 0 echec(s)
commande : 57 verifications, 0 echec(s)
ligne : 122 verifications, 0 echec(s)
entrees : 19 verifications, 0 echec(s)
```

- [ ] **Step 5 : brancher les tests hôte sur le lanceur général.**

Dans `outils/tester.sh`, remplacer :

```sh
python3 -m unittest discover -s "$ICI/test"
```

par :

```sh
sh "$DEPOT/sonde/test/lancer.sh"
python3 -m unittest discover -s "$ICI/test"
```

Puis, dans le même fichier, remplacer :

```sh
# Tous les tests sans carte, depuis la racine du depot :
#   sh outils/tester.sh
# 1. tests des outils Python (outils/test) ;
# 2. garde des vrais identifiants (outils/garde.py).
```

par :

```sh
# Tous les tests sans carte, depuis la racine du depot :
#   sh outils/tester.sh
# 1. tests hote du firmware de la sonde (sonde/test/lancer.sh) ;
# 2. tests des outils Python (outils/test) ;
# 3. garde des vrais identifiants (outils/garde.py).
```

Run : `sh outils/tester.sh`

Expected : les quatre programmes ci-dessus, puis les 7 tests Python, puis la garde, sans échec.

- [ ] **Step 6 : commit.**

```bash
git add sonde/src/options.h sonde/src/commande.h sonde/src/commande.cpp sonde/src/ligne.h sonde/src/ligne.cpp sonde/src/entrees.h sonde/src/entrees.cpp sonde/test/verif.h sonde/test/lancer.sh sonde/test/test_commande.cpp sonde/test/test_ligne.cpp sonde/test/test_entrees.cpp outils/tester.sh
git commit -m "Ecrire le protocole de la sonde : commandes, lignes machine, entrees des tables

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Pagination, garde-fou de cadence, liste blanche

**Files:**
- Create: `sonde/src/pagination.h`, `sonde/src/cadence.h`, `sonde/src/cadence.cpp`, `sonde/src/liste_blanche.h`, `sonde/test/test_pagination.cpp`, `sonde/test/test_cadence.cpp`
- Modify: `sonde/test/lancer.sh` (blocs ci-dessous)

**Interfaces:**
- Consumes : `options.h` (tâche 3), `verif.h` (tâche 3).
- Produces (utilisés par la tâche 6) :
  - `pagination.h` :
    - `enum class Issue {kEnCours, kOk, kDelai, kStatut, kCadence, kEnvoi, kSuspendue, kNonMembre}` ;
    - `template <typename Entree, size_t N> class Pagination` : `commencer(t, delaiPageMs)`, `actif()`, `aEnvoyer(t)`, `index()`, `numeroAEnvoyer()`, `envoyee(t)`, `page(numero, statut, total, debut, nombre, entrees, t)`, `abandonner(issue, t)`, `issue()`, `statut()`, `partielle()`, `total()`, `pages()`, `nombre()`, `entree(i)`, `dureeMs()` ;
    - `kDureeMaxMs` = 120000, `kStatutDelai` = 0x85 ;
  - `cadence.h` : `class Cadence` : `avis(t)` → `Avis::{kOui, kAttendre, kRefus}`, `compter(t)`, `refuser()`, `refus()` ;
  - `liste_blanche.h` : `kZdoMgmtLqi`, `kZdoMgmtRtg`, `kZdoMgmtNwkUpdate`, `bool requetePermise(uint16_t cluster, uint16_t cible)` (jamais vers `FFF8` à `FFFF`), `bool balayagePermis(uint32_t masque, uint8_t duree, uint8_t canal)`.

- [ ] **Step 1 : écrire les tests et les ajouter au lanceur.**

`sonde/test/test_pagination.cpp` :

```cpp
// Tests hote de sonde/src/pagination.h : pages, reprises, delais, total qui
// change, entrees en trop. Les entrees sont des entiers.
// Lancer : sh sonde/test/lancer.sh
#include "pagination.h"
#include "verif.h"

using P = Pagination<int, 8>;

// Envoie la page attendue (aEnvoyer doit dire oui) et rend son numero.
static uint32_t envoyer(P &p, uint32_t t) {
  if (!p.aEnvoyer(t)) return 0;
  const uint32_t n = p.numeroAEnvoyer();
  p.envoyee(t);
  return n;
}

int main() {
  const int e[] = {10, 11, 12, 13, 14, 15, 16, 17, 18, 19};
  P p;
  CHECK(!p.actif() && !p.aEnvoyer(0), "inactive au depart");

  // Deux pages : 3 puis 2 entrees sur 5.
  p.commencer(1000, 5000);
  CHECK(p.actif() && p.index() == 0, "commencee");
  uint32_t n = envoyer(p, 1000);
  CHECK(n == 1 && !p.aEnvoyer(1001), "page 0 partie, attente");
  p.page(n, 0, 5, 0, 3, e, 1100);
  CHECK(p.actif() && p.index() == 3, "page 0 recue");
  n = envoyer(p, 1200);
  CHECK(n == 2, "page 3 partie");
  p.page(n, 0, 5, 3, 2, e + 3, 1300);
  CHECK(!p.actif() && p.issue() == Issue::kOk && !p.partielle() && p.nombre() == 5 && p.pages() == 2 &&
            p.total() == 5 && p.dureeMs() == 300,
        "finie");
  CHECK(p.entree(0) == 10 && p.entree(4) == 14, "entrees dans l'ordre");
  p.page(n, 0, 5, 3, 2, e, 1400);
  CHECK(p.nombre() == 5, "page apres la fin ignoree");

  // Table vide.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 0, 0, 0, e, 10);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 0 && !p.partielle(), "table vide");

  // Delai : une page redemandee une fois, la reponse tardive ecartee.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  CHECK(!p.aEnvoyer(4999), "avant le delai");
  CHECK(p.aEnvoyer(5000), "delai : redemander");
  const uint32_t n2 = envoyer(p, 5000);
  CHECK(n2 == n + 1, "nouveau numero");
  p.page(n, 0, 2, 0, 2, e, 5100);
  CHECK(p.actif() && p.nombre() == 0, "reponse tardive ecartee");
  p.page(n2, 0, 2, 0, 2, e, 5200);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 2, "reponse a la seconde demande");

  // Deux silences : delai.
  p.commencer(0, 1000);
  envoyer(p, 0);
  envoyer(p, 1000);
  CHECK(!p.aEnvoyer(2000) && !p.actif() && p.issue() == Issue::kDelai && p.dureeMs() == 2000, "deux silences");

  // La nouvelle tentative est permise de nouveau apres une page reussie.
  p.commencer(0, 1000);
  envoyer(p, 0);
  n = envoyer(p, 1000);
  p.page(n, 0, 4, 0, 2, e, 1100);
  envoyer(p, 1200);
  n = envoyer(p, 2200);
  CHECK(n != 0 && p.actif(), "seconde page redemandee");
  p.page(n, 0, 4, 2, 2, e + 2, 2300);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 4, "reprise par page");

  // Statut 0x85 de la pile : comme un silence.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0x85, 0, 0, 0, e, 10);
  CHECK(p.actif() && p.aEnvoyer(11), "0x85 : redemander");
  n = envoyer(p, 11);
  p.page(n, 0x85, 0, 0, 0, e, 20);
  CHECK(!p.actif() && p.issue() == Issue::kDelai, "deux 0x85 : delai");

  // Autre statut : fin en « statut ».
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0x84, 0, 0, 0, e, 10);
  CHECK(!p.actif() && p.issue() == Issue::kStatut && p.statut() == 0x84, "statut 0x84");

  // Total qui change : recommencer une fois, puis partielle.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 7, 3, 3, e + 3, 30);
  CHECK(p.actif() && p.index() == 0 && p.nombre() == 0 && p.pages() == 0, "total change : on recommence");
  n = envoyer(p, 40);
  p.page(n, 0, 7, 0, 3, e, 50);
  n = envoyer(p, 60);
  p.page(n, 0, 8, 3, 3, e + 3, 70);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 3, "change encore : partielle");

  // Page qui ne commence pas a l'index demande : comme un total qui change.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 6, 2, 3, e + 2, 30);
  CHECK(p.actif() && p.index() == 0, "index decale : on recommence");

  // Page vide avant le total : partielle.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 6, 3, 0, e, 30);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 3, "page vide : partielle");

  // Plus d'entrees que la place (8) : partielle avec les 8 premieres.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 10, 0, 5, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 10, 5, 5, e + 5, 30);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 8 && p.entree(7) == 17,
        "trop d'entrees : partielle");

  // 120 s au plus, meme quand chaque page repond dans son delai.
  p.commencer(0, 30000);
  uint32_t t = 0;
  for (int i = 0; i < 4 && p.actif(); i++) {
    n = envoyer(p, t);
    t += 29000;
    p.page(n, 0, 200, (uint8_t)(i * 2), 2, e, t);
  }
  CHECK(p.actif(), "116 s : encore en cours");
  CHECK(!p.aEnvoyer(120000) && !p.actif() && p.issue() == Issue::kDelai, "120 s : delai");

  // Abandon par l'appelant.
  p.commencer(0, 5000);
  p.abandonner(Issue::kCadence, 5);
  CHECK(!p.actif() && p.issue() == Issue::kCadence && p.dureeMs() == 5, "abandon en cadence");
  p.abandonner(Issue::kEnvoi, 9);
  CHECK(p.issue() == Issue::kCadence, "abandon d'une table finie : rien");
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.abandonner(Issue::kNonMembre, 7);
  p.page(n, 0, 1, 0, 1, e, 8);
  CHECK(!p.actif() && p.issue() == Issue::kNonMembre && p.nombre() == 0, "sortie du reseau : la page tardive ignoree");

  // Retour a zero de millis().
  const uint32_t presque = 0xFFFFFF00u;
  p.commencer(presque, 1000);
  n = envoyer(p, presque);
  CHECK(!p.aEnvoyer(presque + 999), "avant le delai, a travers zero");
  CHECK(p.aEnvoyer(presque + 1000), "delai a travers zero");
  n = envoyer(p, presque + 1000);
  p.page(n, 0, 1, 0, 1, e, presque + 1100);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.dureeMs() == 1100, "duree a travers zero");

  return bilan("pagination");
}
```

`sonde/test/test_cadence.cpp` :

```cpp
// Tests hote de sonde/src/cadence.{h,cpp} (garde-fou de cadence) et de
// sonde/src/liste_blanche.h. Compile deux fois par lancer.sh : options par
// defaut, puis SONDE_ROUTES=0 et SONDE_ECHECS=0.
// Lancer : sh sonde/test/lancer.sh
#include "cadence.h"
#include "liste_blanche.h"
#include "verif.h"

int main() {
  // 100 ms entre deux envois.
  Cadence c;
  CHECK(c.avis(0) == Cadence::Avis::kOui, "premier envoi");
  c.compter(0);
  CHECK(c.avis(99) == Cadence::Avis::kAttendre, "99 ms");
  CHECK(c.avis(100) == Cadence::Avis::kOui, "100 ms");

  // 600 envois en 60 s : le 601e est refuse jusqu'a ce que le premier sorte
  // de la fenetre de 10 minutes.
  Cadence d;
  uint32_t t = 0;
  for (int i = 0; i < 600; i++, t += 100) {
    CHECK(d.avis(t) == Cadence::Avis::kOui, "envoi %d", i);
    d.compter(t);
  }
  CHECK(d.avis(t) == Cadence::Avis::kRefus, "601e refuse");
  CHECK(d.avis(599999) == Cadence::Avis::kRefus, "encore refuse juste avant 10 min");
  CHECK(d.avis(600000) == Cadence::Avis::kOui, "le premier sort de la fenetre a 10 min");
  d.compter(600000);
  CHECK(d.avis(600100) == Cadence::Avis::kOui, "le deuxieme sort a son tour");
  d.compter(600100);
  CHECK(d.avis(600150) == Cadence::Avis::kRefus, "fenetre de nouveau pleine : le refus passe avant l'ecart");
  CHECK(d.avis(600200) == Cadence::Avis::kOui, "le troisieme sort a son tour");
  CHECK(d.refus() == 0, "rien de compte sans refuser()");
  d.refuser();
  d.refuser();
  CHECK(d.refus() == 2, "refus comptes");

  // Retour a zero de millis().
  Cadence z;
  z.compter(0xFFFFFFC0u);
  CHECK(z.avis(0xFFFFFFC0u + 99) == Cadence::Avis::kAttendre, "a travers zero : 99 ms");
  CHECK(z.avis(0xFFFFFFC0u + 100) == Cadence::Avis::kOui, "a travers zero : 100 ms");

  // Liste blanche.
  CHECK(requetePermise(kZdoMgmtLqi, 0x1A2B) && requetePermise(kZdoMgmtLqi, 0x0000), "Mgmt_Lqi_req");
  CHECK(requetePermise(kZdoMgmtLqi, 0xFFF7), "derniere adresse d'appareil");
  CHECK(!requetePermise(kZdoMgmtLqi, 0xFFF8) && !requetePermise(kZdoMgmtLqi, 0xFFFC) &&
            !requetePermise(kZdoMgmtLqi, 0xFFFD) && !requetePermise(kZdoMgmtLqi, 0xFFFF),
        "jamais vers une diffusion");
  CHECK(requetePermise(kZdoMgmtRtg, 0x1A2B) == (SONDE_ROUTES != 0), "Mgmt_Rtg_req selon SONDE_ROUTES");
  CHECK(requetePermise(kZdoMgmtNwkUpdate, 0x1A2B) == (SONDE_ECHECS != 0), "Mgmt_NWK_Update_req selon SONDE_ECHECS");
  CHECK(!requetePermise(kZdoMgmtNwkUpdate, 0xFFFD), "balayage vers une diffusion");
  CHECK(!requetePermise(0x0034, 0x1A2B), "Mgmt_Leave_req interdite");
  CHECK(!requetePermise(0x0036, 0x1A2B), "Mgmt_Permit_Joining_req interdite");
  CHECK(!requetePermise(0x0021, 0x1A2B), "Bind_req interdite");
  CHECK(!requetePermise(0x0006, 0x1A2B), "Match_Desc_req interdite");
  CHECK(!requetePermise(0x8031, 0x1A2B), "une reponse n'est pas une requete");
  CHECK(balayagePermis(1u << 25, 0, 25) == (SONDE_ECHECS != 0), "canal courant, duree 0");
  CHECK(!balayagePermis(1u << 25, 1, 25), "duree 1");
  CHECK(!balayagePermis(1u << 25, 0xFE, 25), "changement de canal");
  CHECK(!balayagePermis(1u << 25, 0xFF, 25), "changement de gestionnaire");
  CHECK(!balayagePermis((1u << 25) | (1u << 11), 0, 25), "deux canaux");
  CHECK(!balayagePermis(1u << 24, 0, 25), "un autre canal");
  CHECK(!balayagePermis(0x07FFF800u, 0, 25), "tous les canaux");
  CHECK(!balayagePermis(1u << 10, 0, 10), "canal 10 hors bande");

  return bilan("cadence");
}
```

Dans `sonde/test/lancer.sh`, remplacer :

```sh
compiler test_entrees "$ICI/test_entrees.cpp" "$SRC/entrees.cpp"
```

par :

```sh
compiler test_entrees "$ICI/test_entrees.cpp" "$SRC/entrees.cpp"
compiler test_pagination "$ICI/test_pagination.cpp"
compiler test_cadence "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
compiler test_cadence_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
```

Puis remplacer :

```sh
"$TMP/test_entrees"
```

par :

```sh
"$TMP/test_entrees"
"$TMP/test_pagination"
"$TMP/test_cadence"
"$TMP/test_cadence_sans"
```

- [ ] **Step 2 : les lancer, ils échouent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
<depot>/sonde/test/test_pagination.cpp:4:10: fatal error: 'pagination.h' file not found
1 error generated.
```

- [ ] **Step 3 : écrire les modules.**

`sonde/src/pagination.h` :

```cpp
#pragma once
// ===========================================================================
//  Pagination d'une table distante (spec de la sonde, section 2)
//
//  La sonde demande les pages une a une (Mgmt_Lqi_req ou Mgmt_Rtg_req) a
//  partir de l'index 0, et garde les entrees :
//  - une page sans reponse dans le delai (ou rendue par la pile avec le
//    statut 0x85, delai depasse) est redemandee une fois ; un second silence
//    termine la table en « delai » ;
//  - un total qui change d'une page a l'autre, ou une page qui ne commence
//    pas a l'index demande : la table recommence au debut une fois, puis se
//    termine avec ce qu'elle a, « partielle » ;
//  - une page vide avant le total, ou plus d'entrees que la place :
//    « partielle » ;
//  - 120 s au plus en tout : au-dela, « delai ».
//  Un autre statut ZDO que 0 et 0x85 termine la table en « statut ».
//
//  Chaque envoi porte un numero : une reponse tardive a un envoi precedent
//  (meme page redemandee, ou table precedente) est ecartee.
//
//  Usage, a chaque tour de loop() :
//    if (p.aEnvoyer(t)) { envoyer la page p.index() avec le numero
//                         p.numeroAEnvoyer() ; si l'envoi part : p.envoyee(t) }
//    pour chaque page recue : p.page(numero, statut, total, debut, nombre, entrees, t)
//    if (!p.actif()) : la table est finie, p.issue() dit comment.
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_pagination.cpp). Instants de millis() : des ecarts non
//  signes, justes a travers le retour a zero.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

enum class Issue : uint8_t { kEnCours, kOk, kDelai, kStatut, kCadence, kEnvoi, kSuspendue, kNonMembre };

template <typename Entree, size_t N>
class Pagination {
 public:
  static constexpr uint32_t kDureeMaxMs = 120000;
  static constexpr uint8_t kStatutDelai = 0x85;  // ZDP : delai depasse

  void commencer(uint32_t maintenant, uint32_t delaiPageMs) {
    actif_ = true;
    attente_ = false;
    debutMs_ = maintenant;
    finMs_ = maintenant;
    delaiPageMs_ = delaiPageMs;
    recommence_ = false;
    partielle_ = false;
    issue_ = Issue::kEnCours;
    statut_ = 0;
    vider(0, false);
  }

  bool actif() const { return actif_; }

  // Une page doit-elle partir maintenant ? Verifie aussi les delais.
  bool aEnvoyer(uint32_t maintenant) {
    if (!actif_) return false;
    if (maintenant - debutMs_ >= kDureeMaxMs) {
      finir(Issue::kDelai, maintenant);
      return false;
    }
    if (attente_ && maintenant - envoiMs_ >= delaiPageMs_) sansReponse(maintenant);
    return actif_ && !attente_;
  }

  uint8_t index() const { return index_; }
  uint32_t numeroAEnvoyer() const { return numero_ + 1; }

  void envoyee(uint32_t maintenant) {
    numero_++;
    attente_ = true;
    envoiMs_ = maintenant;
  }

  void page(uint32_t numero, uint8_t statut, uint8_t total, uint8_t debut, uint8_t nombre, const Entree *entrees,
            uint32_t maintenant) {
    if (!actif_ || !attente_ || numero != numero_) return;
    attente_ = false;
    if (statut == kStatutDelai) {
      sansReponse(maintenant);
      return;
    }
    if (statut != 0) {
      statut_ = statut;
      finir(Issue::kStatut, maintenant);
      return;
    }
    if (!totalConnu_) {
      total_ = total;
      totalConnu_ = true;
    }
    if (total != total_ || debut != index_) {
      if (!recommence_) {
        recommence_ = true;
        vider(total, true);
      } else {
        partielle_ = true;
        finir(Issue::kOk, maintenant);
      }
      return;
    }
    reessai_ = false;
    pages_++;
    if (nombre == 0 && index_ < total_) {
      partielle_ = true;
      finir(Issue::kOk, maintenant);
      return;
    }
    for (uint8_t i = 0; i < nombre; i++) {
      if (nombre_ == N) {
        partielle_ = true;
        finir(Issue::kOk, maintenant);
        return;
      }
      entrees_[nombre_++] = entrees[i];
    }
    index_ = (uint8_t)(index_ + nombre);
    if (index_ >= total_) finir(Issue::kOk, maintenant);
  }

  // Fin imposee par l'appelant : cadence, envoi refuse, suspension, sonde
  // sortie du reseau.
  void abandonner(Issue issue, uint32_t maintenant) {
    if (actif_) finir(issue, maintenant);
  }

  Issue issue() const { return issue_; }
  uint8_t statut() const { return statut_; }
  bool partielle() const { return partielle_; }
  uint8_t total() const { return total_; }
  uint8_t pages() const { return pages_; }
  size_t nombre() const { return nombre_; }
  const Entree &entree(size_t i) const { return entrees_[i]; }
  uint32_t dureeMs() const { return finMs_ - debutMs_; }

 private:
  void vider(uint8_t total, bool totalConnu) {
    index_ = 0;
    total_ = total;
    totalConnu_ = totalConnu;
    reessai_ = false;
    pages_ = 0;
    nombre_ = 0;
  }

  void sansReponse(uint32_t maintenant) {
    if (!reessai_) {
      reessai_ = true;
      attente_ = false;
    } else {
      finir(Issue::kDelai, maintenant);
    }
  }

  void finir(Issue issue, uint32_t maintenant) {
    actif_ = false;
    attente_ = false;
    issue_ = issue;
    finMs_ = maintenant;
  }

  bool actif_ = false;
  bool attente_ = false;  // une page est partie, sa reponse est attendue
  uint32_t debutMs_ = 0;
  uint32_t finMs_ = 0;
  uint32_t envoiMs_ = 0;
  uint32_t delaiPageMs_ = 0;
  uint32_t numero_ = 0;  // numero du dernier envoi
  uint8_t index_ = 0;
  uint8_t total_ = 0;
  bool totalConnu_ = false;
  bool recommence_ = false;
  bool reessai_ = false;  // la page en cours a deja ete redemandee
  bool partielle_ = false;
  uint8_t pages_ = 0;
  Issue issue_ = Issue::kEnCours;
  uint8_t statut_ = 0;
  size_t nombre_ = 0;
  Entree entrees_[N];
};
```

`sonde/src/cadence.h` :

```cpp
#pragma once
// ===========================================================================
//  Garde-fou de cadence (spec de la sonde, section 3)
//
//  Toute requete que la sonde emet dans le reseau (une page de table ou de
//  routes, une requete d'echecs) passe ici :
//  - au moins 100 ms entre deux envois : sinon, attendre ;
//  - au plus 600 envois par fenetre glissante de 10 minutes : au-dela, refus
//    (la table ou la requete se termine en « cadence », sans rien emettre),
//    compte depuis le demarrage (refus_cadence de la commande etat).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_cadence.cpp).
//  Instants de millis() : des ecarts non signes, justes a travers le retour a
//  zero.
// ===========================================================================
#include <stdint.h>

class Cadence {
 public:
  static constexpr uint32_t kEcartMinMs = 100;
  static constexpr uint32_t kFenetreMs = 600000;
  static constexpr uint16_t kEnvoisMax = 600;

  enum class Avis : uint8_t { kOui, kAttendre, kRefus };

  // Peut-on envoyer maintenant ?
  Avis avis(uint32_t maintenant);
  // Un envoi vient de partir.
  void compter(uint32_t maintenant);
  // Compte un refus (l'appelant abandonne la requete).
  void refuser() { refus_++; }
  uint32_t refus() const { return refus_; }

 private:
  void oublierAnciens(uint32_t maintenant);
  uint32_t instants_[kEnvoisMax] = {0};  // anneau des envois de la fenetre
  uint16_t premier_ = 0;
  uint16_t nombre_ = 0;
  bool aucunEnvoi_ = true;
  uint32_t dernier_ = 0;
  uint32_t refus_ = 0;
};
```

`sonde/src/cadence.cpp` :

```cpp
#include "cadence.h"

void Cadence::oublierAnciens(uint32_t maintenant) {
  while (nombre_ > 0 && maintenant - instants_[premier_] >= kFenetreMs) {
    premier_ = (uint16_t)((premier_ + 1) % kEnvoisMax);
    nombre_--;
  }
}

Cadence::Avis Cadence::avis(uint32_t maintenant) {
  oublierAnciens(maintenant);
  if (nombre_ >= kEnvoisMax) return Avis::kRefus;
  if (!aucunEnvoi_ && maintenant - dernier_ < kEcartMinMs) return Avis::kAttendre;
  return Avis::kOui;
}

void Cadence::compter(uint32_t maintenant) {
  oublierAnciens(maintenant);
  if (nombre_ == kEnvoisMax) {  // ne devrait pas arriver : avis() refuse avant
    premier_ = (uint16_t)((premier_ + 1) % kEnvoisMax);
    nombre_--;
  }
  instants_[(premier_ + nombre_) % kEnvoisMax] = maintenant;
  nombre_++;
  aucunEnvoi_ = false;
  dernier_ = maintenant;
}
```

`sonde/src/liste_blanche.h` :

```cpp
#pragma once
// ===========================================================================
//  Liste blanche des requetes de la sonde (spec de la sonde, section 3)
//
//  La sonde n'emet, d'elle-meme ou sur commande, que des requetes ZDO de
//  lecture : Mgmt_Lqi_req, Mgmt_Rtg_req (si SONDE_ROUTES) et
//  Mgmt_NWK_Update_req en balayage d'energie seulement (si SONDE_ECHECS),
//  avec une duree 0 et le seul canal courant. Jamais de changement de canal
//  (duree 0xFE) ni de gestionnaire du reseau (0xFF), et toujours vers un seul
//  appareil : jamais vers une adresse de diffusion (FFF8 a FFFF). Chaque
//  envoi de zigbee.cpp passe par ces fonctions, la voie APS brute comprise.
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_cadence.cpp).
// ===========================================================================
#include <stdint.h>

#include "options.h"

static constexpr uint16_t kZdoMgmtLqi = 0x0031;
static constexpr uint16_t kZdoMgmtRtg = 0x0032;
static constexpr uint16_t kZdoMgmtNwkUpdate = 0x0038;

// Une requete ZDO (profil 0, point d'acces 0) que la sonde peut emettre vers
// cette cible ?
inline bool requetePermise(uint16_t cluster, uint16_t cible) {
  if (cible >= 0xFFF8) return false;  // diffusion
  if (cluster == kZdoMgmtLqi) return true;
  if (cluster == kZdoMgmtRtg) return SONDE_ROUTES != 0;
  if (cluster == kZdoMgmtNwkUpdate) return SONDE_ECHECS != 0;
  return false;
}

// Mgmt_NWK_Update_req : balayage d'energie de duree 0, sur le seul canal
// courant (11 a 26).
inline bool balayagePermis(uint32_t masqueCanaux, uint8_t duree, uint8_t canalCourant) {
  if (!requetePermise(kZdoMgmtNwkUpdate, 0x0000)) return false;
  if (canalCourant < 11 || canalCourant > 26) return false;
  return duree == 0 && masqueCanaux == (1u << canalCourant);
}
```

- [ ] **Step 4 : les tests passent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
commande : 60 verifications, 0 echec(s)
commande : 57 verifications, 0 echec(s)
ligne : 122 verifications, 0 echec(s)
entrees : 19 verifications, 0 echec(s)
pagination : 33 verifications, 0 echec(s)
cadence : 632 verifications, 0 echec(s)
cadence : 632 verifications, 0 echec(s)
```

Puis `sh outils/tester.sh` : sans échec.

- [ ] **Step 5 : commit.**

```bash
git add sonde/src/pagination.h sonde/src/cadence.h sonde/src/cadence.cpp sonde/src/liste_blanche.h sonde/test/test_pagination.cpp sonde/test/test_cadence.cpp sonde/test/lancer.sh
git commit -m "Ecrire la pagination des tables, le garde-fou de cadence et la liste blanche

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Adhésion au réseau et LED

**Files:**
- Create: `sonde/src/adhesion.h`, `sonde/src/adhesion.cpp`, `sonde/src/voyant.h`, `sonde/test/test_adhesion.cpp`, `sonde/test/test_voyant.cpp`
- Modify: `sonde/test/lancer.sh` (blocs ci-dessous)

**Interfaces:**
- Consumes : `verif.h` (tâche 3).
- Produces (utilisés par la tâche 6) :
  - `adhesion.h` : `class Adhesion` :
    - signaux : `premierDemarrage(ok, t)`, `redemarrage(ok, t)`, `recherche(ok, t)`, `rattachementTc(ok, t)`, `parentPerdu(t)`, `depart(retour, t)`, `oubli(t)` ;
    - constat de la pile : `constater(rattachee, t)` ;
    - `tour(t)` → `Action::{kRien, kInitialiser, kChercher, kRattacher, kOublier, kRedemarrer}` ;
    - `etat()`, `membre()`, `cherche()`, `adhesions()`, `echecsRattachement()` ;
  - `voyant.h` : `class Voyant` :
    - `identifier(actif, t)`, `chercher(actif, t)`, `adherer(t)`, `suspendre(actif, t)`, `allumer(actif)` ;
    - `teinte(t)` → `Teinte {couleur, niveau}`, avec `Couleur::{kNoire, kBlanche, kBleue, kVerte, kOrange, kVeille}`.

- [ ] **Step 1 : écrire les tests et les ajouter au lanceur.**

`sonde/test/test_adhesion.cpp` :

```cpp
// Tests hote de sonde/src/adhesion.{h,cpp} : recherche, rattachement, depart.
// Lancer : sh sonde/test/lancer.sh
#include "adhesion.h"
#include "verif.h"

using A = Adhesion::Action;
using E = Adhesion::Etat;

int main() {
  // Premier demarrage (usine) : chercher tout de suite, puis toutes les 30 s.
  Adhesion a;
  CHECK(a.etat() == E::kDemarrage && a.cherche() && !a.membre() && a.tour(0) == A::kRien, "au demarrage");
  a.premierDemarrage(true, 100);
  CHECK(a.etat() == E::kRecherche && a.tour(100) == A::kChercher, "chercher tout de suite");
  CHECK(a.tour(100) == A::kRien, "rendue une seule fois");
  a.recherche(false, 2000);
  CHECK(a.etat() == E::kAttente && a.cherche(), "aucun reseau ouvert : attente");
  CHECK(a.tour(31999) == A::kRien && a.tour(32000) == A::kChercher, "30 s plus tard, chercher encore");
  CHECK(a.tour(91999) == A::kRien && a.tour(92000) == A::kChercher, "filet : sans signal, encore 60 s plus tard");
  a.recherche(true, 93000);
  CHECK(a.membre() && !a.cherche() && a.adhesions() == 1 && a.tour(200000) == A::kRien, "adhesion");

  // Parent perdu : 10 s pour que la pile se rattache seule, puis rattacher
  // toutes les 30 s.
  a.parentPerdu(300000);
  CHECK(a.etat() == E::kRattachement && !a.membre() && a.cherche(), "parent perdu");
  a.parentPerdu(305000);
  CHECK(a.tour(309999) == A::kRien && a.tour(310000) == A::kRattacher, "rattacher 10 s apres la premiere perte");
  CHECK(a.tour(339999) == A::kRien && a.tour(340000) == A::kRattacher, "puis toutes les 30 s");
  a.redemarrage(true, 341000);
  CHECK(a.membre() && a.adhesions() == 2 && a.tour(400000) == A::kRien, "rattachee");

  // La pile se rattache seule avant les 10 s : rien a faire.
  a.parentPerdu(500000);
  a.rattachementTc(true, 503000);
  CHECK(a.membre() && a.tour(510000) == A::kRien && a.adhesions() == 3, "rattachement seul");
  a.parentPerdu(600000);
  a.rattachementTc(false, 601000);
  CHECK(a.etat() == E::kRattachement && a.tour(630999) == A::kRien && a.tour(631000) == A::kRattacher,
        "rattachement TC en echec : relance 30 s plus tard");
  CHECK(a.echecsRattachement() == 1, "echec compte");
  a.redemarrage(true, 632000);
  CHECK(a.echecsRattachement() == 0, "remis a zero une fois membre");

  // Redemarrage avec un reseau en memoire, en echec : rattacher toutes les
  // 30 s, sans jamais oublier le reseau ; les echecs sont comptes.
  Adhesion r;
  r.redemarrage(false, 0);
  CHECK(r.etat() == E::kRattachement && r.tour(29999) == A::kRien && r.tour(30000) == A::kRattacher,
        "redemarrage en echec");
  r.redemarrage(false, 31000);
  r.rattachementTc(false, 32000);
  CHECK(r.echecsRattachement() == 3 && r.etat() == E::kRattachement, "trois echecs, toujours en rattachement");
  CHECK(r.tour(61999) == A::kRien && r.tour(62000) == A::kRattacher, "jamais d'oubli de soi-meme");
  r.redemarrage(true, 63000);
  CHECK(r.membre() && r.adhesions() == 1 && r.echecsRattachement() == 0, "redemarrage reussi");

  // Premier demarrage en echec : reinitialiser 1 s plus tard.
  Adhesion p;
  p.premierDemarrage(false, 0);
  CHECK(p.etat() == E::kDemarrage && p.tour(999) == A::kRien && p.tour(1000) == A::kInitialiser,
        "premier demarrage en echec");
  CHECK(p.tour(30999) == A::kRien && p.tour(31000) == A::kInitialiser, "filet de reinitialisation");

  // Depart : sans retour, oublier ; avec retour, redemarrer. Plus aucun
  // signal n'y change rien.
  Adhesion d;
  d.recherche(true, 0);
  d.depart(false, 10);
  CHECK(d.etat() == E::kDepart && !d.membre() && !d.cherche() && d.tour(10) == A::kOublier, "depart sans retour");
  d.recherche(true, 20);
  d.redemarrage(true, 20);
  d.parentPerdu(20);
  CHECK(d.etat() == E::kDepart && d.tour(30) == A::kRien, "plus rien apres le depart");
  Adhesion dr;
  dr.recherche(true, 0);
  dr.depart(true, 10);
  CHECK(dr.tour(10) == A::kRedemarrer, "depart avec retour");

  // Commande oubli : filet a 15 s ; le depart qui la suit redemarre sans
  // tout effacer (la pile a deja oublie le reseau, et garde le compteur de
  // trames).
  Adhesion o;
  o.recherche(true, 0);
  o.oubli(1000);
  CHECK(o.etat() == E::kDepart && o.tour(15999) == A::kRien && o.tour(16000) == A::kOublier, "filet d'oubli");
  Adhesion o2;
  o2.recherche(true, 0);
  o2.oubli(1000);
  o2.depart(false, 2000);
  CHECK(o2.tour(2000) == A::kRedemarrer && o2.tour(16000) == A::kRien, "depart apres oubli : redemarrer");

  // Constat de la pile : un signal d'adhesion perdu est rattrape.
  Adhesion c;
  c.constater(true, 0);
  CHECK(c.membre() && c.adhesions() == 1, "au demarrage");
  Adhesion c2;
  c2.premierDemarrage(true, 0);
  c2.constater(false, 5000);
  CHECK(c2.etat() == E::kRecherche, "pas rattachee : rien");
  c2.constater(true, 10000);
  CHECK(c2.membre(), "pendant une recherche");
  c2.parentPerdu(20000);
  c2.constater(true, 21000);
  CHECK(c2.etat() == E::kRattachement, "le constat ne dit rien du parent : rattachement garde");
  Adhesion c3;
  c3.recherche(true, 0);
  c3.oubli(100);
  c3.constater(true, 200);
  CHECK(c3.etat() == E::kDepart, "rien apres le depart");

  // Retour a zero de millis().
  Adhesion z;
  z.recherche(false, 0xFFFFF000u);
  CHECK(z.tour(0xFFFFF000u + 29999) == A::kRien && z.tour(0xFFFFF000u + 30000) == A::kChercher, "a travers zero");

  return bilan("adhesion");
}
```

`sonde/test/test_voyant.cpp` :

```cpp
// Tests hote de sonde/src/voyant.h : priorites et sequences de la LED.
// Lancer : sh sonde/test/lancer.sh
#include "verif.h"
#include "voyant.h"

using C = Voyant::Couleur;

// La couleur vaut c sur tout [de, a), lue a chaque milliseconde.
static bool partout(Voyant &v, uint32_t de, uint32_t a, C c) {
  bool ok = true;
  for (uint32_t t = de; t != a; t++) ok = v.teinte(t).couleur == c && ok;
  return ok;
}

int main() {
  Voyant v;
  CHECK(partout(v, 0, 100, C::kNoire), "eteinte par defaut");
  v.allumer(true);
  CHECK(partout(v, 100, 200, C::kVeille), "lampe Hue allumee : veille");
  v.allumer(false);

  // Recherche : pulsation bleue de 2 s, du noir au plein et retour.
  v.chercher(true, 1000);
  CHECK(v.teinte(1000).couleur == C::kBleue && v.teinte(1000).niveau == 0, "pulsation au creux");
  CHECK(v.teinte(2000).niveau == 255, "pulsation au sommet");
  CHECK(v.teinte(1500).niveau == 127 && v.teinte(2500).niveau == 127, "pulsation a mi-chemin");
  CHECK(v.teinte(3000).niveau == 0, "pulsation : periode de 2 s");
  CHECK(partout(v, 1000, 5000, C::kBleue), "bleue tant qu'elle cherche");

  // Adhesion : vert, pause, vert, puis la teinte d'en dessous.
  v.chercher(false, 6000);
  v.adherer(6000);
  CHECK(partout(v, 6000, 6100, C::kVerte) && partout(v, 6100, 6200, C::kNoire) &&
            partout(v, 6200, 6300, C::kVerte) && partout(v, 6300, 6400, C::kNoire),
        "deux eclairs verts");

  // Identification : passe devant tout, blanc 500 ms, eteint 500 ms.
  v.chercher(true, 7000);
  v.identifier(true, 7000);
  CHECK(partout(v, 7000, 7500, C::kBlanche) && partout(v, 7500, 8000, C::kNoire) &&
            partout(v, 8000, 8500, C::kBlanche),
        "identification devant la recherche");
  v.identifier(false, 9000);
  CHECK(v.teinte(9000).couleur == C::kBleue, "fin de l'identification : la recherche reprend");
  v.chercher(false, 9000);

  // Suspendue : bref eclair orange tout de suite, puis toutes les 5 s ; entre
  // deux, la lampe Hue.
  v.allumer(true);
  v.suspendre(true, 10000);
  CHECK(partout(v, 10000, 10100, C::kOrange) && partout(v, 10100, 15000, C::kVeille) &&
            partout(v, 15000, 15100, C::kOrange) && partout(v, 15100, 20000, C::kVeille),
        "eclairs de la suspension");
  // Boucle retenue 12 s : la grille de 5 s est gardee.
  CHECK(v.teinte(32000).couleur == C::kVeille && v.teinte(35000).couleur == C::kOrange, "grille gardee");
  v.suspendre(true, 35500);  // deja suspendue : la grille ne bouge pas
  CHECK(v.teinte(40050).couleur == C::kOrange, "grille gardee malgre un second appel");
  v.suspendre(false, 41000);
  CHECK(partout(v, 41000, 46000, C::kVeille), "reprise : plus d'eclair");

  // Retour a zero de millis() : une adhesion finie ne se ranime pas.
  Voyant z;
  z.adherer(0xFFFFFF00u);
  CHECK(z.teinte(0xFFFFFF00u + 50).couleur == C::kVerte, "eclair avant zero");
  CHECK(z.teinte(0xFFFFFF00u + 400).couleur == C::kNoire, "fini apres zero");
  CHECK(partout(z, 0xFFFFFF00u + 400, 0xFFFFFF00u + 2000, C::kNoire), "rien ne se ranime");

  return bilan("voyant");
}
```

Dans `sonde/test/lancer.sh`, remplacer :

```sh
compiler test_cadence_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
```

par :

```sh
compiler test_cadence_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
compiler test_adhesion "$ICI/test_adhesion.cpp" "$SRC/adhesion.cpp"
compiler test_voyant "$ICI/test_voyant.cpp"
```

Puis remplacer :

```sh
"$TMP/test_cadence_sans"
```

par :

```sh
"$TMP/test_cadence_sans"
"$TMP/test_adhesion"
"$TMP/test_voyant"
```

- [ ] **Step 2 : les lancer, ils échouent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
clang++: error: no such file or directory: '<depot>/sonde/test/../src/adhesion.cpp'
```

- [ ] **Step 3 : écrire les modules.**

`sonde/src/adhesion.h` :

```cpp
#pragma once
// ===========================================================================
//  Adhesion de la sonde au reseau Hue (spec de la sonde, sections 1 et 6)
//
//  zigbee.cpp relaie les signaux de la pile ; loop() appelle tour() et
//  execute l'action rendue, sous le verrou de la pile :
//  - premier demarrage (usine) : chercher un reseau (BDB network steering),
//    puis toutes les 30 s tant qu'aucun ne l'accepte ;
//  - redemarrage avec un reseau en memoire : la pile s'y rattache ; en cas
//    d'echec, rattacher (BDB initialization) toutes les 30 s, sans jamais
//    oublier le reseau de soi-meme (une longue coupure du pont ne doit pas
//    faire perdre l'adhesion) ; les echecs sont comptes (etat), pour que
//    l'app propose oubli ;
//  - parent perdu (appareil final) : si la pile ne s'est pas rattachee seule
//    en 10 s, rattacher, puis toutes les 30 s ;
//  - depart sans retour venu du reseau (le pont retire la sonde) : oublier
//    (effacer zb_storage et redemarrer) ; depart avec retour : redemarrer ;
//  - commande oubli : quitter le reseau (la pile efface sa memoire mais garde
//    le compteur de trames), puis, au depart, redemarrer sans tout effacer ;
//    si la sonde vit encore 15 s plus tard, oublier quand meme ;
//  - constat de la pile (toutes les 10 s) : rattachee alors qu'aucun signal
//    ne l'a dit (signal perdu) : membre.
//  « membre » : rattachee et en service ; « cherche » : ni membre ni sur le
//  depart (la LED pulse en bleu, etat dit recherche:true).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_adhesion.cpp).
//  Instants de millis() : des ecarts non signes.
// ===========================================================================
#include <stdint.h>

class Adhesion {
 public:
  static constexpr uint32_t kRechercheMs = 30000;     // entre deux recherches
  static constexpr uint32_t kRattachementMs = 10000;  // apres un parent perdu
  static constexpr uint32_t kRelanceMs = 30000;       // entre deux rattachements
  static constexpr uint32_t kReinitMs = 1000;         // apres un premier demarrage en echec
  static constexpr uint32_t kOubliMs = 15000;         // filet de la commande oubli

  enum class Etat : uint8_t { kDemarrage, kRecherche, kAttente, kMembre, kRattachement, kDepart };
  enum class Action : uint8_t { kRien, kInitialiser, kChercher, kRattacher, kOublier, kRedemarrer };

  // Signaux de la pile.
  void premierDemarrage(bool ok, uint32_t t);  // ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START
  void redemarrage(bool ok, uint32_t t);       // ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT
  void recherche(bool ok, uint32_t t);         // ESP_ZB_BDB_SIGNAL_STEERING
  void rattachementTc(bool ok, uint32_t t);    // ESP_ZB_BDB_SIGNAL_TC_REJOIN_DONE
  void parentPerdu(uint32_t t);                // ESP_ZB_NLME_STATUS_INDICATION, parent perdu
  void depart(bool retour, uint32_t t);        // ESP_ZB_ZDO_SIGNAL_LEAVE
  // Commande oubli (zigbee.cpp vient de demander le depart).
  void oubli(uint32_t t);
  // Ce que la pile dit d'elle-meme (esp_zb_bdb_dev_joined), toutes les 10 s.
  void constater(bool rattachee, uint32_t t);

  // L'action a faire maintenant, rendue une seule fois.
  Action tour(uint32_t t);

  Etat etat() const { return etat_; }
  bool membre() const { return etat_ == Etat::kMembre; }
  bool cherche() const { return etat_ != Etat::kMembre && etat_ != Etat::kDepart; }
  // Nombre d'entrees dans l'etat membre depuis le demarrage (la LED montre
  // deux eclairs verts a chacune).
  uint32_t adhesions() const { return adhesions_; }
  // Rattachements echoues depuis la derniere fois que la sonde etait membre.
  uint32_t echecsRattachement() const { return echecs_; }

 private:
  void prevoir(Action a, uint32_t t) {
    prevue_ = a;
    echeance_ = t;
  }
  void devenirMembre();
  Etat etat_ = Etat::kDemarrage;
  Action prevue_ = Action::kRien;
  uint32_t echeance_ = 0;
  uint32_t adhesions_ = 0;
  uint32_t echecs_ = 0;
  bool oubliDemande_ = false;
};
```

`sonde/src/adhesion.cpp` :

```cpp
#include "adhesion.h"

void Adhesion::devenirMembre() {
  etat_ = Etat::kMembre;
  prevue_ = Action::kRien;
  adhesions_++;
  echecs_ = 0;
}

void Adhesion::premierDemarrage(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    etat_ = Etat::kRecherche;
    prevoir(Action::kChercher, t);
  } else {
    etat_ = Etat::kDemarrage;
    prevoir(Action::kInitialiser, t + kReinitMs);
  }
}

void Adhesion::redemarrage(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kRattachement;
    echecs_++;
    prevoir(Action::kRattacher, t + kRelanceMs);
  }
}

void Adhesion::recherche(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kAttente;
    prevoir(Action::kChercher, t + kRechercheMs);
  }
}

void Adhesion::rattachementTc(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kRattachement;
    echecs_++;
    prevoir(Action::kRattacher, t + kRelanceMs);
  }
}

void Adhesion::parentPerdu(uint32_t t) {
  if (etat_ != Etat::kMembre) return;
  etat_ = Etat::kRattachement;
  prevoir(Action::kRattacher, t + kRattachementMs);
}

void Adhesion::depart(bool retour, uint32_t t) {
  etat_ = Etat::kDepart;
  // Apres oubli, la pile a deja tout efface sauf le compteur de trames : un
  // simple redemarrage le garde (des voisins rejetteraient sinon les trames
  // de la sonde, revenue avec un compteur a zero).
  prevoir(retour || oubliDemande_ ? Action::kRedemarrer : Action::kOublier, t);
}

void Adhesion::oubli(uint32_t t) {
  etat_ = Etat::kDepart;
  oubliDemande_ = true;
  prevoir(Action::kOublier, t + kOubliMs);
}

void Adhesion::constater(bool rattachee, uint32_t t) {
  (void)t;
  if (!rattachee) return;
  if (etat_ == Etat::kDemarrage || etat_ == Etat::kRecherche || etat_ == Etat::kAttente) devenirMembre();
}

Adhesion::Action Adhesion::tour(uint32_t t) {
  if (prevue_ == Action::kRien) return Action::kRien;
  // Echeance atteinte : ecart non signe de moins de 2^31 ms.
  if (t - echeance_ >= 0x80000000u) return Action::kRien;
  const Action a = prevue_;
  prevue_ = Action::kRien;
  // Filets : si la pile ne repond par aucun signal, la meme action repart
  // plus tard. Un signal qui arrive entre-temps prevoit lui-meme la suite.
  if (a == Action::kRattacher) prevoir(Action::kRattacher, t + kRelanceMs);
  else if (a == Action::kChercher) prevoir(Action::kChercher, t + 2 * kRechercheMs);
  else if (a == Action::kInitialiser) prevoir(Action::kInitialiser, t + kRelanceMs);
  return a;
}
```

`sonde/src/voyant.h` :

```cpp
#pragma once
// ===========================================================================
//  LED de la carte (WS2812 de la SuperMini, sur IO8 ; spec de la sonde,
//  section 1)
//
//  La teinte a montrer a chaque instant, par ordre de priorite :
//  1. identification demandee par l'app Hue : blanc, 500 ms allume, 500 ms
//     eteint ;
//  2. recherche d'un reseau ou rattachement : pulsation bleue lente (2 s) ;
//  3. adhesion : deux eclairs verts rapides (100 ms, pause, 100 ms) ;
//  4. suspendue : un bref eclair orange (100 ms) toutes les 5 s, le premier
//     tout de suite, aussi apres un redemarrage ;
//  5. sinon, la lampe Hue : blanc tres faible si allumee, eteinte sinon.
//  main.cpp la pilote dans loop() seulement, jamais depuis un rappel de la
//  pile Zigbee (qui ne fait que poser des drapeaux).
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_voyant.cpp). Instants de millis() : des ecarts non
//  signes ; une sequence finie est oubliee au premier appel qui la voit
//  finie, si bien que le retour a zero de millis() ne ranime rien.
// ===========================================================================
#include <stdint.h>

class Voyant {
 public:
  enum Couleur : uint8_t { kNoire, kBlanche, kBleue, kVerte, kOrange, kVeille };
  static constexpr uint32_t kIdentMs = 500;     // demi-periode du clignotement d'identification
  static constexpr uint32_t kPulsationMs = 2000;  // periode de la pulsation bleue
  static constexpr uint32_t kVertMs = 100;      // chaque eclair vert, et la pause entre eux
  static constexpr uint32_t kBrefMs = 100;      // bref eclair orange de la suspension...
  static constexpr uint32_t kPeriodeMs = 5000;  // ... toutes les 5 s

  struct Teinte {
    Couleur couleur;
    uint8_t niveau;  // 0 a 255 : fraction de l'intensite maximale de la couleur
  };

  void identifier(bool actif, uint32_t t) {
    if (actif && !ident_) debutIdent_ = t;
    ident_ = actif;
  }
  void chercher(bool actif, uint32_t t) {
    if (actif && !cherche_) debutPulsation_ = t;
    cherche_ = actif;
  }
  void adherer(uint32_t t) {
    adhesion_ = true;
    debutAdhesion_ = t;
  }
  void suspendre(bool actif, uint32_t t) {
    if (actif && !suspendue_) prochain_ = t;
    suspendue_ = actif;
  }
  void allumer(bool actif) { lampe_ = actif; }

  Teinte teinte(uint32_t t) {
    if (ident_) return {((t - debutIdent_) / kIdentMs) % 2 == 0 ? kBlanche : kNoire, 255};
    if (cherche_) {
      const uint32_t phase = (t - debutPulsation_) % kPulsationMs;
      const uint32_t demi = kPulsationMs / 2;
      const uint32_t montee = phase < demi ? phase : kPulsationMs - phase;
      return {kBleue, (uint8_t)(montee * 255 / demi)};
    }
    if (adhesion_) {
      const uint32_t e = t - debutAdhesion_;
      if (e < 3 * kVertMs) return {e / kVertMs == 1 ? kNoire : kVerte, 255};
      adhesion_ = false;
    }
    if (suspendue_) {
      // Ecart depuis le prochain bref eclair : au-dela de 2^31 ms, il est
      // encore a venir (prochain_ n'est jamais a plus d'une periode en avance).
      const uint32_t e = t - prochain_;
      if (e < 0x80000000u) {
        if (e % kPeriodeMs < kBrefMs) return {kOrange, 255};
        // Eclair fini (plusieurs si loop() a ete retenue) : le suivant, sur la
        // meme grille de 5 s.
        prochain_ += (e / kPeriodeMs + 1) * kPeriodeMs;
      }
    }
    return {lampe_ ? kVeille : kNoire, 255};
  }

 private:
  bool ident_ = false;
  uint32_t debutIdent_ = 0;
  bool cherche_ = false;
  uint32_t debutPulsation_ = 0;
  bool adhesion_ = false;
  uint32_t debutAdhesion_ = 0;
  bool suspendue_ = false;
  uint32_t prochain_ = 0;  // debut du prochain bref eclair, ou de celui en cours
  bool lampe_ = false;
};
```

- [ ] **Step 4 : les tests passent.**

Run : `sh sonde/test/lancer.sh`

Expected :

```text
commande : 60 verifications, 0 echec(s)
commande : 57 verifications, 0 echec(s)
ligne : 122 verifications, 0 echec(s)
entrees : 19 verifications, 0 echec(s)
pagination : 33 verifications, 0 echec(s)
cadence : 632 verifications, 0 echec(s)
cadence : 632 verifications, 0 echec(s)
adhesion : 32 verifications, 0 echec(s)
voyant : 17 verifications, 0 echec(s)
```

Puis `sh outils/tester.sh` : sans échec.

- [ ] **Step 5 : commit.**

```bash
git add sonde/src/adhesion.h sonde/src/adhesion.cpp sonde/src/voyant.h sonde/test/test_adhesion.cpp sonde/test/test_voyant.cpp sonde/test/lancer.sh
git commit -m "Ecrire l'adhesion de la sonde au reseau et la LED de la carte

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Firmware 0.9.0 : colle Zigbee, boucle principale, variantes

**Files:**
- Create: `sonde/src/version.h`, `sonde/src/zigbee.h`, `sonde/src/zigbee.cpp`, `sonde/src/main.cpp`, `sonde/platformio.ini`, `sonde/cle_hue.exemple.h`, `sonde/README.md`

**Interfaces:**
- Consumes : tous les modules des tâches 3 à 5, avec les noms listés dans leurs blocs Interfaces.
- Produces :
  - le firmware 0.9.0, dans les variantes `sonde`, `sonde_variable`, `sonde_routeur` et `sonde_routeur_variable` (avec la vraie clé, à la tâche 8), et `verif`, `verif_routeur` (clé factice, jamais flashées) ;
  - `zigbee.h` : `namespace zigbee` :
    - `demarrer()`, `routeur()`, `prete()`, `verrou(ms)`, `libere()` ;
    - sous le verrou : `rattachee`, `ieee`, `court`, `pan`, `epid`, `canal`, `voisinSuivant`, `envoyerVoisins`, `envoyerRoutes`, `envoyerEchecs`, `initialiser`, `chercher`, `quitter`, `oublier`, `versionPile` ;
    - hors verrou : `evenement(Evenement *)` (`Evenement {signal, ok, brut, detail, nom}`, `Signal::kBrut` pour tout signal de la pile), `reponse(Reponse *)`.

Ce fichier touche la radio et la concurrence entre tâches : la relecture de cette tâche se fait au modèle le plus fort.

- [ ] **Step 1 : écrire le firmware.**

`sonde/src/version.h` :

```cpp
#pragma once
// Version du firmware de la sonde : bonjour.version, et attribut SW Build ID
// de la grappe Basic (ce que le pont Hue lit). 0.9.0 pendant l'essai (spec
// de la sonde, section 4), 1.0.0 ensuite.
#define SONDE_VERSION "0.9.0"
```

`sonde/src/zigbee.h` :

```cpp
#pragma once
// ===========================================================================
//  Colle avec la pile Zigbee d'Espressif (esp-zigbee-lib 1.6.8, ZBOSS 1.6.4)
//
//  Le seul fichier de la sonde qui parle a la pile. Il ne passe pas par la
//  bibliotheque Zigbee d'Arduino, qui envoie d'elle-meme des Match_Desc_req
//  quand un appareil s'annonce : la liste blanche l'interdit (spec, section
//  3).
//
//  Deux mondes :
//  - la tache Zigbee (creee par demarrer()) fait tourner la pile ; ses
//    rappels ne font que remplir deux files (evenements et reponses) ;
//  - loop() lit ces files, et appelle les fonctions « sous le verrou » apres
//    avoir pris le verrou de la pile (verrou(), 200 ms au plus), puis le
//    rend (libere()).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "entrees.h"

namespace zigbee {

// Signaux de la pile et commandes de la grappe lampe, pour loop().
enum class Signal : uint8_t {
  kPremierDemarrage,  // ok : statut de la pile
  kRedemarrage,       // ok : rattachee au reseau garde en memoire
  kRecherche,         // ok : adhesion reussie
  kRattachementTc,    // ok : rattachement par le centre de confiance reussi
  kParentPerdu,
  kDepart,            // ok : depart avec retour (rejoin)
  kIdentification,    // ok : identification en cours (attribut Identify Time)
  kEffet,             // ok : effet d'identification lance ; false : arrete
  kLampe,             // ok : lampe Hue allumee
  kBrut,              // tout signal de la pile, pour le journal de l'essai (SONDE_SIGNAUX)
};

struct Evenement {
  Signal signal;
  bool ok;
  uint8_t brut = 0;          // kBrut : type du signal de la pile
  uint8_t detail = 0;        // kBrut : statut NLME, ou type de depart
  const char *nom = nullptr; // kBrut : nom du signal (table constante de la pile)
};

// Reponse a une requete de la sonde, reperee par son numero.
enum class Genre : uint8_t { kVoisins, kRoutes, kEchecs };
static constexpr size_t kVoisinsParPageMax = 8;

struct Reponse {
  Genre genre = Genre::kVoisins;
  uint32_t numero = 0;
  uint8_t statut = 0;
  uint8_t total = 0;
  uint8_t debut = 0;
  uint8_t nombre = 0;
  EntreeVoisin voisins[kVoisinsParPageMax];  // kVoisins
  EntreeRoute routes[kRoutesParPageMax];     // kRoutes
  uint16_t emissions = 0;                    // kEchecs
  uint16_t echecs = 0;
  uint8_t energie = 0;
};

// Cree la pile, le point d'acces lampe et la tache Zigbee (dans setup()).
void demarrer();
// Role fixe a la compilation : routeur si ZIGBEE_MODE_ZCZR (repli de
// l'essai E1 bis), appareil final sinon.
bool routeur();

// La pile a demarre (premier signal recu) : avant, aucun verrou n'est pris.
bool prete();
// Verrou de la pile, ms au plus ; toujours refuse avant prete().
bool verrou(uint32_t ms);
void libere();

// --- Sous le verrou -------------------------------------------------------
bool rattachee();              // esp_zb_bdb_dev_joined()
void ieee(uint8_t sortie[8]);  // ordre du reseau (poids faible d'abord)
uint16_t court();
uint16_t pan();
void epid(uint8_t sortie[8]);
uint8_t canal();
// Table des voisins de la sonde : *iterateur a 0 pour la premiere entree.
bool voisinSuivant(uint16_t *iterateur, VoisinSonde *v);
// Requetes (refusees par la liste blanche si elles n'y sont pas) ; la
// reponse arrive dans la file avec le meme numero.
bool envoyerVoisins(uint16_t cible, uint8_t index, uint32_t numero);  // Mgmt_Lqi_req
bool envoyerRoutes(uint16_t cible, uint8_t index, uint32_t numero);   // Mgmt_Rtg_req, APS brute
bool envoyerEchecs(uint16_t cible, uint32_t numero);                  // Mgmt_NWK_Update_req
// Mise en service (BDB) : initialisation (rattachement au reseau garde),
// recherche (network steering). Une recherche alors que la sonde est deja
// rattachee diffuserait un Mgmt_Permit_Joining_req (norme BDB) et ouvrirait
// le reseau Hue : chercher() ne la lance pas, et annonce la recherche reussie.
void initialiser();
void chercher();
// Quitter le reseau et effacer la memoire Zigbee (signal de depart a la fin).
void quitter();
// Effacer zb_storage et redemarrer.
void oublier();
// Version de la pile : « majeure.mineure.correctif ».
void versionPile(char *sortie, size_t taille);

// --- Hors verrou ----------------------------------------------------------
bool evenement(Evenement *e);
bool reponse(Reponse *r);

}  // namespace zigbee
```

`sonde/src/zigbee.cpp` :

```cpp
// Colle avec la pile Zigbee d'Espressif : voir zigbee.h.
#include "zigbee.h"

#include <esp_err.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>
#include <string.h>

#include <atomic>

#include "aps/esp_zigbee_aps.h"
#include "esp_zigbee_core.h"
#include "ha/esp_zigbee_ha_standard.h"
#include "liste_blanche.h"
#include "nwk/esp_zigbee_nwk.h"
#include "esp_zigbee_version.h"
#include "options.h"
#include "version.h"
#include "zdo/esp_zigbee_zdo_command.h"

// Cle de liaison du centre de confiance Hue : fichier local, jamais dans le
// depot (spec, section 1 ; sonde/README.md). Les variantes de verification
// (verif, verif_routeur) compilent avec une cle factice : elles ne
// rejoindraient aucun pont, et outils/flasher.py refuse de les flasher.
#if defined(SONDE_CLE_FACTICE)
static constexpr uint8_t kCleHue[16] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                                        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10};
#elif __has_include("cle_hue.local.h")
#include "cle_hue.local.h"
#else
#error "sonde/cle_hue.local.h absent : copier sonde/cle_hue.exemple.h et y mettre la cle de liaison Hue (sonde/README.md)"
#endif

static constexpr bool cleRemplie(const uint8_t (&c)[16], int i = 0) {
  return i < 16 && (c[i] != 0 || cleRemplie(c, i + 1));
}
static_assert(cleRemplie(kCleHue), "sonde/cle_hue.local.h : la cle est encore a zero (sonde/README.md)");

#ifndef SONDE_LAMPE_VARIABLE
#define SONDE_LAMPE_VARIABLE 0  // 1 : Dimmable Light (0x0101) au lieu d'On/Off Light (0x0100)
#endif

namespace zigbee {
namespace {

constexpr uint8_t kPointAcces = 11;
// Canaux possibles d'un reseau Hue : 11, 15, 20 et 25.
constexpr uint32_t kCanauxHue = (1u << 11) | (1u << 15) | (1u << 20) | (1u << 25);
// Appareil final : maintien aupres du parent toutes les 10 s ; le parent
// l'oublie apres 64 minutes de silence.
constexpr uint32_t kMaintienMs = 10000;

QueueHandle_t sEvenements = nullptr;
QueueHandle_t sReponses = nullptr;
// Posee au premier signal de la pile (tache Zigbee), lue par loop().
std::atomic<bool> sPrete{false};

// Chaines ZCL : la longueur d'abord.
char sFabricant[] = "\x08"
                    "Maillage";
char sModele[] = "\x0C"
                 "sonde-zigbee";
char sVersionLogiciel[1 + 16] = {0};
bool sScenesGlobales = true;
uint16_t sDureeAllumage = 0;
uint16_t sAttenteExtinction = 0;

void pousser(Signal s, bool ok) {
  Evenement e;
  e.signal = s;
  e.ok = ok;
  xQueueSend(sEvenements, &e, 0);  // file pleine : evenement perdu (32 places ; le constat d'Adhesion rattrape)
}

void pousserBrut(uint8_t brut, bool ok, uint8_t detail, const char *nom) {
  Evenement e;
  e.signal = Signal::kBrut;
  e.ok = ok;
  e.brut = brut;
  e.detail = detail;
  e.nom = nom;
  xQueueSend(sEvenements, &e, 0);
}

void pousserReponse(const Reponse &r) { xQueueSend(sReponses, &r, 0); }  // pleine : la page sera redemandee

// --- Rappels de la tache Zigbee --------------------------------------------

void surVoisins(const esp_zb_zdo_mgmt_lqi_rsp_t *rsp, void *ctx) {
  static Reponse r;  // tache Zigbee seulement : pas sur sa pile
  r = Reponse();
  r.genre = Genre::kVoisins;
  r.numero = (uint32_t)(uintptr_t)ctx;
  if (!rsp) {
    r.statut = 0x85;
    pousserReponse(r);
    return;
  }
  r.statut = rsp->status;
  r.total = rsp->neighbor_table_entries;
  r.debut = rsp->start_index;
  if (r.statut == 0 && rsp->neighbor_table_list) {
    const uint8_t n = rsp->neighbor_table_list_count;
    r.nombre = n > kVoisinsParPageMax ? (uint8_t)kVoisinsParPageMax : n;
    for (uint8_t i = 0; i < r.nombre; i++) {
      const esp_zb_zdo_neighbor_table_list_record_t &s = rsp->neighbor_table_list[i];
      EntreeVoisin &e = r.voisins[i];
      memcpy(e.ieee, s.extended_addr, 8);
      e.court = s.network_addr;
      e.type = s.device_type;
      e.ecoute = s.rx_when_idle;
      e.relation = s.relationship;
      e.admission = s.permit_join;
      e.profondeur = s.depth;
      e.lqi = s.lqi;
    }
  }
  pousserReponse(r);
}

#if SONDE_ROUTES
// Mgmt_Rtg_req en attente de reponse (posee sous le verrou, lue par la tache
// Zigbee, qui tient le verrou quand elle appelle ses rappels).
struct AttenteRoutes {
  bool actif = false;
  uint8_t tsn = 0;
  uint16_t cible = 0;
  uint32_t numero = 0;
};
AttenteRoutes sAttenteRoutes;
uint8_t sTsn = 0x80;

// Mgmt_Rtg_rsp (cluster 0x8032) de la cible : lue dans la trame brute.
bool surIndicationAps(esp_zb_apsde_data_ind_t ind) {
  if (ind.profile_id != 0 || ind.cluster_id != (0x8000 | kZdoMgmtRtg) || !sAttenteRoutes.actif ||
      ind.src_short_addr != sAttenteRoutes.cible || !ind.asdu)
    return false;
  PageRoutes p;
  if (!lirePageRoutes(ind.asdu, ind.asdu_length, &p) || p.tsn != sAttenteRoutes.tsn) return false;
  sAttenteRoutes.actif = false;
  // Rendue a l'appelant seulement : la pile ne doit pas la confondre avec la
  // reponse d'une de ses requetes (meme numero de transaction).
  static Reponse r;
  r = Reponse();
  r.genre = Genre::kRoutes;
  r.numero = sAttenteRoutes.numero;
  r.statut = p.statut;
  r.total = p.total;
  r.debut = p.debut;
  r.nombre = p.nombre;
  for (uint8_t i = 0; i < p.nombre; i++) r.routes[i] = p.entrees[i];
  pousserReponse(r);
  return true;
}
#endif

#if SONDE_ECHECS
void surEchecs(const esp_zb_zdo_mgmt_update_notify_t *n, void *ctx) {
  static Reponse r;
  r = Reponse();
  r.genre = Genre::kEchecs;
  r.numero = (uint32_t)(uintptr_t)ctx;
  if (!n) {
    r.statut = 0x85;
  } else {
    r.statut = n->status;
    r.total = 1;
    r.nombre = n->status == 0 ? 1 : 0;
    r.emissions = n->total_transmission;
    r.echecs = n->transmission_failures;
    r.energie = n->scanned_channels_list_count ? n->energy_values[0] : 0;
  }
  pousserReponse(r);
}
#endif

esp_err_t surAction(esp_zb_core_action_callback_id_t id, const void *message) {
  if (!message) return ESP_OK;
  if (id == ESP_ZB_CORE_SET_ATTR_VALUE_CB_ID) {
    const esp_zb_zcl_set_attr_value_message_t *m = (const esp_zb_zcl_set_attr_value_message_t *)message;
    if (m->info.status == ESP_ZB_ZCL_STATUS_SUCCESS && m->info.dst_endpoint == kPointAcces &&
        m->info.cluster == ESP_ZB_ZCL_CLUSTER_ID_ON_OFF && m->attribute.id == ESP_ZB_ZCL_ATTR_ON_OFF_ON_OFF_ID &&
        m->attribute.data.type == ESP_ZB_ZCL_ATTR_TYPE_BOOL && m->attribute.data.value)
      pousser(Signal::kLampe, *(const bool *)m->attribute.data.value);
  } else if (id == ESP_ZB_CORE_IDENTIFY_EFFECT_CB_ID) {
    const esp_zb_zcl_identify_effect_message_t *m = (const esp_zb_zcl_identify_effect_message_t *)message;
    // 0xFE : finir l'effet ; 0xFF : l'arreter.
    pousser(Signal::kEffet, m->effect_id != 0xFE && m->effect_id != 0xFF);
  }
  return ESP_OK;
}

void surIdentification(uint8_t actif) { pousser(Signal::kIdentification, actif != 0); }

void tacheZigbee(void *) {
  ESP_ERROR_CHECK(esp_zb_start(false));
  // Apres esp_zb_start (en-tete de la pile) : alimentation secteur.
  esp_zb_set_node_descriptor_power_source(true);
  esp_zb_stack_main_loop();
}

void creerPointAcces() {
  const size_t n = strlen(SONDE_VERSION);
  sVersionLogiciel[0] = (char)n;
  memcpy(sVersionLogiciel + 1, SONDE_VERSION, n);

  esp_zb_on_off_light_cfg_t config = ESP_ZB_DEFAULT_ON_OFF_LIGHT_CONFIG();
  config.basic_cfg.power_source = ESP_ZB_ZCL_BASIC_POWER_SOURCE_MAINS_SINGLE_PHASE;
  esp_zb_cluster_list_t *grappes = esp_zb_on_off_light_clusters_create(&config);
  esp_zb_attribute_list_t *base =
      esp_zb_cluster_list_get_cluster(grappes, ESP_ZB_ZCL_CLUSTER_ID_BASIC, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_MANUFACTURER_NAME_ID, sFabricant);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_MODEL_IDENTIFIER_ID, sModele);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_SW_BUILD_ID, sVersionLogiciel);
  // Le pont Hue envoie « Off with effect » : attributs de la grappe On/Off
  // qu'il attend (constate par d'autres avant nous).
  esp_zb_attribute_list_t *marche =
      esp_zb_cluster_list_get_cluster(grappes, ESP_ZB_ZCL_CLUSTER_ID_ON_OFF, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_GLOBAL_SCENE_CONTROL, &sScenesGlobales);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_ON_TIME, &sDureeAllumage);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_OFF_WAIT_TIME, &sAttenteExtinction);
#if SONDE_LAMPE_VARIABLE
  esp_zb_level_cluster_cfg_t niveau = {};
  niveau.current_level = 254;
  esp_zb_cluster_list_add_level_cluster(grappes, esp_zb_level_cluster_create(&niveau),
                                        ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);
#endif

  esp_zb_endpoint_config_t pa = {};
  pa.endpoint = kPointAcces;
  pa.app_profile_id = ESP_ZB_AF_HA_PROFILE_ID;
  pa.app_device_id = SONDE_LAMPE_VARIABLE ? ESP_ZB_HA_DIMMABLE_LIGHT_DEVICE_ID : ESP_ZB_HA_ON_OFF_LIGHT_DEVICE_ID;
  pa.app_device_version = 1;  // exige par le pont Hue
  esp_zb_ep_list_t *liste = esp_zb_ep_list_create();
  esp_zb_ep_list_add_ep(liste, grappes, pa);
  ESP_ERROR_CHECK(esp_zb_device_register(liste));
}

}  // namespace

bool routeur() {
#if defined(ZIGBEE_MODE_ZCZR)
  return true;
#else
  return false;
#endif
}

void demarrer() {
  sEvenements = xQueueCreate(32, sizeof(Evenement));
  sReponses = xQueueCreate(4, sizeof(Reponse));

  esp_zb_platform_config_t plateforme = {};
  plateforme.radio_config.radio_mode = ZB_RADIO_MODE_NATIVE;
  plateforme.host_config.host_connection_mode = ZB_HOST_CONNECTION_MODE_NONE;
  ESP_ERROR_CHECK(esp_zb_platform_config(&plateforme));

  esp_zb_cfg_t config = {};
  config.install_code_policy = false;
#if defined(ZIGBEE_MODE_ZCZR)
  // Repli en routeur (essai E1 bis) : jamais le parent de personne.
  config.esp_zb_role = ESP_ZB_DEVICE_TYPE_ROUTER;
  config.nwk_cfg.zczr_cfg.max_children = 0;
#else
  config.esp_zb_role = ESP_ZB_DEVICE_TYPE_ED;
  config.nwk_cfg.zed_cfg.ed_timeout = ESP_ZB_ED_AGING_TIMEOUT_64MIN;
  config.nwk_cfg.zed_cfg.keep_alive = kMaintienMs;
#endif
  esp_zb_init(&config);

  creerPointAcces();
  esp_zb_core_action_handler_register(surAction);
  esp_zb_identify_notify_handler_register(kPointAcces, surIdentification);
#if SONDE_ROUTES
  esp_zb_aps_data_indication_handler_register(surIndicationAps);
#endif
  ESP_ERROR_CHECK(esp_zb_set_primary_network_channel_set(kCanauxHue));
  // Adhesion au pont Hue : la cle de liaison de Signify (ZLL).
  esp_zb_enable_joining_to_distributed(true);
  esp_zb_secur_TC_standard_distributed_key_set((uint8_t *)kCleHue);
#if !defined(ZIGBEE_MODE_ZCZR)
  esp_zb_set_rx_on_when_idle(true);  // appareil final non endormi
#endif

  xTaskCreate(tacheZigbee, "zigbee", 8192, nullptr, 5, nullptr);
}

bool prete() { return sPrete; }
bool verrou(uint32_t ms) { return sPrete && esp_zb_lock_acquire(pdMS_TO_TICKS(ms)); }
void libere() { esp_zb_lock_release(); }

bool rattachee() { return esp_zb_bdb_dev_joined(); }
void ieee(uint8_t sortie[8]) { esp_zb_get_long_address(sortie); }
uint16_t court() { return esp_zb_get_short_address(); }
uint16_t pan() { return esp_zb_get_pan_id(); }
void epid(uint8_t sortie[8]) { esp_zb_get_extended_pan_id(sortie); }
uint8_t canal() { return esp_zb_get_current_channel(); }

bool voisinSuivant(uint16_t *iterateur, VoisinSonde *v) {
  esp_zb_nwk_info_iterator_t i = *iterateur;
  esp_zb_nwk_neighbor_info_t n = {};
  if (esp_zb_nwk_get_next_neighbor(&i, &n) != ESP_OK) return false;
  *iterateur = i;
  memcpy(v->ieee, n.ieee_addr, 8);
  v->court = n.short_addr;
  v->type = n.device_type;
  v->relation = n.relationship;
  v->lqi = n.lqi;
  v->rssi = n.rssi;
  v->coutSortant = n.outgoing_cost;
  v->age = n.age;
  return true;
}

bool envoyerVoisins(uint16_t cible, uint8_t index, uint32_t numero) {
  if (!requetePermise(kZdoMgmtLqi, cible)) return false;
  esp_zb_zdo_mgmt_lqi_req_param_t req = {};
  req.start_index = index;
  req.dst_addr = cible;
  esp_zb_zdo_mgmt_lqi_req(&req, surVoisins, (void *)(uintptr_t)numero);
  return true;
}

bool envoyerRoutes(uint16_t cible, uint8_t index, uint32_t numero) {
#if SONDE_ROUTES
  if (!requetePermise(kZdoMgmtRtg, cible)) return false;
  static uint8_t asdu[2];
  if (++sTsn < 0x80) sTsn = 0x80;  // 0x80 a 0xFF : loin des numeros de la pile
  requeteRoutes(sTsn, index, asdu);
  esp_zb_apsde_data_req_t req = {};
  req.dst_addr_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
  req.dst_addr.addr_short = cible;
  req.dst_endpoint = 0;
  req.profile_id = 0;
  req.cluster_id = kZdoMgmtRtg;
  req.src_endpoint = 0;
  req.asdu_length = sizeof(asdu);
  req.asdu = asdu;
  req.tx_options = 0;
  req.use_alias = false;
  req.radius = 0;
  sAttenteRoutes.actif = true;
  sAttenteRoutes.tsn = sTsn;
  sAttenteRoutes.cible = cible;
  sAttenteRoutes.numero = numero;
  if (esp_zb_aps_data_request(&req) != ESP_OK) {
    sAttenteRoutes.actif = false;
    return false;
  }
  return true;
#else
  (void)cible;
  (void)index;
  (void)numero;
  return false;
#endif
}

bool envoyerEchecs(uint16_t cible, uint32_t numero) {
#if SONDE_ECHECS
  const uint8_t c = esp_zb_get_current_channel();
  esp_zb_zdo_mgmt_nwk_update_req_param_t req = {};
  req.scan_channels = 1u << c;
  req.scan_duration = 0;
  req.scan_count = 1;
  req.nwk_manager_addr = 0;
  req.dst_addr = cible;
  if (c < 11 || c > 26 || !requetePermise(kZdoMgmtNwkUpdate, cible) ||
      !balayagePermis(req.scan_channels, req.scan_duration, c))
    return false;
  esp_zb_zdo_mgmt_nwk_update_req(&req, surEchecs, (void *)(uintptr_t)numero);
  return true;
#else
  (void)cible;
  (void)numero;
  return false;
#endif
}

void initialiser() { esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION); }

void chercher() {
  if (esp_zb_bdb_dev_joined()) {
    pousser(Signal::kRecherche, true);
    return;
  }
  esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
}
void quitter() { esp_zb_bdb_reset_via_local_action(); }
void oublier() { esp_zb_factory_reset(); }

void versionPile(char *sortie, size_t taille) {
  snprintf(sortie, taille, "%d.%d.%d", ESP_ZB_VER_MAJOR, ESP_ZB_VER_MINOR, ESP_ZB_VER_PATCH);
}

bool evenement(Evenement *e) { return sEvenements && xQueueReceive(sEvenements, e, 0) == pdTRUE; }
bool reponse(Reponse *r) { return sReponses && xQueueReceive(sReponses, r, 0) == pdTRUE; }

}  // namespace zigbee

// Signaux de la pile (tache Zigbee) : l'initialisation repond tout de suite ;
// le reste part a loop() par la file.
extern "C" void esp_zb_app_signal_handler(esp_zb_app_signal_t *signal) {
  using zigbee::Signal;
  uint32_t *p = signal->p_app_signal;
  const bool ok = signal->esp_err_status == ESP_OK;
  const esp_zb_app_signal_type_t type = (esp_zb_app_signal_type_t)*p;
  uint8_t detail = 0;
  switch (type) {
    case ESP_ZB_ZDO_SIGNAL_SKIP_STARTUP:
      zigbee::sPrete = true;
      // Initialisation refusee : comme un premier demarrage en echec, relance
      // par Adhesion une seconde plus tard.
      if (esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION) != ESP_OK)
        zigbee::pousser(Signal::kPremierDemarrage, false);
      break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START: zigbee::pousser(Signal::kPremierDemarrage, ok); break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT: zigbee::pousser(Signal::kRedemarrage, ok); break;
    case ESP_ZB_BDB_SIGNAL_STEERING: zigbee::pousser(Signal::kRecherche, ok); break;
    case ESP_ZB_BDB_SIGNAL_TC_REJOIN_DONE: zigbee::pousser(Signal::kRattachementTc, ok); break;
    case ESP_ZB_NLME_STATUS_INDICATION: {
      const esp_zb_zdo_signal_nwk_status_indication_params_t *s =
          (const esp_zb_zdo_signal_nwk_status_indication_params_t *)esp_zb_app_signal_get_params(p);
      if (s) detail = s->status;
      if (s && s->status == ESP_ZB_NWK_COMMAND_STATUS_PARENT_LINK_FAILURE)
        zigbee::pousser(Signal::kParentPerdu, true);
      break;
    }
    case ESP_ZB_ZDO_SIGNAL_LEAVE: {
      const esp_zb_zdo_signal_leave_params_t *d =
          (const esp_zb_zdo_signal_leave_params_t *)esp_zb_app_signal_get_params(p);
      if (d) detail = d->leave_type;
      zigbee::pousser(Signal::kDepart, d && d->leave_type == ESP_ZB_NWK_LEAVE_TYPE_REJOIN);
      break;
    }
    default: break;
  }
  // Tout signal, pour le journal de l'essai : on y verra ce que la pile fait
  // a la perte du parent, au depart, au rattachement.
  zigbee::pousserBrut((uint8_t)type, ok, detail, esp_zb_zdo_signal_to_string(type));
}
```

`sonde/src/main.cpp` :

```cpp
// ===========================================================================
//  Sonde de maillage Zigbee, firmware 0.9.0 (spec :
//  docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md)
//
//  ESP32-C6 membre du reseau Hue : appareil final non endormi (ou routeur,
//  repli de l'essai E1 bis), point d'acces « lampe » (endpoint 11). Il ne
//  relaie rien en appareil final, n'envoie aucune commande aux lampes, et
//  n'emet que les requetes ZDO de lecture de la liste blanche
//  (liste_blanche.h) : il donne par l'USB la table des voisins de n'importe
//  quel routeur, et la sienne. L'app (Maillage Zigbee) orchestre la tournee,
//  decode et dessine.
//
//  USB : une commande par ligne ; chaque reponse est une ligne machine,
//  RS (0x1E) + JSON compact + LF, 4095 octets au plus (ligne.h).
//    bonjour                          produit, version, nom, adresse longue,
//                                     membre, role, suspendue (aussi au
//                                     demarrage)
//    nom <texte>                      change le nom et le garde ; bonjour a
//                                     jour, ou erreur syntaxe / ecriture
//    etat                             membre, recherche, adresses, parent,
//                                     PAN, EPID, canal, suspendue,
//                                     refus_cadence, version de la pile
//    voisins                          table des voisins de la sonde
//    table <cible> <id> [<delai ms>]  table complete des voisins d'un
//                                     routeur (Mgmt_Lqi_req, page par page)
//    routes <cible> <id> [<delai ms>] table de routage (Mgmt_Rtg_req en APS
//                                     brute ; si SONDE_ROUTES, essai E4)
//    echecs <cible> <id> [<delai ms>] emissions et echecs d'un routeur
//                                     (Mgmt_NWK_Update_req ; si
//                                     SONDE_ECHECS, essai E5)
//    suspendre | reprendre            garde l'etat ; repond par etat
//    oubli                            quitter le reseau et l'oublier ; la
//                                     sonde redemarre, et son bonjour de
//                                     demarrage suit
//  Une seule requete reseau a la fois (sinon « occupee »), garde-fou de
//  cadence (cadence.h), une seule nouvelle tentative par page ; une requete
//  en cours s'arrete en « non_membre » si la sonde quitte le reseau.
//  Si SONDE_SIGNAUX : une ligne « signal » pour chaque signal de la pile
//  (type, nom, statut, detail), pour comprendre l'essai.
//
//  Dans l'app Hue, la sonde est une lampe : on/off et identification ne
//  pilotent que la LED, jamais la suspension (« Tout eteindre » ne doit pas
//  la suspendre).
// ===========================================================================

#include <Arduino.h>
#include <Preferences.h>
#include <esp_log.h>
#include <esp_system.h>

#include "adhesion.h"
#include "cadence.h"
#include "commande.h"
#include "entrees.h"
#include "ligne.h"
#include "options.h"
#include "pagination.h"
#include "version.h"
#include "voyant.h"
#include "zigbee.h"

// ---------------------------------------------------------------------------
//  Etat
// ---------------------------------------------------------------------------

static Preferences sPreferences;  // espace « sonde » : nom, suspendue
static const char *const kCleNom = "nom";
static const char *const kCleSuspendue = "suspendue";
static const char *const kNomDefaut = "SONDE-Z1";
static char sNom[kNomMax + 1] = "SONDE-Z1";
static bool sSuspendue = false;

static Adhesion sAdhesion;
static Cadence sCadence;
static Voyant sVoyant;
static Ligne sLigne;
static uint32_t sAdhesionsVues = 0;
static uint32_t sFinEffet = 0;  // fin de l'effet d'identification en cours
static bool sEffet = false;

static uint8_t sIeee[8] = {0};
static bool sIeeeConnu = false;
static uint32_t sDernierConstat = 0;  // dernier constat de la pile (Adhesion::constater)

// La requete reseau en cours (une seule a la fois).
enum class Travail : uint8_t { kAucun, kTable, kRoutes, kEchecs };
static Travail sTravail = Travail::kAucun;
static uint16_t sCible = 0;
static uint32_t sId = 0;
static constexpr size_t kEntreesMax = 64;
static Pagination<EntreeVoisin, kEntreesMax> sTable;
#if SONDE_ROUTES
static Pagination<EntreeRoute, kEntreesMax> sRoutes;
#endif
#if SONDE_ECHECS
struct ResultatEchecs {
  uint16_t emissions;
  uint16_t echecs;
  uint8_t energie;
};
static Pagination<ResultatEchecs, 1> sEchecs;  // une « table » d'une entree
#endif

// ---------------------------------------------------------------------------
//  Sorties
// ---------------------------------------------------------------------------

static void ecrire(void *, const uint8_t *octets, size_t n) { Serial.write(octets, n); }

static void finir() {
  size_t n = 0;
  const uint8_t *o = sLigne.fin(&n);
  ecrire(nullptr, o, n);
}

static void repondreErreur(const char *erreur) {
  sLigne.debut("erreur");
  sLigne.ajoute(",\"erreur\":\"%s\"", erreur);
  finir();
}

static void ajouteIeee(const char *cle, const uint8_t ieee[8]) {
  char t[17];
  texteIeee(ieee, t);
  sLigne.ajoute(",\"%s\":\"%s\"", cle, t);
}

// Adresse longue de la sonde, lue une fois sous le verrou.
static void lireIeee(uint32_t attenteMs) {
  if (sIeeeConnu || !zigbee::verrou(attenteMs)) return;
  zigbee::ieee(sIeee);
  zigbee::libere();
  sIeeeConnu = true;
}

static const char *texteRole() {
  if (!sAdhesion.membre()) return nullptr;
  return zigbee::routeur() ? "routeur" : "final";
}

// ---------------------------------------------------------------------------
//  Commandes simples
// ---------------------------------------------------------------------------

static void cmdBonjour() {
  lireIeee(200);
  sLigne.debut("bonjour");
  sLigne.ajoute(",\"produit\":\"sonde-zigbee\",\"version\":\"%s\",\"nom\":\"%s\"", SONDE_VERSION, sNom);
  if (sIeeeConnu) ajouteIeee("ieee", sIeee);
  else sLigne.ajoute(",\"ieee\":null");
  const char *role = texteRole();
  sLigne.ajoute(",\"membre\":%s", sAdhesion.membre() ? "true" : "false");
  if (role) sLigne.ajoute(",\"role\":\"%s\"", role);
  else sLigne.ajoute(",\"role\":null");
  sLigne.ajoute(",\"suspendue\":%s", sSuspendue ? "true" : "false");
  finir();
}

static void cmdNom(const char *nom) {
  // putString rend le nombre d'octets ecrits : 0 si la NVS refuse.
  if (sPreferences.putString(kCleNom, nom) == 0) return repondreErreur("ecriture");
  snprintf(sNom, sizeof(sNom), "%s", nom);
  cmdBonjour();
}

static void cmdEtat() {
  if (!zigbee::verrou(200)) {
    sLigne.debut("etat");
    sLigne.ajoute(",\"erreur\":\"occupee\"");
    return finir();
  }
  const bool membre = sAdhesion.membre();
  uint8_t ieee[8], epid[8];
  zigbee::ieee(ieee);
  zigbee::epid(epid);
  const uint16_t court = zigbee::court();
  const uint16_t pan = zigbee::pan();
  const uint8_t canal = zigbee::canal();
  VoisinSonde parent;
  bool parentConnu = false;
  if (membre && !zigbee::routeur()) {
    uint16_t it = 0;
    VoisinSonde v;
    while (!parentConnu && zigbee::voisinSuivant(&it, &v)) {
      if (v.relation == 0) {
        parent = v;
        parentConnu = true;
      }
    }
  }
  char pile[24];
  zigbee::versionPile(pile, sizeof(pile));
  zigbee::libere();

  sLigne.debut("etat");
  sLigne.ajoute(",\"membre\":%s,\"recherche\":%s", membre ? "true" : "false", sAdhesion.cherche() ? "true" : "false");
  if (membre) sLigne.ajoute(",\"court\":\"%04X\"", court);
  else sLigne.ajoute(",\"court\":null");
  ajouteIeee("ieee", ieee);
  const char *role = texteRole();
  if (role) sLigne.ajoute(",\"role\":\"%s\"", role);
  else sLigne.ajoute(",\"role\":null");
  if (parentConnu) {
    char t[17];
    texteIeee(parent.ieee, t);
    sLigne.ajoute(",\"parent\":{\"court\":\"%04X\",\"ieee\":\"%s\",\"lqi\":%u,\"rssi\":%d}", parent.court, t,
                  parent.lqi, parent.rssi);
  } else {
    sLigne.ajoute(",\"parent\":null");
  }
  if (membre) {
    sLigne.ajoute(",\"pan\":\"%04X\"", pan);
    ajouteIeee("epid", epid);
    sLigne.ajoute(",\"canal\":%u", canal);
  } else {
    sLigne.ajoute(",\"pan\":null,\"epid\":null,\"canal\":null");
  }
  sLigne.ajoute(",\"suspendue\":%s,\"refus_cadence\":%lu,\"rattachements_echoues\":%lu,\"pile\":\"%s\"",
                sSuspendue ? "true" : "false", (unsigned long)sCadence.refus(),
                (unsigned long)sAdhesion.echecsRattachement(), pile);
  finir();
}

static void cmdVoisins() {
  if (!zigbee::verrou(200)) {
    sLigne.debut("voisins");
    sLigne.ajoute(",\"erreur\":\"occupee\"");
    return finir();
  }
  // Copie sous le verrou, ecriture apres.
  static VoisinSonde voisins[kEntreesMax];
  size_t n = 0;
  uint16_t it = 0;
  while (n < kEntreesMax && zigbee::voisinSuivant(&it, &voisins[n])) n++;
  zigbee::libere();
  ListeDecoupee liste(sLigne, ecrire, nullptr);
  liste.commencer("voisins", "");
  char objet[256];
  for (size_t i = 0; i < n; i++) {
    if (jsonVoisinSonde(voisins[i], objet, sizeof(objet))) liste.ajouter(objet);
  }
  liste.terminer();
}

static void cmdSuspendre(bool suspendue) {
  sSuspendue = suspendue;
  sPreferences.putBool(kCleSuspendue, suspendue);
  cmdEtat();
}

// ---------------------------------------------------------------------------
//  Requetes reseau : table, routes, echecs
// ---------------------------------------------------------------------------

static const char *texteIssue(Issue i) {
  switch (i) {
    case Issue::kDelai: return "delai";
    case Issue::kStatut: return "statut";
    case Issue::kCadence: return "cadence";
    case Issue::kEnvoi: return "envoi";
    case Issue::kSuspendue: return "suspendue";
    case Issue::kNonMembre: return "non_membre";
    default: return "envoi";
  }
}

static const char *typeTravail(Travail t) {
  switch (t) {
    case Travail::kRoutes: return "routes";
    case Travail::kEchecs: return "echecs";
    default: return "table";
  }
}

// Echec avant ou pendant une requete : une ligne, sans liste.
static void repondreEchec(Travail t, uint32_t id, uint16_t cible, const char *erreur, int statut = -1) {
  sLigne.debut(typeTravail(t));
  sLigne.ajoute(",\"id\":%lu,\"cible\":\"%04X\",\"ok\":false,\"erreur\":\"%s\"", (unsigned long)id, cible, erreur);
  if (statut >= 0) sLigne.ajoute(",\"statut\":\"0x%02X\"", statut);
  finir();
}

static void commencer(const Commande &c, Travail t, uint32_t maintenant) {
#if !SONDE_ROUTES
  if (t == Travail::kRoutes) return repondreErreur("inconnue");
#endif
#if !SONDE_ECHECS
  if (t == Travail::kEchecs) return repondreErreur("inconnue");
#endif
  if (sTravail != Travail::kAucun) return repondreEchec(t, c.id, c.cible, "occupee");
  if (sSuspendue) return repondreEchec(t, c.id, c.cible, "suspendue");
  if (!sAdhesion.membre()) return repondreEchec(t, c.id, c.cible, "non_membre");
  sTravail = t;
  sCible = c.cible;
  sId = c.id;
  if (t == Travail::kTable) sTable.commencer(maintenant, c.delaiMs);
#if SONDE_ROUTES
  if (t == Travail::kRoutes) sRoutes.commencer(maintenant, c.delaiMs);
#endif
#if SONDE_ECHECS
  if (t == Travail::kEchecs) sEchecs.commencer(maintenant, c.delaiMs);
#endif
}

// En-tete d'une reponse reussie, repris sur chaque ligne de la liste.
template <typename P>
static void entete(const P &p, char *sortie, size_t taille) {
  snprintf(sortie, taille, ",\"id\":%lu,\"cible\":\"%04X\",\"ok\":true,\"ms\":%lu,\"pages\":%u,\"total\":%u,\"partielle\":%s",
           (unsigned long)sId, sCible, (unsigned long)p.dureeMs(), p.pages(), p.total(),
           p.partielle() ? "true" : "false");
}

// Ecrit le resultat d'une table finie.
template <typename P, typename F>
static void rendre(const P &p, F json) {
  if (p.issue() != Issue::kOk) {
    return repondreEchec(sTravail, sId, sCible, texteIssue(p.issue()),
                         p.issue() == Issue::kStatut ? (int)p.statut() : -1);
  }
  char tete[ListeDecoupee::kEnteteMax + 1];
  entete(p, tete, sizeof(tete));
  ListeDecoupee liste(sLigne, ecrire, nullptr);
  liste.commencer(typeTravail(sTravail), tete);
  char objet[256];
  for (size_t i = 0; i < p.nombre(); i++) {
    if (json(p.entree(i), objet, sizeof(objet))) liste.ajouter(objet);
  }
  liste.terminer();
}

#if SONDE_ECHECS
static void rendreEchecs() {
  if (sEchecs.issue() != Issue::kOk || sEchecs.nombre() == 0) {
    const Issue i = sEchecs.issue() == Issue::kOk ? Issue::kStatut : sEchecs.issue();
    return repondreEchec(Travail::kEchecs, sId, sCible, texteIssue(i),
                         i == Issue::kStatut ? (int)sEchecs.statut() : -1);
  }
  const ResultatEchecs &r = sEchecs.entree(0);
  sLigne.debut("echecs");
  sLigne.ajoute(",\"id\":%lu,\"cible\":\"%04X\",\"ok\":true,\"ms\":%lu,\"emissions\":%u,\"echecs\":%u,\"energie\":%u",
                (unsigned long)sId, sCible, (unsigned long)sEchecs.dureeMs(), r.emissions, r.echecs, r.energie);
  finir();
}
#endif

// Envoie la page attendue si la cadence le permet ; envoyer(index, numero)
// sous le verrou.
template <typename P, typename Envoi>
static void pousserPage(P &p, uint32_t maintenant, Envoi envoyer) {
  if (!p.aEnvoyer(maintenant)) return;
  switch (sCadence.avis(maintenant)) {
    case Cadence::Avis::kAttendre: return;
    case Cadence::Avis::kRefus:
      sCadence.refuser();
      p.abandonner(Issue::kCadence, maintenant);
      return;
    case Cadence::Avis::kOui: break;
  }
  if (!zigbee::verrou(50)) return;  // pile occupee : au prochain tour
  const bool parti = envoyer(p.index(), p.numeroAEnvoyer());
  zigbee::libere();
  if (!parti) return p.abandonner(Issue::kEnvoi, maintenant);
  sCadence.compter(maintenant);
  p.envoyee(maintenant);
}

// Arret impose a la requete en cours (suspendue, sortie du reseau) : rien si
// aucune ; la fin est ecrite par progresser().
static void arreter(Issue issue, uint32_t maintenant) {
  sTable.abandonner(issue, maintenant);
#if SONDE_ROUTES
  sRoutes.abandonner(issue, maintenant);
#endif
#if SONDE_ECHECS
  sEchecs.abandonner(issue, maintenant);
#endif
}

static void progresser(uint32_t maintenant) {
  // Les reponses d'abord : celles d'une requete finie ou d'un autre genre
  // sont ecartees par leur numero ou leur genre.
  static zigbee::Reponse r;
  while (zigbee::reponse(&r)) {
    if (r.genre == zigbee::Genre::kVoisins && sTravail == Travail::kTable)
      sTable.page(r.numero, r.statut, r.total, r.debut, r.nombre, r.voisins, maintenant);
#if SONDE_ROUTES
    if (r.genre == zigbee::Genre::kRoutes && sTravail == Travail::kRoutes)
      sRoutes.page(r.numero, r.statut, r.total, r.debut, r.nombre, r.routes, maintenant);
#endif
#if SONDE_ECHECS
    if (r.genre == zigbee::Genre::kEchecs && sTravail == Travail::kEchecs) {
      const ResultatEchecs e = {r.emissions, r.echecs, r.energie};
      sEchecs.page(r.numero, r.statut, r.total, 0, r.nombre, &e, maintenant);
    }
#endif
  }

  if (sTravail != Travail::kAucun && sSuspendue) arreter(Issue::kSuspendue, maintenant);
  if (sTravail != Travail::kAucun && !sAdhesion.membre()) arreter(Issue::kNonMembre, maintenant);
  switch (sTravail) {
    case Travail::kAucun: return;
    case Travail::kTable:
      pousserPage(sTable, maintenant,
                  [](uint8_t index, uint32_t numero) { return zigbee::envoyerVoisins(sCible, index, numero); });
      if (!sTable.actif()) {
        rendre(sTable, jsonEntreeVoisin);
        sTravail = Travail::kAucun;
      }
      return;
    case Travail::kRoutes:
#if SONDE_ROUTES
      pousserPage(sRoutes, maintenant,
                  [](uint8_t index, uint32_t numero) { return zigbee::envoyerRoutes(sCible, index, numero); });
      if (!sRoutes.actif()) {
        rendre(sRoutes, jsonEntreeRoute);
        sTravail = Travail::kAucun;
      }
#endif
      return;
    case Travail::kEchecs:
#if SONDE_ECHECS
      pousserPage(sEchecs, maintenant,
                  [](uint8_t, uint32_t numero) { return zigbee::envoyerEchecs(sCible, numero); });
      if (!sEchecs.actif()) {
        rendreEchecs();
        sTravail = Travail::kAucun;
      }
#endif
      return;
  }
}

// ---------------------------------------------------------------------------
//  Oubli
// ---------------------------------------------------------------------------

static void cmdOubli(uint32_t maintenant) {
  // Une requete en cours finit d'abord, en « non_membre ».
  if (sTravail != Travail::kAucun) {
    arreter(Issue::kNonMembre, maintenant);
    progresser(maintenant);
  }
  // Comme a la premiere mise en service : non suspendue ; le nom est garde.
  sSuspendue = false;
  sPreferences.putBool(kCleSuspendue, false);
  sLigne.debut("oubli");
  sLigne.ajoute(",\"ok\":true");
  finir();
  Serial.flush();
  const bool membre = sAdhesion.membre();
  sAdhesion.oubli(maintenant);
  if (!zigbee::verrou(1000)) return;  // le filet d'Adhesion oubliera dans 15 s
  if (membre) zigbee::quitter();      // signal de depart a la fin, puis oublier
  else zigbee::oublier();             // redemarre
  zigbee::libere();
}

// ---------------------------------------------------------------------------
//  Commandes de l'USB
// ---------------------------------------------------------------------------

static void executer(const char *ligne, uint32_t maintenant) {
  const Commande c = lireCommande(ligne);
  switch (c.type) {
    case TypeCommande::kBonjour: return cmdBonjour();
    case TypeCommande::kNom: return cmdNom(c.nom);
    case TypeCommande::kEtat: return cmdEtat();
    case TypeCommande::kVoisins: return cmdVoisins();
    case TypeCommande::kTable: return commencer(c, Travail::kTable, maintenant);
    case TypeCommande::kRoutes: return commencer(c, Travail::kRoutes, maintenant);
    case TypeCommande::kEchecs: return commencer(c, Travail::kEchecs, maintenant);
    case TypeCommande::kSuspendre: return cmdSuspendre(true);
    case TypeCommande::kReprendre: return cmdSuspendre(false);
    case TypeCommande::kOubli: return cmdOubli(maintenant);
    case TypeCommande::kSyntaxe: return repondreErreur("syntaxe");
    case TypeCommande::kInconnue: return repondreErreur("inconnue");
  }
}

// ---------------------------------------------------------------------------
//  Adhesion et signaux de la pile
// ---------------------------------------------------------------------------

static void evenements(uint32_t maintenant) {
  zigbee::Evenement e;
  while (zigbee::evenement(&e)) {
    switch (e.signal) {
      case zigbee::Signal::kPremierDemarrage: sAdhesion.premierDemarrage(e.ok, maintenant); break;
      case zigbee::Signal::kRedemarrage: sAdhesion.redemarrage(e.ok, maintenant); break;
      case zigbee::Signal::kRecherche: sAdhesion.recherche(e.ok, maintenant); break;
      case zigbee::Signal::kRattachementTc: sAdhesion.rattachementTc(e.ok, maintenant); break;
      case zigbee::Signal::kParentPerdu: sAdhesion.parentPerdu(maintenant); break;
      case zigbee::Signal::kDepart: sAdhesion.depart(e.ok, maintenant); break;
      case zigbee::Signal::kIdentification: sVoyant.identifier(e.ok, maintenant); break;
      case zigbee::Signal::kEffet:
        // Un effet d'identification dure 3 s ; « finir » ou « arreter »
        // l'eteint tout de suite.
        sEffet = e.ok;
        sFinEffet = maintenant + 3000;
        sVoyant.identifier(e.ok, maintenant);
        break;
      case zigbee::Signal::kLampe: sVoyant.allumer(e.ok); break;
      case zigbee::Signal::kBrut:
#if SONDE_SIGNAUX
        sLigne.debut("signal");
        sLigne.ajoute(",\"signal\":\"0x%02X\",\"nom\":\"%s\",\"ok\":%s,\"detail\":%u", e.brut,
                      e.nom ? e.nom : "?", e.ok ? "true" : "false", e.detail);
        finir();
#endif
        break;
    }
  }
  // Constat de la pile toutes les 10 s (un signal d'adhesion perdu est
  // rattrape), sans attendre le verrou.
  if (maintenant - sDernierConstat >= 10000 && zigbee::verrou(0)) {
    const bool rattachee = zigbee::rattachee();
    zigbee::libere();
    sDernierConstat = maintenant;
    sAdhesion.constater(rattachee, maintenant);
  }
  if (sEffet && (int32_t)(maintenant - sFinEffet) >= 0) {
    sEffet = false;
    sVoyant.identifier(false, maintenant);
  }

  const Adhesion::Action a = sAdhesion.tour(maintenant);
  if (a == Adhesion::Action::kRien) return;
  if (a == Adhesion::Action::kRedemarrer) esp_restart();
  // Le verrou, 1 s au plus : une action perdue repart par les filets
  // d'Adhesion (sauf oublier, que le depart ne refait pas : on insiste).
  for (int essai = 0; essai < 5; essai++) {
    if (!zigbee::verrou(200)) continue;
    switch (a) {
      case Adhesion::Action::kInitialiser:
      case Adhesion::Action::kRattacher: zigbee::initialiser(); break;
      case Adhesion::Action::kChercher: zigbee::chercher(); break;
      case Adhesion::Action::kOublier: zigbee::oublier(); break;
      default: break;
    }
    zigbee::libere();
    return;
  }
  if (a == Adhesion::Action::kOublier) esp_restart();
}

// ---------------------------------------------------------------------------
//  LED de la carte
// ---------------------------------------------------------------------------

// WS2812 de la SuperMini, sur IO8 : faible intensite, 24/255 au plus par
// canal, comme la sonde Thread ; orange : un quart de vert.
static constexpr uint8_t kBrocheVoyant = 8;
static constexpr uint8_t kVoyantMax = 24;
static uint32_t sVoyantEcrit = 0xFFFFFFFFu;  // RGB ecrit ; rien encore

static void ecrireVoyant(uint8_t r, uint8_t g, uint8_t b) {
  const uint32_t rgb = (uint32_t)r << 16 | (uint32_t)g << 8 | b;
  if (rgb == sVoyantEcrit) return;
  sVoyantEcrit = rgb;
  rgbLedWrite(kBrocheVoyant, r, g, b);
}

static void voyantTour(uint32_t maintenant) {
  if (sAdhesion.adhesions() != sAdhesionsVues) {
    sAdhesionsVues = sAdhesion.adhesions();
    sVoyant.adherer(maintenant);
  }
  sVoyant.chercher(sAdhesion.cherche(), maintenant);
  sVoyant.suspendre(sSuspendue, maintenant);
  const Voyant::Teinte t = sVoyant.teinte(maintenant);
  const uint8_t m = (uint8_t)(kVoyantMax * t.niveau / 255);
  switch (t.couleur) {
    case Voyant::kBlanche: ecrireVoyant(m, m, m); break;
    case Voyant::kBleue: ecrireVoyant(0, 0, m); break;
    case Voyant::kVerte: ecrireVoyant(0, m, 0); break;
    case Voyant::kOrange: ecrireVoyant(m, m / 4, 0); break;
    case Voyant::kVeille: ecrireVoyant(2, 2, 2); break;
    default: ecrireVoyant(0, 0, 0); break;
  }
}

// ---------------------------------------------------------------------------
//  setup et loop
// ---------------------------------------------------------------------------

static char sCommande[256];
static size_t sCmdLong = 0;
static bool sCmdTropLongue = false;  // plus de 255 caracteres : refusee en entier

void setup() {
  Serial.begin(115200);
  // Aucun journal de la pile ni d'Arduino : sur le meme USB, il couperait les
  // lignes machine (les signaux arrivent en lignes « signal »).
  esp_log_level_set("*", ESP_LOG_NONE);
  // LED au noir d'abord : une WS2812 garde sa couleur a travers un redemarrage.
  ecrireVoyant(0, 0, 0);
  sPreferences.begin("sonde", false);
  const String nom = sPreferences.getString(kCleNom, kNomDefaut);
  if (nomValide(nom.c_str())) snprintf(sNom, sizeof(sNom), "%s", nom.c_str());
  sSuspendue = sPreferences.getBool(kCleSuspendue, false);
  zigbee::demarrer();
  // La pile demarre dans sa tache : jusqu'a 2 s pour lire l'adresse longue
  // avant le bonjour du demarrage (sinon "ieee":null, et le suivant l'aura).
  for (int i = 0; i < 200 && !zigbee::prete(); i++) delay(10);
  lireIeee(200);
  cmdBonjour();
}

void loop() {
  while (Serial.available()) {
    const int o = Serial.read();
    if (o == '\n' || o == '\r') {
      sCommande[sCmdLong] = 0;
      if (sCmdTropLongue) repondreErreur("syntaxe");
      else if (sCmdLong) executer(sCommande, millis());
      sCmdLong = 0;
      sCmdTropLongue = false;
    } else if (o >= 0x20 && o < 0x7F) {
      if (sCmdLong < sizeof(sCommande) - 1) sCommande[sCmdLong++] = (char)o;
      else sCmdTropLongue = true;
    }
  }
  // L'heure relue a chaque etape : une commande ou une action d'adhesion peut
  // prendre jusqu'a 1 s.
  evenements(millis());
  progresser(millis());
  voyantTour(millis());
  delay(5);
}
```

`sonde/platformio.ini` :

```ini
; Sonde de maillage Zigbee, firmware 0.9.0 (spec :
; docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md).
; ESP32-C6 SuperMini (flash de 4 Mo), membre du reseau Hue, lignes JSON sur
; l'USB. Chaine calee sur la sonde Thread : pioarduino 55.03.312-1
; (Arduino-ESP32 3.3.12, ESP-IDF 5.5.5, esp-zigbee-lib 1.6.8,
; esp-zboss-lib 1.6.4).
;
; Quatre variantes, tranchees a l'essai (spec, section 4) :
;   sonde                   appareil final, On/Off Light (0x0100) : E1
;   sonde_variable          appareil final, Dimmable Light (0x0101)
;   sonde_routeur           routeur, On/Off Light : repli E1 bis
;   sonde_routeur_variable  routeur, Dimmable Light
; Toutes avec la table de partitions zigbee_zczr.csv (zb_storage et zb_fct
; aux memes adresses : passer de l'une a l'autre demande un effacement).
; Deux variantes de verification, a cle factice (SONDE_CLE_FACTICE), pour
; compiler sans la vraie cle ; outils/flasher.py ne les flashe jamais :
;   verif                   appareil final, On/Off Light
;   verif_routeur           routeur, Dimmable Light
;
; Flasher : python3 outils/flasher.py (verifie la carte avant d'ecrire, voir
; sonde/README.md). Jamais un pio run -t upload a la main.

[platformio]
default_envs = sonde

[env]
platform = https://github.com/pioarduino/platform-espressif32/releases/download/55.03.312-1/platform-espressif32.zip
framework = arduino
; Pas de definition PlatformIO pour la SuperMini : la DevKitC-1 (meme puce),
; flash de 4 Mo.
board = esp32-c6-devkitc-1
board_build.flash_size = 4MB
board_upload.flash_size = 4MB
board_build.partitions = zigbee_zczr.csv
; app0 de zigbee_zczr.csv : 0x140000 octets.
board_upload.maximum_size = 1310720
monitor_speed = 115200
; La bibliotheque Zigbee d'Arduino envoie des Match_Desc_req d'elle-meme et
; definit son propre esp_zb_app_signal_handler : jamais liee ici.
lib_ignore = Zigbee
; sonde/test : tests hote (sh sonde/test/lancer.sh), pas des tests pio.
test_ignore = *
build_flags =
    ; Aucun journal sur l'USB : il couperait les lignes machine.
    -DCORE_DEBUG_LEVEL=0
    ; USB Serial/JTAG materiel pour Serial.
    -DARDUINO_USB_MODE=1
    -DARDUINO_USB_CDC_ON_BOOT=1
    ; sonde/cle_hue.local.h (cle de liaison Hue, jamais dans le depot).
    -I$PROJECT_DIR
    ; Commandes de l'essai E4 (routes) et E5 (echecs), et lignes « signal » :
    ; 1 pendant l'essai, decidees ensuite (sonde/src/options.h).
    -DSONDE_ROUTES=1
    -DSONDE_ECHECS=1
    -DSONDE_SIGNAUX=1

[env:sonde]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ED

[env:sonde_variable]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ED -DSONDE_LAMPE_VARIABLE=1

[env:sonde_routeur]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ZCZR

[env:sonde_routeur_variable]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ZCZR -DSONDE_LAMPE_VARIABLE=1

[env:verif]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ED -DSONDE_CLE_FACTICE=1

[env:verif_routeur]
build_flags = ${env.build_flags} -DZIGBEE_MODE_ZCZR -DSONDE_LAMPE_VARIABLE=1 -DSONDE_CLE_FACTICE=1
```

`sonde/cle_hue.exemple.h` :

```cpp
#pragma once
// Modele de sonde/cle_hue.local.h (spec de la sonde, section 1).
//
// Copier ce fichier en sonde/cle_hue.local.h (ignore par git, jamais
// commite) et remplacer les zeros par les 16 octets de la cle de liaison du
// centre de confiance des ponts Hue (cle ZLL de Signify). C'est Majid qui la
// pose : aucun agent ne l'ecrit ni ne la cherche. Tant que la cle est a
// zero, la compilation s'arrete (static_assert de sonde/src/zigbee.cpp).
#include <stdint.h>

static constexpr uint8_t kCleHue[16] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
```

`sonde/README.md` :

````markdown
# Sonde de maillage Zigbee (firmware)

Un ESP32-C6 SuperMini (flash de 4 Mo), branché au Mac en USB. La sonde
entre dans le réseau Hue comme **appareil final non endormi** : elle reçoit
en permanence, ne relaie rien, et n'envoie aucune commande aux lampes. Sur
demande, elle donne la table complète des voisins de n'importe quel routeur
(`Mgmt_Lqi_req`, page par page) et sa propre table de voisins. C'est l'app
qui orchestre la tournée et décode.

Spec : `docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md`.

## Avant de compiler : la clé de liaison Hue

Le pont Hue n'accepte un appareil que s'il connaît la clé de liaison de son
centre de confiance (clé ZLL de Signify). Elle n'entre jamais dans le dépôt :

```sh
cp sonde/cle_hue.exemple.h sonde/cle_hue.local.h
```

puis remplacer les zéros de `sonde/cle_hue.local.h` par les 16 octets de la
clé. C'est Majid qui la pose. Sans ce fichier, ou avec une clé à zéro, la
compilation s'arrête avec un message clair.

## Compiler

Chaîne calée sur la sonde Thread : pioarduino `55.03.312-1` (Arduino-ESP32
3.3.12, ESP-IDF 5.5.5, esp-zigbee-lib 1.6.8, esp-zboss-lib 1.6.4).

```sh
cd sonde
pio run                     # variante par defaut : sonde
pio run -e sonde_routeur    # une autre variante
```

`~/.platformio/penv/bin/pio` si `pio` n'est pas dans le `PATH`.

| Variante | Rôle | Point d'accès | Quand |
|---|---|---|---|
| `sonde` | appareil final | On/Off Light (`0x0100`) | essai E1 |
| `sonde_variable` | appareil final | Dimmable Light (`0x0101`) | si le pont exige une lampe variable |
| `sonde_routeur` | routeur, sans enfant | On/Off Light | repli E1 bis |
| `sonde_routeur_variable` | routeur, sans enfant | Dimmable Light | repli E1 bis |

Les commandes `routes` (E4) et `echecs` (E5), et les lignes `signal` (chaque
signal de la pile, pour comprendre l'essai), dépendent de `SONDE_ROUTES`,
`SONDE_ECHECS` et `SONDE_SIGNAUX` dans `platformio.ini` : à 1 pendant
l'essai, puis gardées ou retirées.

Deux variantes de vérification, `verif` (appareil final, On/Off) et
`verif_routeur` (routeur, lampe variable), compilent avec une clé factice :
c'est ainsi qu'on vérifie le code sans la vraie clé. Elles ne rejoindraient
aucun pont, et l'outil de flash refuse de les écrire.

```sh
cd sonde
pio run -e verif -e verif_routeur
```

## Flasher

**Toujours par l'outil, jamais par un `pio run -t upload` à la main** : le
pont Halo, la sonde Thread et la carte témoin de benq sont aussi des C6, et
le nom d'un port suit la prise USB, pas la carte. `outils/sonde.local.json`
(ignoré par git) désigne la carte :

```json
{"port": "/dev/cu.usbmodemXXXX", "mac": "AA:BB:CC:DD:EE:FF"}
```

```sh
python3 outils/flasher.py --effacer          # premier flash, ou changement de variante
python3 outils/flasher.py                    # mise a jour : le reseau est garde
python3 outils/flasher.py --env sonde_routeur --effacer
```

Avant d'écrire, l'outil vérifie la carte deux fois. D'abord le numéro de
série USB de l'appareil branché sur le port, lu par `ioreg`, sans toucher la
carte : pour un C6, c'est sa MAC. Puis, après la compilation et juste avant
d'écrire, la MAC lue par esptool. Si l'une des deux n'est pas celle du
fichier, il refuse et n'écrit rien. Pour trouver la MAC d'un C6 :
`ioreg -p IOUSB -l | grep "USB Serial Number"`.

## Entrer dans le réseau Hue

1. Flasher avec effacement : la LED pulse en bleu, la sonde cherche un
   réseau toutes les 30 s.
2. Dans l'app Hue : « Ajouter des lampes ». La sonde rejoint le pont : deux
   éclairs verts.
3. Dans l'app Hue, la nommer « Sonde maillage » et la laisser hors de toute
   pièce.

La lampe Hue ne pilote que la LED (on/off, identification) ; elle ne suspend
jamais la sonde. Pour la retirer : la supprimer dans l'app Hue, ou envoyer
`oubli` par l'USB.

## LED

Par ordre de priorité : identification demandée par l'app Hue (blanc, 500 ms
sur 500 ms) ; recherche ou rattachement (pulsation bleue) ; adhésion (deux
éclairs verts) ; suspendue (bref éclair orange toutes les 5 s) ; sinon la
lampe Hue (blanc très faible si elle est allumée).

## Parler à la sonde

`outils/essai_sonde.py` (voir son en-tête) : `bonjour`, `etat`, `voisins`,
`table <cible>`, `tournee`, `nuit`... Tout ce qui passe va dans `essais/`
(ignoré par git), lignes `signal` comprises.

Le délai par page va de 500 à 5000 ms : la pile Zigbee borne elle-même une
requête ZDO à 5 s. Une cible est toujours une adresse d'appareil, jamais une
adresse de diffusion (`FFF8` à `FFFF`).

## Tests hôte

```sh
sh sonde/test/lancer.sh
```

Les modules purs de `sonde/src` (commandes, lignes, entrées, pagination,
cadence et liste blanche, adhésion, LED) sont compilés par clang++ avec ASan
et UBSan et testés sur le Mac. `sh outils/tester.sh` lance tout.
````

- [ ] **Step 2 : compiler sans la vraie clé.**

Run : `cd sonde && ~/.platformio/penv/bin/pio run -e verif -e verif_routeur`

Expected, en fin de sortie :

```text
RAM:   [=         ]  14.4% (used 47044 bytes from 327680 bytes)
Flash: [=====     ]  53.8% (used 704852 bytes from 1310720 bytes)
Building .pio/build/verif_routeur/firmware.bin
========================= [SUCCESS] Took 11.88 seconds =========================
Environment    Status    Duration
-------------  --------  ------------
verif          SUCCESS   00:00:12.844
verif_routeur  SUCCESS   00:00:11.877
```

- [ ] **Step 3 : les garde-fous de la clé arrêtent bien une vraie variante.**

Sans `sonde/cle_hue.local.h` (c'est le cas dans un worktree, et l'agent n'en crée jamais) :

Run : `cd sonde && ~/.platformio/penv/bin/pio run -e sonde 2>&1 | grep "error:" | head -1`

Expected :

```text
src/zigbee.cpp:32:2: error: #error "sonde/cle_hue.local.h absent : copier sonde/cle_hue.exemple.h et y mettre la cle de liaison Hue (sonde/README.md)"
```

Si `sonde/cle_hue.local.h` existe (Majid l'a déjà posé dans le dépôt principal), sauter cette vérification : ne jamais le déplacer ni le lire.

- [ ] **Step 4 : tout le reste passe toujours.**

Run : `sh outils/tester.sh`

Expected : sans échec, garde comprise. `sonde/.pio/` est ignoré par git.

- [ ] **Step 5 : commit.**

```bash
git add sonde/src/version.h sonde/src/zigbee.h sonde/src/zigbee.cpp sonde/src/main.cpp sonde/platformio.ini sonde/cle_hue.exemple.h sonde/README.md
git commit -m "Ecrire le firmware 0.9.0 de la sonde : colle Zigbee, boucle principale, variantes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Outils Python : liaison USB, essai, flash vérifié

**Files:**
- Create: `outils/sonde_usb.py`, `outils/essai_sonde.py`, `outils/flasher.py`, `outils/test/test_sonde_usb.py`, `outils/test/test_essai_sonde.py`, `outils/test/test_flasher.py`

**Interfaces:**
- Consumes : le protocole de la tâche 6 (types `bonjour`, `etat`, `voisins`, `table`, `routes`, `echecs`, `oubli`, `erreur` ; listes avec `suite`).
- Produces (utilisés à la tâche 8 par le contrôleur, jamais par un agent) :
  - `sonde_usb.ouvrir(chemin)`, `couper(tampon)`, `fusionner(lignes)`, `PortPerdu`, `class Sonde(fd, journal, horloge)` : `envoyer`, `lire(jusqua)`, `vider()`, `commande(texte, types, id, delai)` (écarte d'abord ce qui traîne), `verifier()` ;
  - `python3 outils/essai_sonde.py [--port P] <commande>`, avec ses fonctions pures `parcourir(table, depart)`, `complete(m)` et `resumer(resultats, duree_s)`. Une table incomplète est redemandée une fois, et la nuit se reconnecte si le port est perdu ;
  - `python3 outils/flasher.py [--env V] [--effacer] [--ecoute]`, avec ses fonctions `normaliser_mac`, `mac_lue`, `ports_par_serie` et `flasher(port, mac, env, effacer, lancer, dossier)`. L'ordre : numéro de série USB (ioreg, sans toucher la carte), compilation, MAC lue par esptool, effacement si demandé, téléversement sans recompiler.

- [ ] **Step 1 : écrire les tests.**

`outils/test/test_sonde_usb.py` :

```python
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
```

`outils/test/test_essai_sonde.py` :

```python
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
```

`outils/test/test_flasher.py` :

```python
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
```

- [ ] **Step 2 : les lancer, ils échouent.**

Run : `python3 -m unittest discover -s outils/test`

Expected, en fin de sortie :

```text
----------------------------------------------------------------------
Ran 10 tests in 0.357s
FAILED (errors=3)
```

- [ ] **Step 3 : écrire les outils.**

`outils/sonde_usb.py` :

```python
"""Liaison USB avec la sonde Zigbee (spec de la sonde, section 2).

Ouverture sure du C6 (comme la sonde Thread et le pont Halo) : TIOCEXCL, DTR = RTS = 0 en un seul TIOCMSET
(RTS = 1 avec DTR = 0 redemarre le C6), termios brut sans HUPCL.

Lignes machine : RS (0x1E), JSON compact, fin de ligne. La ligne machine commence au dernier RS de la
ligne ; ce qui le precede (journal de la carte) est rendu a part, comme une ligne sans RS ou illisible.

Aucun appel a un port serie dans ce module tant qu'on n'appelle pas ouvrir() : les tests lui donnent une
paire de sockets locale.
"""
import fcntl
import json
import os
import select
import struct
import termios
import time

RS = b"\x1e"
PRODUIT = "sonde-zigbee"


class PortPerdu(Exception):
    """Le port ne repond plus : carte debranchee, ou USB re-enumere."""


def ouvrir(chemin):
    fd = os.open(chemin, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    fcntl.ioctl(fd, termios.TIOCEXCL)
    fcntl.ioctl(fd, termios.TIOCMSET, struct.pack("I", 0))
    i, o, c, l, _, _, cc = termios.tcgetattr(fd)
    i &= ~(termios.IGNBRK | termios.BRKINT | termios.PARMRK | termios.ISTRIP | termios.INLCR | termios.IGNCR
           | termios.ICRNL | termios.IXON)
    o &= ~termios.OPOST
    l &= ~(termios.ECHO | termios.ECHONL | termios.ICANON | termios.ISIG | termios.IEXTEN)
    c &= ~(termios.CSIZE | termios.PARENB | termios.HUPCL)
    c |= termios.CS8 | termios.CLOCAL | termios.CREAD
    termios.tcsetattr(fd, termios.TCSANOW, [i, o, c, l, termios.B115200, termios.B115200, cc])
    return fd


def couper(tampon):
    """Coupe le tampon en lignes completes. Rend (elements, reste) ; chaque element est un dict (message
    decode) ou un str (texte hors ligne machine : journal, ligne sans RS, ligne machine illisible)."""
    elements = []
    while b"\n" in tampon:
        brut, tampon = tampon.split(b"\n", 1)
        brut = brut.rstrip(b"\r")
        i = brut.rfind(RS)
        avant = brut if i < 0 else brut[:i]
        if avant.strip():
            elements.append(avant.decode("ascii", "replace"))
        if i < 0:
            continue
        try:
            m = json.loads(brut[i + 1:].decode("ascii"))
        except (ValueError, UnicodeDecodeError):
            m = None
        if isinstance(m, dict):
            elements.append(m)
        else:
            elements.append(brut[i + 1:].decode("ascii", "replace"))
    return elements, tampon


def fusionner(lignes):
    """Une reponse en plusieurs lignes ("suite":true sauf la derniere) devient un seul message : l'en-tete de
    la premiere ligne, toutes les listes mises bout a bout, sans "suite"."""
    if not lignes:
        return None
    m = {k: v for k, v in lignes[0].items() if k != "suite"}
    if "liste" in m:
        m["liste"] = [e for l in lignes for e in l.get("liste", [])]
    return m


class Sonde:
    """Une sonde au bout d'un descripteur (port serie ou socket de test). journal(sens, element) recoit tout ce
    qui passe : ("envoi", texte) et ("recu", dict ou str)."""

    def __init__(self, fd, journal=None, horloge=time.time):
        self.fd, self.journal, self.horloge, self.tampon = fd, journal, horloge, b""
        self.attente = []  # elements decodes pas encore rendus (une lecture peut en porter plusieurs)

    def _noter(self, sens, element):
        if self.journal:
            self.journal(sens, element)

    def envoyer(self, texte):
        self._noter("envoi", texte)
        os.write(self.fd, (texte + "\n").encode("ascii"))

    def _recevoir(self, attente_s):
        """Une lecture, attente_s secondes au plus. True si des octets sont arrives ; PortPerdu si le port ne
        repond plus (erreur, ou fin de flux apres un select qui dit « lisible »)."""
        r, _, _ = select.select([self.fd], [], [], attente_s)
        if not r:
            return False
        try:
            morceau = os.read(self.fd, 4096)
        except BlockingIOError:
            return False
        except OSError as e:
            raise PortPerdu(str(e)) from e
        if not morceau:
            raise PortPerdu("fin de flux")
        self.tampon += morceau
        elements, self.tampon = couper(self.tampon)
        for e in elements:
            self._noter("recu", e)
        self.attente.extend(elements)
        return True

    def lire(self, jusqua):
        """Elements recus jusqu'a l'echeance (horloge). Ceux qu'on n'a pas pris restent pour la lecture
        suivante."""
        while True:
            while self.attente:
                yield self.attente.pop(0)
            reste = jusqua - self.horloge()
            if reste <= 0:
                return
            self._recevoir(min(reste, 0.1))

    def vider(self):
        """Ecarte ce qui est deja arrive (c'est note dans le journal) : une reponse en retard a une commande
        precedente ne sera pas prise pour celle qui part."""
        while self._recevoir(0):
            pass
        self.attente.clear()

    def commande(self, texte, types, id=None, delai=10.0):
        """Envoie une commande et rend sa reponse fusionnee (fusionner), ou None au bout du delai. Reponse :
        un message dont le type est dans types (et, si id est donne, de meme id), jusqu'a "suite":false ; ou
        une erreur generale ("t":"erreur", sans id), qui repond a toute commande."""
        self.vider()
        self.envoyer(texte)
        lignes = []
        for e in self.lire(self.horloge() + delai):
            if not isinstance(e, dict):
                continue
            if e.get("t") == "erreur" and "id" not in e:
                return e
            if e.get("t") not in types or (id is not None and e.get("id") != id):
                continue
            lignes.append(e)
            if not e.get("suite"):
                return fusionner(lignes)
        return None

    def verifier(self, delai=3.0):
        """bonjour : rend le message si c'est bien une sonde Zigbee, sinon leve ValueError."""
        m = self.commande("bonjour", ("bonjour",), delai=delai)
        if not m or m.get("produit") != PRODUIT:
            raise ValueError(f"pas de sonde Zigbee sur ce port (bonjour : {m!r})")
        return m
```

`outils/essai_sonde.py` :

```python
#!/usr/bin/env python3
"""Essai de la sonde Zigbee par l'USB (spec de la sonde, section 4).

  python3 outils/essai_sonde.py [--port P] <commande> [<argument> ...]

Commandes :
  bonjour | etat | voisins | suspendre | reprendre | oubli
  nom <texte>
  table <cible> [<delai ms>]      table des voisins d'un routeur (E2)
  routes <cible> [<delai ms>]     table de routage (E4)
  echecs <cible> [<delai ms>]     emissions et echecs (E5 : seulement avec l'accord de Majid)
  tournee [<delai ms>]            parcours en largeur depuis le pont (E3)
  nuit <heures> [<periode s>]     etat et tournee toutes les <periode> s, 900 par defaut (E6)
  ecoute <secondes>               lit sans rien envoyer

Port : --port, sinon "port" de outils/sonde.local.json (ignore par git). Avant toute commande sauf ecoute,
l'outil verifie par bonjour que c'est une sonde Zigbee. Aucun agent ne lance cet outil : il ouvre un port
serie (plan, contraintes globales).

Journal : tout ce qui passe va dans essais/<AAAA-MM-JJ>/sonde.jsonl, et le resume de chaque tournee dans
essais/<AAAA-MM-JJ>/tournee-<HHMMSS>.json. essais/ est ignore par git : identifiants reels.
"""
import collections
import json
import os
import sys
import time

ICI = os.path.dirname(os.path.abspath(__file__))
DEPOT = os.path.normpath(os.path.join(ICI, ".."))
sys.path.insert(0, ICI)
import sonde_usb  # noqa: E402

ATTENTE_TABLE_S = 125  # la sonde borne une table a 120 s
TYPES_INTERROGES = ("coordinateur", "routeur")


def parcourir(table, depart="0000"):
    """Parcours en largeur des routeurs, depuis le pont. table(cible) rend la reponse fusionnee de la sonde
    (dict, ou None sans reponse). Rend {cible: reponse} dans l'ordre du parcours. Seuls le coordinateur et
    les routeurs sont interroges ; les appareils finaux ne repondent pas a Mgmt_Lqi_req."""
    resultats = {}
    a_voir = collections.deque([depart])
    prevus = {depart}
    while a_voir:
        cible = a_voir.popleft()
        reponse = table(cible)
        resultats[cible] = reponse
        if not reponse or not reponse.get("ok"):
            continue
        for e in reponse.get("liste", []):
            court = e.get("court")
            if e.get("type") in TYPES_INTERROGES and court and court not in prevus:
                prevus.add(court)
                a_voir.append(court)
    return resultats


def complete(m):
    """Une table reussie et non partielle porte exactement total entrees ; sinon une ligne s'est perdue en
    route (journal de la carte au milieu, par exemple)."""
    return not m or not m.get("ok") or m.get("partielle") or "total" not in m or len(m.get("liste", [])) == m["total"]


def resumer(resultats, duree_s):
    """Resume d'une tournee : routeurs interroges, reponses, erreurs, pages, noeuds vus."""
    erreurs = collections.Counter()
    pages = 0
    noeuds, finaux, liens = set(), set(), 0
    for cible, r in resultats.items():
        if not r:
            erreurs["sans_reponse"] += 1
            continue
        if not r.get("ok"):
            erreurs[r.get("erreur", "?")] += 1
            continue
        pages += r.get("pages", 0)
        for e in r.get("liste", []):
            liens += 1
            noeuds.add(e.get("ieee"))
            if e.get("type") == "final":
                finaux.add(e.get("ieee"))
    return {
        "interroges": len(resultats),
        "reponses": sum(1 for r in resultats.values() if r and r.get("ok")),
        "partielles": sum(1 for r in resultats.values() if r and r.get("ok") and r.get("partielle")),
        "incoherentes": sum(1 for r in resultats.values() if r and r.get("incoherente")),
        "erreurs": dict(erreurs),
        "pages": pages,
        "noeuds_vus": len(noeuds),
        "finaux_vus": len(finaux),
        "entrees": liens,
        "duree_s": round(duree_s, 1),
    }


def config_locale():
    chemin = os.path.join(ICI, "sonde.local.json")
    if not os.path.exists(chemin):
        return {}
    with open(chemin) as f:
        return json.load(f)


def dossier_du_jour(maintenant=None):
    jour = time.strftime("%Y-%m-%d", time.localtime(maintenant))
    d = os.path.join(DEPOT, "essais", jour)
    os.makedirs(d, exist_ok=True)
    return d


def journal_vers(chemin):
    def noter(sens, element):
        with open(chemin, "a") as f:
            f.write(json.dumps({"t": round(time.time(), 3), "sens": sens, "element": element}) + "\n")
    return noter


def afficher(m):
    if m is None:
        print("(pas de reponse)")
        return
    entete = {k: v for k, v in m.items() if k != "liste"}
    print(json.dumps(entete, ensure_ascii=False))
    for e in m.get("liste", []):
        print("   ", json.dumps(e, ensure_ascii=False))


class Essai:
    def __init__(self, sonde):
        self.sonde = sonde
        self.id = int(time.time()) % 1000000

    def prochain_id(self):
        self.id += 1
        return self.id

    def requete(self, genre, cible, delai_ms=None):
        """Une table incomplete sans « partielle » est redemandee une fois, puis rendue marquee incoherente."""
        for _ in range(2):
            i = self.prochain_id()
            texte = f"{genre} {cible} {i}" + (f" {delai_ms}" if delai_ms else "")
            m = self.sonde.commande(texte, (genre,), id=i, delai=ATTENTE_TABLE_S)
            if complete(m):
                return m
            m["incoherente"] = True
        return m

    def tournee(self, delai_ms=None):
        debut = time.time()
        resultats = parcourir(lambda c: self.requete("table", c, delai_ms))
        resume = resumer(resultats, time.time() - debut)
        chemin = os.path.join(dossier_du_jour(), time.strftime("tournee-%H%M%S.json"))
        with open(chemin, "w") as f:
            json.dump({"resume": resume, "tables": resultats}, f, indent=1)
        return resume, chemin


def main(argv):
    port = None
    if len(argv) >= 2 and argv[0] == "--port":
        port, argv = argv[1], argv[2:]
    if not argv:
        print(__doc__)
        return 2
    port = port or config_locale().get("port")
    if not port:
        print("Port inconnu : --port, ou \"port\" dans outils/sonde.local.json")
        return 2
    commande, args = argv[0], argv[1:]
    journal = os.path.join(dossier_du_jour(), "sonde.jsonl")
    sonde = sonde_usb.Sonde(sonde_usb.ouvrir(port), journal_vers(journal))

    def reconnecter():
        try:
            os.close(essai.sonde.fd)
        except OSError:
            pass
        essai.sonde = sonde_usb.Sonde(sonde_usb.ouvrir(port), journal_vers(journal))
        essai.sonde.verifier()

    if commande == "ecoute":
        for e in sonde.lire(time.time() + float(args[0] if args else 10)):
            afficher(e) if isinstance(e, dict) else print("   |", e[:160])
        return 0
    try:
        sonde.verifier()
    except ValueError as e:
        print(e)
        return 1
    essai = Essai(sonde)
    simples = {"bonjour": ("bonjour",), "etat": ("etat",), "voisins": ("voisins",), "suspendre": ("etat",),
               "reprendre": ("etat",), "oubli": ("oubli",)}
    if commande in simples and not args:
        afficher(sonde.commande(commande, simples[commande]))
    elif commande == "nom" and len(args) == 1:
        afficher(sonde.commande(f"nom {args[0]}", ("bonjour",)))
    elif commande in ("table", "routes", "echecs") and 1 <= len(args) <= 2:
        afficher(essai.requete(commande, args[0], args[1] if len(args) == 2 else None))
    elif commande == "tournee" and len(args) <= 1:
        resume, chemin = essai.tournee(args[0] if args else None)
        print(json.dumps(resume, ensure_ascii=False), "->", chemin)
    elif commande == "nuit" and 1 <= len(args) <= 2:
        fin = time.time() + float(args[0]) * 3600
        periode = float(args[1]) if len(args) == 2 else 900.0
        while time.time() < fin:
            debut = time.time()
            try:
                etat = essai.sonde.commande("etat", ("etat",))
                print(time.strftime("%H:%M:%S"), "membre" if etat and etat.get("membre") else "NON MEMBRE",
                      (etat or {}).get("parent"))
                resume, chemin = essai.tournee()
                print(time.strftime("%H:%M:%S"), json.dumps(resume, ensure_ascii=False), "->", chemin, flush=True)
            except sonde_usb.PortPerdu as e:
                print(time.strftime("%H:%M:%S"), "PORT PERDU :", e, flush=True)
                time.sleep(10)
                try:
                    reconnecter()
                except (OSError, ValueError, sonde_usb.PortPerdu) as e2:
                    print(time.strftime("%H:%M:%S"), "reconnexion impossible :", e2, flush=True)
                continue
            time.sleep(max(0.0, periode - (time.time() - debut)))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

`outils/flasher.py` :

```python
#!/usr/bin/env python3
"""Flash de la sonde Zigbee, seulement sur la bonne carte (spec de la sonde, section 5).

  python3 outils/flasher.py [--env sonde] [--effacer]
  python3 outils/flasher.py --ecoute [--effacer]      firmware d'ecoute passive (outils/ecoute/firmware)

Lit outils/sonde.local.json (ignore par git) : {"port": "/dev/cu.usbmodem...", "mac": "AA:BB:CC:DD:EE:FF"}.
Le pont Halo, la sonde Thread et la carte temoin de benq sont aussi des C6, et le nom d'un port suit la prise
USB, pas la carte. Avant d'ecrire, dans cet ordre :
  1. le numero de serie USB de l'appareil derriere le port (ioreg, sans toucher la carte) : c'est la MAC
     d'un C6, elle doit etre celle du fichier ;
  2. la compilation (pio run) ;
  3. juste avant d'ecrire, la MAC lue par esptool (qui redemarre la carte, desormais la bonne) ;
  4. l'effacement si --effacer, puis le televersement sans recompiler (-t nobuild).
Autre carte a l'une des etapes 1 ou 3 : refus, rien n'est ecrit.

--effacer : effacement complet d'abord (premier flash, ou passage d'une variante a l'autre).
--env : variante de sonde/platformio.ini (sonde, sonde_variable, sonde_routeur, sonde_routeur_variable) ;
les variantes de verification (verif, verif_routeur, a cle factice) ne se flashent jamais.
Aucun agent ne lance cet outil : seul le controleur, avec Majid (plan, contraintes globales).
"""
import json
import os
import re
import subprocess
import sys

ICI = os.path.dirname(os.path.abspath(__file__))
DEPOT = os.path.normpath(os.path.join(ICI, ".."))
PENV = os.path.expanduser("~/.platformio/penv/bin")
VARIANTES = ("sonde", "sonde_variable", "sonde_routeur", "sonde_routeur_variable")


def normaliser_mac(texte):
    """12 hexa majuscules, sans separateurs ; None si ce n'est pas une MAC de 6 octets."""
    h = re.sub(r"[^0-9A-Fa-f]", "", texte or "").upper()
    return h if len(h) == 12 else None


def mac_lue(sortie):
    """MAC de base (6 octets) dans la sortie d'esptool read-mac : ligne « BASE MAC: » (esptool 5), sinon
    ligne « MAC: » de 6 octets (esptool 4). None si absente."""
    for motif in (r"^\s*BASE MAC:\s*([0-9A-Fa-f:]+)\s*$", r"^\s*MAC:\s*([0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5})\s*$"):
        m = re.search(motif, sortie, re.MULTILINE)
        if m:
            return normaliser_mac(m.group(1))
    return None


def ports_par_serie(texte):
    """{port /dev/cu.* : numero de serie USB de l'appareil qui le porte}, d'apres l'arbre d'ioreg : chaque
    port (IOCalloutDevice) va au plus proche ancetre qui a un « USB Serial Number »."""
    pile, resultat = [], {}  # pile : (colonne du « +-o », proprietes du noeud)
    for ligne in texte.splitlines():
        i = ligne.find("+-o ")
        if i >= 0:
            while pile and pile[-1][0] >= i:
                pile.pop()
            pile.append((i, {}))
            continue
        m = re.search(r'"([^"]+)" = "([^"]*)"', ligne)
        if m and pile:
            pile[-1][1][m.group(1)] = m.group(2)
            if m.group(1) == "IOCalloutDevice":
                resultat[m.group(2)] = next(
                    (p["USB Serial Number"] for _, p in reversed(pile) if "USB Serial Number" in p), None)
    return resultat


def outil(nom):
    chemin = os.path.join(PENV, nom)
    return chemin if os.path.exists(chemin) else nom


def lancer(commande):
    return subprocess.run(commande, capture_output=True, text=True)


def flasher(port, mac_attendue, env, effacer, lancer=lancer, dossier=os.path.join(DEPOT, "sonde")):
    """Rend 0 si le flash a reussi, 1 s'il a echoue, 2 si la carte est refusee."""
    attendue = normaliser_mac(mac_attendue)
    if not attendue:
        print(f"MAC attendue illisible : {mac_attendue!r}")
        return 2
    r = lancer(["ioreg", "-p", "IOService", "-l", "-w0", "-r", "-c", "IOUSBHostDevice"])
    serie = normaliser_mac(ports_par_serie(r.stdout).get(port))
    if serie != attendue:
        print(f"REFUS : l'appareil USB de {port} a le numero de serie {serie}, attendu {attendue}. "
              "Rien n'est ecrit, la carte n'a pas ete touchee.")
        return 2
    pio = [outil("pio"), "run", "-d", dossier, "-e", env]
    r = lancer(pio)
    if r.returncode != 0:
        sys.stdout.write(r.stdout[-2000:] + r.stderr[-2000:])
        print("ECHEC de la compilation : rien n'est ecrit.")
        return 1
    r = lancer([outil("python"), "-m", "esptool", "--port", port, "read-mac"])
    lue = mac_lue(r.stdout + r.stderr)
    if lue != attendue:
        print(f"REFUS : la carte de {port} a la MAC {lue}, attendue {attendue}. Rien n'est ecrit.")
        return 2
    print(f"Carte verifiee : {port}, MAC {lue}.")
    etapes = ([["-t", "erase"]] if effacer else []) + [["-t", "nobuild", "-t", "upload"]]
    for etape in etapes:
        r = lancer(pio + etape + ["--upload-port", port])
        sys.stdout.write(r.stdout[-2000:])
        if r.returncode != 0:
            sys.stdout.write(r.stderr[-2000:])
            print(f"ECHEC de « {' '.join(etape)} ».")
            return 1
    return 0


def main(argv):
    env, effacer, ecoute = "sonde", False, False
    i = 0
    while i < len(argv):
        if argv[i] == "--env" and i + 1 < len(argv):
            env, i = argv[i + 1], i + 2
        elif argv[i] == "--effacer":
            effacer, i = True, i + 1
        elif argv[i] == "--ecoute":
            ecoute, i = True, i + 1
        else:
            print(__doc__)
            return 2
    if ecoute:
        env, dossier = "ecoute", os.path.join(DEPOT, "outils", "ecoute", "firmware")
    elif env not in VARIANTES:
        print(f"Variante inconnue : {env} (permises : {', '.join(VARIANTES)})")
        return 2
    else:
        dossier = os.path.join(DEPOT, "sonde")
    chemin = os.path.join(ICI, "sonde.local.json")
    if not os.path.exists(chemin):
        print("outils/sonde.local.json absent : {\"port\": ..., \"mac\": ...} (sonde/README.md)")
        return 2
    with open(chemin) as f:
        config = json.load(f)
    return flasher(config.get("port"), config.get("mac"), env, effacer, dossier=dossier)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

- [ ] **Step 4 : les tests passent.**

Run : `python3 -m unittest discover -s outils/test`

Expected, en fin de sortie :

```text
----------------------------------------------------------------------
Ran 37 tests in 0.703s
OK
```

Puis `sh outils/tester.sh` : sans échec.

- [ ] **Step 5 : commit.**

```bash
git add outils/sonde_usb.py outils/essai_sonde.py outils/flasher.py outils/test/test_sonde_usb.py outils/test/test_essai_sonde.py outils/test/test_flasher.py
git commit -m "Ecrire les outils de la sonde : liaison USB, essai, flash qui verifie la carte

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Essai sur la carte, avec Majid (par le contrôleur, pas par un sous-agent)

**Files:**
- Create (locaux, ignorés par git, jamais commités) : `outils/sonde.local.json` (contrôleur), `sonde/cle_hue.local.h` (Majid), `essais/` (outils)
- Modify: `docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md` (section 8, valeurs inventées)

**Interfaces:**
- Consumes : tout ce qui précède ; la carte désignée par Majid (le C6 de l'essai d'écoute, dont la MAC est dans la mémoire du projet et dans `garde.local.txt`, jamais dans le dépôt).
- Produces : les décisions pour la tâche 9 :
  - la variante à garder (`sonde`, `sonde_variable`, `sonde_routeur` ou `sonde_routeur_variable`) ;
  - `SONDE_ROUTES` (E4) et `SONDE_ECHECS` (E5) : 1 ou 0 ;
  - les durées et volumes mesurés.

Le niveau d'effort conseillé pour cette tâche est **Élevé** (pilotage en direct avec Majid).

- [ ] **Step 1 : préparer la carte, avec Majid.**
  1. Majid copie `sonde/cle_hue.exemple.h` en `sonde/cle_hue.local.h` et y pose la clé. Le contrôleur ne la lit pas et ne l'affiche pas.
  2. Le contrôleur repère le port de la carte. `ioreg -p IOUSB -l | grep "USB Serial Number"` donne la MAC de chaque C6, et le port suit la prise USB. Il fait confirmer la carte par Majid, puis écrit `outils/sonde.local.json` : `{"port": "/dev/cu.usbmodem…", "mac": "…"}`.
  3. Run : `python3 outils/flasher.py --effacer`. Expected : `Carte verifiee : …`, puis l'effacement et le flash réussis. La LED pulse en bleu. Un `REFUS` veut dire que la carte n'est pas la bonne : ne pas insister, revoir le port avec Majid.
  4. Run : `python3 outils/essai_sonde.py bonjour`, puis `python3 outils/essai_sonde.py etat`. Expected :
     - `bonjour` : `"produit":"sonde-zigbee"`, `"version":"0.9.0"`, `"membre":false` ;
     - `etat` : `"recherche":true`.

- [ ] **Step 2 : E1, adhésion en appareil final.**
  1. Majid lance « Ajouter des lampes » dans l'app Hue.
  2. Le contrôleur relance `etat` toutes les 20 s, 5 minutes au plus. Expected : `"membre":true`, `"role":"final"`, un `parent`, `"canal":25`, et deux éclairs verts sur la LED.
     Le contrôleur vérifie aussi que le `pan` est celui du réseau Hue relevé pendant l'essai d'écoute (dans la mémoire du projet). Il compare sans écrire la valeur nulle part. Un autre PAN voudrait dire que la sonde a rejoint un réseau voisin ouvert : `oubli`, puis recommencer.
  3. Majid voit la lampe dans l'app Hue, la nomme « Sonde maillage » et la laisse hors de toute pièce. Il l'allume, l'éteint et l'identifie : seule la LED réagit.
  4. 30 minutes plus tard : `etat` donne toujours `"membre":true`.
  5. Majid débranche puis rebranche la carte. 1 minute plus tard : `etat` donne `"membre":true` sans nouvelle recherche dans l'app Hue.

  **Si E1 échoue** (jamais membre, ou un départ venu du pont), dans cet ordre, chaque fois avec `python3 outils/flasher.py --env <variante> --effacer` et une nouvelle recherche dans l'app Hue :
  1. `sonde_variable` (le pont exige peut-être une lampe variable) ;
  2. E1 bis : `sonde_routeur`, puis `sonde_routeur_variable`. Prévenir Majid d'abord : selon la norme BDB, un routeur qui vient d'adhérer peut ouvrir le réseau Hue 180 s (spec, section 3). La sonde n'accepte de toute façon aucun enfant.

  Si rien ne marche, s'arrêter et en reparler avec Majid (spec, section 4).

- [ ] **Step 3 : E2, tables du pont et de trois lampes.**
  1. Run : `python3 outils/essai_sonde.py table 0000`. Puis `table <court>` pour trois routeurs de la réponse, en choisissant le parent de la sonde et deux autres.
  2. Expected, pour chacune :
     - `"ok":true`, `"partielle":false`, et `len(liste) == total` ;
     - des LQI de 0 à 255 ;
     - les adresses longues au préfixe de Signify, **dans l'ordre de l'essai d'écoute**. Une adresse à l'envers trahirait un ordre d'octets inversé dans `texteIeee`.
  3. Noter la durée (`ms`) et le nombre de pages. Si le pont ne répond pas (`delai` ou `statut`), le noter : ses voisins se liront dans les tables des lampes.

- [ ] **Step 4 : E3, tournée complète.**

Run : `python3 outils/essai_sonde.py tournee`

Expected : un résumé, qui compare les `interroges` et les `noeuds_vus` au nombre de lampes de l'app Hue ; aucune erreur `cadence` ; et la durée totale. `etat` donne ensuite `"refus_cadence":0`.

- [ ] **Step 5 : E4, table de routage en trame APS brute.**

Run : `python3 outils/essai_sonde.py routes <court d'une lampe>`

Expected, deux cas :
- **E4 réussi :** une liste d'entrées lisibles (`destination`, `etat`, `prochain`) ;
- **E4 échoué :** `delai` (la pile ne transmet pas la réponse ZDO au rappel APS) ou `envoi` (la pile refuse l'envoi depuis le point d'accès 0). `SONDE_ROUTES` passera à 0 à la tâche 9.

- [ ] **Step 6 : E5, taux d'échec, seulement avec l'accord explicite de Majid.**
  1. Lui rappeler le prix : la lampe interrogée reste sourde environ 31 ms. Lui demander laquelle interroger.
  2. Run : `python3 outils/essai_sonde.py echecs <court>`.
  3. Expected : `"ok":true`, avec `emissions`, `echecs` et `energie` vraisemblables, et aucun effet visible sur la lampe (Majid regarde).
  4. Décider avec Majid si on garde `echecs` (`SONDE_ECHECS`).

  Sans son accord, ne pas lancer E5 : `SONDE_ECHECS` passe à 0.

- [ ] **Step 7 : E7, perte du parent (si Majid le veut).**
  1. Majid coupe à l'interrupteur la lampe qui est le parent de la sonde (`etat.parent`).
  2. Expected :
     - dans la minute, `etat` donne `"membre":false` et `"recherche":true`, et la LED pulse en bleu ;
     - puis, en moins de 2 minutes, `"membre":true` avec un autre parent.

     Si la sonde ne voit rien, la pile n'a peut-être signalé aucune perte : la noter.
  3. Majid rallume la lampe.
  4. Lire les lignes `signal` de ce moment dans `essais/<date>/sonde.jsonl`. Ce que la pile a émis, et dans quel ordre, ira dans la section 8.

- [ ] **Step 8 : E6, une nuit.**

Run, en tâche de fond : `python3 outils/essai_sonde.py nuit 10 900`

Expected au matin :
- une ligne `membre` et un résumé de tournée toutes les 15 minutes, sans `NON MEMBRE` ;
- des lampes normales pendant la nuit, et rien d'anormal dans l'app Hue (Majid regarde).

- [ ] **Step 9 : consigner les résultats.**

Dans la spec, remplacer :

```markdown
## 8. Résultats de l'essai

À remplir pendant l'exécution du plan (section 4), avec des valeurs
inventées.
```

par la section 8 remplie, **sans aucun identifiant réel**. Les adresses sont remplacées par des valeurs inventées ; on garde les comptes, les durées, les pages, les LQI typiques et les décisions. Elle couvre :
- E1, avec sa variante retenue ;
- E2 à E7, avec les signaux de la pile vus à E7 ;
- les volumes mesurés ;
- les décisions pour `SONDE_ROUTES`, `SONDE_ECHECS`, `SONDE_SIGNAUX` et la variante par défaut.

Run : `sh outils/tester.sh`. Expected : sans échec, garde comprise.

```bash
git add docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md
git commit -m "Noter dans la spec de la sonde les resultats de l'essai

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Sonde 1.0.0 : décisions de l'essai (par le contrôleur, avec Majid)

**Files:**
- Modify: `sonde/src/version.h`, `sonde/platformio.ini`, `sonde/README.md`, `docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md` (blocs ci-dessous)

**Interfaces:**
- Consumes : les décisions de la tâche 8.
- Produces : le firmware 1.0.0 sur la carte, base du morceau 2 (l'app).

- [ ] **Step 1 : la version.**

Dans `sonde/src/version.h`, remplacer :

```cpp
#define SONDE_VERSION "0.9.0"
```

par :

```cpp
#define SONDE_VERSION "1.0.0"
```

Dans `sonde/src/main.cpp`, remplacer :

```cpp
//  Sonde de maillage Zigbee, firmware 0.9.0 (spec :
```

par :

```cpp
//  Sonde de maillage Zigbee, firmware 1.0.0 (spec :
```

Dans `sonde/platformio.ini`, remplacer :

```ini
; Sonde de maillage Zigbee, firmware 0.9.0 (spec :
```

par :

```ini
; Sonde de maillage Zigbee, firmware 1.0.0 (spec :
```

- [ ] **Step 2 : les commandes de l'essai, selon E4 et E5, et les lignes `signal`.**

Pour chaque élément que l'essai ne garde pas, dans `sonde/platformio.ini` :
- E4 échoué : remplacer `    -DSONDE_ROUTES=1` par `    -DSONDE_ROUTES=0` ;
- E5 non retenu : remplacer `    -DSONDE_ECHECS=1` par `    -DSONDE_ECHECS=0` ;
- lignes `signal` jugées inutiles avec Majid : remplacer `    -DSONDE_SIGNAUX=1` par `    -DSONDE_SIGNAUX=0`. Les garder sert au journal de l'app (morceau 3).

Dans le même fichier, remplacer :

```ini
    ; Commandes de l'essai E4 (routes) et E5 (echecs), et lignes « signal » :
    ; 1 pendant l'essai, decidees ensuite (sonde/src/options.h).
```

par la décision, par exemple :

```ini
    ; Apres l'essai : routes retiree (E4 : la pile ne rend pas la reponse
    ; ZDO brute), echecs gardee (E5, accord de Majid du JJ/MM), lignes
    ; signal gardees.
```

Le code reste. `SONDE_ROUTES=0` et `SONDE_ECHECS=0` le retirent à la compilation, et `sonde/test/lancer.sh` teste déjà les deux cas.

- [ ] **Step 3 : la variante par défaut, selon E1.**

Si la variante retenue n'est pas `sonde`, dans `sonde/platformio.ini`, remplacer :

```ini
default_envs = sonde
```

par la variante retenue, par exemple `default_envs = sonde_routeur`. Dans `sonde/README.md`, ajouter sous le tableau des variantes une phrase qui dit laquelle est retenue et pourquoi (E1 de la section 8 de la spec).

- [ ] **Step 4 : la spec.**

Dans l'en-tête de la spec, remplacer :

```markdown
> **Plan :** `docs/superpowers/plans/2026-10-05-maillage-zigbee-plan1-sonde.md`.
```

par :

```markdown
> **Plan :** `docs/superpowers/plans/2026-10-05-maillage-zigbee-plan1-sonde.md`,
> exécuté ; sonde 1.0.0 (variante et commandes retenues : section 8).
```

Puis, selon les décisions, dans la section 2 de la spec :
- E4 échoué : retirer la commande `routes` et son message ;
- E5 : décrire `echecs` (son format est dans `sonde/src/main.cpp`, `rendreEchecs`) ou dire qu'elle est retirée ;
- lignes `signal` : dire si elles sont gardées.

- [ ] **Step 5 : vérifier, puis flasher la 1.0.0 (contrôleur, avec Majid).**

Run :

```bash
sh outils/tester.sh
cd sonde && ~/.platformio/penv/bin/pio run -e verif -e verif_routeur && cd ..
python3 outils/flasher.py --env <variante retenue>
python3 outils/essai_sonde.py bonjour
python3 outils/essai_sonde.py etat
```

Expected :
- tests et compilation sans échec ;
- le flash est fait **sans** effacement, et le réseau est gardé ;
- `bonjour` donne `"version":"1.0.0"` ;
- `etat` donne `"membre":true` sans nouvelle recherche dans l'app Hue.

- [ ] **Step 6 : commit.**

```bash
git add sonde/src/version.h sonde/src/main.cpp sonde/platformio.ini sonde/README.md docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md
git commit -m "Passer la sonde en 1.0.0 d'apres l'essai

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ensuite : relecture finale de la branche (modèle le plus fort), puis le morceau 2 (l'app) commence par sa propre spec.
