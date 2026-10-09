[English](README.md) · **Français**

# Maillage Zigbee

<p align="center"><img src="docs/images/vue-3d.png" alt="La vue par pièces en 3D : les pièces, le pont, les routeurs, les appareils finaux et les chemins vers le pont" width="100%"></p>

<p align="center">
  <img src="docs/images/vue-2d.png" alt="La vue par pièces en 2D, avec les chemins vers le pont" width="49%">
  <img src="docs/images/fiche-noeud.png" alt="La fiche d'un appareil final endormi qui garde son parent d'avant" width="49%">
</p>

<p align="center">
  <img src="docs/images/reglages-pont.png" alt="Réglages, Pont Hue : un pont lié" width="49%">
  <img src="docs/images/reglages-maison.png" alt="Réglages, Maison : le relevé de Maison et les appareils du pont qu'il nomme" width="49%">
</p>

<p align="center"><sub>Mode démo : un faux réseau Hue, aux noms, pièces et adresses inventés.</sub></p>

App native de la barre des menus de macOS (SwiftUI) qui montre le maillage
Zigbee d'un réseau Philips Hue : quelle lampe parle à quelle autre, avec
quelle qualité de lien, et le chemin que prennent vraiment les messages de
chaque routeur jusqu'au pont. Le pont Hue n'en dit rien. Une sonde, un
ESP32-C6 qui entre dans le réseau Hue comme appareil final et se branche au
Mac en USB, lit les tables de voisins et de routage de chaque routeur ; le
pont, par son API locale, donne les appareils et leur état ; l'app Maison,
lue par Passeur Noms, donne leurs noms, leurs pièces et les étages.
L'app tient le journal des changements (un routeur disparu, un appareil qui
change de parent ou le perd) et notifie les alertes.

Le dépôt contient l'app, le firmware de la sonde (`sonde/`) et leurs outils.
L'app dérive de [Maillage Thread](https://github.com/Djoko-cli/maillage-thread),
la même app pour un réseau Thread.

## Installation

