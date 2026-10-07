# Maillage Zigbee : conception de la sonde (morceau 1)

> **Statut : conception validée** par Majid le 05/10/2026, section par
> section (1 à 6). Un essai sur la carte ouvre le plan d'implémentation
> (section 4) ; ses résultats iront dans la section 8.
>
> **Plan :** `docs/superpowers/plans/2026-10-05-maillage-zigbee-plan1-sonde.md`,
> exécuté ; sonde 1.0.0 (variante et commandes retenues : section 8).
>
> **Révision du 07/10 après l'essai (section 8).**
> - la sonde reste **appareil final, point d'accès On/Off Light** ; le repli
>   en routeur et la lampe variable sont retirés : la sonde ne sera jamais
>   routeur, elle ne relaie le trafic de personne (décision de Majid) ;
> - `routes` est gardée (E4), avec 255 places par table (section 2) ;
> - `echecs` est retirée (E5 : les lampes Hue ne répondent pas) ;
> - les lignes `signal` sont gardées, pour le journal de l'app ;
> - la perte du parent pendant une tournée est un fait connu (section 8).
>
> **Révision du 05/10 en écrivant le plan.** Le code a été écrit, compilé et
> relu (modèle le plus fort) avant le plan ; la relecture a changé :
> - le délai par page : de 500 à 5000 ms, car la pile Zigbee borne
>   elle-même une requête ZDO à 5 s (section 2) ;
> - les cibles : jamais une adresse de diffusion (sections 2 et 3) ;
> - le rattachement : la sonde n'oublie jamais le réseau d'elle-même, et
>   `etat` compte les rattachements échoués (sections 2 et 6) ;
> - `oubli`, qui répond tout de suite puis redémarre (section 2) ;
> - les lignes `signal`, une par signal de la pile, pendant l'essai
>   (section 2) ;
> - la recherche : jamais relancée quand la sonde est déjà rattachée, sinon
>   la pile ouvrirait le réseau Hue (section 3) ;
> - le flash : la carte est vérifiée d'abord par son numéro de série USB,
>   sans la toucher (section 5) ;
> - l'essai : il vérifie aussi le réseau rejoint (E1) et la perte du parent
>   (E7) (section 4).
>
> **Valeurs.** Toutes les adresses, tous les identifiants et tous les noms de
> ce document sont **inventés** (section 5). Les vrais identifiants du réseau
> de Majid ne sont jamais écrits dans le dépôt.

## 0. Contexte, but, décisions

**Origine.** Maillage Thread (dépôt voisin `~/Dev/maillage-thread`) montre
le maillage Thread de Majid grâce à une sonde ESP32-C6 membre du réseau qui
interroge les routeurs. Le 05/10/2026, Majid demande la même chose pour son
réseau Zigbee, uniquement des produits Philips Hue, pilotés par un Hue
Bridge Pro (modèle `BSB003`).

**Le pont ne donne pas le maillage.** L'API Hue v2 n'expose, par appareil,
qu'un statut de connectivité (`connected`, `disconnected`,
`connectivity_issue`, `unidirectional_incoming`, `pending_discovery`) et
l'adresse MAC ; le service Zigbee du pont seul donne le canal et l'extended
PAN ID. Ni table de voisins, ni LQI, ni routes. MotionAware ne publie qu'un
état de santé par zone et par lampe, sans mesure du signal.

**Essai d'écoute passive du 05/10** (annexe A) : une carte en écoute pure
entend une bonne part du réseau, mais pas le pont depuis le bureau, et ni
les voisins ni les coûts des liens (chiffrés). D'où la voie retenue : une
sonde **membre** du réseau qui interroge chaque routeur.

**But du morceau 1.** Une sonde ESP32-C6, membre du réseau Hue, qui donne
par l'USB la table des voisins de n'importe quel routeur (adresse courte et
longue, type, relation, LQI), et sa propre table de voisins. Elle ne dessine
rien : l'app (morceau 2) orchestre la tournée, décode et affiche.

**Décisions de Majid (05/10) :**
- une **app dédiée**, « Maillage Zigbee » ; la fusion avec Maillage Thread
  sera un **chantier futur séparé** ;
