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
