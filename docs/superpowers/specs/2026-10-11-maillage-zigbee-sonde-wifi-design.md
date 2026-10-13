# Maillage Zigbee : la sonde en Wi-Fi (sonde 1.1.0, app 1.1.0)

> **Statut : conception validée** par Djoko le 11/10/2026, en chat, section
> par section ; spec écrite à relire avant le plan (voie complète : nouveau
> sous-système, sonde et app).
>
> **Base :** sonde 1.0.0 (`docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md`),
> app 1.0.0 (`docs/superpowers/specs/2026-10-08-maillage-zigbee-app-design.md`).
> Enveloppe H1 reprise du pont Halo (dépôt benq : `src/h1_proto.*`,
> `src/h1_crypto.cpp`, `tools/host_tests/test_h1.cpp`,
> `apps/macos/HaloProtocole/Reseau/EnveloppeH1.swift`,
> `apps/macos/HaloProtocole/Session/MoteurSession.swift`). Clé et liste
> blanche sur le modèle de la sonde de Maillage Thread
> (`2026-09-28-maillage-thread-sonde-design.md`, section 3 bis).
>
> **Valeurs.** Toutes les adresses, tous les noms de réseau, mots de passe,
> clés et identifiants de ce document et du code sont **inventés** ; la garde
> (`outils/garde.py`) passe avant chaque commit.

## 1. But et périmètre

La sonde vit sur un chargeur mural, loin du Mac, et l'app la trouve et
l'interroge par le réseau local, avec la même tournée et le même résultat
qu'en USB. L'USB reste le chemin de la mise en service et du dépannage.

Décisions de Djoko :

- Wi-Fi plutôt que BLE (06/10) ; 2,4 GHz (le C6 n'a pas de 5 GHz).
- Le même protocole en lignes JSON, sur TCP ; la sonde est trouvée par Bonjour.
- **Accès authentifié** (11/10) : clé créée par l'USB, trousseau du Mac,
  liste blanche à distance, comme Maillage Thread.
- **Wi-Fi configuré par l'USB depuis l'app** (11/10), gardé par la sonde ; le
  firmware ne contient aucun secret. (Remplace le « fichier local ajouté à la
  garde » du 06/10.)
- **Chemin choisi automatiquement**, avec un réglage manuel (11/10).
- **Approche A** (11/10) : TCP + enveloppe H1, une ligne par message.
  L'approche B (TLS-PSK, chiffrée) est au backlog, commune à Halo, Maillage
  Thread et Maillage Zigbee.

Hors champ : chiffrement des échanges (backlog), mise à jour du firmware par le
réseau, plusieurs sondes, plusieurs Mac en même temps au-delà des deux sessions
H1.

## 2. Ce que les essais ont établi (09-11/10, branche jetable `essai-wifi`)

1. **Après la pile 802.15.4, une réinitialisation par l'USB (RTS, chaque
   flash) ou logicielle laisse la radio sans réception Wi-Fi** (scan à 0,
   écoute brute à 0 trame) ; seules une mise sous tension ou un sommeil
   profond l'effacent. Contre-épreuve propre le 10/10. Contournement : au tout
   début du démarrage, si `esp_reset_reason()` n'est ni `ESP_RST_POWERON` ni
   `ESP_RST_DEEPSLEEP`, sommeil profond de 0,2 s.
2. **Cohabitation :** `esp_coex_wifi_i154_enable()`, Wi-Fi connecté **avant**
   la pile Zigbee, puis `esp_wifi_set_ps(WIFI_PS_MIN_MODEM)`, comme l'exemple
   `esp_zigbee_gateway` d'Espressif ; sans cela, « point d'accès introuvable »
   en boucle une fois le Zigbee lancé.
3. **Envoyer la réponse par le Wi-Fi avant que la requête suivante parte** :
   nuit du 11/10, 1224/1224 tables, 2,1 pertes de parent par tournée avec un
   parent faible (LQI ≈ 55), contre 3,1 avec une recopie concurrente de jour
   (parent LQI ≈ 209) et 1,2 en USB seul (E6). Le protocole requête/réponse
   par le réseau donne cet ordre de lui-même : l'app n'envoie la requête
   suivante qu'après avoir reçu la réponse.