- la **parité avec Maillage Thread** : graphe, fiche, journal, historique de
  90 jours et courbes, légende, vue des pièces en 3D. Le projet est découpé
  en quatre morceaux, chacun avec sa spec, son plan et sa mise en œuvre :
  1. **la sonde** (cette spec) ;
  2. **le cœur de l'app** : appairage au pont Hue (bouton du pont), appareils,
     noms et pièces lus dans l'API v2, tournée de la sonde, graphe, fiche,
     légende ;
  3. **le journal et l'historique** (90 jours, courbes) ;
  4. **la vue des pièces en 3D** ;
- le code de Maillage Thread est repris par **copie adaptée** dans ce dépôt,
  sans paquet commun. Une autre session anonymise en ce moment Maillage
  Thread : on n'écrit rien dans son dépôt, et on ne copie qu'après la fin de
  cette anonymisation ;
- la sonde **peut rejoindre le réseau Hue** ; si le pont refuse un appareil
  final, **repli accepté en lampe routeur** (inutile : E1 a réussi ; retiré
  le 07/10, la sonde ne sera jamais routeur) ;
- **une seule carte, membre** (voie A). L'écoute passive (voie B) pourra
  venir plus tard avec une deuxième carte ;
- **la sonde pagine, l'app orchestre** : l'app demande la table complète d'un
  routeur, la sonde enchaîne les pages et renvoie le tout.

## 1. La sonde dans le réseau Hue (validée)

**La carte.** Un ESP32-C6 SuperMini (flash de 4 Mo) désigné par Majid, le
même que pour l'essai d'écoute. Sa MAC est notée hors du dépôt
(`outils/sonde.local.json`, section 5). La sonde est branchée **en USB sur
le Mac seulement** : pas d'accès par le réseau. Son emplacement compte peu,
car les requêtes passent par le maillage ; il lui suffit d'un parent à
portée.

**Son identité Zigbee.**
- **Appareil final non endormi** (`rx_on_when_idle`) : il reçoit en
  permanence et ne relaie rien.
- Un point d'accès « lampe » (endpoint 11, profil Home Automation), la
  condition pour que le pont l'accepte : On/Off Light (`0x0100`), acceptée
  par le pont à l'essai E1.
