# Release notes · Notes de version

Maillage Zigbee: one section per published version, in English then in French. `outils/publier.sh` takes from it
the notes of the GitHub release and those of the update window.

Maillage Zigbee : une section par version publiée, en anglais puis en français. `outils/publier.sh` en tire les
notes de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

## 1.2.0

**English**

- Maillage Zigbee is becoming Maillage IoT, a single app that brings Maillage Thread and Maillage Zigbee together.
  The menu now opens with a notice saying so, with a download link once Maillage IoT is published.
- New link in that notice, "Export for Maillage IoT…": a save panel asks where to write an export folder, which Maillage IoT
  reads to take over your data. The folder holds a manifest (with the size and SHA-256 of every file), a copy of the
  app's data (the journal and the whole mesh history included), and the settings worth keeping (probe, Hue bridge
  choice, notifications, views, and the page counts of the probe's last tables).
- Nothing secret is exported: neither the keys kept in the Mac's keychain (Hue bridge, probe) nor the Wi-Fi password.
  What the export leaves out (Sparkle settings, window positions, and any unknown file) is listed in the manifest.
- The export changes nothing in the app, which keeps working normally. It is written to a temporary folder, read back
  and checked file by file, and only then moved to the place you chose; if the check fails, nothing is written.
- Once the export is done, the app offers to stop opening Maillage Zigbee at login, so that the two apps do not
  compete for the USB probe when the Mac starts.

**Français**

- Maillage Zigbee devient Maillage IoT, une seule app qui réunit Maillage Thread et Maillage Zigbee. Le menu
  s'ouvre désormais sur une annonce en ce sens, avec un lien de téléchargement dès que Maillage IoT est publiée.
- Nouveau lien dans cette annonce, « Exporter pour Maillage IoT… » : un panneau d'enregistrement demande où écrire un dossier
  d'export, que Maillage IoT lit pour reprendre vos données. Le dossier contient un manifeste (avec la taille et le
  SHA-256 de chaque fichier), une copie des données de l'app (le journal et tout l'historique du maillage compris) et
  les réglages utiles (sonde, choix du pont Hue, notifications, vues, et le nombre de pages des dernières tables de la sonde).
- Rien de secret n'est exporté : ni les clés gardées dans le trousseau du Mac (pont Hue, sonde), ni le mot de passe du
  Wi-Fi. Ce que l'export laisse de côté (réglages de Sparkle, positions des fenêtres, fichiers inconnus) est listé dans
  le manifeste.
- L'export ne modifie rien dans l'app, qui continue de marcher normalement. Il est écrit dans un dossier temporaire,
  relu et vérifié fichier par fichier, puis seulement déplacé à l'endroit choisi ; si la vérification échoue, rien
  n'est écrit.
- Une fois l'export fait, l'app propose de ne plus ouvrir Maillage Zigbee à l'ouverture de session, pour que les deux
  apps ne se disputent pas la sonde USB au démarrage du Mac.

## 1.1.1

**English**

- Home names are now served continuously by the Passeur Noms daemon (installed by Maillage Thread): the app
  subscribes to it at launch and receives the names, rooms and floors again as soon as they change in Home, with
  no more reading to wait for. It reconnects by itself if the daemon quits or restarts.
- The names follow Home's tiles: a device with a single tile takes the tile's name, a device with several tiles
  takes the accessory's name.
- New setting, Settings, Home: "Open Passeur Noms at login", with the daemon's state and a reminder 30 days before
  its profile expires.
- "Identify via Home" on the node card: the device blinks through Home, next to the existing "Identify" through the
  Hue bridge. It is greyed out for a device not found in Home, or while the daemon is not connected.
- Home names are matched to the Hue bridge devices more tolerantly: punctuation (parentheses, dashes) and small
  linking words ("de", "du", "la"…) no longer prevent a match, as long as it stays unambiguous. Pairings found by
  name are remembered (not those found only by room and model), so renaming a tile in Home no longer loses them.
- The old iOS Passeur (the "designed for iPad" app) is no longer used: Maillage Thread's `outils/passeur.sh`
  installs the daemon instead. If the old one is the only one present, the app says so.
- Needs the Passeur Noms daemon of Maillage Thread 1.3.0 or later (`outils/passeur.sh`); without it, the app keeps
  the Hue app names.

**Français**

- Les noms de Maison sont désormais servis en continu par le démon Passeur Noms (installé par Maillage Thread) :
  l'app s'y abonne au lancement et reçoit de nouveau les noms, pièces et étages dès qu'ils changent dans Maison,
  sans relevé à attendre. Elle se reconnecte seule si le démon se ferme ou redémarre.
- Les noms suivent les tuiles de Maison : un appareil à une seule tuile prend le nom de la tuile, un appareil à
  plusieurs tuiles prend le nom de l'accessoire.