4. Le transport n'a perdu aucune ligne mesurable pendant 17 h d'essais.

## 3. La sonde (firmware 1.1.0)

### 3.1 Un seul firmware, Wi-Fi facultatif

Sans Wi-Fi configuré, la sonde 1.1.0 se comporte exactement comme la 1.0.0 :
ni Wi-Fi, ni cohabitation, ni sommeil au démarrage. La liste des commandes USB
de la 1.0.0 est inchangée ; les nouvelles s'y ajoutent (3.5).

### 3.2 Démarrage, Wi-Fi configuré

1. Sommeil profond de 0,2 s si la raison du démarrage n'est ni une mise sous
   tension ni un réveil (2.1).
2. `esp_coex_wifi_i154_enable()`, Wi-Fi en station, connexion attendue 15 s
   au plus.
3. `WIFI_PS_MIN_MODEM`, puis démarrage de la pile Zigbee.
4. Wi-Fi absent ou refusé : la pile Zigbee démarre quand même ; le Wi-Fi se
   reconnecte seul ensuite (reconnexion automatique), la cause est dans `etat`.

### 3.3 Réseau

- Serveur TCP sur le port fixe **5481**, IPv4.
- Annonce Bonjour (mDNS) : service `_maillage-zigbee._tcp`, nom d'instance =
  nom de la sonde (celui de `bonjour`), TXT `v=1` seulement.
- Une ligne TCP = un message H1, terminé par LF ; 4 200 octets au plus
  (une ligne de la sonde fait 4 095 octets au plus, plus l'en-tête H1 et le
  rid). Une ligne plus longue ferme la connexion.
- **Enveloppe H1** du pont Halo, inchangée dans ses règles (textes canoniques,
  `SALUT`/`DEFI`, clé de session, fenêtre anti-rejeu de 32 par sens, 2 sessions
  établies et 1 provisoire, 2 DEFI par seconde au total, comparaisons en temps
  constant), portée du datagramme à la ligne : une session est liée à sa
  connexion TCP et tombe avec elle.
