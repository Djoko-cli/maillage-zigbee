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