- Nouveau réglage, Réglages, Maison : « Ouvrir Passeur Noms à l'ouverture de session », avec l'état du démon et un
  rappel 30 jours avant l'expiration de son profil.
- « Identifier par Maison » dans la fiche d'un nœud : l'appareil clignote par Maison, à côté de « Identifier » par
  le pont Hue qui reste. Le bouton est grisé pour un appareil non retrouvé dans Maison, ou tant que le démon n'est
  pas connecté.
- Les noms de Maison sont rapprochés des appareils du pont Hue plus souplement : la ponctuation (parenthèses,
  tirets) et les petits mots de liaison (« de », « du », « la »…) n'empêchent plus l'appariement, tant qu'il reste
  sans ambiguïté. Les appariements trouvés par le nom sont mémorisés (pas ceux trouvés seulement par la pièce et le
  modèle) : renommer une tuile dans Maison ne les fait plus perdre.
- L'ancien Passeur iOS (l'app « conçue pour iPad ») n'est plus utilisé : c'est `outils/passeur.sh` de Maillage
  Thread qui installe le démon. Si l'ancien est le seul présent, l'app l'indique.
- Il faut le démon Passeur Noms de Maillage Thread 1.3.0 ou plus récent (`outils/passeur.sh`) ; sans lui, l'app
  garde les noms de l'app Hue.

## 1.1.0

**English**

- Signed with an Apple Developer ID and notarized by Apple: a fresh download opens without going through System
  Settings, Privacy & Security, "Open Anyway".
- Updating from 1.0.0: at the first launch of 1.1.0, macOS says the app differs from the versions opened before
  and asks whether to open it; choose "Open Anyway". Only once: the Hue bridge key in the keychain and the
  settings are kept. macOS may also ask again for local network access (the probe and the Hue bridge): allow it.
- The probe can live on a wall charger: the app queries it over Wi-Fi, on the local network, found by Bonjour.
  This needs probe firmware 1.1.0, flashed over USB (the probe stays a member of the Hue network).
- Setup over USB in Settings, Probe: the Wi-Fi name and password go straight to the probe and are not kept by the
  app; the probe creates an access key, which stays in the Mac's keychain. "Regenerate a key" with the password
  left empty keeps the probe's Wi-Fi.
- Probe link: Automatic (USB when the probe is plugged in, otherwise Wi-Fi), USB, or Wi-Fi.
- The exchanges over Wi-Fi are signed with that key, not encrypted; the probe refuses there the setup, the Wi-Fi
  and leaving the Zigbee network, which stay on USB. Without Wi-Fi, the probe still answers over USB right away.
- The probe's LED is the one shared by the boards: a rainbow while the Hue app identifies it, two blues off its
  network (fast blinking if it never joined, a slow pulse while it rejoins), slow orange when its Wi-Fi is
  configured but not connected, and a faint glow at rest.
- In the room view, the probe is drawn with waves on each side of its dot.
- A 1.0.0 probe keeps working over USB.
- At launch, the app shows the last known mesh again, with "Incomplete mesh" until the next pass completes it.

**Français**

- Signée par un Developer ID d'Apple et notarisée par Apple : une app fraîchement téléchargée s'ouvre sans passer
  par Réglages Système, Confidentialité et sécurité, « Ouvrir quand même ».
- Depuis la 1.0.0 : au premier lancement de la 1.1.0, macOS dit que l'app diffère des versions ouvertes jusque-là
  et demande s'il faut l'ouvrir ; choisir « Ouvrir quand même ». Une seule fois : la clé du pont Hue, dans le
  trousseau, et les réglages sont gardés. macOS peut aussi redemander l'accès au réseau local (la sonde et le pont
  Hue) : l'autoriser.
- La sonde peut vivre sur un chargeur mural : l'app l'interroge par le Wi-Fi, sur le réseau local, trouvée par
  Bonjour. Il faut le firmware de sonde 1.1.0, à flasher par l'USB (la sonde reste membre du réseau Hue).
- Mise en service par l'USB dans Réglages, Sonde : le nom et le mot de passe du Wi-Fi vont directement à la sonde
  et l'app ne les garde pas ; la sonde crée une clé d'accès, rangée dans le trousseau du Mac. « Régénérer une
  clé » avec le mot de passe laissé vide garde le Wi-Fi de la sonde.
