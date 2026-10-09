#!/bin/sh
# Publie une version de Maillage Zigbee sur GitHub (spec du deploiement, section 3) : verifications, numeros,
# compilation Release signee par le certificat de Djoko, .dmg signe par Sparkle (cle du trousseau), controle
# d'anonymisation, version publiee (etiquette app-vX.Y.Z, avec le .dmg), puis le flux des mises a jour
# (appcast.xml, qui garde toutes les versions) commite sur main et pousse aussitot, .dmg sur le Bureau.
# Le .dmg porte aussi la licence de Sparkle 2.10.0 (outils/Sparkle-LICENSE.txt, le fichier LICENSE de l'etiquette
# 2.10.0, entier) ; le commit du flux est signe Djoko-cli, a l'adresse noreply de GitHub.
# La logique est dans outils/publication.py, ses tests dans outils/test.
#   outils/publier.sh X.Y.Z [--sans-bureau]
# La repetition, sans GitHub ni Bureau (spec, section 4), avec la cle du trousseau, ou une paire d'essai :
#   outils/publier.sh X.Y.Z --repetition DOSSIER --url-base URL [--cle-privee FICHIER --cle-publique CLE]
#                           [--trousseau TROUSSEAU] [--sans-tests]
# SPARKLE_BIN : le dossier bin de l'archive de Sparkle 2.10.0 (sign_update, generate_keys), obligatoire hors repetition.
# NOTARISER=1 (desactive par defaut) : notarisation du .dmg, avec PROFIL_NOTARISATION, le profil que
# notarytool store-credentials a range dans le trousseau ; il faut alors un Developer ID pour IDENTITE_SIGNATURE.
# Produits : build/publication/X.Y.Z/ ; compilation dans DD (par defaut DerivedData/maillage-zigbee-publication).
set -eu
cd "$(dirname "$0")/.."
# L'identite de signature de la version publiee, a ce seul endroit : le certificat auto-signe de Djoko, trouve par
# son nom dans le trousseau (les compilations de travail et les tests restent ad hoc).
IDENTITE_SIGNATURE=${IDENTITE_SIGNATURE:-Djoko-cli Code Signing}
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
