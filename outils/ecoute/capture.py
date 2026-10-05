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
