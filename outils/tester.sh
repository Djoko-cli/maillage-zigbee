#!/bin/sh
# Tous les tests sans carte, depuis la racine du depot :
#   sh outils/tester.sh
# 1. tests des outils Python (outils/test) ;
# 2. garde des vrais identifiants (outils/garde.py).
# Aucun port serie n'est ouvert, rien n'est flashe.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
DEPOT=$(cd "$ICI/.." && pwd)
python3 -m unittest discover -s "$ICI/test"
python3 "$ICI/garde.py"
