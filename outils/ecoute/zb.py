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
