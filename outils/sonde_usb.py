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