- Grappes serveur : Basic, Identify, Groups, Scenes, On/Off.
- Basic : fabricant « Maillage », modèle « sonde-zigbee », alimentation
  secteur. Version d'appareil du point d'accès `app_device_version = 1`
  (exigée par le pont Hue, constatée par d'autres avant nous).
- **Jamais routeur** : le repli en routeur prévu si le pont refusait un
  appareil final n'a pas servi (E1), et il est retiré (Majid, 07/10). La
  sonde ne relaie le trafic de personne.

**L'adhésion.**
- La clé de liaison du centre de confiance de Hue (clé ZLL de Signify) est
  publique, mais elle n'entre **jamais dans le dépôt** : elle vit dans
  `sonde/cle_hue.local.h`, ignoré par git. Sans ce fichier, la compilation
  échoue avec un message clair. La sonde la pose par
  `esp_zb_secur_TC_standard_distributed_key_set()` avant de chercher.
- Tant qu'elle n'est pas membre, la sonde cherche un réseau (BDB *network
  steering*) toutes les 30 s. Majid lance « Ajouter des lampes » dans l'app
  Hue ; le pont ouvre son réseau et la sonde le rejoint.
- Elle garde ensuite le réseau en mémoire et s'y rattache seule après un
  redémarrage. La commande USB `oubli` la fait quitter le réseau proprement
  (section 2).

**Dans l'app Hue,** elle apparaît comme une lampe ; Majid la nomme « Sonde
maillage » et la laisse hors de toute pièce.
- **La lampe Hue ne pilote que la LED** : on/off et clignotement
  d'identification, pour reconnaître la carte. Elle ne suspend jamais la
  sonde : « Tout éteindre », une automatisation de départ ou une scène
  globale la suspendraient sinon à l'insu de Majid. C'est un écart voulu
  avec la sonde Thread, dont l'interrupteur de Maison suspend la sonde.
- La **suspension** passe par l'USB (`suspendre`, `reprendre`), depuis les
  Réglages de l'app (morceau 2).

**La LED** (WS2812 sur IO8, faible intensité). Par ordre de priorité :
1. clignotement d'identification demandé par l'app Hue (grappe Identify) ;
2. pulsation bleue lente tant que la sonde cherche un réseau ou se
   rattache ;
3. deux éclairs verts rapides à l'adhésion ;
4. un bref éclair orange toutes les 5 s tant qu'elle est suspendue, aussi
   après un redémarrage ;
5. sinon, l'état on/off de la lampe Hue : blanc très faible ou éteinte.

Seule la boucle principale pilote la LED, d'après des drapeaux : jamais
depuis un rappel de la pile Zigbee (leçon de la sonde Thread).

## 2. Protocole USB (validée)

**Trame.** Celle de la sonde Thread et du pont Halo : RS (`0x1E`), JSON
compact, fin de ligne ; ASCII imprimable seulement ; 4096 octets au plus, RS
compris et fin de ligne non comprise (le firmware n'en émet jamais plus de
4095, RS et fin de ligne compris) ; `v` (version, 1) et `t` (type) en tête.
La ligne machine est retrouvée au dernier RS de la ligne ; ce qui le précède
est abandonné. À l'ouverture du port, régler DTR et RTS **d'un seul coup**,
sinon le C6 peut redémarrer.

**Produit `sonde-zigbee`.** `bonjour` le donne toujours. Maillage Thread
attend `sonde-maillage` et refuse donc cette sonde ; Maillage Zigbee refuse
la sonde Thread.

**Formats.** Adresse courte : 4 hexa en majuscules, sans `0x` (`1A2B`).
Adresse longue : 16 hexa en majuscules, octet de poids fort d'abord
(`A000000000000001`). `id` : entier décimal choisi par l'app ; les `id`
repartent de 1 à chaque connexion. Tout argument mal formé donne l'erreur
`syntaxe`, comme une ligne de plus de 255 caractères.

**Commandes du Mac** (texte, une par ligne) :
- `bonjour` ;
- `nom <texte>` : 1 à 32 caractères parmi les lettres ASCII, les chiffres,
  `-`, `_` et `.` ; « SONDE-Z1 » par défaut ; réponse : un `bonjour` à jour,
  ou l'erreur `syntaxe` ou `ecriture` ;
- `etat` ;
- `voisins` ;
- `table <cible> <id> [<délai ms>]` : `<cible>` est l'adresse courte d'un
  appareil, jamais une adresse de diffusion (`FFF8` à `FFFF` : `syntaxe`) ;
  le délai, par page, va de 500 à 5000 ms, 5000 par défaut (la pile Zigbee
  borne elle-même une requête ZDO à 5 s : révision du 05/10) ;
- `routes <cible> <id> [<délai ms>]` : table de routage d'un routeur
  (`Mgmt_Rtg_req` en trame APS brute ; E4 réussi), mêmes règles que
  `table` ;
- `suspendre`, `reprendre` : réponse, un `etat` à jour ;
- `oubli` : la sonde répond `{"v":1,"t":"oubli","ok":true}`, quitte le
  réseau (*leave* sans rejoindre), efface sa mémoire Zigbee (la pile garde
  son compteur de trames), garde son nom, revient non suspendue, redémarre
  et se remet à chercher ; son `bonjour` de démarrage est le `bonjour` à
  jour. Une table en cours finit d'abord en `non_membre`.

Une commande inconnue reçoit `{"v":1,"t":"erreur","erreur":"inconnue"}`.

**Messages de la sonde** (valeurs inventées) :

- `bonjour` :
  `{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.0.0","nom":"SONDE-Z1","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false}`.
  `role` vaut `final` ; `null` si elle n'est pas membre. Au démarrage, `ieee` vaut `null` si la pile n'a pas démarré dans
  les 2 s ; le `bonjour` suivant le donne.
- `etat` :
  `{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":{"court":"1A2B","ieee":"A000000000000002","lqi":180,"rssi":-71},"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":false,"refus_cadence":0,"rattachements_echoues":0,"pile":"1.6.8"}`.
  `parent` vaut `null` hors adhésion ou pendant un rattachement. Hors adhésion, `court`, `pan`, `epid` et `canal` valent aussi
  `null`. `refus_cadence` compte les refus `cadence` depuis le démarrage
  (section 3) ; `rattachements_echoues`, les rattachements échoués depuis
  la dernière fois que la sonde était membre (section 6).
- `voisins` : la table de voisins de la sonde (`esp_zb_nwk_get_next_neighbor`),
  l'équivalent du « signal vu par la sonde » de Thread :
  `{"v":1,"t":"voisins","liste":[{"court":"1A2B","ieee":"A000000000000002","type":"routeur","relation":"parent","lqi":180,"rssi":-71,"cout_sortant":1,"age":0}],"suite":false}`.
- `table`, en cas de succès, sur une ou plusieurs lignes de même `id`, la
  dernière avec `"suite":false` :
  `{"v":1,"t":"table","id":7,"cible":"1A2B","ok":true,"ms":840,"pages":2,"total":3,"partielle":false,"liste":[{"court":"0000","ieee":"A000000000000003","type":"coordinateur","relation":"aucune","ecoute":true,"profondeur":0,"admission":false,"lqi":212},…],"suite":false}`.
  - `type` : `coordinateur`, `routeur`, `final` ou `inconnu` ;
  - `relation` : `parent`, `enfant`, `frere`, `aucune` ou `ancien_enfant`
    (un enfant pas encore authentifié compte comme `enfant`) ;
  - `ecoute` (récepteur allumé au repos) et `admission` (accepte des
    adhésions) : `true`, `false` ou `null` (inconnu) ;
  - `profondeur` et `lqi` : entiers, tels que la cible les donne ;
  - l'EPID de chaque entrée n'est pas repris : c'est celui du réseau,
    donné par `etat`.
- `table`, en cas d'échec : `"ok":false` et `"erreur"` valant `delai`,
  `suspendue`, `occupee`, `non_membre`, `cadence`, `envoi` ou `statut` (avec
  `"statut":"0x84"`, le code ZDO de la réponse). Les entrées déjà reçues ne
  sont pas renvoyées : l'app ne garde que des tables entières ou marquées
  `partielle`. Une table qui n'est pas `partielle` porte exactement `total`
  entrées : sinon, une ligne s'est perdue en route, et l'app la redemande.
  Une table en cours s'arrête en `non_membre` si la sonde quitte le réseau
  (perte du parent, départ, `oubli`).
- `routes` : même enveloppe que `table` ; une entrée :
  `{"destination":"3C4D","etat":"active","prochain":"1A2B","memoire_limitee":false,"plusieurs_vers_un":false,"enregistrement":false}`.
  Une table de routage donne toutes ses places, utilisées ou non : le pont
  Hue en annonce 254, dont une cinquantaine actives (`etat` dit lesquelles).
  La sonde garde jusqu'à 255 routes par table (64 voisins pour `table`).
- `etat`, `voisins` : si la sonde n'a pas pu prendre le verrou de la pile
  Zigbee (200 ms), `{"v":1,"t":"etat","erreur":"occupee"}` (de même pour
  `voisins`).
- `signal` (`SONDE_SIGNAUX`, gardé après l'essai pour le journal de l'app),
  de lui-même, pour chaque signal de la pile :
  `{"v":1,"t":"signal","signal":"0x32","nom":"NLME_STATUS_INDICATION","ok":true,"detail":9}`.
  `detail` : le statut NLME (`9`, parent perdu) ou le type de départ ; `0`
  sinon. L'app ignore les types qu'elle ne connaît pas.

**Pagination** (`table`) :
- la sonde envoie `Mgmt_Lqi_req` avec l'index de départ 0, puis l'index
  suivant tant que le total n'est pas atteint ;
- une page sans réponse dans le délai est redemandée **une fois** ; un
  second silence donne `delai` ;
- si le total annoncé change d'une page à l'autre, la sonde recommence au
  début **une fois** ; s'il change encore, elle renvoie ce qu'elle a avec
  `"partielle":true` ;
- une page vide alors que le total n'est pas atteint termine la table avec
  `"partielle":true` ;
- une table dure au plus 120 s, quelles que soient les pages : au-delà,
  `delai`. L'app attend donc au plus 125 s une réponse à `table`.

**Limites.**
- **Une seule table en cours à la fois** : une deuxième demande reçoit
  `occupee` sans attendre.
- `suspendue` : la sonde reste membre mais refuse `table` et `routes` ;
  `etat` et `voisins` restent permis.
- Lignes de 4 Ko au plus : une entrée de table fait environ 150 octets, une
  ligne en porte donc au plus 25 ; au-delà, `suite`.

**Choix du port** (rappel pour le morceau 2, repris de Maillage Thread) :
l'app n'ouvre aucun port qu'on ne lui a pas désigné, retient le numéro de
série USB, et refuse un port qui ne répond pas `"produit":"sonde-zigbee"` à
`bonjour`.

## 3. Comportement dans le réseau et garde-fous (validée)

**Liste blanche.** Le firmware n'émet, de lui-même ou sur commande, que :
- `Mgmt_Lqi_req` (ZDO `0x0031`) ;
- `Mgmt_Rtg_req` (ZDO `0x0032`), si l'essai E4 la valide ;
- `Mgmt_NWK_Update_req` (ZDO `0x0038`) **en balayage d'énergie seulement**,
  si l'essai E5 la valide (ci-dessous) ;
- ce que la pile émet d'elle-même pour rester membre : adhésion,
  rattachement, maintien auprès du parent, réponses aux lectures du pont sur
  ses propres grappes.

Jamais de commande ZCL vers un autre appareil (ni on/off, ni scène, ni
groupe), jamais de `Mgmt_Leave_req`, de `Mgmt_Permit_Joining_req`, de
liaison (*bind*), ni de changement de canal ou de gestionnaire du réseau, et
jamais vers une adresse de diffusion : chaque requête vise un seul appareil.
La voie APS brute, si on la garde, passe par la même liste blanche, vérifiée
avant chaque envoi.

**Jamais de recherche une fois rattachée.** Selon la norme BDB, un nœud déjà
membre qui lance une recherche diffuse un `Mgmt_Permit_Joining_req`, ce qui
ouvrirait le réseau Hue pendant 180 s : la sonde ne la lance jamais quand la
pile se dit rattachée.

**Volume attendu.** Une tournée complète : environ 30 routeurs × 10 pages,
soit près de 300 paires requête-réponse relayées sur un ou deux sauts, de
l'ordre de 1200 trames et 3,5 s de temps d'antenne. Une tournée toutes les
15 minutes ajoute environ 0,4 % d'occupation moyenne au canal (aujourd'hui
environ 9 %, Thread compris, annexe A). L'essai E3 mesure les vrais chiffres.