Télécharger `Maillage-Zigbee-X.Y.Z.dmg` dans la dernière
[version publiée](https://github.com/Djoko-cli/maillage-zigbee/releases)
(`app-vX.Y.Z`), l'ouvrir, et glisser **Maillage Zigbee** sur
**Applications**. macOS 26 ou ultérieur.

- **Premier lancement (Gatekeeper).** L'app est signée par un certificat
  auto-signé, `Djoko-cli Code Signing`, pas par un Developer ID d'Apple, et
  n'est pas notarisée. macOS refuse de l'ouvrir la première fois : dans
  Réglages Système, Confidentialité et sécurité, cliquer « Ouvrir quand même »
  à côté de Maillage Zigbee, puis confirmer avec son mot de passe. Une seule
  fois.
- **Réseau local.** macOS demande une fois de laisser l'app accéder au réseau
  local : il le lui faut pour trouver et lire le pont Hue.
- **Mises à jour automatiques** (Sparkle 2). L'app cherche une nouvelle
  version au démarrage puis toutes les 24 heures, la télécharge, vérifie sa
  signature Ed25519, et l'installe à la fermeture de l'app, ou tout de suite
  par « Installer et relancer ». « Rechercher les mises à jour… » est dans le
  menu ; Réglages, Général, « Mises à jour », a « Rechercher
  automatiquement » et « Installer automatiquement », tous deux actifs par
  défaut.
- **La sonde** se compile et se flashe depuis une copie de ce dépôt (voir
  « Sonde » plus bas).

## Ce que montre l'app

### Trois sources

| Source | Donne |
|---|---|
| la sonde, par l'USB | la table des voisins de chaque routeur (qualité des liens, LQI, dans chaque sens ; les appareils finaux sous chaque parent), les tables de routage (le prochain saut de chaque routeur vers le pont), les voisins de la sonde |
| le pont Hue, API v2 en HTTPS, sur le réseau local | la liste des appareils : la marque, le modèle et la pile de chacun ; son adresse longue (IEEE), la clé qui le rapproche de la sonde ; son état de connexion vu par le pont (connecté, problème de connexion, déconnecté) ; son nom et sa pièce dans l'app Hue, à défaut de Maison |
| l'app Maison, par Passeur Noms, sur la boucle locale du Mac | le nom et la pièce de chaque appareil, qui l'emportent sur ceux de l'app Hue ; les zones, qui deviennent les étages de la vue par pièces ; le domicile |

Un nœud est une adresse longue (IEEE), qui ne change jamais ; l'adresse courte
change quand un appareil se rattache, ce n'est donc jamais une clé. Le pont,
le coordinateur, est au centre avec sa couronne ; les routeurs (lampes,
prises) relaient ; les appareils finaux (interrupteurs, capteurs) dépendent
d'un parent ; la sonde a un signe à elle. La qualité d'un lien vient du LQI
(0 à 255), converti à un seul endroit : bonne à partir de 170, moyenne à
partir de 100, faible en dessous. Un lien radio a deux sens : l'app montre le
pire des deux, et pour chaque sens la mesure la plus récente l'emporte.

### Le pont Hue et sa liaison

L'app trouve le pont par Bonjour (`_hue._tcp`) ; sinon, son adresse IP se
saisit dans Réglages, Pont Hue (l'app Hue la donne, parmi les réglages du
pont). La liaison se fait une fois : « Lier… », puis appuyer dans les 60
secondes sur le bouton rond du pont. La clé d'application donnée par le pont
va au trousseau du Mac ; « Oublier le pont » l'efface.

Toute connexion au pont est en HTTPS **avec vérification** : le certificat
doit être signé par l'autorité de Signify (ses certificats publics sont
intégrés à l'app) et porter l'identifiant du pont comme nom commun. Aucun
certificat n'est jamais accepté sans cette vérification, la clé ne part
qu'au pont auquel elle appartient, et aucune redirection n'est suivie. Le
pont est lu au lancement puis toutes les 5 minutes ; son dernier relevé est
gardé sur disque, pour un démarrage sans réseau.

### Les noms de Maison (Passeur Noms)

Les lampes Hue arrivent dans l'app Maison par le pont, et c'est là qu'on les
nomme et qu'on les range : l'app prend donc les noms, les pièces et les étages
de Maison, et garde ceux de l'app Hue pour ce qu'elle n'y retrouve pas.

Une app du Mac ne peut pas lire Maison elle-même (il faut HomeKit, qu'une
équipe gratuite n'obtient que dans une app iOS). C'est le rôle de **Passeur Noms**,
une petite app iOS « conçue pour iPad » que
[Maillage Thread](https://github.com/Djoko-cli/maillage-thread) installe sur
le Mac (`outils/passeur.sh` de ce dépôt-là ; profil gratuit de 7 jours, à
reconstruire ensuite). Elle est générique : Maillage Zigbee s'en sert telle
quelle, sans la modifier.

- **Le relevé** : l'app écoute sur 127.0.0.1 seulement, sur un port choisi par
  le système, tire un jeton à usage unique, puis ouvre le Passeur sans
  l'activer avec `maillage-passeur://releve?port=<port>&jeton=<jeton>`. Le
  Passeur lit Maison et renvoie le relevé (jeton, longueur, JSON) ; l'app
  compare le jeton à temps constant, lit au plus 8 Mo, accepte une seule
  connexion et attend au plus 2 minutes.
- **Quand** : au lancement, si le dernier relevé a plus d'un jour ; à la
  demande, par « Rafraîchir depuis Maison » (menu, et Réglages, Maison). Le
  dernier relevé réussi est gardé dans le conteneur de l'app
  (`releve-maison.json`, jamais dans le dépôt) ; un échec ne l'efface pas.
- **Rapprochement** : pour chaque appareil du pont, l'app cherche son
  accessoire Maison parmi ceux de Signify ou de Philips (ou portés par le
  nœud Matter du pont Hue), d'abord par le nom (à la casse, aux accents et
  aux espaces près), à défaut par la pièce et le modèle s'il n'y a qu'un
  candidat ; jamais d'appariement ambigu. Retrouvé : son nom et sa pièce de
  Maison. Sinon : ceux de l'app Hue, et sa fiche le dit (« nom de l'app Hue
  (pas trouvé dans Maison) »). L'adresse longue, l'état de connexion et la
  pile viennent toujours du pont.
- **Sans Passeur** : l'app marche avec les seuls noms de l'app Hue, sur un seul
  plateau ; Réglages, Maison dit comment l'installer.

### Les tournées et le budget de pages

Toutes les 15 minutes, et par Rafraîchir, l'app fait une **tournée** par la
sonde : l'état et les voisins de la sonde, puis la table de routage du pont et
de chaque routeur et, une tournée sur quatre (ou quand un routeur inconnu
paraît dans une route), les tables de voisins, en largeur depuis le pont. Un
routeur qui ne donne ni sa table ni ses routes deux fois de suite est
« muet ». Si la sonde perd son parent pendant une tournée (environ une fois
par tournée ; elle se rattache seule en 10 s), la tournée attend son retour.

La sonde plafonne les requêtes réseau qu'elle accepte (600 pages par 10
minutes, pour ménager le réseau Hue). L'app tient son propre **budget de 550
pages sur 10 minutes glissantes**, gardé d'un lancement à l'autre : une
tournée qui n'y tiendrait pas attend (« Tournée complète à 19:24 : la sonde a
déjà beaucoup servi »), et les routes des routeurs qui n'y ont pas tenu sont
lues dans une passe complémentaire dès que le budget le permet, les plus
anciennes d'abord.

