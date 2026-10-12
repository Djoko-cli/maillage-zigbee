#!/bin/sh
# Publie une version de Maillage Zigbee sur GitHub (spec du deploiement, section 3) : verifications, numeros,
# compilation Release signee par le Developer ID de Djoko et notarisee, .dmg signe par Sparkle (cle du trousseau),
# controle d'anonymisation, version publiee (etiquette app-vX.Y.Z, avec le .dmg), puis le flux des mises a jour
# (appcast.xml, qui garde toutes les versions) commite sur main et pousse aussitot, .dmg sur le Bureau.
# Le .dmg porte aussi la licence de Sparkle 2.10.0 (outils/Sparkle-LICENSE.txt, le fichier LICENSE de l'etiquette
# 2.10.0, entier) ; le commit du flux est signe Djoko-cli, a l'adresse noreply de GitHub.
# La logique est dans outils/publication.py, ses tests dans outils/test.
#   outils/publier.sh X.Y.Z [--sans-bureau]
# La repetition, sans GitHub ni Bureau (spec, section 4), avec la cle du trousseau, ou une paire d'essai :
#   outils/publier.sh X.Y.Z --repetition DOSSIER --url-base URL [--cle-privee FICHIER --cle-publique CLE]
#                           [--trousseau TROUSSEAU] [--sans-tests]
# SPARKLE_BIN : le dossier bin de l'archive de Sparkle 2.10.0 (sign_update, generate_keys), obligatoire hors repetition.
# Depuis la 1.1.0 (decision de Djoko du 12/10/2026), les versions publiees sont signees par son Developer ID et
# notarisees : NOTARISER=1 et PROFIL_NOTARISATION=djoko-notarisation (le profil que notarytool store-credentials a
# range dans le trousseau) par defaut. La 1.0.0 l'etait par le certificat auto-signe « Djoko-cli Code Signing ».
# Produits : build/publication/X.Y.Z/ ; compilation dans DD (par defaut DerivedData/maillage-zigbee-publication).
set -eu
cd "$(dirname "$0")/.."
# L'identite de signature de la version publiee, a ce seul endroit : le Developer ID de Djoko, trouve dans le
# trousseau par son prefixe (son nom complet porte le nom legal du titulaire : il n'est ecrit nulle part ici).
IDENTITE_SIGNATURE=${IDENTITE_SIGNATURE:-Developer ID Application}
NOTARISER=${NOTARISER:-1}
PROFIL_NOTARISATION=${PROFIL_NOTARISATION:-djoko-notarisation}
export NOTARISER PROFIL_NOTARISATION
# Le cliquet du Developer ID : depuis la 1.1.0, une version publiee n'est jamais signee autrement (un retour au
# certificat auto-signe ramenerait l'alerte « l'app differe » de macOS et le blocage de Gatekeeper). La repetition
# seule peut signer autrement.
repetition=0
for x in "$@"; do
  case $x in --repetition|--repetition=*) repetition=1;; esac
done
if [ $repetition = 0 ] && { [ "$IDENTITE_SIGNATURE" != "Developer ID Application" ] || [ "$NOTARISER" != 1 ]; }; then
  echo "publier.sh : une version publiee est signee par le Developer ID et notarisee (IDENTITE_SIGNATURE, NOTARISER)" >&2
  exit 1
fi
DD=${DD:-$HOME/Library/Developer/Xcode/DerivedData/maillage-zigbee-publication}
export DD
exec /usr/bin/python3 outils/publication.py publier "$@" --identite "$IDENTITE_SIGNATURE" \
  --auteur Djoko-cli --etiquette app-v --flux appcast.xml --licence outils/Sparkle-LICENSE.txt \
  --nom-app "Maillage Zigbee" --fichier Maillage-Zigbee --depot-github Djoko-cli/maillage-zigbee \
  --projet MaillageZigbee.xcodeproj --schema MaillageZigbee --cible MaillageZigbee \
  --test 'sh outils/tester.sh' \
  --test 'sh outils/tester-app.sh' \
  --test 'xcodebuild -project MaillageZigbee.xcodeproj -scheme MaillageZigbee -destination platform=macOS -derivedDataPath "$DD" -testLanguage en -testRegion US test' \
  --textes MaillageZigbee/Ressources/Localizable.xcstrings --textes MaillageZigbee/Ressources/InfoPlist.xcstrings