**Garde-fou de la sonde**, indépendant de l'app :
- au moins 100 ms entre deux pages envoyées ;
- au plus 600 pages par fenêtre glissante de 10 minutes (environ deux
  tournées complètes) ;
- au-delà, la demande est refusée en `cadence` sans rien émettre, et
  `refus_cadence` augmente.

**Cadence côté app** (proposée ici, décidée dans le morceau 2) : `etat` et
`voisins` toutes les 5 minutes (lectures locales, aucune trame radio) ; la
tournée complète toutes les 15 minutes et au bouton rafraîchir.

**Option : le taux d'échec par routeur** (`Mgmt_NWK_Update_req`).
- Avec un balayage d'énergie sur le seul canal courant et une durée 0, la
  réponse (`Mgmt_NWK_Update_notify`) donne les émissions totales et les
  échecs d'émission du routeur interrogé.
- Prix : le routeur reste sourd environ 31 ms pendant le balayage ; une
  trame qui lui arrive à ce moment est réémise, au pire perdue.
- Testé à l'essai E5 sur **une seule lampe, avec l'accord de Majid** : la
  lampe n'a pas répondu. **Retiré** de la sonde 1.0.0 (`SONDE_ECHECS=0`) ;
  le code reste, hors compilation.
- Les valeurs `scan_duration` `0xFE` (changement de canal) et `0xFF`
  (changement du gestionnaire) sont interdites par la liste blanche ; le
  masque de canaux est toujours le seul canal courant.