- Liaison de la sonde : Automatique (l'USB quand elle est branchée, le Wi-Fi sinon), USB, ou Wi-Fi.
- Les échanges par le Wi-Fi sont signés avec cette clé, non chiffrés ; la sonde y refuse la mise en service, le
  Wi-Fi et l'oubli du réseau Zigbee, qui restent sur l'USB. Sans Wi-Fi, la sonde répond quand même tout de suite
  par l'USB.
- Le voyant de la sonde est celui commun aux cartes : arc-en-ciel quand l'app Hue l'identifie, deux bleus hors de
  son réseau (clignotement rapide si elle n'y est jamais entrée, pulsation lente pendant un rattachement), orange
  lent quand son Wi-Fi est configuré mais pas connecté, et une lueur au repos.
- Dans la vue par pièces, la sonde est dessinée avec des ondes de part et d'autre de sa pastille.
- Une sonde 1.0.0 reste servie par l'USB.
- Au lancement, l'app réaffiche le dernier maillage connu, avec « Maillage incomplet » jusqu'à ce que la passe
  suivante le complète.

## 1.0.0

**English**

- First published version: the menu bar app that shows the Zigbee mesh of a Philips Hue network, read by the
  probe (an ESP32-C6 end device, over USB) and named by the Home app and the Hue bridge; the room view in 2D and
  3D, the node card, the log of changes, 90 days of history with curves, and notifications.
- The Hue bridge is found by Bonjour (or by its address), linked once with its button, and read over HTTPS
  checked against Signify's authority; its key stays in the Mac's keychain. Nothing leaves the local network.
- The names, rooms and floors of the Home app, read by Passeur Noms and handed over the Mac's loopback with a
  one-time token: a device found in Home takes its Home name and room, the zones become the floors of the room
  view; the others keep their Hue app names.
- A round every 15 minutes, within a budget of 550 pages per 10 minutes kept across launches; the neighbor tables
  one round out of four, the routes of every router at each round, and a follow-up pass for the routes left over.
- The real paths to the bridge, read in the routing tables ("Links: paths"), and the heard neighbors of the
  selected node; a sleepy end device keeps its previous parent for 24 hours, drawn dotted.
- Focus: click a node and its path to the bridge, the devices that depend on it and, if you wish, its heard
  neighbors stay sharp while everything else fades. The node card lays out in four columns (identity, path,
  dependents, a summary of the heard neighbors), its history shows the links that matter in a wide band, and the
  log groups the path and parent changes of a device by hour, with the relays it went through.
- "Identify" on a node card makes the device blink, through the Hue bridge (never the probe).
- Automatic updates (Sparkle 2): a check at launch and then every 24 hours, download, and installation when the
  app quits, or right away with "Install and Relaunch". "Check for Updates…" is in the menu; Settings, General,
  "Updates", can turn them off.

**Français**

- Première version publiée : l'app de la barre des menus qui montre le maillage Zigbee d'un réseau Philips Hue, lu
  par la sonde (un ESP32-C6 appareil final, par l'USB) et nommé par Maison et le pont Hue ; la vue par pièces en 2D
  et en 3D, la fiche d'un nœud, le journal des changements, 90 jours d'historique avec leurs courbes, et les
  notifications.
- Le pont Hue est trouvé par Bonjour (ou par son adresse), lié une fois par son bouton, et lu en HTTPS vérifié
  par l'autorité de Signify ; sa clé reste dans le trousseau du Mac. Rien ne sort du réseau local.
- Les noms, pièces et étages de Maison, lus par Passeur Noms et remis par la boucle locale du Mac avec un jeton à
  usage unique : un appareil retrouvé dans Maison prend son nom et sa pièce de Maison, les zones deviennent les
  étages de la vue par pièces ; les autres gardent les noms de l'app Hue.
- Une tournée toutes les 15 minutes, dans un budget de 550 pages par 10 minutes gardé d'un lancement à l'autre ;
  les tables de voisins une tournée sur quatre, les routes de chaque routeur à chaque tournée, et une passe
  complémentaire pour les routes restées en attente.
- Les vrais chemins vers le pont, lus dans les tables de routage (« Liens : chemins »), et les voisins entendus du
  nœud choisi ; un appareil final endormi garde son parent d'avant pendant 24 heures, tracé en pointillé.
- Le focus : un clic sur un nœud garde nets son chemin jusqu'au pont, les appareils qui dépendent de lui et, au
  choix, ses voisins entendus, et estompe tout le reste. La fiche d'un nœud se range en quatre colonnes
  (identité, chemin, dépendants, résumé des voisins entendus), son historique montre les liens qui comptent dans
  une large bande, et le journal regroupe par heure les changements de chemin et de parent d'un appareil, avec les
  relais par lesquels il est passé.
- « Identifier », dans la fiche d'un nœud, fait clignoter l'appareil, par le pont Hue (jamais par la sonde).
- Mises à jour automatiques (Sparkle 2) : recherche au démarrage puis toutes les 24 heures, téléchargement et
  installation à la fermeture de l'app, ou tout de suite par « Installer et relancer ». « Rechercher les mises à
  jour… » est dans le menu ; Réglages, Général, « Mises à jour », permet de les arrêter.