- **Requêtes :** `<rid> <commande>` (rid décimal, croissant, choisi par l'app),
  la commande étant le texte de l'USB sans fin de ligne. **Réponses :**
  `<rid> <ligne JSON>` (la ligne de l'USB sans RS ni LF). **Signaux** et
  autres lignes non sollicitées : rid `0`, envoyés à toutes les sessions
  établies.
- Une réponse ne part que vers le canal qui a posé la question (USB ou une
  session réseau). La règle « une seule requête réseau Zigbee à la fois »
  vaut tous canaux confondus : une seconde requête répond `occupee`.
- **Liste blanche à distance :** `bonjour`, `etat`, `voisins`, `table`,
  `routes`, `suspendre`, `reprendre`. Toute autre commande répond
  `{"v":1,"t":"erreur","erreur":"refuse"}`.
- Sans clé, ou avec une clé fausse, la sonde ne répond rien (ni `DEFI`, ni
  erreur).

### 3.4 Mémoire et partitions

Le firmware d'essai occupait déjà 96 % de la partition application
(1,26 Mo sur 1,31 Mo). La 1.1.0 utilise une table de partitions propre au
projet (`sonde/partitions.csv`) :

| Nom | Type | Adresse | Taille |
|---|---|---|---|
| nvs | data/nvs | 0x9000 | 0x5000 |
| otadata | data/ota | 0xE000 | 0x2000 |
| app0 | app/ota_0 | 0x10000 | 0x3DA000 |
| zb_storage | data/fat | 0x3EA000 | 0x4000 |
| zb_fct | data/fat | 0x3EE000 | 0x1000 |
| rcp_fw | data/spiffs | 0x3EF000 | 0x1000 |
| coredump | data/coredump | 0x3F0000 | 0x10000 |

`nvs`, `zb_storage` et `zb_fct` gardent leurs adresses : la sonde reste
membre du réseau Hue après le flash, sans effacement. La seconde partition
application et `spiffs` disparaissent (pas de mise à jour à distance, aucun
fichier). `board_upload.maximum_size` suit (0x3DA000).

### 3.5 Nouvelles commandes, USB seulement

- `wifi <NOM HEXA> <MOT DE PASSE HEXA> <id>` : nom de réseau (1 à 32 octets)
  et mot de passe (8 à 63 octets, ou vide pour un réseau ouvert), en
  hexadécimal majuscule pour passer les espaces et les caractères spéciaux.
  Gardés en NVS, jamais renvoyés. Réponse : `wifi`, puis la sonde redémarre
  pour appliquer (redémarrage logiciel, donc sommeil profond de 3.2 avant le
  Wi-Fi).
- `wifi` : `{"v":1,"t":"wifi","configure":true|false,"nom":"<NOM HEXA>"|null}`
  (le nom, jamais le mot de passe).
- `wifi efface` : oublie nom et mot de passe, redémarre en sonde USB seule.
- `cle nouvelle <64 HEXA> <id>` : l'app envoie 32 octets tirés au hasard ; la
  carte tire les siens, calcule `HMAC-SHA256(clé = aléa de l'app, message =
  aléa de la carte)`, la garde en NVS et la rend **une seule fois** :
  `{"v":1,"t":"cle","id":<id>,"cle":"<64 HEXA>","empreinte":"<8 HEXA>"}`.
  Une nouvelle clé remplace l'ancienne et ferme les sessions ouvertes.
- `cle` : empreinte (`null` sans clé) et compteurs du transport (sessions,
  lignes envoyées, refusées, connexions fermées).
- `cle efface` : oublie la clé, ferme les sessions.

### 3.6 `etat`

`etat` gagne un objet `reseau` (absent si le Wi-Fi n'est pas configuré) :
`{"connecte":true,"canal":6,"rssi":-58,"raison":0,"sessions":1,"envois":1234,"echecs":0,"reconnexions":2}`
— `raison` : dernière raison de déconnexion du Wi-Fi (`wifi_err_reason_t`,
0 : aucune). `bonjour` gagne `"reseau":true|false` (Wi-Fi configuré) et la
version passe à `1.1.0`.

### 3.7 Code

Nouveaux fichiers, purs et testés sur l'hôte autant que possible : `h1_proto`
et `h1_crypto` (repris du pont Halo), `reseau` (Wi-Fi, serveur TCP, Bonjour,
sessions), `canaux` (qui a posé la question, à qui va la réponse, liste
blanche), `config_wifi` (analyse et garde des commandes `wifi` et `cle`).
`main.cpp` reste l'aiguillage : il ne connaît que « une ligne arrive d'un
canal » et « une ligne part vers un canal ou vers tous ».

## 4. L'app (Maillage Zigbee 1.1.0)

### 4.1 Canal réseau

- `CanalReseau` implémente `CanalSonde` (ouvrir, envoyer, fermer), comme le
  canal série : connexion TCP par Network.framework, poignée de main H1,
  signature de chaque ligne (Swift de Halo repris, du datagramme à la ligne),
  ajout du rid à l'envoi, retrait à la réception. Il remonte les lignes JSON
  telles quelles : la logique de requête et la tournée ne changent pas.
- `SondeUSB` devient `Sonde` (elle ne sert plus seulement l'USB) ; pas d'autre
  changement de son interface.
- Les délais d'attente sont ceux de l'USB, plus 3 s par requête en réseau.

### 4.2 Découverte et choix du chemin

- Découverte par Bonjour (`_maillage-zigbee._tcp`), avec le navigateur et la
  résolution DNS-SD déjà présents dans l'app pour le pont ; l'instance retenue
  est celle qui porte le nom de la sonde retenue.
- **Automatique** (par défaut) : la sonde retenue branchée en USB → USB ;
  sinon, clé présente dans le trousseau → réseau ; sinon, aucune sonde.
- Réglage **« Chemin de la sonde » : Automatique / USB seulement / Réseau
  seulement**.
- Le chemin en cours s'affiche dans Réglages › Sonde et dans l'état de la
  sonde : « USB », « Réseau », « Réseau — sonde injoignable ».
- Une connexion coupée se rouvre à la tournée suivante ; une coupure pendant
  une tournée fait échouer la requête en cours, que la tournée reprend une
  fois, comme une page perdue aujourd'hui.

### 4.3 Réglages › Sonde, « Accès par le réseau »

- Champs : nom du Wi-Fi, mot de passe (champ masqué).
- Bouton **« Autoriser l'accès réseau »**, qui devient **« Régénérer la clé »**
  une fois une clé créée ; actif seulement si la sonde retenue est branchée en
  USB, en version 1.1.0 ou plus, hors tournée. Il envoie `wifi …`, attend le
  redémarrage de la sonde, puis `cle nouvelle …`, vérifie l'empreinte et range
  la clé dans le trousseau.
- Trousseau : service `fr.djoko.maillage.zigbee.sonde`, compte = adresse
  longue de la sonde (`bonjour.ieee`), commentaire = empreinte. Jamais dans un
  journal, une préférence ou un fichier ; les tests n'utilisent jamais le vrai
  trousseau.
- Le mot de passe Wi-Fi n'est jamais gardé par l'app : il passe du champ à la
  sonde, puis le champ se vide.
- État du Wi-Fi de la sonde : connecté ou non, canal, signal (depuis
  `etat.reseau`).
- « Oublier la sonde » efface aussi la clé de ce Mac (la carte garde la
  sienne ; `cle efface` par l'USB l'efface côté carte).
- Sonde 1.0.0 : la partie est grisée, avec « Sonde 1.1.0 requise ».

### 4.4 macOS

`NSLocalNetworkUsageDescription` (français et anglais : trouver la sonde et
s'y connecter sur le réseau local) et `NSBonjourServices` avec
`_maillage-zigbee._tcp`, à côté du service du pont déjà déclaré.

## 5. Erreurs et sécurité

- Un Wi-Fi absent, faux ou injoignable ne bloque jamais le Zigbee ; `etat`
  le dit.
- Sans clé valable, la sonde se tait ; une commande hors liste blanche répond
  `refuse` ; `wifi`, `cle`, `nom`, `oubli` ne passent que par l'USB.
- La clé ne sort de la carte qu'une fois, par l'USB ; le mot de passe Wi-Fi
  jamais.
- Messages authentifiés, non chiffrés : la topologie circule en clair sur le
  réseau local, comme pour Maillage Thread (chiffrement : backlog).
- Dépôt public : valeurs inventées dans les tests et les exemples ; garde et
  contrôle d'anonymisation avant chaque push ; le hook `pre-push` vérifie
  l'identité des commits.

## 6. Tests

- **Sonde, sur l'hôte (`sonde/test/lancer.sh`) :** H1 par ligne (tests du pont
  Halo repris, plus découpage en lignes, ligne trop longue), commandes `wifi` et
  `cle` (hexa, longueurs, refus), liste blanche, routage des réponses par canal
  et diffusion des signaux.
- **App :** H1 en Swift (tests de Halo repris) ; `CanalReseau` sur un faux
  transport (poignée de main, rid, signaux, coupure, ligne trop longue) ; choix
  du chemin (les trois réglages, sonde branchée ou non, clé présente ou non) ;
  trousseau sur une fausse implémentation.
- **Outil :** `outils/sonde_reseau.py`, client H1 en Python (poignée de main,
  une commande, lecture des signaux), pour valider la sonde en réseau avant
  l'app ; la clé lui est donnée par une commande de terminal masquée, jamais
  dans le chat.
- **Banc avec Djoko :** (1) flash 1.1.0 sans effacement, la sonde reste
  membre ; (2) mise en service par l'USB depuis l'app ; (3) sonde sur chargeur
  mural, tournées par le réseau ; (4) une nuit de comparaison avec E6.

## 7. Découpage et livraison

Une spec, un plan en deux parties, chacune testable seule, relue puis passée
au banc :

1. **Sonde 1.1.0** et `outils/sonde_reseau.py`.
2. **App 1.1.0** : canal réseau, découverte, choix du chemin, Réglages.

Publication commune sonde 1.1.0 + app 1.1.0 ; notes de version en anglais
puis en français. La branche `essai-wifi` reste jetable : on en reprend les
idées, pas le code tel quel.
