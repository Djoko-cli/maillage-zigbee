#!/bin/sh
# Tests hote purs de la sonde, sans carte : chaque module pur de sonde/src a
# son programme de test ici (test_<module>.cpp).
#
#   sh sonde/test/lancer.sh
#
# clang++ de Xcode, ASan et UBSan. Les binaires vont dans un dossier
# temporaire : rien ne reste dans le depot. Les commandes routes et echecs
# sont testees actives (par defaut) puis coupees (SONDE_ROUTES=0,
# SONDE_ECHECS=0), comme apres l'essai si on les retire.
set -e
ICI=$(cd "$(dirname "$0")" && pwd)
SRC="$ICI/../src"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
DRAPEAUX="-std=gnu++17 -g -O1 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-sanitize-recover=undefined -fno-omit-frame-pointer"
compiler() {
  nom=$1
  shift
  clang++ $DRAPEAUX -I"$SRC" "$@" -o "$TMP/$nom"
}
compiler test_commande "$ICI/test_commande.cpp" "$SRC/commande.cpp"
compiler test_commande_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_commande.cpp" "$SRC/commande.cpp"
compiler test_ligne "$ICI/test_ligne.cpp" "$SRC/ligne.cpp"
compiler test_entrees "$ICI/test_entrees.cpp" "$SRC/entrees.cpp"
compiler test_pagination "$ICI/test_pagination.cpp"
compiler test_cadence "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
compiler test_cadence_sans -DSONDE_ROUTES=0 -DSONDE_ECHECS=0 "$ICI/test_cadence.cpp" "$SRC/cadence.cpp"
compiler test_adhesion "$ICI/test_adhesion.cpp" "$SRC/adhesion.cpp"
compiler test_voyant "$ICI/test_voyant.cpp"
"$TMP/test_commande"
"$TMP/test_commande_sans"
"$TMP/test_ligne"
"$TMP/test_entrees"
"$TMP/test_pagination"
"$TMP/test_cadence"
"$TMP/test_cadence_sans"
"$TMP/test_adhesion"
"$TMP/test_voyant"
