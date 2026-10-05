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
