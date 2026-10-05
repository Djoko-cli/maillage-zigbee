#!/usr/bin/env python3
"""Essai de la sonde Zigbee par l'USB (spec de la sonde, section 4).

  python3 outils/essai_sonde.py [--port P] <commande> [<argument> ...]

Commandes :
  bonjour | etat | voisins | suspendre | reprendre | oubli
  nom <texte>
  table <cible> [<delai ms>]      table des voisins d'un routeur (E2)
  routes <cible> [<delai ms>]     table de routage (E4)
  echecs <cible> [<delai ms>] --accord   emissions et echecs (E5 : la lampe interrogee devient sourde
                                  ~31 ms ; exige --accord, donc l'accord explicite de Majid)
  tournee [<delai ms>]            parcours en largeur depuis le pont (E3)
  nuit <heures> [<periode s>]     etat et tournee toutes les <periode> s, 900 par defaut (E6)
  ecoute <secondes>               lit sans rien envoyer

Port : --port, sinon "port" de outils/sonde.local.json (ignore par git). Avant toute commande sauf ecoute,
l'outil verifie par bonjour que c'est une sonde Zigbee. Aucun agent ne lance cet outil : il ouvre un port
serie (plan, contraintes globales).

Journal : tout ce qui passe va dans essais/<AAAA-MM-JJ>/sonde.jsonl, et le resume de chaque tournee dans
essais/<AAAA-MM-JJ>/tournee-<HHMMSS>.json, dans le dossier du jour de lancement (un seul par execution,
meme si la nuit passe minuit). essais/ est ignore par git : identifiants reels.
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
    def __init__(self, sonde, dossier=None):
        self.sonde = sonde
        self.dossier = dossier
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
        chemin = os.path.join(self.dossier or dossier_du_jour(), time.strftime("tournee-%H%M%S.json"))
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
    accord = "--accord" in args
    args = [a for a in args if a != "--accord"]
    if commande == "echecs" and not accord:
        print("echecs rend la lampe interrogee sourde ~31 ms (E5) : a n'utiliser qu'avec l'accord explicite de "
              "Majid, en ajoutant --accord")
        return 2
    dossier = dossier_du_jour()
    journal = os.path.join(dossier, "sonde.jsonl")
    sonde = sonde_usb.Sonde(sonde_usb.ouvrir(port), journal_vers(journal))

    def reconnecter():
        nouvelle = sonde_usb.Sonde(sonde_usb.ouvrir(port), journal_vers(journal))
        try:
            nouvelle.verifier()
        except (ValueError, sonde_usb.PortPerdu):
            os.close(nouvelle.fd)
            raise
        try:
            os.close(essai.sonde.fd)
        except OSError:
            pass
        essai.sonde = nouvelle

    if commande == "ecoute":
        for e in sonde.lire(time.time() + float(args[0] if args else 10)):
            afficher(e) if isinstance(e, dict) else print("   |", e[:160])
        return 0
    try:
        sonde.verifier()
    except ValueError as e:
        print(e)
        return 1
    essai = Essai(sonde, dossier)
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
                if etat and "erreur" in etat:
                    statut = f"etat {etat['erreur']}"
                else:
                    statut = "membre" if etat and etat.get("membre") else "NON MEMBRE"
                print(time.strftime("%H:%M:%S"), statut, (etat or {}).get("parent"))
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