### Les vrais chemins vers le pont

Avec « Liens : chemins » (le réglage par défaut), la vue dessine pour chaque
routeur le chemin que prennent vraiment ses messages vers le pont, lu dans sa
table de routage, coloré par la qualité de chaque saut ; un chemin que les
tables ne donnent pas (une route inactive, un routeur muet) est tracé comme
« supposé ». Les voisins entendus d'un nœud paraissent à sa sélection
(« Voisins à la sélection » les masque). « Liens : tous » montre tous les
liens radio.

Un appareil final dépend de son parent. Un appareil final endormi manque
parfois à la table de son parent le temps d'une tournée, alors que le pont le
dit connecté : pendant 24 heures, l'app garde son **parent d'avant**, tracé
en pointillé, et sa fiche dit de quand date sa lecture.

### La vue par pièces (2D et 3D)

La vue par pièces, reprise de Maillage Thread, range chaque appareil dans sa
pièce (celle de Maison) et dessine les pièces comme des cartes sur des
plateaux, en 2D ou en 3D : un plateau par zone de Maison, en général un étage ;
une pièce de l'app Hue que Maison n'a pas va dans « Autres pièces » ; sans
relevé de Maison, un seul plateau. Zoomer, se déplacer,
isoler une pièce, survoler un nœud. La fiche d'un nœud donne son nom, sa
pièce, sa marque et son modèle, sa pile, son rôle, ses adresses IEEE et
courte, son parent (avec la qualité et le LQI) ou ses voisins dans chaque
sens, son chemin vers le pont, son journal, et la courbe de son signal dans le
temps. Un appareil que le pont ne place pas (la sonde comprise) se range à la
main (« Placer dans une pièce… »).

### Journal, historique, notifications

- **Journal** (menu, « Journal… ») : surveillance démarrée, veille du Mac,
  appareil nouveau (vu des tournées), disparu ou revenu (d'après l'état de
  connexion que donne le pont : disparu après deux lectures de suite, soit
  10 minutes ; revenu aussi par les
  tournées), routeur apparu ou disparu, changement de parent, appareil sans
  parent, chemin changé. Gardé 90 jours, en fichiers mensuels.
- **Historique** : une ligne par tournée (nœuds, liens, parents), gardée 90
  jours ; il trace les courbes des fiches.
- **Notifications** (Réglages, Notifications) : routeur disparu ; au moins 3
  appareils perdus en 10 minutes (une notification groupée) ; autres
  changements.

### Réglages

