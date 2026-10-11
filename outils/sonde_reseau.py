#!/usr/bin/env python3
"""Client de la sonde Zigbee 1.1.0 par le reseau (spec sonde Wi-Fi, section 6), pour le banc.

  python3 outils/sonde_reseau.py wifi
      USB : demande le nom du Wi-Fi (visible) et le mot de passe (masque), les envoie a la sonde, qui
      redemarre. Rien n'est affiche du mot de passe.
  python3 outils/sonde_reseau.py cle
      USB : nouvelle cle d'acces ; rangee dans outils/cle_reseau.local (droits 600, ignore par git),
      jamais affichee : seule l'empreinte l'est.
  python3 outils/sonde_reseau.py [--hote H] bonjour | etat | voisins | table <cible> | routes <cible>
  python3 outils/sonde_reseau.py [--hote H] ecoute <secondes>
      Reseau : poignee de main H1 sur <hote>:5481 (par defaut sonde-z1.local, le nom de la sonde en
      minuscules), puis la commande ; ecoute compte les lignes signal recues.

Port USB : "port" de outils/sonde.local.json. Aucun agent ne lance cet outil (il ouvre un port serie et
utilise la vraie cle).
"""
import getpass
import hashlib
import hmac
import json
import os
import secrets
import socket
import sys
import time

ICI = os.path.dirname(os.path.abspath(__file__))
FICHIER_CLE = os.path.join(ICI, "cle_reseau.local")
PORT = 5481


def _mac(cle, texte):
    return hmac.new(cle, texte, hashlib.sha256).digest()[:16].hex().upper()


def kid(psk):
    return hashlib.sha256(psk).hexdigest()[:8].upper()


def salut(psk, na):
    k, n = kid(psk), na.hex().upper()
    return f"H1 SALUT {k} {n} {_mac(psk, f'H1|SALUT|{k}|{n}'.encode())}"


def verifier_defi(ligne, psk, na):
    champs = ligne.split(" ")
    if len(champs) != 5 or champs[:2] != ["H1", "DEFI"]:
        return None
    sid, nc, mac = champs[2], champs[3], champs[4]
    attendu = _mac(psk, f"H1|DEFI|{kid(psk)}|{na.hex().upper()}|{nc}|{sid}".encode())
    return (sid, nc) if hmac.compare_digest(attendu, mac) else None


class Session:
    def __init__(self, psk, na, nc, sid):
        self.sid = sid
        self.ks = hmac.new(psk, f"H1|SESSION|{na.hex().upper()}|{nc}|{sid}".encode(), hashlib.sha256).digest()
        self.ctr = 0
        self.haut, self.bits = 0, 0

    def sceller(self, charge):
        self.ctr += 1
        mac = _mac(self.ks, f"A|{self.sid}|{self.ctr}|".encode() + charge.encode())
        return f"H1 {self.sid} {self.ctr} {mac} {charge}"

    def ouvrir(self, ligne):
        champs = ligne.split(" ", 4)
        if len(champs) != 5 or champs[0] != "H1" or champs[1] != self.sid:
            return None
        c = champs[2]
        if not c.isdigit() or c.startswith("0"):
            return None
        ctr = int(c)
        if not hmac.compare_digest(_mac(self.ks, f"C|{self.sid}|{ctr}|".encode() + champs[4].encode()), champs[3]):
            return None
        if ctr > self.haut:
            saut = ctr - self.haut
            self.bits = (0 if saut >= 32 else (self.bits << saut) & 0xFFFFFFFF) | 1
            self.haut = ctr
        else:
            recul = self.haut - ctr
            if recul >= 32 or self.bits & (1 << recul):
                return None
            self.bits |= 1 << recul
        return champs[4]


def couper_rid(charge):
    rid, _, json_ = charge.partition(" ")
    if not rid.isdigit() or not json_:
        return None
    return int(rid), json_


def ligne_wifi(nom, mdp, id_):
    n = nom.encode("utf-8")
    m = mdp.encode("utf-8")
    if not 1 <= len(n) <= 32 or (m and not 8 <= len(m) <= 63) or b"\x00" in n + m:
        raise ValueError("nom de 1 a 32 octets, mot de passe vide ou de 8 a 63 octets")
    return f"wifi {n.hex().upper()} {m.hex().upper() if m else '-'} {id_}"


