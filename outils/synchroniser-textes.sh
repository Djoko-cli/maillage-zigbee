#!/bin/sh
# Met le catalogue de l'app a jour avec les textes extraits par le compilateur
# (a lancer apres une compilation, par exemple outils/tester-app.sh) : ajoute les
# nouvelles cles, marque "stale" celles qui ont disparu du code. Ensuite :
#   python3 outils/traduire.py MaillageZigbee/Ressources/Localizable.xcstrings outils/traductions/<fichier>.json
set -eu
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-zigbee}
I="$DD/Build/Intermediates.noindex/MaillageZigbee.build/Debug/MaillageZigbee.build/Objects-normal"
xcrun xcstringstool sync MaillageZigbee/Ressources/Localizable.xcstrings --stringsdata "$I"/*/*.stringsdata
