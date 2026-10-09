# Release notes · Notes de version

Maillage Zigbee: one section per published version, in English then in French. `outils/publier.sh` takes from it
the notes of the GitHub release and those of the update window.

Maillage Zigbee : une section par version publiée, en anglais puis en français. `outils/publier.sh` en tire les
notes de la version publiée sur GitHub et celles de la fenêtre de mise à jour.

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
- Mises à jour automatiques (Sparkle 2) : recherche au démarrage puis toutes les 24 heures, téléchargement et
  installation à la fermeture de l'app, ou tout de suite par « Installer et relancer ». « Rechercher les mises à
  jour… » est dans le menu ; Réglages, Général, « Mises à jour », permet de les arrêter.