## 4. Essai, en tête du plan (validée)

Comme pour la sonde Thread, le plan commence par un essai sur la carte, avec
Majid. L'outil `outils/essai_sonde.py` pilote la sonde par l'USB et affiche
les résultats ; ses journaux vont dans `essais/` (ignoré par git).

| # | Ce qu'on vérifie | Réussi si |
|---|---|---|
| E1 | Adhésion en appareil final, point d'accès lampe | membre **du réseau Hue de Majid** (même PAN que l'essai d'écoute), visible dans l'app Hue, encore membre 30 min plus tard et après un redémarrage, sans *leave* du pont |
| E1 bis | Repli en lampe routeur, **seulement si E1 échoue** | mêmes critères |
| E2 | `table` sur le pont (`0000`) et sur 3 lampes | toutes les pages arrivent, le total concorde ; durée et LQI notés. Si le pont ne répond pas, ses voisins se déduisent des tables des lampes |
| E3 | Tournée complète, en largeur, depuis le pont | routeurs trouvés comparés au nombre de lampes de l'app Hue ; durée, pages, aucun refus `cadence` |
| E4 | `Mgmt_Rtg_req` en trame APS brute sur une lampe | une réponse lisible ; sinon, pas de commande `routes` |
| E5 | Taux d'échec (`Mgmt_NWK_Update_req`) sur une seule lampe, **avec l'accord de Majid** | compteurs vraisemblables, aucun effet visible sur la lampe ; puis décision ensemble |
| E6 | Une nuit, tournée toutes les 15 minutes | toujours membre au matin ; lampes normales ; l'app Hue ne signale rien d'anormal |
| E7 | Perte du parent, si Majid le veut : sa lampe parente coupée à l'interrupteur | la sonde se rattache à un autre routeur en moins de 2 minutes ; les lignes `signal` montrent ce que la pile a fait |

