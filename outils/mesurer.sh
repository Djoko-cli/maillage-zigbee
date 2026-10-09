#!/bin/sh
# Temps de calcul de la vue par pieces, en Release (spec de la vue par pieces, section 10) : la
# disposition d'une grande maison inventee (sous 1 s) et le placement de 150 noms (sous 2 ms dans une
# fenetre ordinaire, sous 4 ms tres serres). En Debug (outils/tester-app.sh), ces trois tests sont
# sautes. Schema MaillageCoeur : le coeur et ses tests seuls. Journal complet dans
# $TMPDIR/maillage-mesures.log. Produits de compilation hors du depot (DD).
set -u
cd "$(dirname "$0")/.."
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-zigbee}
JOURNAL=${TMPDIR:-/tmp}/maillage-mesures.log
xcodegen generate --quiet || exit 1
xcodebuild -project MaillageZigbee.xcodeproj -scheme MaillageCoeur -destination 'platform=macOS' \
  -derivedDataPath "$DD" -configuration Release ENABLE_TESTABILITY=YES ONLY_ACTIVE_ARCH=YES test \
  -only-testing:MaillageCoeurTests/DispositionPiecesTests -only-testing:MaillageCoeurTests/PlacementNomsTests \
  > "$JOURNAL" 2>&1
CODE=$?
grep -E "(error|warning): |✘|mesure : |Test run with|\*\* TEST" "$JOURNAL" | grep -v -e appintentsmetadataprocessor -e "\[Connection\]"
# Un test de temps saute (compilation non optimisee) passe sans rien mesurer : il faut ses trois lignes.
MESURES=$(grep -c "mesure : " "$JOURNAL")
if [ "$CODE" -eq 0 ] && [ "$MESURES" -ne 3 ]; then
  echo "echec : $MESURES ligne(s) « mesure : » au lieu de 3 (un test de temps a ete saute)"
  CODE=1
fi
echo "journal complet : $JOURNAL (code $CODE)"
exit $CODE
