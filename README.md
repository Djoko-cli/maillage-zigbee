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
