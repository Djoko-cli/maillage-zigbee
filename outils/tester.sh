#!/bin/sh
# Tous les tests sans carte, depuis la racine du depot :
#   sh outils/tester.sh
# 1. tests hote du firmware de la sonde (sonde/test/lancer.sh) ;
# 2. tests des outils Python (outils/test) ;
# 3. garde des vrais identifiants (outils/garde.py).
# Aucun port serie n'est ouvert, rien n'est flashe.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
DEPOT=$(cd "$ICI/.." && pwd)
sh "$DEPOT/sonde/test/lancer.sh"
python3 -m unittest discover -s "$ICI/test"
python3 "$ICI/garde.py"