- Si E1 et E1 bis échouent tous les deux, on s'arrête et on en reparle avec
  Majid ; le repli naturel est l'écoute passive (voie B) sur la même carte,
  avec le code de `outils/ecoute/`.
- Rôle de Majid : lancer « Ajouter des lampes » dans l'app Hue, regarder
  l'app Hue et ses lampes, donner son accord pour E5.
- Les résultats vont dans la section 8, avec des valeurs inventées.

## 5. Dépôt, tests, données personnelles (validée)

**Le dépôt.** `~/Dev/maillage-zigbee`, à côté de Maillage Thread, hors de
`~/Documents` (synchronisé par iCloud, qui a déjà abîmé un dépôt). Il reste
**local** : rien n'est poussé tant que Majid n'a pas choisi entre public et
privé.

**Organisation** (morceau 1) :
- `sonde/` : le firmware, PlatformIO, même chaîne que la sonde Thread
  (pioarduino `55.03.312-1`, Arduino-ESP32 3.3.12, ESP-IDF 5.5.5,
  esp-zigbee-lib 1.6.8, esp-zboss-lib 1.6.4), avec la table de partitions
  Zigbee (`zb_storage`, `zb_fct`) ;
- `sonde/test/` : les tests hôte du firmware ;
- `outils/` : `essai_sonde.py` et ses tests ; `outils/ecoute/` : le code de
  l'essai d'écoute du 05/10 (firmware d'écoute, décodeur, capture, analyse),
  versé tel quel, **sans aucune capture** ;
- `docs/superpowers/specs/`, puis `docs/superpowers/plans/`.
- L'app (`MaillageZigbee/`, `MaillageZigbeeCoeur/`) arrive avec le
  morceau 2.

**Un firmware testable sur le Mac.** La logique vit dans des modules C++
purs, compilés et testés sur le Mac comme le `sonde/test` de la sonde
Thread : lecture des commandes, pagination (reprise sur changement du total,
nouvelle tentative), liste blanche, garde-fou de cadence, mise en trame JSON
(découpage et `suite`), états de la LED. La colle avec la pile Zigbee reste
mince ; l'essai la vérifie.

**Le flash.** Toujours sur le port désigné, et **avant d'écrire**, deux
vérifications : d'abord le numéro de série USB de l'appareil derrière le port
(`ioreg`, sans toucher la carte ; pour un C6, c'est sa MAC), puis, après la
compilation, la MAC lue par esptool. Les deux doivent être celle de
`outils/sonde.local.json` : l'outil refuse toute autre carte (pont Halo,
sonde Thread, carte témoin de benq : ce sont aussi des C6). Le premier flash
se fait avec effacement ; les suivants, sans, pour garder le réseau.

**Données personnelles, dès le premier commit.**
- Dans le code, les tests, les docs et les exemples : uniquement des valeurs
  inventées (adresses longues `A0000000000000xx`, adresses courtes, PAN,
  EPID, identifiant du pont, noms et pièces Hue).
- Ignorés par git : `sonde/cle_hue.local.h`, `outils/sonde.local.json`,
  `essais/`, `garde.local.txt`.
- **La garde**, lancée avec les tests : elle lit dans `garde.local.txt` la
  liste des vrais identifiants de Majid (un par ligne) et échoue si l'un
  d'eux apparaît dans un fichier suivi par git, sans tenir compte de la
  casse ni des séparateurs `:` et `0x`. Sans ce fichier, elle le dit et
  passe.

## 6. Pannes et reprises (validée)

- **Perte du parent** (lampe coupée à l'interrupteur) : la pile se rattache
  seule à un autre routeur ; entre-temps, `etat` montre `parent:null`,
  `table` répond `non_membre`, la LED pulse en bleu.
- **Pont éteint ou qui redémarre** : la sonde reste membre ; les requêtes
  échouent en `delai` ; rien d'autre.
- **Lampe « Sonde maillage » supprimée dans l'app Hue** : le pont envoie un
  *leave* ; la sonde efface sa mémoire Zigbee et se remet à chercher (LED
  bleue). C'est la façon propre de la retirer côté Hue, l'équivalent
  d'`oubli`.
- **Changement de la clé réseau par le pont** : la pile la reçoit
  normalement. Si la sonde la manque, elle tente un rattachement sécurisé.
  En cas d'échec, elle retente toutes les 30 s sans jamais oublier le réseau
  d'elle-même (une longue coupure du pont ne doit pas lui faire perdre son
  adhésion) ; `etat` compte les échecs (`rattachements_echoues`), et l'app
  propose alors `oubli`, puis « Ajouter des lampes » (révision du 05/10).
- **Signal de la pile perdu** (file pleine) : toutes les 10 s, la sonde
  demande à la pile si elle est rattachée, et rattrape une adhésion qu'aucun
  signal n'a annoncée.
- **Une lampe change d'adresse courte** : `table` échoue sur l'ancienne ;
  retrouver la nouvelle relève de l'app (morceau 2), qui suit chaque nœud
  par son adresse longue.
- **Pile occupée** : chaque commande prend le verrou de la pile 200 ms au
  plus, sinon `occupee`. Les rappels de la pile ne font que poser des
  drapeaux et remplir des files ; la boucle principale écrit sur l'USB et
  pilote la LED.
- **USB débranché** : la sonde continue de vivre dans le réseau ; l'app la
  retrouve à la reconnexion.
- **Redémarrage** : réseau, nom et état de suspension sont gardés.

## 7. Hors champ

- Les morceaux 2 à 4 (app, journal et historique, vue 3D), chacun avec sa
  spec.
- La voie B (écoute passive permanente sur une deuxième carte), qui
  ajouterait les réémissions par lien et, avec la clé réseau, les coûts des
  liens annoncés par les routeurs. La clé reste dans la sonde ; la sortir
  serait une décision à part.
- La fusion avec Maillage Thread.
- Pour le morceau 2 : avant toute tournée, l'app compare `etat.epid` à
  l'extended PAN ID que donne l'API Hue (la sonde rejoint tout réseau ouvert
  sur les canaux Hue) ; elle propose `oubli` après des rattachements
  échoués ; elle redemande une table incomplète.
- La copie du code de Maillage Thread, qui attend la fin de son
  anonymisation (section 0).

## 8. Résultats de l'essai

Essai du 06/10/2026 au 07/10/2026, sonde 0.9.0 puis correctifs, depuis le
bureau de Majid. Ordres de grandeur, sans identifiant (section 5).

| # | Résultat |
|---|---|
| E1 | **Réussi** du premier coup en appareil final, On/Off Light : canal et PAN du réseau Hue de l'essai d'écoute ; la lampe « On/off light 1 » apparaît dans l'app Hue et la LED de la carte la suit ; 30 min sans départ ; débranchée puis rebranchée, elle revient seule, sans recherche. E1 bis inutile |
| E2 | **Réussi** : la table du pont arrive entière, 25 voisins en 13 pages (2 par page), en 1,8 s. Le pont range chaque voisin en « frère », profondeur 15, sans « admission » : l'app s'en passe. LQI de 74 à 255 |
| E3 | **Réussi** : 36 routeurs interrogés, 36 réponses en 50 à 110 s ; 56 à 57 nœuds vus, dont 20 à 21 appareils finaux (34 nœuds connus après l'écoute passive) ; environ 450 pages par tournée ; aucun refus `cadence` |
| E4 | **Réussi** : `Mgmt_Rtg_req` en APS brute. La table du pont fait 254 entrées en 22 pages (2,6 s), dont une cinquantaine de routes actives vers une vingtaine de relais. Une lampe montre une route « plusieurs vers un » vers le pont |
| E5 | **Échoué, retiré** : la lampe interrogée (une seule, accord de Majid) n'a pas répondu dans les 5 s, deux fois. Sans doute réservé au gestionnaire du réseau. `echecs` est retirée |
| E6 | **Réussi** : 35 tournées, une toutes les 15 min, sur 8 h 30 (l'outil s'est arrêté à 2 h 36, sans doute avec l'app) ; 32 tournées complètes, 3 tables perdues sur environ 1260 (corrigé depuis côté outil) ; aucun redémarrage ; toujours membre au matin |
| E7 | **Vu sans le provoquer** : la pile déclare le parent perdu (statut NWK 9) pendant les tournées, environ une fois par tournée (43 en E6), toujours dans les 2 s suivant une requête, jamais au repos, sur une vingtaine de cibles différentes, alors que le lien avec le parent est bon (environ -46 dBm). La sonde se rattache seule au même parent en 10 s |

**Défauts trouvés et corrigés pendant l'essai.**
- `outils/flasher.py` téléversait avec `-t nobuild -t upload`, que
  pioarduino ne sait pas faire (aucune image transmise à esptool) :
  `-t upload`, sans recompiler puisque la compilation précède.
- La sortie USB est tamponnée : un redémarrage voulu (départ avec retour)
  perdait la ligne `signal` qui l'expliquait. La sonde la vide avant de
  redémarrer.
- Pendant un rattachement, la tournée enchaînait toutes les cibles en
  `non_membre` : `essai_sonde.py` attend le retour de la sonde, deux fois
  par table au plus.
- La sonde gardait 64 entrées par table : celle de routage du pont (254)
  sortait `partielle`. Les routes ont maintenant 255 places (section 2).

**La perte du parent.** Hypothèse : la petite table des voisins de la pile
« appareil final » se remplit des cibles de la tournée et finit par écraser
l'entrée du parent (on y a vu une entrée marquée parent, LQI 0, qui n'était
pas le parent). La pile « appareil final » refuse
`esp_zb_overall_network_size_set` (`ESP_FAIL`). Acceptée en 1.0.0 : elle
coûte environ 10 s par tournée, et la sonde revient toujours seule. Le
passage en routeur, qui la supprimerait, est exclu (section 1).

**Décisions pour la sonde 1.0.0.** Variante `sonde` seule (appareil final,
On/Off Light) ; `routes` et lignes `signal` gardées ; `echecs` retirée.

## Annexe A. Essai d'écoute passive du 05/10/2026

Quinze minutes d'écoute sur le canal du réseau Hue, depuis le bureau de
Majid, avec un C6 en mode promiscuité qui n'émet jamais (code versé dans
`outils/ecoute/`, section 5).

**Piège du pilote 802.15.4.** Par défaut, le pilote d'ESP-IDF **acquitte
toute trame reçue qui demande un accusé, même en mode promiscuité** : la
carte répondrait à la place des lampes. Il faut couper l'acquittement simple
et l'acquittement amélioré **après** `esp_ieee802154_enable()`, qui remet
la configuration à ses défauts :
`esp_ieee802154_set_auto_ack_tx(false)` et
`ieee802154_pib_set_enhance_ack_tx(false)` (fonctions présentes dans
`libieee802154.a` mais absentes de l'en-tête public). Le firmware d'écoute
le vérifie dans chacune de ses lignes d'état.

**Constats** (ordres de grandeur, sans identifiant) :
- le réseau Hue partage son canal avec le réseau Thread de Majid ; temps
  d'antenne mesuré : Thread 7,6 %, Zigbee 0,5 %, accusés 0,7 % ; les trois
  autres canaux possibles pour Hue étaient muets ;
- 34 nœuds connus, dont 22 entendus directement ; 23 adresses longues
  relevées, toutes au préfixe de Signify ;
- l'adresse longue de l'en-tête de sécurité NWK est bien celle de
  l'émetteur de la trame (582 cas sur 582) ;
- 16 routeurs reconnus à leur *Link Status*, toutes les 16 s environ ;
  6 appareils finaux, reliés à leur parent par leurs *data requests* ;
- chaque routeur entendu est à 1 ou 2 sauts du pont, d'après le rayon des
  diffusions du pont relayées de proche en proche ;
- une soixantaine de liens unicast observés, avec un taux de réémission MAC
  de 0 à 29 % selon le lien ;
- le pont lui-même n'est jamais entendu depuis le bureau ;
- les *Link Status* sont chiffrés, et leur longueur plafonne à 26 voisins
  par trame : le maillage compte au moins 27 routeurs, mais leurs voisins et
  les coûts des liens restent invisibles sans la clé réseau.
