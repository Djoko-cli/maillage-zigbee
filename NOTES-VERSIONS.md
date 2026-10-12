# Release notes · Notes de version

Maillage Zigbee: one section per published version, in English then in French. `outils/publier.sh` takes from it
the notes of the GitHub release and those of the update window.

Maillage Zigbee : une section par version publiée, en anglais puis en français. `outils/publier.sh` en tire les
notes de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

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