Général (ouverture à la connexion, mises à jour, langue, vue par pièces),
Notifications, Pont Hue (état, liaison, adresse), Maison (dernier relevé,
étages, appareils nommés par Maison ou non, « Rafraîchir depuis Maison »),
Sonde (port USB, état,
firmware, dernière tournée, prochaine tournée), Diagnostic (dernier maillage,
capture, journal).

## Sonde

Un ESP32-C6 SuperMini qui entre dans le réseau Hue comme **appareil final
non endormi** : il reçoit en permanence, ne relaie et ne route jamais, et
n'envoie aucune commande aux lampes. Sur demande, il donne la table complète
des voisins de n'importe quel routeur (`Mgmt_Lqi_req`, page par page), sa
table de routage (`Mgmt_Rtg_req`) et ses propres voisins ; l'app mène la
tournée et décode. Compiler, flasher (toujours par `outils/flasher.py`, qui
vérifie la carte), entrer dans le réseau Hue : voir
[`sonde/README.md`](sonde/README.md).

Pour entrer dans le réseau, la sonde a besoin de la clé de liaison du centre
de confiance Hue : elle n'entre jamais dans le dépôt
(`sonde/cle_hue.local.h`, ignoré par git).

## Confidentialité

- **Aucune donnée ne sort du réseau local.** L'app parle à la sonde par l'USB
  et au pont sur le réseau local, jamais par le nuage ni par un proxy. Son
  seul accès à Internet est la recherche des mises à jour (le flux de ce
  dépôt, puis le `.dmg` d'une version publiée).
- **La clé du pont** reste dans le trousseau du Mac (non synchronisée), et ne
  part qu'au pont vérifié.
- **Le relevé de Maison** ne quitte pas le Mac : il passe par la boucle locale
  (127.0.0.1), protégé par un jeton à usage unique. Le Passeur ne peut pas
  reconnaître l'app (ni App Group ni équipe commune) : un autre programme du
  Mac qui écouterait sur la boucle locale et l'ouvrirait pourrait recevoir ce
  relevé (noms, pièces, zones).
- **Le dépôt ne contient aucune vraie donnée** : noms, pièces, adresses, PAN,
  identifiants du réseau et identifiant du pont sont inventés. Ne sont jamais
  commités, et `.gitignore` les exclut : la clé de liaison Hue
  (`sonde/cle_hue.local.h`), le port et la MAC de la sonde
  (`outils/sonde.local.json`), les captures et journaux réels (`essais/`), et
  la liste des vrais identifiants (`garde.local.txt`), que `outils/garde.py`
  cherche dans les fichiers suivis à chaque `sh outils/tester.sh`.

## Compiler et tester

Prérequis : macOS 26 ou ultérieur, Xcode 26 ou ultérieur,
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) ;
pour la sonde, [PlatformIO](https://platformio.org). Une dépendance, Sparkle 2
(2.10.0), par le gestionnaire de paquets Swift. Le projet Xcode est généré :
seul `project.yml` est suivi.

```sh
sh outils/tester-app.sh                                 # générer, compiler, tous les tests de l'app
sh outils/tester-app.sh MaillageCoeurTests/TourneeTests # une suite
sh outils/tester.sh                                     # tests hôte de la sonde, outils Python, garde des identifiants
sh outils/mesurer.sh                                    # temps de calcul de la vue par pièces, en Release
```

Les produits de compilation vont dans
`~/Library/Developer/Xcode/DerivedData/maillage-zigbee` (`DD` pour en
changer). Swift 6 en concurrence stricte complète, avertissements traités
comme des erreurs.

### Mode démo

```sh
open "…/Maillage Zigbee.app" --args -demo
open "…/Maillage Zigbee.app" --args -demo -captures ~/Library/Containers/fr.djoko.maillage.zigbee/Data/tmp/captures
```

La démo est un faux réseau Hue (un pont, douze lampes et prises, sept
appareils finaux, la sonde, un routeur que le pont ne connaît pas) et un faux
relevé de Maison (quatre étages, quelques noms différents de ceux du pont,
pour montrer le rapprochement) : rien n'est lu, écrit ni notifié, et le
Passeur n'est jamais lancé. Avec `-captures <dossier>` (dans le conteneur de
l'app, qui est dans le bac à sable), l'app écrit des images de la vue par
pièces et de Réglages, Pont Hue et Maison, puis quitte ; les images de cette page en
viennent.

### Signature

`Signature.xcconfig` (suivi) signe ad hoc : le dépôt compile et se teste
partout, sans compte Apple, mais l'autorisation « réseau local » ne tient pas
d'une compilation à l'autre. Pour signer avec son équipe, créer
`Local.xcconfig` (ignoré par git) :

```
DEVELOPMENT_TEAM = <équipe, 10 caractères>
CODE_SIGN_IDENTITY = Apple Development
```

### Publier une version

`outils/publier.sh X.Y.Z` publie la version X.Y.Z, le `MARKETING_VERSION` de
`project.yml`, depuis un `main` à jour : tous les tests, une compilation
Release signée par le certificat `Djoko-cli Code Signing`, un `.dmg` avec
l'app et la licence de Sparkle, le contrôle d'anonymisation privé, la
signature Ed25519 du `.dmg` (clé du trousseau), la version publiée sur GitHub
(étiquette `app-vX.Y.Z`) et le flux des mises à jour, `appcast.xml`, commité
sur `main`. Les notes viennent de [`NOTES-VERSIONS.md`](NOTES-VERSIONS.md).
`--repetition` fait de même sans GitHub, pour un essai local. Le détail est en
tête de `outils/publier.sh` et `outils/publication.py` ; les tests dans
`outils/test/`.

### Textes : français et anglais

Le français est la langue de développement (les clés des catalogues sont les
textes français), l'anglais est complet. Après avoir changé un texte :
compiler, puis `sh outils/synchroniser-textes.sh`, puis
`python3 outils/traduire.py MaillageZigbee/Ressources/Localizable.xcstrings outils/traductions/interface.json`.

## Code

| Dossier | Rôle |
|---|---|
| `MaillageCoeur/` | cadre sans interface, testé : le modèle Zigbee (`Zigbee/` : nœuds, liens radio, parents, chemins vers le pont, tournée et budget de pages, parents connus), le protocole de la sonde (`Sonde/`), l'API v2 de Hue et le certificat du pont (`Pont/`), suivi, journal et historique (`Suivi/`, `Journal/`, `Maillage/`), noms, relevé de Maison et rapprochement avec le pont (`Noms/`), la vue par pièces sans interface (`Scene/`), la démo (`Demo/`) |
| `MaillageZigbee/` | l'app : pont (`Pont/` : Bonjour, HTTPS vérifié, trousseau), Passeur (`Noms/` : écoute sur la boucle locale, relevé de Maison), sonde (`Sonde/` : port série, USB, tournées), surveillance, notifications, mises à jour (`Surveillance/`), barre des menus, vue par pièces, journal et réglages (`Vues/`) |
| `sonde/` | firmware de la sonde (ESP32-C6, PlatformIO) et ses tests hôte |
| `outils/` | tests, publication, textes, outils d'essai et de flash de la sonde, garde des identifiants, essai d'écoute passive du 5 octobre 2026 (`ecoute/`) |
| `docs/superpowers/` | conception (specs) et plans |

## Crédits

- Le logo Zigbee de l'icône de la barre des menus et de l'icône de l'app est
  dessiné d'après l'icône « Zigbee » de [SVG Repo](https://www.svgrepo.com),
  elle-même d'après [Simple Icons](https://simpleicons.org) (CC0). Zigbee est
  une marque déposée de la Connectivity Standards Alliance ; ce projet n'est
  lié ni à elle, ni à Signify (Philips Hue).
- L'app intègre [Sparkle](https://sparkle-project.org) 2.10.0 (mises à jour
  automatiques), sous licence MIT ; le texte de la licence est livré dans le
  `.dmg`, à côté de l'app (`Sparkle-LICENSE.txt`, aussi dans `outils/`).
- L'app dérive de [Maillage Thread](https://github.com/Djoko-cli/maillage-thread),
  dont elle reprend la vue par pièces, le journal, l'historique, la liaison
  USB, les mises à jour et le côté app de Passeur Noms.
