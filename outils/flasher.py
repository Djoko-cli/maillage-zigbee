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
  4. l'effacement si --effacer, puis le televersement (-t upload, qui ne recompile pas : deja fait en 2 ;
     -t nobuild ne marche pas, pioarduino ne donne alors a esptool que des options sans images).
Autre carte a l'une des etapes 1 ou 3 : refus, rien n'est ecrit.

--effacer : effacement complet d'abord (premier flash : la sonde quitte le reseau Hue).
--env : variante de sonde/platformio.ini, sonde seulement (la variante de verification verif, a cle
factice, ne se flashe jamais).
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
VARIANTES = ("sonde",)


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
    etapes = ([["-t", "erase"]] if effacer else []) + [["-t", "upload"]]
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