def ranger_cle(cle, chemin=FICHIER_CLE):
    """Ecrit la cle (64 hexa) avec des droits 600, meme si le fichier existait deja avec d'autres droits."""
    fd = os.open(chemin, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        os.fchmod(fd, 0o600)
        f.write(cle + "\n")


# --- USB --------------------------------------------------------------------

def _sonde_usb():
    import sonde_usb  # noqa: E402 (meme dossier)

    with open(os.path.join(ICI, "sonde.local.json")) as f:
        port = json.load(f)["port"]
    s = sonde_usb.Sonde(sonde_usb.ouvrir(port))  # sans journal : la cle ne doit jamais etre notee
    s.verifier()
    return s


def cmd_wifi():
    nom = input("Nom du Wi-Fi (2,4 GHz) : ")
    mdp = getpass.getpass("Mot de passe (vide : reseau ouvert) : ")
    try:
        ligne = ligne_wifi(nom, mdp, 1)
    finally:
        mdp = None
    r = _sonde_usb().commande(ligne, ("wifi", "erreur"))
    del ligne
    print("Wi-Fi :", "enregistre, la sonde redemarre" if r and r.get("configure") else r)


def cmd_cle():
    alea = secrets.token_bytes(32)
    r = _sonde_usb().commande(f"cle nouvelle {alea.hex().upper()} 1", ("cle", "erreur"))
    if not r or r.get("t") != "cle" or "cle" not in r:
        print("Echec :", r)
        return 1
    cle = r["cle"]
    if kid(bytes.fromhex(cle)) != r.get("empreinte"):
        print("Empreinte fausse : cle non rangee ; la carte a peut-etre une cle que l'outil n'a pas, "
              "relancer cle pour la remplacer")
        return 1
    ranger_cle(cle)
    print("Cle rangee dans outils/cle_reseau.local, empreinte", r["empreinte"])
    return 0


# --- Reseau -----------------------------------------------------------------

class Client:
    def __init__(self, hote, psk):
        self.s = socket.create_connection((hote, PORT), timeout=10)
        self.tampon = b""
        na = secrets.token_bytes(16)
        self._ecrire(salut(psk, na))
        try:
            ligne = self._lire(5.0)
        except socket.timeout:
            ligne = ""
        defi = verifier_defi(ligne, psk, na)
        if not defi:
            raise RuntimeError("poignee de main refusee (cle ?)")
        self.session = Session(psk, na, defi[1], defi[0])
        self.rid = 0

    def _ecrire(self, ligne):
        self.s.sendall(ligne.encode() + b"\n")

    def _lire(self, attente):
        self.s.settimeout(attente)
        while b"\n" not in self.tampon:
            d = self.s.recv(4096)
            if not d:
                raise ConnectionError("connexion fermee par la sonde")
            self.tampon += d
        ligne, self.tampon = self.tampon.split(b"\n", 1)
        return ligne.decode()

    def commande(self, texte, delai=15.0):
        """Lignes JSON de la reponse (jusqu'a "suite": false pour une liste)."""
        self.rid += 1
        self._ecrire(self.session.sceller(f"{self.rid} {texte}"))
        lignes, fin = [], time.time() + delai
        while time.time() < fin:
            try:
                charge = self.session.ouvrir(self._lire(max(0.1, fin - time.time())))
            except socket.timeout:
                break
            r = couper_rid(charge) if charge else None
            if not r or r[0] != self.rid:
                continue
            j = json.loads(r[1])
            lignes.append(j)
            if not j.get("suite"):
                return lignes
        return lignes

    def ecouter(self, secondes):
        n, fin = 0, time.time() + secondes
        while time.time() < fin:
            try:
                charge = self.session.ouvrir(self._lire(max(0.1, fin - time.time())))
            except socket.timeout:
                break
            r = couper_rid(charge) if charge else None
            if r and r[0] == 0:
                n += 1
        return n


def _psk():
    with open(FICHIER_CLE) as f:
        return bytes.fromhex(f.read().strip())


def main(argv):
    hote = "sonde-z1.local"
    if argv[:1] == ["--hote"] and len(argv) >= 2:
        hote, argv = argv[1], argv[2:]
    if not argv:
        print(__doc__)
        return 2
    if argv == ["wifi"]:
        return cmd_wifi()
    if argv == ["cle"]:
        return cmd_cle()
    try:
        psk = _psk()
    except FileNotFoundError:
        print("Cle absente : lancer d'abord cle (USB) pour la creer")
        return 1
    except ValueError:
        print("Cle illisible dans outils/cle_reseau.local : relancer cle (USB)")
        return 1
    try:
        c = Client(hote, psk)
    except (OSError, ValueError, RuntimeError) as e:
        print("Connexion impossible :", e)
        return 1
    if argv[0] == "ecoute" and len(argv) == 2:
        print(c.ecouter(float(argv[1])), "lignes signal")
        return 0
    if argv[0] in ("table", "routes") and len(argv) == 2:
        texte = f"{argv[0]} {argv[1].upper()} 1"
    elif argv[0] in ("bonjour", "etat", "voisins") and len(argv) == 1:
        texte = argv[0]
    else:
        print(__doc__)
        return 2
    for j in c.commande(texte, delai=130.0 if argv[0] in ("table", "routes") else 15.0):
        print(json.dumps(j, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
