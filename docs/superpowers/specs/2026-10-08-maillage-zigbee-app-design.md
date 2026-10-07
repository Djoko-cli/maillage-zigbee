# Maillage Zigbee : l'app (morceau 2), spec courte

> **Statut : validée** par Majid le 08/10/2026, en chat, avec la voie courte
> (prototype, relecture, banc, report sur `main`).
>
> **Base :** Maillage Thread **1.1.0** (étiquette `maillage-v1.1.0` du dépôt
> `Djoko-cli/maillage-thread`), copiée puis adaptée. La sonde est celle du
> morceau 1 (`docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md`,
> firmware 1.0.0).
>
> **Valeurs.** Toutes les adresses, tous les identifiants et tous les noms de
> ce document et du code sont **inventés** ; la garde (`outils/garde.py`)
> passe avant chaque commit.

## 1. Périmètre

La même app que Maillage Thread 1.1.0, pour le réseau Zigbee du pont Hue :
barre des menus, graphe 2D/3D par pièces, fiche d'un nœud, légende, journal,
historique de 90 jours et courbes, notifications, réglages, mises à jour
Sparkle. Les morceaux 2 (cœur), 3 (journal, historique) et 4 (vue 3D) prévus
au départ n'en font qu'un : l'interface existe.

Hors champ : la sonde en Wi-Fi (chantier à part, décidé le 06/10), l'écoute
passive, la fusion avec Maillage Thread.

## 2. Ce qu'on reprend de la 1.1.0

D'après l'inventaire de la 1.1.0 (≈ 17 800 lignes de Swift hors tests) :

- **copié tel quel** (≈ 6 800 lignes) : la scène et le moteur de la vue par
  pièces, le journal et l'historique en fichiers mensuels, les fichiers
  gardés, l'USB (ports, liaison série, découpage RS + JSON + LF), Sparkle,
  notifications, langue, ouverture à la connexion, navigateur Bonjour et
  résolution DNS-SD (pour trouver le pont) ;
- **adapté** (≈ 7 300 lignes, un tiers à changer) : fenêtre, fiche,
  légende, menu, réglages, protocole et gestion de la sonde, graphe, scène,
  événements, alertes, historique, noms ;
- **remplacé** (≈ 3 700 lignes Thread, ≈ 3 000 lignes neuves) : modèle de
  la tournée, tournée, `Surveillance`, démo ; nouveau client du pont Hue ;
- **retiré** (≈ 3 100 lignes) : Passeur et HomeKit, Matter, annonces DNS-SD,
  partitions, IPv6, Thread Route, transport UDP de la sonde. Le trousseau est
  gardé, pour la clé du pont.

## 3. Deux sources

- **La sonde, par l'USB** : le maillage (tables de voisins, routes).
- **Le pont Hue, par son API v2** : nom et pièce de chaque appareil, marque,
  modèle, pile ; son **adresse longue** (`zigbee_connectivity.mac_address`),
  clé de rapprochement avec la sonde ; son **état de connexion** vu par le
  pont (`connected`, `connectivity_issue`, `disconnected`,
  `unidirectional_incoming`), qui donne l'état affiché.

## 4. Le modèle

- **Un nœud = une adresse longue (IEEE)**, stable. L'adresse courte change
  au rattachement : jamais une clé (historique, surnoms, pièces choisies).
- **Rôles** : le coordinateur (pont, `0000`) au centre, avec la couronne ;
  les routeurs ; les appareils finaux ; la sonde, appareil final, avec un
  signe à elle.
- **Liens radio entre routeurs** : chaque routeur donne, dans sa table, le
  LQI de ce qu'il reçoit de chaque voisin ; un lien a donc deux sens. On
  affiche le pire des deux, et par sens la mesure la plus récente l'emporte
  (comme Thread). Conversion LQI (0..255) → qualité 0..3 à un seul endroit,
  seuils de départ à ajuster au banc : ≥ 170 bonne (3), 100..169 moyenne
  (2), 50..99 faible (1), < 50 très faible (0).
- **Liens parent** : un appareil final est « enfant » dans la table de son
  parent ; le LQI de cette entrée qualifie le lien.
- **Routes** : celles du pont seulement, dans la fiche d'un nœud (« vers le
  pont : via … »).
- **Pas d'étages** : Hue n'en a pas ; un seul plateau, que la vue sait déjà
  dessiner. Un appareil que le pont ne place pas (la sonde comprise) se
  range à la main (« Placer dans une pièce… »).

## 5. Le pont Hue

- Trouvé par Bonjour (`_hue._tcp`).
- Liaison une fois, depuis les Réglages : appui sur le bouton du pont ; la
  clé d'application va dans le trousseau.
- HTTPS **avec vérification** : certificat signé par l'autorité de Signify
  (certificat public intégré à l'app), nom commun = identifiant du pont.
  Jamais de certificat accepté sans vérification.
- Relu au lancement et toutes les 5 minutes ; le flux d'événements du pont
  pourra venir plus tard.

## 6. La tournée

- Toutes les **15 minutes** et au bouton Rafraîchir (une tournée prend
  ≈ 60 s et peut faire décrocher la sonde).
- En largeur depuis le pont : une `table` par routeur, puis `routes 0000`
  (≈ 470 pages, sous le plafond de 600 pages par 10 minutes de la sonde).
- Perte du parent tolérée : sur `non_membre`, la tournée attend le retour de
  la sonde, deux fois par table au plus (comme `outils/essai_sonde.py`).
- Sonde suspendue : pas de tournée, et aucun routeur ne passe pour muet.

## 7. Journal et alertes

Gardés : surveillance démarrée, veille du Mac, appareil nouveau, disparu ou
revenu (pont et tournée), routeur apparu ou disparu, changement de parent,
appareil sans parent. Retirés : partitions, préfixes, routeurs de bordure,
chef et BBR. Les notifications regroupent les pertes, comme Thread.

## 8. Identité

- Nom « Maillage Zigbee », identifiants d'app propres
  (`fr.djoko.maillage.zigbee`…), dossier `Application Support/Maillage Zigbee`.
- **Nouvelle paire de clés Sparkle** et flux `appcast.xml` dans ce dépôt
  (sinon les deux apps se mettraient à jour l'une avec l'autre).
- Démo refaite sur un faux réseau Hue.
- README et notes de version bilingues, anglais d'abord.
- Icône : maquette à part, choisie par Majid.
- L'outil de publication ne lit rien dans le dépôt de Maillage Thread.

## 9. Méthode

Voie courte : prototype dans une copie de travail, en quatre étapes qui
compilent chacune (1. copie renommée et allégée de Thread ; 2. pont Hue ;
3. sonde et tournée ; 4. journal, historique, démo), relecture par Opus,
banc avec Majid sur son réseau, report sur `main` en quelques commits,
relecture finale.
