# Sonde en Wi-Fi (sonde 1.1.0, app 1.1.0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal :** la sonde vit sur un chargeur mural et l'app l'interroge par le réseau local (TCP + enveloppe H1 + Bonjour), avec la même tournée qu'en USB.

**Architecture :** côté sonde, trois modules purs testés sur l'hôte (`canaux` : liste blanche et charges ; `cle_reseau` : dérivation de la clé ; `portail` : H1 par lignes sur des connexions numérotées) et un module de colle ESP32 (`reseau` : NVS, Wi-Fi, serveur TCP, mDNS) ; `main.cpp` route chaque réponse vers le canal qui a posé la question et diffuse les signaux. Côté app, un `CanalReseau` implémente le protocole `CanalSonde` déjà utilisé par le canal série : la logique de requête et la tournée ne changent pas ; `SondeMaillage` choisit le chemin (USB, réseau) et met la sonde en service par l'USB.

**Tech Stack :** ESP32-C6, pioarduino 55.03.312-1 (Arduino-ESP32 3.3.12, ESP-IDF 5.5.5, esp-zigbee-lib 1.6.8), ESPmDNS, WiFiServer ; Swift 6, SwiftUI, Network.framework, CryptoKit, Swift Testing, XcodeGen ; Python 3 (hmac, hashlib, socket, unittest).

**Spec :** `docs/superpowers/specs/2026-10-11-maillage-zigbee-sonde-wifi-design.md` (commit db434c6). Lire les deux : la spec fait foi, le plan l'argumente.

## Global Constraints

- Port TCP fixe **5481**, IPv4 ; service Bonjour **`_maillage-zigbee._tcp`**, nom d'instance = nom de la sonde, TXT `v=1` seulement.
- Une ligne TCP = un message H1 terminé par LF ; **4 200 octets au plus** hors LF ; une ligne plus longue ferme la connexion.
- Enveloppe H1 **du pont Halo, inchangée dans ses règles** (dépôt benq, commit `3a1ad2f` : `src/h1_proto.h`, `src/h1_proto.cpp`, `src/h1_crypto.cpp`, `tools/host_tests/test_h1.cpp`, `apps/macos/HaloProtocole/Reseau/EnveloppeH1.swift`, `apps/macos/HaloProtocoleTests/EnveloppeH1Tests.swift`), recopiée dans ce dépôt ; 2 sessions établies au plus.
- Requête par le réseau : `<rid> <commande>` (rid décimal 1..4294967295, sans zéro de tête) ; réponse : `<rid> <ligne JSON>` ; signaux et lignes non sollicitées : rid `0`, à toutes les sessions établies.
- **Liste blanche à distance :** `bonjour`, `etat`, `voisins`, `table`, `routes`, `suspendre`, `reprendre`. Tout le reste : `{"v":1,"t":"erreur","erreur":"refuse"}`.
- Sans clé valable, la sonde **ne répond rien** par le réseau.
- `wifi`, `cle`, `nom`, `oubli` : **USB seulement**. La clé ne sort de la carte qu'une fois (réponse à `cle nouvelle`), le mot de passe Wi-Fi jamais.
- Démarrage, Wi-Fi configuré : **sommeil profond de 0,2 s** si `esp_reset_reason()` n'est ni `ESP_RST_POWERON` ni `ESP_RST_DEEPSLEEP` ; puis `esp_coex_wifi_i154_enable()`, Wi-Fi connecté (15 s au plus), `esp_wifi_set_ps(WIFI_PS_MIN_MODEM)`, **puis** la pile Zigbee. Sans Wi-Fi configuré : comportement de la 1.0.0, rien de tout cela.
- Table de partitions : `nvs` 0x9000, `zb_storage` 0x3EA000, `zb_fct` 0x3EE000 **inchangés** (la sonde reste membre du réseau Hue sans effacement) ; `app0` 0x10000, taille 0x3DA000.
- Trousseau de l'app : service **`fr.djoko.maillage.zigbee.sonde`**, compte = adresse longue de la sonde (`bonjour.ieee`), valeur = la clé en 64 hexa majuscules.
- Délais de l'app par le réseau : ceux de l'USB **+ 3 s** par requête.
- Version : sonde **1.1.0**, app **1.1.0** ; une sonde 1.0.0 reste servie par l'USB, la partie réseau des Réglages est alors grisée (« Sonde 1.1.0 requise »).
- Dépôt public : **valeurs inventées** dans tout le code, les tests et les exemples ; `python3 outils/garde.py` avant chaque commit ; commits en français sans accents, `git add` explicite, terminés par `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` ; auteur `Djoko-cli <12185352+Djoko-cli@users.noreply.github.com>`.
- Aucun agent ne flashe, n'ouvre de port série ni n'utilise le vrai trousseau : les étapes de banc (tâches 10 et 20) se font avec Djoko.
- Ne jamais écrire dans `~/Dev/maillage-thread` ni dans le dépôt benq : on y lit seulement les fichiers à recopier.

## Review Focus

1. **Un rid réutilisé ou une réponse qui arrive après une coupure** : une réponse ne doit jamais servir une autre requête ; l'app ignore une ligne dont le rid n'est pas celui qu'elle attend (tâche 13, test `ridInattenduIgnore`).
2. **Le Wi-Fi tombe pendant une tournée** : la requête en cours échoue proprement (nil, pas de blocage jusqu'à 125 s sans fin), la tournée la reprend une fois, l'app se reconnecte ensuite (tâche 13 `coupurePendantRequete`, tâche 16 `reconnexionApresCoupure`).
3. **Deux clients en même temps** (l'app et l'outil Python) : la sonde sert les deux, chacun ne reçoit que ses réponses, les deux reçoivent les signaux (tâche 6 `deuxSessionsSeparees`).
4. **Nom de Wi-Fi ou mot de passe avec espaces, guillemets ou accents** : l'hexadécimal les transporte octet pour octet ; un octet nul est refusé (tâche 3, tâche 12 `wifiHexaUtf8`).
5. **Une commande refusée par le réseau** (`oubli`, `nom`, `wifi`, `cle`, commande inconnue) répond `refuse` et ne s'exécute pas, même entourée d'espaces (tâche 5 `listeBlanche`, tâche 8 étape de vérification).

---

## Structure des fichiers

**Sonde (`sonde/`)**

| Fichier | Rôle |
|---|---|
| `partitions.csv` (nouveau) | table de partitions 1.1.0 |
| `platformio.ini` | table de partitions, taille maximale |
| `src/h1_proto.h`, `src/h1_proto.cpp`, `src/h1_crypto.cpp` (repris) | enveloppe H1 du pont Halo |
| `src/commande.h`, `src/commande.cpp` | commandes `wifi …` et `cle …` |
| `src/cle_reseau.h`, `src/cle_reseau.cpp` (nouveaux) | dérivation de la clé |
| `src/canaux.h`, `src/canaux.cpp` (nouveaux) | liste blanche, requête et réponse réseau, origine d'une commande |
| `src/portail.h`, `src/portail.cpp` (nouveaux) | H1 par lignes sur connexions numérotées |
| `src/reseau.h`, `src/reseau.cpp` (nouveaux) | NVS, Wi-Fi, serveur TCP, mDNS (colle ESP32) |
| `src/main.cpp`, `src/version.h` | routage par canal, nouvelles commandes, `etat.reseau`, démarrage |
| `test/crypto_hote.cpp` (nouveau) | HMAC et SHA-256 de CommonCrypto pour les tests |
| `test/test_h1.cpp` (repris), `test/test_cle_reseau.cpp`, `test/test_canaux.cpp`, `test/test_portail.cpp` (nouveaux), `test/test_commande.cpp` | tests hôte |
| `test/lancer.sh` | compile et lance les nouveaux tests |

**Outils (`outils/`)** : `sonde_reseau.py` (nouveau), `test/test_sonde_reseau.py` (nouveau), `.gitignore` (racine).

**App**

| Fichier | Rôle |
|---|---|
| `MaillageCoeur/Reseau/EnveloppeH1.swift` (repris) | H1 côté app |
| `MaillageCoeur/Sonde/ProtocoleSonde.swift` | `bonjour.reseau`, `etat.reseau`, messages `wifi` et `cle`, commandes `wifi` et `cle nouvelle` |
| `MaillageZigbee/Sonde/CanalReseau.swift` (nouveau) | canal TCP + H1 + rid |
| `MaillageZigbee/Sonde/Sonde.swift` (renommé de `SondeUSB.swift`) | requêtes, plus `configurerWifi` et `nouvelleCle` |
| `MaillageZigbee/Sonde/CheminSonde.swift` (nouveau) | réglage du chemin et décision |
| `MaillageZigbee/Sonde/SondeMaillage.swift` | connexion par le réseau, mise en service |
| `MaillageZigbee/Vues/FenetreReglages.swift` | Réglages › Sonde : chemin, accès par le réseau |
| `project.yml`, `MaillageZigbee/Ressources/*.xcstrings` | réseau local, Bonjour, textes, version |
| `MaillageCoeurTests/EnveloppeH1Tests.swift` (repris), `MaillageCoeurTests/ProtocoleSondeTests.swift`, `MaillageZigbeeTests/CanalReseauTests.swift`, `MaillageZigbeeTests/CheminSondeTests.swift`, `MaillageZigbeeTests/SondeTests.swift`, `MaillageZigbeeTests/SondeReseauTests.swift` | tests |

---

# Partie 1 — La sonde 1.1.0

### Task 1: Table de partitions 1.1.0

**Files:**
- Create: `sonde/partitions.csv`
- Modify: `sonde/platformio.ini` (en-tête de commentaires, `board_build.partitions`, `board_upload.maximum_size`)

**Interfaces:**
- Consumes: rien.
- Produces: une partition application de 0x3DA000 octets ; les tâches suivantes peuvent grossir le firmware.

- [x] **Step 1: Écrire la table**

`sonde/partitions.csv` :

```csv
# Sonde 1.1.0 (spec sonde Wi-Fi, 3.4) : une seule application, agrandie ; pas de
# mise a jour a distance (flash par l'USB), donc ni app1 ni spiffs.
# nvs, zb_storage et zb_fct gardent les adresses de zigbee_zczr.csv (sonde 1.0.0) :
# la sonde reste membre du reseau Hue apres un flash sans effacement.
# Name,     Type, SubType, Offset,  Size, Flags
nvs,        data, nvs,     0x9000,  0x5000,
otadata,    data, ota,     0xe000,  0x2000,
app0,       app,  ota_0,   0x10000, 0x3DA000,
zb_storage, data, fat,     0x3EA000,0x4000,
zb_fct,     data, fat,     0x3EE000,0x1000,
rcp_fw,     data, spiffs,  0x3EF000,0x1000,
coredump,   data, coredump,0x3F0000,0x10000,
```

- [x] **Step 2: Brancher la table dans `platformio.ini`**

Remplacer, dans la section `[env]` :

```ini
board_build.partitions = zigbee_zczr.csv
; app0 de zigbee_zczr.csv : 0x140000 octets.
board_upload.maximum_size = 1310720
```

par :

```ini
; Table propre a la sonde 1.1.0 (partitions.csv) : nvs et zb_storage aux
; adresses de zigbee_zczr.csv, une seule application de 0x3DA000 octets.
board_build.partitions = partitions.csv
board_upload.maximum_size = 4038656
```

Et, dans le commentaire d'en-tête, remplacer les trois lignes qui commencent par `; Table de partitions zigbee_zczr.csv, celle de l'essai` par :

```ini
; Table de partitions partitions.csv (1.1.0) : celle de zigbee_zczr.csv pour
; nvs et zb_storage, une seule application agrandie. Deplacer nvs ou
; zb_storage demanderait un effacement (la sonde quitterait le reseau Hue).
```

- [x] **Step 3: Compiler les deux variantes**

Run : `cd sonde && ~/.platformio/penv/bin/pio run -e sonde -e verif 2>&1 | grep -E "Flash:|SUCCESS|FAILED"`
Expected : deux `SUCCESS`, et `Flash: [=   ]  15.x% (used 60xxxx bytes from 4038656 bytes)` (le pourcentage baisse : même firmware, partition plus grande).

- [x] **Step 4: Vérifier les adresses gardées**

Run : `cd sonde && python3 ~/.platformio/packages/framework-arduinoespressif32/tools/gen_esp32part.py .pio/build/sonde/partitions.bin | grep -E "nvs|zb_storage|zb_fct|app0"`
Expected : `nvs,data,nvs,0x9000,20K`, `app0,app,ota_0,0x10000,3944K`, `zb_storage,data,fat,0x3ea000,16K`, `zb_fct,data,fat,0x3ee000,4K`.

- [x] **Step 5: Commit**

```bash
git add sonde/partitions.csv sonde/platformio.ini
git commit -m "Agrandir la partition application de la sonde en gardant nvs et zb_storage en place

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Enveloppe H1 reprise du pont Halo

**Files:**
- Create (copies) : `sonde/src/h1_proto.h`, `sonde/src/h1_proto.cpp`, `sonde/src/h1_crypto.cpp` depuis `~/Documents/Dev/esp32/benq/src/` (commit `3a1ad2f`)
- Create : `sonde/test/crypto_hote.cpp`
- Create (copie adaptée) : `sonde/test/test_h1.cpp` depuis `~/Documents/Dev/esp32/benq/tools/host_tests/test_h1.cpp`
- Modify : `sonde/test/lancer.sh`

**Interfaces:**
- Consumes : rien.
- Produces : l'espace de noms `h1` de `h1_proto.h` (`h1::Table`, `h1::parse`, `h1::keyId`, `h1::toHex`, `h1::fromHex`, `h1::wipe`, `h1::salutMac`, `h1::defiMac`, `h1::sessionKey`, `h1::messageMac`, constantes `h1::kKeyLen`, `h1::kSlots`, `h1::kHeaderMax`, `h1::kDefiLen`) ; `sonde/test/crypto_hote.cpp` fournit `h1::hmacSha256` et `h1::sha256` aux tests hôte.

- [x] **Step 1: Copier les sources**

```bash
B=~/Documents/Dev/esp32/benq
git -C $B log -1 --format=%h -- src/h1_proto.cpp   # doit afficher 3a1ad2f
cp $B/src/h1_proto.h $B/src/h1_proto.cpp $B/src/h1_crypto.cpp sonde/src/
cp $B/tools/host_tests/test_h1.cpp sonde/test/test_h1.cpp
```

- [x] **Step 2: Situer les copies**

En tête de `sonde/src/h1_proto.h`, juste après la ligne `//  Enveloppe H1 du transport reseau (docs/PROTOCOLE-JSON.md, 10.4) : briques pures`, ajouter :

```cpp
//
//  Maillage Zigbee : repris tel quel du pont Halo (depot benq, commit 3a1ad2f).
//  Ici, un message H1 est une ligne TCP et non un datagramme UDP : voir
//  portail.h (spec sonde Wi-Fi, 3.3). Ne pas modifier les regles d'ici sans
//  modifier le pont Halo et Maillage Thread.
```

- [x] **Step 3: Sortir la crypto de l'hôte dans son fichier**

Dans `sonde/test/test_h1.cpp`, couper le bloc `namespace h1 { bool hmacSha256(...) {...} bool sha256(...) {...} }` (et les `#include <CommonCrypto/...>`) et le mettre dans `sonde/test/crypto_hote.cpp` :

```cpp
// Crypto de l'enveloppe H1 pour les tests hote : CommonCrypto (macOS). Sur la
// carte : mbedTLS (sonde/src/h1_crypto.cpp).
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>

#include "h1_proto.h"

namespace h1 {
bool hmacSha256(const uint8_t *key, size_t keyLen, const Part *parts, size_t nParts, uint8_t out[32]) {
  CCHmacContext c;
  CCHmacInit(&c, kCCHmacAlgSHA256, key, keyLen);
  for (size_t i = 0; i < nParts; i++) CCHmacUpdate(&c, parts[i].p, parts[i].n);
  CCHmacFinal(&c, out);
  return true;
}
bool sha256(const void *p, size_t n, uint8_t out[32]) {
  CC_SHA256(p, (CC_LONG)n, out);
  return true;
}
}  // namespace h1
```

Dans `test_h1.cpp`, remplacer la ligne `// Lancer : sh tools/test_halo1.sh` par `// Lancer : sh sonde/test/lancer.sh (repris du pont Halo, commit 3a1ad2f)` et la mention de `src/h1_crypto.cpp` par `sonde/test/crypto_hote.cpp`.

- [x] **Step 4: Ajouter le test à `lancer.sh`**

Après la ligne `compiler test_voyant "$ICI/test_voyant.cpp"` :

```sh
compiler test_h1 "$ICI/test_h1.cpp" "$SRC/h1_proto.cpp" "$ICI/crypto_hote.cpp"
```

et après la dernière ligne qui lance un test (`"$TMP/test_voyant"` ou la dernière présente) :

```sh
"$TMP/test_h1"
```

- [x] **Step 5: Lancer**

Run : `sh sonde/test/lancer.sh 2>&1 | tail -4`
Expected : une ligne `test_h1 ... 0 echec(s)` (ou le bilan propre à test_h1), code de sortie 0. Si `-Werror` refuse un avertissement dans la copie de `test_h1.cpp` (le pont compile avec d'autres drapeaux), corriger l'avertissement dans la copie de test seulement, jamais dans `h1_proto.*`.

- [x] **Step 6: Compiler la carte**

Run : `cd sonde && ~/.platformio/penv/bin/pio run -e verif 2>&1 | grep -E "SUCCESS|FAILED"`
Expected : `SUCCESS` (`h1_crypto.cpp` compile avec mbedTLS ; rien ne l'appelle encore).

- [x] **Step 7: Commit**

```bash
git add sonde/src/h1_proto.h sonde/src/h1_proto.cpp sonde/src/h1_crypto.cpp sonde/test/crypto_hote.cpp sonde/test/test_h1.cpp sonde/test/lancer.sh
git commit -m "Reprendre l'enveloppe H1 du pont Halo pour l'acces par le reseau

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Commandes `wifi` et `cle`

**Files:**
- Modify : `sonde/src/commande.h`, `sonde/src/commande.cpp`
- Test : `sonde/test/test_commande.cpp`

**Interfaces:**
- Consumes : rien.
- Produces :
  - `enum class TypeCommande` gagne, **avant** `kInconnue` : `kWifi, kWifiLire, kWifiEfface, kCleNouvelle, kCleLire, kCleEfface`.
  - Constantes `kWifiNomMax = 32`, `kWifiMdpMin = 8`, `kWifiMdpMax = 63`, `kAleaLong = 32`.
  - `struct Commande` gagne `uint8_t wifiNom[kWifiNomMax]`, `uint8_t wifiNomLong`, `uint8_t wifiMdp[kWifiMdpMax]`, `uint8_t wifiMdpLong` (0 : réseau ouvert), `uint8_t alea[kAleaLong]` ; `id` sert aussi à `wifi` et `cle nouvelle`.
  - `bool lireHexa(const char *s, uint8_t *out, size_t max, size_t *n)`.
- Syntaxe (précision de la spec 3.5, écrite ici) : `wifi <NOM HEXA> <MDP HEXA | -> <id>` ; `-` = réseau ouvert (un mot vide n'existe pas) ; `wifi` ; `wifi efface` ; `cle nouvelle <64 HEXA> <id>` ; `cle` ; `cle efface`. Hexa : MAJUSCULES seulement, nombre pair de chiffres ; un octet `00` est refusé dans le nom et le mot de passe.

- [x] **Step 1: Écrire les tests**

Ajouter à la fin de `main()` de `sonde/test/test_commande.cpp`, avant `return bilan(...)` :

```cpp
  // Hexa
  uint8_t h[4];
  size_t hn = 9;
  CHECK(lireHexa("0A1B", h, 4, &hn) && hn == 2 && h[0] == 0x0A && h[1] == 0x1B, "deux octets");
  hn = 9;
  CHECK(!lireHexa("0a1b", h, 4, &hn) && hn == 9, "minuscules refusees");
  CHECK(!lireHexa("ABC", h, 4, &hn), "impair");
  CHECK(!lireHexa("", h, 4, &hn), "vide");
  CHECK(!lireHexa("0011223344", h, 4, &hn), "trop long");
  CHECK(!lireHexa("0G", h, 4, &hn), "pas hexa");

  // wifi
  {
    // « Mon Wifi » / « motdepasse » (inventes)
    const Commande c = lireCommande("wifi 4D6F6E2057696669 6D6F7464657061737365 7");
    CHECK(c.type == TypeCommande::kWifi && c.id == 7, "wifi");
    CHECK(c.wifiNomLong == 8 && memcmp(c.wifiNom, "Mon Wifi", 8) == 0, "nom");
    CHECK(c.wifiMdpLong == 10 && memcmp(c.wifiMdp, "motdepasse", 10) == 0, "mot de passe");
  }
  {
    const Commande c = lireCommande("wifi 4F7576657274 - 8");
    CHECK(c.type == TypeCommande::kWifi && c.wifiMdpLong == 0 && c.id == 8, "reseau ouvert");
  }
  CHECK(est("wifi", TypeCommande::kWifiLire), "wifi seul");
  CHECK(est("wifi efface", TypeCommande::kWifiEfface), "wifi efface");
  CHECK(est("wifi 41 3132333435363738 1", TypeCommande::kWifi), "nom d'un octet, mdp de 8");
  CHECK(est("wifi 41 31323334353637 1", TypeCommande::kSyntaxe), "mdp de 7");
  CHECK(est("wifi 4100 3132333435363738 1", TypeCommande::kSyntaxe), "octet nul dans le nom");
  CHECK(est("wifi 41 3132333435363700 1", TypeCommande::kSyntaxe), "octet nul dans le mdp");
  CHECK(est("wifi 41 3132333435363738", TypeCommande::kSyntaxe), "sans id");
  CHECK(est("wifi 41 3132333435363738 1 2", TypeCommande::kSyntaxe), "mot de trop");
  CHECK(est("wifi efface 1", TypeCommande::kSyntaxe), "efface avec argument");
  CHECK(est("wifi 4142434445464748494A4B4C4D4E4F505152535455565758595A303132333435 - 1", TypeCommande::kWifi),
        "nom de 32 octets");
  CHECK(est("wifi 4142434445464748494A4B4C4D4E4F505152535455565758595A30313233343536 - 1", TypeCommande::kSyntaxe),
        "nom de 33 octets");

  // cle
  {
    const Commande c =
        lireCommande("cle nouvelle 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F 3");
    CHECK(c.type == TypeCommande::kCleNouvelle && c.id == 3 && c.alea[0] == 0x00 && c.alea[31] == 0x1F, "cle nouvelle");
  }
  CHECK(est("cle", TypeCommande::kCleLire), "cle seule");
  CHECK(est("cle efface", TypeCommande::kCleEfface), "cle efface");
  CHECK(est("cle nouvelle 0001 3", TypeCommande::kSyntaxe), "alea trop court");
  CHECK(est("cle nouvelle 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F", TypeCommande::kSyntaxe),
        "sans id");
  CHECK(est("cle autre", TypeCommande::kSyntaxe), "cle autre");
```

- [x] **Step 2: Vérifier l'échec**

Run : `sh sonde/test/lancer.sh 2>&1 | tail -3`
Expected : erreur de compilation (`lireHexa` et `kWifi` inconnus).

- [x] **Step 3: Implémenter**

Dans `sonde/src/commande.h`, compléter le commentaire d'en-tête (après la ligne `echecs <cible> <id> [<delai ms>]`) :

```cpp
//    wifi <NOM HEXA> <MDP HEXA | -> <id>         Wi-Fi (spec sonde Wi-Fi, 3.5) ;
//                                               « - » : reseau ouvert
//    wifi | wifi efface                         lire, oublier
//    cle nouvelle <64 HEXA> <id> | cle | cle efface
//  Hexa : MAJUSCULES, nombre pair de chiffres ; nom 1 a 32 octets, mot de
//  passe 8 a 63 octets, alea 32 octets ; un octet nul est refuse.
```

Remplacer l'enum et la structure :

```cpp
enum class TypeCommande : uint8_t {
  kBonjour,
  kNom,
  kEtat,
  kVoisins,
  kTable,
  kRoutes,
  kEchecs,
  kSuspendre,
  kReprendre,
  kOubli,
  kWifi,
  kWifiLire,
  kWifiEfface,
  kCleNouvelle,
  kCleLire,
  kCleEfface,
  kInconnue,
  kSyntaxe,
};

static constexpr size_t kNomMax = 32;
static constexpr uint32_t kDelaiDefautMs = 5000;
static constexpr uint32_t kDelaiMinMs = 500;
static constexpr uint32_t kDelaiMaxMs = 5000;
static constexpr uint16_t kCibleMax = 0xFFF7;  // FFF8 a FFFF : diffusions
static constexpr size_t kWifiNomMax = 32;
static constexpr size_t kWifiMdpMin = 8;
static constexpr size_t kWifiMdpMax = 63;
static constexpr size_t kAleaLong = 32;

struct Commande {
  TypeCommande type = TypeCommande::kInconnue;
  uint16_t cible = 0;                // table, routes, echecs
  uint32_t id = 0;                   // table, routes, echecs, wifi, cle nouvelle
  uint32_t delaiMs = kDelaiDefautMs; // table, routes, echecs
  char nom[kNomMax + 1] = {0};       // nom
  uint8_t wifiNom[kWifiNomMax] = {0};
  uint8_t wifiNomLong = 0;
  uint8_t wifiMdp[kWifiMdpMax] = {0};
  uint8_t wifiMdpLong = 0;           // 0 : reseau ouvert
  uint8_t alea[kAleaLong] = {0};     // cle nouvelle
};
```

Et ajouter avant `Commande lireCommande(const char *ligne);` :

```cpp
// Hexadecimal MAJUSCULE, nombre pair de chiffres, 1 a max octets. Refuse : n
// intact.
bool lireHexa(const char *s, uint8_t *out, size_t max, size_t *n);
```

Dans `sonde/src/commande.cpp`, après `lireCourt` :

```cpp
bool lireHexa(const char *s, uint8_t *out, size_t max, size_t *n) {
  const size_t l = strlen(s);
  if (l == 0 || l % 2 != 0 || l / 2 > max) return false;
  for (size_t i = 0; i < l; i++) {
    const char c = s[i];
    if (!((c >= '0' && c <= '9') || (c >= 'A' && c <= 'F'))) return false;
  }
  for (size_t i = 0; i < l / 2; i++) {
    const char a = s[2 * i], b = s[2 * i + 1];
    const uint8_t ha = (uint8_t)(a <= '9' ? a - '0' : a - 'A' + 10);
    const uint8_t hb = (uint8_t)(b <= '9' ? b - '0' : b - 'A' + 10);
    out[i] = (uint8_t)(ha << 4 | hb);
  }
  *n = l / 2;
  return true;
}
```

Dans l'espace de noms anonyme, après `cibleIdDelai` :

```cpp
bool sansNul(const uint8_t *o, size_t n) {
  for (size_t i = 0; i < n; i++)
    if (o[i] == 0) return false;
  return true;
}

// wifi | wifi efface | wifi <NOM> <MDP | -> <id>
Commande wifi(char *mots[kMotsMax], size_t n) {
  Commande c;
  c.type = TypeCommande::kSyntaxe;
  if (n == 1) {
    c.type = TypeCommande::kWifiLire;
    return c;
  }
  if (n == 2 && strcmp(mots[1], "efface") == 0) {
    c.type = TypeCommande::kWifiEfface;
    return c;
  }
  if (n != 4) return c;
  size_t nNom = 0, nMdp = 0;
  uint32_t id;
  if (!lireHexa(mots[1], c.wifiNom, kWifiNomMax, &nNom) || !sansNul(c.wifiNom, nNom)) return c;
  if (strcmp(mots[2], "-") != 0) {
    if (!lireHexa(mots[2], c.wifiMdp, kWifiMdpMax, &nMdp) || nMdp < kWifiMdpMin || !sansNul(c.wifiMdp, nMdp))
      return c;
  }
  if (!lireEntier(mots[3], &id)) return c;
  c.type = TypeCommande::kWifi;
  c.wifiNomLong = (uint8_t)nNom;
  c.wifiMdpLong = (uint8_t)nMdp;
  c.id = id;
  return c;
}

// cle | cle efface | cle nouvelle <64 HEXA> <id>
Commande cle(char *mots[kMotsMax], size_t n) {
  Commande c;
  c.type = TypeCommande::kSyntaxe;
  if (n == 1) {
    c.type = TypeCommande::kCleLire;
    return c;
  }
  if (n == 2 && strcmp(mots[1], "efface") == 0) {
    c.type = TypeCommande::kCleEfface;
    return c;
  }
  if (n != 4 || strcmp(mots[1], "nouvelle") != 0) return c;
  size_t nAlea = 0;
  uint32_t id;
  if (!lireHexa(mots[2], c.alea, kAleaLong, &nAlea) || nAlea != kAleaLong || !lireEntier(mots[3], &id)) return c;
  c.type = TypeCommande::kCleNouvelle;
  c.id = id;
  return c;
}
```

Dans `lireCommande`, avant `if (strcmp(m, "table") == 0)` :

```cpp
  if (strcmp(m, "wifi") == 0) return wifi(mots, n);
  if (strcmp(m, "cle") == 0) return cle(mots, n);
```

- [x] **Step 4: Vérifier**

Run : `sh sonde/test/lancer.sh 2>&1 | grep -E "test_commande|ECHEC"`
Expected : trois lignes `test_commande ... 0 echec(s)` (les trois variantes d'options), aucun `ECHEC`.

- [x] **Step 5: Commit**

```bash
git add sonde/src/commande.h sonde/src/commande.cpp sonde/test/test_commande.cpp
git commit -m "Lire les commandes wifi et cle de la sonde, en hexadecimal

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`main.cpp` ne compile plus pour la carte tant que la tâche 8 n'a pas traité les nouveaux types dans son `switch` (avertissement `-Wswitch` seulement : la carte compile sans `-Werror`) ; les tests hôte passent.

---

### Task 4: Dérivation de la clé

**Files:**
- Create : `sonde/src/cle_reseau.h`, `sonde/src/cle_reseau.cpp`
- Test : `sonde/test/test_cle_reseau.cpp`
- Modify : `sonde/test/lancer.sh`

**Interfaces:**
- Consumes : `h1::hmacSha256`, `h1::keyId`, `h1::kKeyLen` (tâche 2).
- Produces : `bool deriverCle(const uint8_t aleaApp[32], const uint8_t aleaCarte[32], uint8_t cle[32]);`

- [x] **Step 1: Écrire le test**

`sonde/test/test_cle_reseau.cpp` :

```cpp
// Tests hote de sonde/src/cle_reseau.{h,cpp} : derivation de la cle de l'acces par
// le reseau. Vecteur calcule en Python (hmac, hashlib) le 11/10/2026.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "cle_reseau.h"
#include "h1_proto.h"
#include "verif.h"

int main() {
  uint8_t app[32], carte[32], cle[32];
  for (int i = 0; i < 32; i++) {
    app[i] = (uint8_t)i;
    carte[i] = (uint8_t)(32 + i);
  }
  CHECK(deriverCle(app, carte, cle), "derivation");
  char hexa[65];
  h1::toHex(cle, 32, hexa);
  CHECK(strcmp(hexa, "62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D") == 0, "cle : %s", hexa);
  char kid[9];
  CHECK(h1::keyId(cle, kid) && strcmp(kid, "91CB5C39") == 0, "empreinte : %s", kid);
  return bilan("test_cle_reseau");
}
```

Dans `lancer.sh`, après la ligne `compiler test_h1 ...` : `compiler test_cle_reseau "$ICI/test_cle_reseau.cpp" "$SRC/cle_reseau.cpp" "$SRC/h1_proto.cpp" "$ICI/crypto_hote.cpp"`, et après `"$TMP/test_h1"` : `"$TMP/test_cle_reseau"`.

- [x] **Step 2: Vérifier l'échec**

Run : `sh sonde/test/lancer.sh 2>&1 | tail -3`
Expected : `cle_reseau.h` introuvable.

- [x] **Step 3: Implémenter**

`sonde/src/cle_reseau.h` :

```cpp
#pragma once
// ===========================================================================
//  Cle de l'acces par le reseau (spec sonde Wi-Fi, 3.5)
//
//  cle = HMAC-SHA256(cle = alea de l'app, message = alea de la carte). L'app
//  tire le sien, la carte le sien : ni l'une ni l'autre ne fixe seule la cle.
//  Empreinte : le kid H1 (h1::keyId, 8 hexa de SHA-256 de la cle).
//
//  Pur : teste sur l'hote (sonde/test/test_cle_reseau.cpp).
// ===========================================================================
#include <stdint.h>

bool deriverCle(const uint8_t aleaApp[32], const uint8_t aleaCarte[32], uint8_t cle[32]);
```

`sonde/src/cle_reseau.cpp` :

```cpp
#include "cle_reseau.h"

#include "h1_proto.h"

bool deriverCle(const uint8_t aleaApp[32], const uint8_t aleaCarte[32], uint8_t cle[32]) {
  const h1::Part part = {aleaCarte, 32};
  return h1::hmacSha256(aleaApp, 32, &part, 1, cle);
}
```

- [x] **Step 4: Vérifier**

Run : `sh sonde/test/lancer.sh 2>&1 | grep -E "test_cle_reseau|ECHEC"`
Expected : `test_cle_reseau : 3 verifications, 0 echec(s)`.

- [x] **Step 5: Commit**

```bash
git add sonde/src/cle_reseau.h sonde/src/cle_reseau.cpp sonde/test/test_cle_reseau.cpp sonde/test/lancer.sh
git commit -m "Deriver la cle de l'acces reseau des aleas de l'app et de la carte

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Canaux : liste blanche, requête et réponse réseau

**Files:**
- Create : `sonde/src/canaux.h`, `sonde/src/canaux.cpp`
- Test : `sonde/test/test_canaux.cpp`
- Modify : `sonde/test/lancer.sh`

**Interfaces:**
- Consumes : `TypeCommande`, `lireEntier` (`commande.h`).
- Produces :
  - `static constexpr size_t kCommandeMax = 255;`
  - `struct Origine { bool reseau = false; uint8_t session = 0; uint32_t rid = 0; };` (l'USB par défaut)
  - `bool distanceAutorisee(TypeCommande t);`
  - `bool lireRequete(const uint8_t *charge, size_t n, uint32_t *rid, char commande[kCommandeMax + 1]);`
  - `size_t chargeReponse(uint32_t rid, const uint8_t *ligne, size_t n, uint8_t *sortie, size_t taille);`

- [x] **Step 1: Écrire les tests**

`sonde/test/test_canaux.cpp` :

```cpp
// Tests hote de sonde/src/canaux.{h,cpp} : liste blanche du reseau, requetes
// « <rid> <commande> » et reponses « <rid> <ligne> » (spec sonde Wi-Fi, 3.3).
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "canaux.h"
#include "commande.h"
#include "verif.h"

static bool lire(const char *s, uint32_t *rid, char *cmd) {
  return lireRequete((const uint8_t *)s, strlen(s), rid, cmd);
}

int main() {
  // listeBlanche
  CHECK(distanceAutorisee(TypeCommande::kBonjour), "bonjour");
  CHECK(distanceAutorisee(TypeCommande::kEtat), "etat");
  CHECK(distanceAutorisee(TypeCommande::kVoisins), "voisins");
  CHECK(distanceAutorisee(TypeCommande::kTable), "table");
  CHECK(distanceAutorisee(TypeCommande::kRoutes), "routes");
  CHECK(distanceAutorisee(TypeCommande::kSuspendre), "suspendre");
  CHECK(distanceAutorisee(TypeCommande::kReprendre), "reprendre");
  CHECK(!distanceAutorisee(TypeCommande::kNom), "nom");
  CHECK(!distanceAutorisee(TypeCommande::kOubli), "oubli");
  CHECK(!distanceAutorisee(TypeCommande::kEchecs), "echecs");
  CHECK(!distanceAutorisee(TypeCommande::kWifi), "wifi");
  CHECK(!distanceAutorisee(TypeCommande::kWifiLire), "wifi lire");
  CHECK(!distanceAutorisee(TypeCommande::kWifiEfface), "wifi efface");
  CHECK(!distanceAutorisee(TypeCommande::kCleNouvelle), "cle nouvelle");
  CHECK(!distanceAutorisee(TypeCommande::kCleLire), "cle");
  CHECK(!distanceAutorisee(TypeCommande::kCleEfface), "cle efface");
  CHECK(!distanceAutorisee(TypeCommande::kInconnue), "inconnue");
  CHECK(!distanceAutorisee(TypeCommande::kSyntaxe), "syntaxe");
  CHECK(lireCommande("  oubli  ").type == TypeCommande::kOubli && !distanceAutorisee(lireCommande("  oubli  ").type),
        "oubli entoure d'espaces : toujours refuse");

  // Requetes
  uint32_t rid = 0;
  char cmd[kCommandeMax + 1];
  CHECK(lire("7 etat", &rid, cmd) && rid == 7 && strcmp(cmd, "etat") == 0, "simple");
  CHECK(lire("4294967295 table 1A2B 3", &rid, cmd) && rid == 4294967295u && strcmp(cmd, "table 1A2B 3") == 0, "max");
  rid = 9;
  CHECK(!lire("0 etat", &rid, cmd) && rid == 9, "rid 0 (reserve aux signaux)");
  CHECK(!lire("07 etat", &rid, cmd), "zero de tete");
  CHECK(!lire("4294967296 etat", &rid, cmd), "rid trop grand");
  CHECK(!lire("7", &rid, cmd), "sans commande");
  CHECK(!lire("7 ", &rid, cmd), "commande vide");
  CHECK(!lire("etat", &rid, cmd), "sans rid");
  CHECK(!lire("7 et\x01t", &rid, cmd), "caractere de controle");
  CHECK(!lire("7 caf\xc3\xa9", &rid, cmd), "non ASCII");
  char longue[300];
  memset(longue, 'a', sizeof(longue));
  memcpy(longue, "7 ", 2);
  longue[2 + 255] = 0;
  CHECK(lire(longue, &rid, cmd) && strlen(cmd) == 255, "255 caracteres");
  longue[2 + 255] = 'a';
  longue[2 + 256] = 0;
  CHECK(!lire(longue, &rid, cmd), "256 caracteres");

  // Reponses
  uint8_t s[64];
  const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
  size_t n = chargeReponse(12, (const uint8_t *)l, strlen(l), s, sizeof(s));
  CHECK(n == strlen("12 {\"v\":1,\"t\":\"etat\"}") && memcmp(s, "12 {\"v\":1,\"t\":\"etat\"}", n) == 0, "rid 12");
  n = chargeReponse(0, (const uint8_t *)l, strlen(l), s, sizeof(s));
  CHECK(n == strlen("0 {\"v\":1,\"t\":\"etat\"}") && memcmp(s, "0 ", 2) == 0, "rid 0 : signal");
  CHECK(chargeReponse(12, (const uint8_t *)l, strlen(l), s, 10) == 0, "trop petit");
  const char *sansRs = "{\"v\":1}\n";
  n = chargeReponse(1, (const uint8_t *)sansRs, strlen(sansRs), s, sizeof(s));
  CHECK(n == strlen("1 {\"v\":1}") && memcmp(s, "1 {\"v\":1}", n) == 0, "sans RS");
  return bilan("test_canaux");
}
```

Dans `lancer.sh` : `compiler test_canaux "$ICI/test_canaux.cpp" "$SRC/canaux.cpp" "$SRC/commande.cpp"` et `"$TMP/test_canaux"`.

- [x] **Step 2: Vérifier l'échec**

Run : `sh sonde/test/lancer.sh 2>&1 | tail -3`
Expected : `canaux.h` introuvable.

- [x] **Step 3: Implémenter**

`sonde/src/canaux.h` :

```cpp
#pragma once
// ===========================================================================
//  Canaux de la sonde (spec sonde Wi-Fi, 3.3) : l'USB et les sessions reseau
//
//  Origine : qui a pose la question (l'USB, ou une session reseau et son rid) ;
//  la reponse ne va qu'a elle. Les signaux vont a tous (main.cpp).
//  Requete reseau : « <rid> <commande> », rid decimal 1..4294967295 sans zero
//  de tete, une espace, puis la commande de l'USB (1 a 255 caracteres ASCII
//  imprimables). Reponse : « <rid> » puis la ligne de l'USB sans RS ni LF.
//
//  Pur : teste sur l'hote (sonde/test/test_canaux.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "commande.h"

static constexpr size_t kCommandeMax = 255;

struct Origine {
  bool reseau = false;  // false : l'USB
  uint8_t session = 0;  // emplacement de la session H1
  uint32_t rid = 0;
};

// Lecture et suspension seulement : ni nom, ni oubli, ni configuration.
bool distanceAutorisee(TypeCommande t);

bool lireRequete(const uint8_t *charge, size_t n, uint32_t *rid, char commande[kCommandeMax + 1]);

// 0 si la reponse ne tient pas dans taille octets.
size_t chargeReponse(uint32_t rid, const uint8_t *ligne, size_t n, uint8_t *sortie, size_t taille);
```

`sonde/src/canaux.cpp` :

```cpp
#include "canaux.h"

#include <stdio.h>
#include <string.h>

bool distanceAutorisee(TypeCommande t) {
  switch (t) {
    case TypeCommande::kBonjour:
    case TypeCommande::kEtat:
    case TypeCommande::kVoisins:
    case TypeCommande::kTable:
    case TypeCommande::kRoutes:
    case TypeCommande::kSuspendre:
    case TypeCommande::kReprendre: return true;
    default: return false;
  }
}

bool lireRequete(const uint8_t *charge, size_t n, uint32_t *rid, char commande[kCommandeMax + 1]) {
  size_t i = 0;
  while (i < n && i < 10 && charge[i] >= '0' && charge[i] <= '9') i++;
  if (i == 0 || i >= n || charge[i] != ' ' || charge[0] == '0') return false;
  char texte[11];
  memcpy(texte, charge, i);
  texte[i] = 0;
  uint32_t r;
  if (!lireEntier(texte, &r) || r == 0) return false;
  const size_t debut = i + 1, l = n - debut;
  if (l == 0 || l > kCommandeMax) return false;
  for (size_t k = debut; k < n; k++)
    if (charge[k] < 0x20 || charge[k] > 0x7E) return false;
  memcpy(commande, charge + debut, l);
  commande[l] = 0;
  *rid = r;
  return true;
}

size_t chargeReponse(uint32_t rid, const uint8_t *ligne, size_t n, uint8_t *sortie, size_t taille) {
  if (n > 0 && ligne[0] == 0x1E) {
    ligne++;
    n--;
  }
  if (n > 0 && ligne[n - 1] == '\n') n--;
  char tete[12];
  const int t = snprintf(tete, sizeof(tete), "%lu ", (unsigned long)rid);
  if (t < 0 || (size_t)t + n > taille) return 0;
  memcpy(sortie, tete, (size_t)t);
  memcpy(sortie + t, ligne, n);
  return (size_t)t + n;
}
```

- [x] **Step 4: Vérifier**

Run : `sh sonde/test/lancer.sh 2>&1 | grep -E "test_canaux|ECHEC"`
Expected : `test_canaux : ... 0 echec(s)`.

- [x] **Step 5: Commit**

```bash
git add sonde/src/canaux.h sonde/src/canaux.cpp sonde/test/test_canaux.cpp sonde/test/lancer.sh
git commit -m "Ajouter la liste blanche du reseau et les charges des requetes et reponses

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Portail : H1 par lignes sur des connexions numérotées

**Files:**
- Create : `sonde/src/portail.h`, `sonde/src/portail.cpp`
- Test : `sonde/test/test_portail.cpp`
- Modify : `sonde/test/lancer.sh`

**Interfaces:**
- Consumes : `h1::Table`, `h1::parse`, `h1::Peer`, `h1::kDefiLen`, `h1::kHeaderMax`, `h1::kSlots` (tâche 2) ; `lireRequete`, `chargeReponse`, `kCommandeMax` (tâche 5).
- Produces : la classe `Portail` ci-dessous (utilisée par `reseau.cpp`, tâche 7).

Règles : une connexion = un numéro 0..2 ; la session H1 promue sur une connexion lui est liée (`Peer.port` = numéro de connexion) et tombe (`Table::end`) quand elle se ferme ; un message H1 refusé (forme, clé, MAC, rejeu) ne reçoit **rien** ; une ligne de plus de 4 200 octets ferme la connexion ; `CR` est ignoré.

- [x] **Step 1: Écrire les tests**

`sonde/test/test_portail.cpp` :

```cpp
// Tests hote de sonde/src/portail.{h,cpp} : H1 par lignes TCP (spec sonde Wi-Fi,
// 3.3). Le client des tests est ecrit avec les briques de h1_proto.h.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include <string>
#include <vector>

#include "h1_proto.h"
#include "portail.h"
#include "verif.h"

namespace {

uint8_t gCle[32];
uint8_t gAutre[32];
uint8_t gCompteur = 0x50;

void aleatoire(void *p, size_t n) {
  uint8_t *o = (uint8_t *)p;
  for (size_t i = 0; i < n; i++) o[i] = gCompteur++;
}

struct Fausse : Portail::Sortie {
  std::vector<std::string> lignes[Portail::kConnexions];
  bool fermee[Portail::kConnexions] = {};
  void envoyer(uint8_t c, const uint8_t *o, size_t n) override { lignes[c].emplace_back((const char *)o, n); }
  void fermer(uint8_t c) override { fermee[c] = true; }
};

// Un client H1 : poignee de main, messages scelles, reponses ouvertes.
struct Client {
  const uint8_t *cle;
  std::string sid;
  uint8_t ks[32];
  uint32_t ctr = 0;

  std::string salut(const char *na) {
    char kid[9];
    h1::keyId(cle, kid);
    uint8_t mac[16];
    h1::salutMac(cle, kid, na, mac);
    char m[33];
    h1::toHex(mac, 16, m);
    return std::string("H1 SALUT ") + kid + " " + na + " " + m + "\n";
  }
  bool defi(const std::string &ligne, const char *na) {
    const h1::Parsed p = h1::parse((const uint8_t *)ligne.data(), ligne.size() - 1);
    if (p.kind != h1::Kind::Defi) return false;
    char kid[9];
    h1::keyId(cle, kid);
    uint8_t mac[16];
    if (!h1::defiMac(cle, kid, na, p.nc, p.sidHex, mac) || memcmp(mac, p.mac, 16) != 0) return false;
    sid = p.sidHex;
    return h1::sessionKey(cle, na, p.nc, p.sidHex, ks);
  }
  std::string message(const std::string &charge) {
    ctr++;
    uint8_t mac[16];
    h1::messageMac(ks, 'A', sid.c_str(), ctr, (const uint8_t *)charge.data(), charge.size(), mac);
    char m[33];
    h1::toHex(mac, 16, m);
    return "H1 " + sid + " " + std::to_string(ctr) + " " + m + " " + charge + "\n";
  }
  // Charge d'une ligne de la carte, MAC verifie ; "" sinon.
  std::string ouvrir(const std::string &ligne) {
    const h1::Parsed p = h1::parse((const uint8_t *)ligne.data(), ligne.size() - 1);
    if (p.kind != h1::Kind::Data || sid != p.sidHex) return "";
    uint8_t mac[16];
    h1::messageMac(ks, 'C', p.sidHex, p.ctr, p.payload, p.payloadLen, mac);
    if (memcmp(mac, p.mac, 16) != 0) return "";
    return std::string((const char *)p.payload, p.payloadLen);
  }
};

const char *kNa1 = "A0A1A2A3A4A5A6A7A8A9AAABACADAEAF";
const char *kNa2 = "B0B1B2B3B4B5B6B7B8B9BABBBCBDBEBF";

void recevoir(Portail &p, uint8_t c, const std::string &s, uint32_t now, Fausse &f) {
  p.recevoir(c, (const uint8_t *)s.data(), s.size(), now, aleatoire, f);
}

// Poignee de main complete sur la connexion c ; true si la session est etablie.
bool etablir(Portail &p, Fausse &f, Client &cl, uint8_t c, const char *na, uint32_t now) {
  p.ouverte(c);
  const size_t avant = f.lignes[c].size();
  recevoir(p, c, cl.salut(na), now, f);
  if (f.lignes[c].size() != avant + 1 || !cl.defi(f.lignes[c].back(), na)) return false;
  recevoir(p, c, cl.message("1 bonjour"), now + 1, f);
  Portail::Requete r;
  return p.requete(&r) && r.rid == 1 && strcmp(r.commande, "bonjour") == 0;
}

}  // namespace

int main() {
  for (int i = 0; i < 32; i++) {
    gCle[i] = (uint8_t)i;
    gAutre[i] = (uint8_t)(0x80 + i);
  }

  {  // poigneeDeMain, requete, reponse
    Portail p;
    Fausse f;
    CHECK(p.cle(gCle), "cle");
    Client cl{gCle};
    CHECK(etablir(p, f, cl, 0, kNa1, 1000), "session etablie");
    CHECK(p.sessions() == 1, "une session");
    Portail::Requete r;
    recevoir(p, 0, cl.message("2 table 1A2B 5"), 1004, f);
    CHECK(p.requete(&r) && r.rid == 2 && strcmp(r.commande, "table 1A2B 5") == 0, "requete table");
    CHECK(!p.requete(&r), "file vide");
    const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
    CHECK(p.repondre(r.session, 2, (const uint8_t *)l, strlen(l), f), "reponse partie");
    CHECK(cl.ouvrir(f.lignes[0].back()) == "2 {\"v\":1,\"t\":\"etat\"}", "reponse scellee");
    CHECK(p.envois() == 1, "un envoi");
  }

  {  // morceaux : une ligne arrive en plusieurs fois, CR ignore
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client cl{gCle};
    p.ouverte(1);
    const std::string s = cl.salut(kNa1);
    recevoir(p, 1, s.substr(0, 10), 10, f);
    CHECK(f.lignes[1].empty(), "rien avant LF");
    recevoir(p, 1, s.substr(10, s.size() - 11) + "\r\n", 11, f);
    CHECK(f.lignes[1].size() == 1 && cl.defi(f.lignes[1].back(), kNa1), "DEFI apres LF");
  }

  {  // mauvaiseCle : silence
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client intrus{gAutre};
    p.ouverte(0);
    recevoir(p, 0, intrus.salut(kNa1), 10, f);
    CHECK(f.lignes[0].empty(), "aucune reponse a une autre cle");
    CHECK(p.refus() == 1, "refus compte");
  }

  {  // sansCle : silence
    Portail p;
    Fausse f;
    Client cl{gCle};
    p.ouverte(0);
    recevoir(p, 0, cl.salut(kNa1), 10, f);
    CHECK(f.lignes[0].empty(), "aucune reponse sans cle");
  }

  {  // ligneTropLongue : connexion fermee
    Portail p;
    Fausse f;
    p.cle(gCle);
    p.ouverte(2);
    recevoir(p, 2, std::string(Portail::kLigneMax + 1, 'x'), 10, f);
    CHECK(f.fermee[2], "fermee");
    CHECK(p.fermetures() == 1, "fermeture comptee");
  }

  {  // requeteInvalide : rid absent, refusee sans reponse
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client cl{gCle};
    CHECK(etablir(p, f, cl, 0, kNa1, 1000), "session");
    const size_t avant = f.lignes[0].size();
    recevoir(p, 0, cl.message("etat"), 1004, f);
    Portail::Requete r;
    CHECK(!p.requete(&r), "pas de requete");
    CHECK(f.lignes[0].size() == avant, "pas de reponse");
  }

  {  // deuxSessionsSeparees : chacun ses reponses, les deux recoivent les signaux
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle}, b{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    CHECK(etablir(p, f, b, 1, kNa2, 1100), "b");
    CHECK(p.sessions() == 2, "deux sessions");
    recevoir(p, 1, b.message("2 etat"), 1200, f);
    Portail::Requete r;
    CHECK(p.requete(&r) && r.rid == 2, "requete de b");
    const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
    const size_t na = f.lignes[0].size();
    p.repondre(r.session, r.rid, (const uint8_t *)l, strlen(l), f);
    CHECK(f.lignes[0].size() == na, "a ne recoit pas la reponse de b");
    CHECK(b.ouvrir(f.lignes[1].back()) == "2 {\"v\":1,\"t\":\"etat\"}", "b la recoit");
    const char *s = "\x1e{\"v\":1,\"t\":\"signal\"}\n";
    p.diffuser((const uint8_t *)s, strlen(s), f);
    CHECK(a.ouvrir(f.lignes[0].back()) == "0 {\"v\":1,\"t\":\"signal\"}", "signal a a");
    CHECK(b.ouvrir(f.lignes[1].back()) == "0 {\"v\":1,\"t\":\"signal\"}", "signal a b");
  }

  {  // fermeture : la session tombe avec sa connexion
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.fermee(0);
    CHECK(p.sessions() == 0, "plus de session");
    const char *l = "\x1e{}\n";
    CHECK(!p.repondre(0, 3, (const uint8_t *)l, strlen(l), f), "reponse impossible");
  }

  {  // changerDeCle : tout tombe
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.cle(gAutre);
    CHECK(p.sessions() == 0, "sessions tombees");
    CHECK(p.aCle(), "nouvelle cle");
    p.cle(nullptr);
    CHECK(!p.aCle(), "cle effacee");
  }
  return bilan("test_portail");
}
```

Dans `lancer.sh` : `compiler test_portail "$ICI/test_portail.cpp" "$SRC/portail.cpp" "$SRC/h1_proto.cpp" "$SRC/canaux.cpp" "$SRC/commande.cpp" "$ICI/crypto_hote.cpp"` et `"$TMP/test_portail"`.

- [x] **Step 2: Vérifier l'échec**

Run : `sh sonde/test/lancer.sh 2>&1 | tail -3`
Expected : `portail.h` introuvable.

- [x] **Step 3: Implémenter**

`sonde/src/portail.h` :

```cpp
#pragma once
// ===========================================================================
//  Portail : l'enveloppe H1 sur des lignes TCP (spec sonde Wi-Fi, 3.3)
//
//  Connexions numerotees 0..kConnexions-1 (reseau.cpp les relie aux sockets).
//  Une ligne terminee par LF = un message H1 ; CR ignore ; une ligne de plus
//  de kLigneMax octets ferme la connexion. La session H1 promue sur une
//  connexion lui est liee et tombe avec elle. Un message refuse (forme, cle,
//  MAC, rejeu, requete mal formee) ne recoit rien : sans cle, la sonde se tait.
//
//  Pur : teste sur l'hote (sonde/test/test_portail.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "canaux.h"
#include "h1_proto.h"

class Portail {
 public:
  static constexpr uint8_t kConnexions = 3;
  static constexpr size_t kLigneMax = 4200;  // LF exclu
  static constexpr uint8_t kAucune = 0xFF;

  struct Sortie {
    // Une ligne complete, LF compris.
    virtual void envoyer(uint8_t connexion, const uint8_t *octets, size_t n) = 0;
    virtual void fermer(uint8_t connexion) = 0;
  };

  struct Requete {
    uint8_t session = 0;
    uint32_t rid = 0;
    char commande[kCommandeMax + 1] = {0};
  };

  // nullptr : aucune cle. Changer de cle fait tomber toutes les sessions.
  bool cle(const uint8_t *psk);
  bool aCle() const { return table_.hasKey(); }

  void ouverte(uint8_t c);
  void fermee(uint8_t c);
  void recevoir(uint8_t c, const uint8_t *octets, size_t n, uint32_t maintenant, h1::Table::Random rnd, Sortie &s);
  // Une requete admise, la plus ancienne ; false s'il n'y en a pas.
  bool requete(Requete *r);
  // Reponse (rid > 0) ou signal (rid 0) a la session ; false si elle n'est
  // reliee a aucune connexion ouverte.
  bool repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n, Sortie &s);
  void diffuser(const uint8_t *ligne, size_t n, Sortie &s);
  void expirer(uint32_t maintenant);

  uint8_t sessions() const;
  uint32_t envois() const { return envois_; }
  uint32_t refus() const { return refus_; }
  uint32_t fermetures() const { return fermetures_; }

 private:
  struct Connexion {
    bool ouverte = false;
    size_t long_ = 0;
    uint8_t tampon[kLigneMax];
  };
  static constexpr uint8_t kFile = 4;

  void ligne(uint8_t c, const uint8_t *l, size_t n, uint32_t maintenant, h1::Table::Random rnd, Sortie &s);

  h1::Table table_;
  Connexion cx_[kConnexions];
  uint8_t connexionDe_[h1::kSlots];
  Requete file_[kFile];
  uint8_t debut_ = 0, nombre_ = 0;
  uint32_t envois_ = 0, refus_ = 0, fermetures_ = 0;
  uint8_t charge_[kLigneMax];
  uint8_t sortie_[kLigneMax + 1];

 public:
  Portail() {
    for (uint8_t &c : connexionDe_) c = kAucune;
  }
};
```

`sonde/src/portail.cpp` :

```cpp
#include "portail.h"

#include <string.h>

bool Portail::cle(const uint8_t *psk) {
  for (uint8_t &c : connexionDe_) c = kAucune;
  nombre_ = 0;
  return table_.setKey(psk);
}

void Portail::ouverte(uint8_t c) {
  if (c >= kConnexions) return;
  cx_[c].ouverte = true;
  cx_[c].long_ = 0;
}

void Portail::fermee(uint8_t c) {
  if (c >= kConnexions) return;
  cx_[c].ouverte = false;
  cx_[c].long_ = 0;
  for (uint8_t i = 0; i < h1::kSlots; i++) {
    if (connexionDe_[i] == c) {
      connexionDe_[i] = kAucune;
      table_.end(i);
    }
  }
}

void Portail::recevoir(uint8_t c, const uint8_t *octets, size_t n, uint32_t maintenant, h1::Table::Random rnd,
                       Sortie &s) {
  if (c >= kConnexions || !cx_[c].ouverte) return;
  Connexion &x = cx_[c];
  for (size_t i = 0; i < n; i++) {
    const uint8_t o = octets[i];
    if (o == '\r') continue;
    if (o == '\n') {
      ligne(c, x.tampon, x.long_, maintenant, rnd, s);
      x.long_ = 0;
      if (!x.ouverte) return;
      continue;
    }
    if (x.long_ == kLigneMax) {
      fermetures_++;
      s.fermer(c);
      fermee(c);
      return;
    }
    x.tampon[x.long_++] = o;
  }
}

void Portail::ligne(uint8_t c, const uint8_t *l, size_t n, uint32_t maintenant, h1::Table::Random rnd, Sortie &s) {
  const h1::Parsed p = h1::parse(l, n);
  h1::Peer de;
  de.port = c;
  if (p.kind == h1::Kind::Salut) {
    char defi[h1::kDefiLen + 1];
    if (table_.onSalut(p, rnd, de, maintenant, defi) != h1::Verdict::Ok) {
      refus_++;
      return;
    }
    defi[h1::kDefiLen] = '\n';
    s.envoyer(c, (const uint8_t *)defi, h1::kDefiLen + 1);
    return;
  }
  if (p.kind != h1::Kind::Data) {
    refus_++;
    return;
  }
  uint8_t slot = 0;
  bool frais = false;
  if (table_.onData(p, de, maintenant, &slot, &frais) != h1::Verdict::Ok) {
    refus_++;
    return;
  }
  connexionDe_[slot] = c;
  Requete r;
  r.session = slot;
  if (!lireRequete(p.payload, p.payloadLen, &r.rid, r.commande) || nombre_ == kFile) {
    refus_++;
    return;
  }
  file_[(debut_ + nombre_) % kFile] = r;
  nombre_++;
}

bool Portail::requete(Requete *r) {
  if (nombre_ == 0) return false;
  *r = file_[debut_];
  debut_ = (uint8_t)((debut_ + 1) % kFile);
  nombre_--;
  return true;
}

bool Portail::repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n, Sortie &s) {
  if (session >= h1::kSlots) return false;
  const uint8_t c = connexionDe_[session];
  if (c == kAucune || !cx_[c].ouverte) return false;
  const size_t m = chargeReponse(rid, ligne, n, charge_, sizeof(charge_));
  if (m == 0) return false;
  char tete[h1::kHeaderMax + 1];
  const size_t t = table_.seal(session, charge_, m, tete);
  if (t == 0 || t + m + 1 > sizeof(sortie_)) return false;
  memcpy(sortie_, tete, t);
  memcpy(sortie_ + t, charge_, m);
  sortie_[t + m] = '\n';
  s.envoyer(c, sortie_, t + m + 1);
  envois_++;
  return true;
}

void Portail::diffuser(const uint8_t *ligne, size_t n, Sortie &s) {
  for (uint8_t i = 0; i < h1::kSlots; i++) repondre(i, 0, ligne, n, s);
}

void Portail::expirer(uint32_t maintenant) {
  const uint8_t liberes = table_.expire(maintenant);
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (liberes & (1u << i)) connexionDe_[i] = kAucune;
}

uint8_t Portail::sessions() const {
  uint8_t n = 0;
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (connexionDe_[i] != kAucune && cx_[connexionDe_[i]].ouverte) n++;
  return n;
}
```

- [x] **Step 4: Vérifier**

Run : `sh sonde/test/lancer.sh 2>&1 | grep -E "test_portail|ECHEC"`
Expected : `test_portail : ... 0 echec(s)`. Si `Table::seal` rend 0 pour une session terminée par `end` (cas « fermeture »), c'est attendu : `repondre` rend déjà false avant, par `connexionDe_`.

- [x] **Step 5: Commit**

```bash
git add sonde/src/portail.h sonde/src/portail.cpp sonde/test/test_portail.cpp sonde/test/lancer.sh
git commit -m "Porter l'enveloppe H1 sur des lignes TCP, une session par connexion

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Réseau : NVS, Wi-Fi, serveur TCP et Bonjour (colle ESP32)

**Files:**
- Create : `sonde/src/reseau.h`, `sonde/src/reseau.cpp`

**Interfaces:**
- Consumes : `Portail` (tâche 6), `Ligne` (`ligne.h`), `h1::keyId`, `h1::toHex`, `h1::wipe` (tâche 2).
- Produces (espace de noms `reseau`, appelé par `main.cpp`, tâche 8) :

```cpp
void gardeDemarrage();
bool configure();
void demarrer(const char *nomSonde);
void tour(uint32_t maintenant);
bool requete(Portail::Requete *r);
void repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n);
void diffuser(const uint8_t *ligne, size_t n);
bool ecrireWifi(const uint8_t *nom, size_t nNom, const uint8_t *mdp, size_t nMdp);
bool effacerWifi();
void nomWifiHexa(char sortie[2 * 32 + 1]);  // "" sans Wi-Fi configure
bool nouvelleCle(const uint8_t cle[32]);
bool effacerCle();
bool empreinte(char kid[9]);
void ajouterEtat(Ligne &l);
void ajouterCompteurs(Ligne &l);
```

Pas de test hôte (WiFi, Preferences, ESPmDNS) : vérification par compilation, puis au banc (tâche 10).

- [x] **Step 1: Écrire l'en-tête**

`sonde/src/reseau.h` :

```cpp
#pragma once
// ===========================================================================
//  Acces par le reseau de la sonde (spec sonde Wi-Fi, sections 3.2 a 3.6)
//
//  NVS (espace « reseau ») : nom et mot de passe du Wi-Fi, cle H1. Sans Wi-Fi
//  configure, rien ne demarre : la sonde est celle de la 1.0.0.
//  Demarrage (Wi-Fi configure) : gardeDemarrage() d'abord (sommeil profond de
//  0,2 s apres une reinitialisation qui n'est ni une mise sous tension ni un
//  reveil : la pile Zigbee laisse la radio sans reception Wi-Fi, essai du
//  10/10), puis demarrer() AVANT la pile Zigbee : cohabitation, Wi-Fi connecte
//  (15 s au plus), economie d'energie minimale, serveur TCP 5481, Bonjour.
//  Tout se fait dans la tache loop, jamais sous le verrou de la pile Zigbee.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "ligne.h"
#include "portail.h"

namespace reseau {

static constexpr uint16_t kPort = 5481;

void gardeDemarrage();
bool configure();
void demarrer(const char *nomSonde);
void tour(uint32_t maintenant);
bool requete(Portail::Requete *r);
void repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n);
void diffuser(const uint8_t *ligne, size_t n);
bool ecrireWifi(const uint8_t *nom, size_t nNom, const uint8_t *mdp, size_t nMdp);
bool effacerWifi();
void nomWifiHexa(char sortie[2 * 32 + 1]);
bool nouvelleCle(const uint8_t cle[32]);
bool effacerCle();
bool empreinte(char kid[9]);
// ,"reseau":{...} si le Wi-Fi est configure, rien sinon.
void ajouterEtat(Ligne &l);
// ,"sessions":..,"envois":..,"refus":..,"fermetures":..
void ajouterCompteurs(Ligne &l);

}  // namespace reseau
```

- [x] **Step 2: Écrire l'implémentation**

`sonde/src/reseau.cpp` :

```cpp
#include "reseau.h"

#include <Arduino.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WiFi.h>
#include <esp_coexist.h>
#include <esp_random.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include <esp_wifi.h>

#include "h1_proto.h"

namespace reseau {
namespace {

const char *const kEspace = "reseau";
const char *const kCleNom = "nom";
const char *const kCleMdp = "mdp";
const char *const kCleH1 = "cle";

Portail sPortail;
WiFiServer sServeur(kPort);
WiFiClient sClients[Portail::kConnexions];
// Place occupee : un WiFiClient deconnecte vaut false, mais sa place n'est
// liberee (Portail::fermee) qu'ici.
bool sOccupe[Portail::kConnexions] = {};
bool sDemarre = false;
bool sMdns = false;
char sNomSonde[33] = {0};
char sHote[40] = {0};
uint8_t sNomWifi[32];
size_t sNomWifiLong = 0;
uint32_t sConnexions = 0;  // adresses obtenues ; reconnexions = connexions - 1
uint32_t sRaison = 0;
uint32_t sEchecs = 0;      // ecritures TCP incompletes

void aleatoire(void *p, size_t n) { esp_fill_random(p, n); }

struct SortieTcp : Portail::Sortie {
  void envoyer(uint8_t c, const uint8_t *o, size_t n) override {
    if (c >= Portail::kConnexions || !sOccupe[c]) return;
    if (sClients[c].write(o, n) != n) sEchecs++;
  }
  // Appele par Portail, qui fait lui-meme sa fermee().
  void fermer(uint8_t c) override {
    if (c >= Portail::kConnexions) return;
    sClients[c].stop();
    sOccupe[c] = false;
  }
};
SortieTcp sSortie;

void surEvenement(arduino_event_id_t e, arduino_event_info_t info) {
  if (e == ARDUINO_EVENT_WIFI_STA_GOT_IP) sConnexions++;
  if (e == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) sRaison = info.wifi_sta_disconnected.reason;
}

// Nom d'hote mDNS : le nom de la sonde en minuscules, « _ » et « . » en « - ».
void nomHote(const char *nom) {
  size_t i = 0;
  for (; nom[i] && i < sizeof(sHote) - 1; i++) {
    const char c = nom[i];
    sHote[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : (c == '_' || c == '.') ? '-' : c;
  }
  sHote[i] = 0;
}

void annoncer() {
  if (sMdns || WiFi.status() != WL_CONNECTED) return;
  if (!MDNS.begin(sHote)) return;
  MDNS.setInstanceName(sNomSonde);
  MDNS.addService("_maillage-zigbee", "_tcp", kPort);
  MDNS.addServiceTxt("_maillage-zigbee", "_tcp", "v", "1");
  sMdns = true;
}

}  // namespace

bool configure() {
  Preferences p;
  if (!p.begin(kEspace, true)) return false;
  const bool oui = p.isKey(kCleNom);
  p.end();
  return oui;
}

void gardeDemarrage() {
  if (!configure()) return;
  const esp_reset_reason_t r = esp_reset_reason();
  if (r == ESP_RST_POWERON || r == ESP_RST_DEEPSLEEP) return;
  esp_sleep_enable_timer_wakeup(200000);
  esp_deep_sleep_start();
}

void demarrer(const char *nomSonde) {
  if (!configure()) return;
  snprintf(sNomSonde, sizeof(sNomSonde), "%s", nomSonde);
  nomHote(nomSonde);
  Preferences p;
  p.begin(kEspace, true);
  sNomWifiLong = p.getBytes(kCleNom, sNomWifi, sizeof(sNomWifi));
  char nom[33] = {0}, mdp[64] = {0};
  memcpy(nom, sNomWifi, sNomWifiLong);
  const size_t nMdp = p.getBytes(kCleMdp, mdp, sizeof(mdp) - 1);
  mdp[nMdp] = 0;
  uint8_t cle[32];
  const bool aCle = p.getBytes(kCleH1, cle, sizeof(cle)) == sizeof(cle);
  p.end();

  esp_coex_wifi_i154_enable();
  WiFi.persistent(false);  // ni nom ni mot de passe gardes par le pilote : la NVS « reseau » les a
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(sHote);
  WiFi.setAutoReconnect(true);
  WiFi.onEvent(surEvenement);
  WiFi.begin(nom, nMdp ? mdp : nullptr);
  h1::wipe(mdp, sizeof(mdp));
  const uint32_t debut = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - debut < 15000) delay(100);
  esp_wifi_set_ps(WIFI_PS_MIN_MODEM);

  sServeur.begin();
  sServeur.setNoDelay(true);
  if (aCle) sPortail.cle(cle);
  h1::wipe(cle, sizeof(cle));
  annoncer();
  sDemarre = true;
}

void tour(uint32_t maintenant) {
  if (!sDemarre) return;
  annoncer();
  WiFiClient nouveau = sServeur.accept();
  if (nouveau) {
    uint8_t libre = Portail::kAucune;
    for (uint8_t i = 0; i < Portail::kConnexions && libre == Portail::kAucune; i++)
      if (!sOccupe[i]) libre = i;
    if (libre == Portail::kAucune) {
      nouveau.stop();
    } else {
      sClients[libre] = nouveau;
      sClients[libre].setNoDelay(true);
      sOccupe[libre] = true;
      sPortail.ouverte(libre);
    }
  }
  static uint8_t tampon[512];
  for (uint8_t i = 0; i < Portail::kConnexions; i++) {
    if (!sOccupe[i]) continue;
    if (!sClients[i].connected()) {
      sClients[i].stop();
      sOccupe[i] = false;
      sPortail.fermee(i);
      continue;
    }
    int n;
    while ((n = sClients[i].read(tampon, sizeof(tampon))) > 0)
      sPortail.recevoir(i, tampon, (size_t)n, maintenant, aleatoire, sSortie);
  }
  sPortail.expirer(maintenant);
}

bool requete(Portail::Requete *r) { return sDemarre && sPortail.requete(r); }

void repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n) {
  if (sDemarre) sPortail.repondre(session, rid, ligne, n, sSortie);
}

void diffuser(const uint8_t *ligne, size_t n) {
  if (sDemarre) sPortail.diffuser(ligne, n, sSortie);
}

bool ecrireWifi(const uint8_t *nom, size_t nNom, const uint8_t *mdp, size_t nMdp) {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  const bool ok = p.putBytes(kCleNom, nom, nNom) == nNom && (nMdp ? p.putBytes(kCleMdp, mdp, nMdp) == nMdp
                                                                   : (p.remove(kCleMdp), true));
  p.end();
  return ok;
}

bool effacerWifi() {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  p.remove(kCleNom);
  p.remove(kCleMdp);
  p.end();
  return true;
}

void nomWifiHexa(char sortie[2 * 32 + 1]) {
  sortie[0] = 0;
  Preferences p;
  if (!p.begin(kEspace, true)) return;
  uint8_t nom[32];
  const size_t n = p.getBytes(kCleNom, nom, sizeof(nom));
  p.end();
  if (n) h1::toHex(nom, n, sortie);
}

bool nouvelleCle(const uint8_t cle[32]) {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  const bool ok = p.putBytes(kCleH1, cle, 32) == 32;
  p.end();
  if (ok) sPortail.cle(cle);  // les sessions ouvertes tombent
  return ok;
}

bool effacerCle() {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  p.remove(kCleH1);
  p.end();
  sPortail.cle(nullptr);
  return true;
}

bool empreinte(char kid[9]) {
  Preferences p;
  if (!p.begin(kEspace, true)) return false;
  uint8_t cle[32];
  const bool aCle = p.getBytes(kCleH1, cle, sizeof(cle)) == sizeof(cle);
  p.end();
  const bool ok = aCle && h1::keyId(cle, kid);
  h1::wipe(cle, sizeof(cle));
  return ok;
}

void ajouterEtat(Ligne &l) {
  if (!configure()) return;
  const bool connecte = WiFi.status() == WL_CONNECTED;
  l.ajoute(",\"reseau\":{\"connecte\":%s", connecte ? "true" : "false");
  if (connecte) l.ajoute(",\"canal\":%d,\"rssi\":%d", (int)WiFi.channel(), (int)WiFi.RSSI());
  else l.ajoute(",\"canal\":null,\"rssi\":null");
  l.ajoute(",\"raison\":%lu,\"sessions\":%u,\"envois\":%lu,\"echecs\":%lu,\"reconnexions\":%lu}",
           (unsigned long)sRaison, sPortail.sessions(), (unsigned long)sPortail.envois(),
           (unsigned long)(sEchecs + sPortail.refus()), (unsigned long)(sConnexions > 0 ? sConnexions - 1 : 0));
}

void ajouterCompteurs(Ligne &l) {
  l.ajoute(",\"sessions\":%u,\"envois\":%lu,\"refus\":%lu,\"fermetures\":%lu", sPortail.sessions(),
           (unsigned long)sPortail.envois(), (unsigned long)sPortail.refus(), (unsigned long)sPortail.fermetures());
}

}  // namespace reseau
```

- [x] **Step 3: Compiler**

Run : `cd sonde && ~/.platformio/penv/bin/pio run -e verif 2>&1 | grep -E "error|SUCCESS|FAILED|Flash:"`
Expected : `SUCCESS` ; `Flash:` d'environ 1,3 Mo sur 4 038 656 octets (WiFi et ESPmDNS sont liés même si `main.cpp` n'appelle encore rien : le compilateur les garde parce que `reseau.cpp` les référence). En cas d'erreur sur `esp_coex_wifi_i154_enable` introuvable, vérifier que `CONFIG_ESP_COEX_SW_COEXIST_ENABLE=y` dans `~/.platformio/packages/framework-arduinoespressif32-libs/esp32c6/sdkconfig` (c'est le cas en 55.03.312-1).

- [x] **Step 4: Commit**

```bash
git add sonde/src/reseau.h sonde/src/reseau.cpp
git commit -m "Ajouter le Wi-Fi, le serveur TCP et l'annonce Bonjour de la sonde

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: `main.cpp` : routage par canal, nouvelles commandes, démarrage

**Files:**
- Modify : `sonde/src/main.cpp`, `sonde/src/version.h`

**Interfaces:**
- Consumes : `Origine`, `distanceAutorisee` (tâche 5) ; `deriverCle` (tâche 4) ; espace `reseau` (tâche 7) ; `Commande.wifi*`, `Commande.alea`, `TypeCommande::kWifi…kCleEfface` (tâche 3) ; `h1::toHex`, `h1::keyId`, `h1::wipe`.
- Produces : firmware 1.1.0 : réponses `wifi`, `cle` ; `bonjour.reseau` ; `etat.reseau`.

Réponses (valeurs inventées) :
- `wifi …` : `{"v":1,"t":"wifi","id":7,"configure":true,"nom":"4D6F6E2057696669"}` puis redémarrage.
- `wifi` : `{"v":1,"t":"wifi","configure":false,"nom":null}`.
- `wifi efface` : `{"v":1,"t":"wifi","configure":false,"nom":null}` puis redémarrage.
- `cle nouvelle …` : `{"v":1,"t":"cle","id":3,"cle":"<64 HEXA>","empreinte":"91CB5C39"}`.
- `cle` et `cle efface` : `{"v":1,"t":"cle","empreinte":"91CB5C39"|null,"sessions":1,"envois":12,"refus":0,"fermetures":0}`.

- [x] **Step 1: Inclusions, version et en-tête**

`sonde/src/version.h` : `#define SONDE_VERSION "1.1.0"` et, dans le commentaire, `0.9.0 pendant l'essai (spec de la sonde, section 4), 1.0.0 ensuite, 1.1.0 avec le Wi-Fi (spec sonde Wi-Fi).`

Dans `main.cpp`, après `#include <esp_system.h>` : `#include <esp_random.h>` ; après `#include "cadence.h"` : `#include "canaux.h"` et `#include "cle_reseau.h"` ; après `#include "entrees.h"` : `#include "h1_proto.h"` ; après `#include "pagination.h"` : `#include "reseau.h"`.

Dans le commentaire d'en-tête, après la ligne `//    oubli                            quitter le reseau et l'oublier ; la` et ses deux lignes de suite, ajouter :

```cpp
//    wifi <NOM HEXA> <MDP HEXA | -> <id> | wifi | wifi efface
//                                     Wi-Fi de l'acces par le reseau (USB
//                                     seulement ; redemarre apres un
//                                     changement)
//    cle nouvelle <64 HEXA> <id> | cle | cle efface
//                                     cle H1 (USB seulement ; la cle n'est
//                                     rendue qu'une fois)
//  Par le reseau (spec sonde Wi-Fi) : « <rid> <commande> » dans un message H1,
//  liste blanche de canaux.h ; la reponse va au canal qui a demande, les
//  lignes signal a tous.
```

- [x] **Step 2: Sorties routées**

Remplacer `static void ecrire(void *, const uint8_t *octets, size_t n) { Serial.write(octets, n); }` par :

```cpp
// Destination des lignes : le canal de la commande en cours (l'USB par
// defaut), ou tous les canaux pour une ligne signal (sDiffusion).
static Origine sDestination;
static bool sDiffusion = false;
// Canal de la requete reseau Zigbee en cours (table, routes, echecs).
static Origine sOrigineTravail;

static void ecrire(void *, const uint8_t *octets, size_t n) {
  if (sDiffusion) {
    Serial.write(octets, n);
    reseau::diffuser(octets, n);
  } else if (sDestination.reseau) {
    reseau::repondre(sDestination.session, sDestination.rid, octets, n);
  } else {
    Serial.write(octets, n);
  }
}
```

Dans `evenements()`, remplacer le bloc `#if SONDE_SIGNAUX ... #endif` du cas `kBrut` par :

```cpp
#if SONDE_SIGNAUX
        sLigne.debut("signal");
        sLigne.ajoute(",\"signal\":\"0x%02X\",\"nom\":\"%s\",\"ok\":%s,\"detail\":%u", e.brut,
                      e.nom ? e.nom : "?", e.ok ? "true" : "false", e.detail);
        sDiffusion = true;
        finir();
        sDiffusion = false;
#endif
```

Dans `commencer()`, juste après `sId = c.id;` : `sOrigineTravail = sDestination;`.

Dans `progresser()`, entourer chacun des trois `rendre(...)` / `rendreEchecs()` du canal de la requête : remplacer

```cpp
      if (!sTable.actif()) {
        rendre(sTable, jsonEntreeVoisin);
        sTravail = Travail::kAucun;
      }
```

par

```cpp
      if (!sTable.actif()) {
        sDestination = sOrigineTravail;
        rendre(sTable, jsonEntreeVoisin);
        sDestination = Origine();
        sTravail = Travail::kAucun;
      }
```

et de même pour `rendre(sRoutes, jsonEntreeRoute)` et `rendreEchecs()`.

- [x] **Step 3: `bonjour` et `etat`**

Dans `cmdBonjour()`, avant `finir();` : `sLigne.ajoute(",\"reseau\":%s", reseau::configure() ? "true" : "false");`

Dans `cmdEtat()`, avant le dernier `finir();` : `reseau::ajouterEtat(sLigne);`

- [x] **Step 4: Nouvelles commandes**

Après `cmdSuspendre()` :

```cpp
// ---------------------------------------------------------------------------
//  Acces par le reseau (USB seulement : liste blanche de canaux.h)
// ---------------------------------------------------------------------------

static void redemarrer();

static void ajouteHexa(const char *cle, const uint8_t *o, size_t n) {
  char t[2 * kWifiNomMax + 1];
  h1::toHex(o, n, t);
  sLigne.ajoute(",\"%s\":\"%s\"", cle, t);
}

static void cmdWifi(const Commande &c) {
  if (!reseau::ecrireWifi(c.wifiNom, c.wifiNomLong, c.wifiMdp, c.wifiMdpLong)) return repondreErreur("ecriture");
  sLigne.debut("wifi");
  sLigne.ajoute(",\"id\":%lu,\"configure\":true", (unsigned long)c.id);
  ajouteHexa("nom", c.wifiNom, c.wifiNomLong);
  finir();
  redemarrer();
}

static void cmdWifiLire() {
  char nom[2 * kWifiNomMax + 1];
  reseau::nomWifiHexa(nom);
  sLigne.debut("wifi");
  if (nom[0]) sLigne.ajoute(",\"configure\":true,\"nom\":\"%s\"", nom);
  else sLigne.ajoute(",\"configure\":false,\"nom\":null");
  finir();
}

static void cmdWifiEfface() {
  if (!reseau::effacerWifi()) return repondreErreur("ecriture");
  sLigne.debut("wifi");
  sLigne.ajoute(",\"configure\":false,\"nom\":null");
  finir();
  redemarrer();
}

static void cmdCleNouvelle(const Commande &c) {
  uint8_t carte[32], cle[32];
  esp_fill_random(carte, sizeof(carte));
  const bool ok = deriverCle(c.alea, carte, cle) && reseau::nouvelleCle(cle);
  h1::wipe(carte, sizeof(carte));
  if (!ok) {
    h1::wipe(cle, sizeof(cle));
    return repondreErreur("ecriture");
  }
  char hexa[65], kid[9];
  h1::toHex(cle, sizeof(cle), hexa);
  h1::keyId(cle, kid);
  sLigne.debut("cle");
  sLigne.ajoute(",\"id\":%lu,\"cle\":\"%s\",\"empreinte\":\"%s\"", (unsigned long)c.id, hexa, kid);
  finir();
  h1::wipe(cle, sizeof(cle));
  h1::wipe(hexa, sizeof(hexa));
}

static void cmdCleLire() {
  char kid[9];
  sLigne.debut("cle");
  if (reseau::empreinte(kid)) sLigne.ajoute(",\"empreinte\":\"%s\"", kid);
  else sLigne.ajoute(",\"empreinte\":null");
  reseau::ajouterCompteurs(sLigne);
  finir();
}

static void cmdCleEfface() {
  if (!reseau::effacerCle()) return repondreErreur("ecriture");
  sLigne.debut("cle");
  sLigne.ajoute(",\"empreinte\":null");
  reseau::ajouterCompteurs(sLigne);
  finir();
}
```

(`redemarrer()` est défini plus bas : la déclaration avancée suffit.)

- [x] **Step 5: `executer` avec l'origine**

Remplacer toute la fonction `executer` par :

```cpp
static void executerCommande(const Commande &c, uint32_t maintenant) {
  switch (c.type) {
    case TypeCommande::kBonjour: return cmdBonjour();
    case TypeCommande::kNom: return cmdNom(c.nom);
    case TypeCommande::kEtat: return cmdEtat();
    case TypeCommande::kVoisins: return cmdVoisins();
    case TypeCommande::kTable: return commencer(c, Travail::kTable, maintenant);
    case TypeCommande::kRoutes: return commencer(c, Travail::kRoutes, maintenant);
    case TypeCommande::kEchecs: return commencer(c, Travail::kEchecs, maintenant);
    case TypeCommande::kSuspendre: return cmdSuspendre(true);
    case TypeCommande::kReprendre: return cmdSuspendre(false);
    case TypeCommande::kOubli: return cmdOubli(maintenant);
    case TypeCommande::kWifi: return cmdWifi(c);
    case TypeCommande::kWifiLire: return cmdWifiLire();
    case TypeCommande::kWifiEfface: return cmdWifiEfface();
    case TypeCommande::kCleNouvelle: return cmdCleNouvelle(c);
    case TypeCommande::kCleLire: return cmdCleLire();
    case TypeCommande::kCleEfface: return cmdCleEfface();
    case TypeCommande::kSyntaxe: return repondreErreur("syntaxe");
    case TypeCommande::kInconnue: return repondreErreur("inconnue");
  }
}

// La reponse va a l'origine ; par le reseau, la liste blanche d'abord.
static void executer(const char *ligne, uint32_t maintenant, const Origine &o) {
  sDestination = o;
  const Commande c = lireCommande(ligne);
  if (o.reseau && !distanceAutorisee(c.type)) repondreErreur("refuse");
  else executerCommande(c, maintenant);
  sDestination = Origine();
}
```

- [x] **Step 6: `setup` et `loop`**

Au tout début de `setup()`, avant `Serial.begin(115200);` :

```cpp
  // Avant tout : apres une reinitialisation qui n'est ni une mise sous tension
  // ni un reveil, sommeil profond de 0,2 s si le Wi-Fi est configure (spec
  // sonde Wi-Fi, 3.2). Sans Wi-Fi, ne fait rien.
  reseau::gardeDemarrage();
```

Avant `zigbee::demarrer();` :

```cpp
  // Le Wi-Fi d'abord, puis la pile Zigbee (cohabitation : essai du 10/10).
  reseau::demarrer(sNom);
```

Dans `loop()`, remplacer `else if (sCmdLong) executer(sCommande, millis());` par `else if (sCmdLong) executer(sCommande, millis(), Origine());`, et après la boucle `while (Serial.available()) {...}` ajouter :

```cpp
  reseau::tour(millis());
  Portail::Requete r;
  while (reseau::requete(&r)) {
    Origine o;
    o.reseau = true;
    o.session = r.session;
    o.rid = r.rid;
    executer(r.commande, millis(), o);
  }
```

- [x] **Step 7: Vérifier**

Run : `sh sonde/test/lancer.sh 2>&1 | grep -c ECHEC; cd sonde && ~/.platformio/penv/bin/pio run -e sonde -e verif 2>&1 | grep -E "warning: enumeration|error|SUCCESS|FAILED|Flash:"`
Expected : `0` ; deux `SUCCESS` ; aucune ligne `enumeration value ... not handled` ; `Flash:` vers 1,3 Mo sur 4 038 656 octets.

Contrôle à la lecture du diff (Review Focus 5) : `executer` refuse avant `executerCommande` dès que `o.reseau` et que `distanceAutorisee` est faux ; aucune autre fonction n'appelle `executerCommande`.

- [x] **Step 8: Commit**

```bash
git add sonde/src/main.cpp sonde/src/version.h
git commit -m "Router les reponses vers leur canal et ajouter le Wi-Fi a la sonde 1.1.0

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Outil `outils/sonde_reseau.py`

**Files:**
- Create : `outils/sonde_reseau.py`, `outils/test/test_sonde_reseau.py`
- Modify : `.gitignore` (racine), `outils/tester.sh` (rien : `unittest discover` trouve le nouveau test)

**Interfaces:**
- Consumes : `sonde_usb.ouvrir`, `sonde_usb.Sonde` (`commande(texte, types, id=None, delai=10.0)`) ; `outils/sonde.local.json` (`port`) comme `essai_sonde.py`.
- Produces : `python3 outils/sonde_reseau.py wifi | cle | [--hote H] bonjour|etat|voisins|table <cible>|routes <cible>|ecoute <secondes>`. La clé est rangée dans `outils/cle_reseau.local` (64 hexa, droits 600, ignoré par git) et jamais affichée.

- [x] **Step 1: Écrire les tests**

`outils/test/test_sonde_reseau.py` :

```python
"""Tests de outils/sonde_reseau.py : enveloppe H1 (vecteurs du pont Halo,
benq tools/host_tests/test_h1.cpp), requetes et reponses par le reseau."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import sonde_reseau as sr  # noqa: E402

PSK = bytes(range(32))
NA = bytes.fromhex("A0A1A2A3A4A5A6A7A8A9AAABACADAEAF")
SALUT = "H1 SALUT 630DCD29 A0A1A2A3A4A5A6A7A8A9AAABACADAEAF 52D853E3FFE9E9CCEFFA98BB5304B32D"
DEFI = "H1 DEFI 1234ABCD 505152535455565758595A5B5C5D5E5F BFF13F71B42243E6017D2807F8E6171F"
KS = "20D6D83D97ED44F2BBF8CE56389BD475CBE2B625CE6CE24768B6B4C1C625012F"
MSG_A = "H1 1234ABCD 1 FD97A0C9E604524B49C763452D0310CE id=1 json 1"
HDR_C = "H1 1234ABCD 1 347A2E6A129BC822ECFF39BEC910451C "
JSON_C = '{"v":1,"t":"hb","n":7,"ms":1234}'


class H1(unittest.TestCase):
    def test_kid(self):
        self.assertEqual(sr.kid(PSK), "630DCD29")

    def test_salut(self):
        self.assertEqual(sr.salut(PSK, NA), SALUT)

    def test_defi(self):
        self.assertEqual(sr.verifier_defi(DEFI, PSK, NA), ("1234ABCD", "505152535455565758595A5B5C5D5E5F"))
        self.assertIsNone(sr.verifier_defi(DEFI.replace("BFF1", "BFF2"), PSK, NA))

    def test_session(self):
        s = sr.Session(PSK, NA, "505152535455565758595A5B5C5D5E5F", "1234ABCD")
        self.assertEqual(s.ks.hex().upper(), KS)
        self.assertEqual(s.sceller("id=1 json 1"), MSG_A)
        self.assertEqual(s.ouvrir(HDR_C + JSON_C), JSON_C)
        self.assertIsNone(s.ouvrir(HDR_C + JSON_C), "rejeu refuse")

    def test_session_mac_faux(self):
        s = sr.Session(PSK, NA, "505152535455565758595A5B5C5D5E5F", "1234ABCD")
        self.assertIsNone(s.ouvrir(HDR_C.replace("347A", "347B") + JSON_C))


class Charges(unittest.TestCase):
    def test_reponse(self):
        self.assertEqual(sr.couper_rid('12 {"v":1}'), (12, '{"v":1}'))
        self.assertEqual(sr.couper_rid('0 {"v":1,"t":"signal"}'), (0, '{"v":1,"t":"signal"}'))
        self.assertIsNone(sr.couper_rid("x {}"))

    def test_hexa_wifi(self):
        self.assertEqual(sr.ligne_wifi("Mon Wifi", "motdepasse", 7), "wifi 4D6F6E2057696669 6D6F7464657061737365 7")
        self.assertEqual(sr.ligne_wifi("Ouvert", "", 8), "wifi 4F7576657274 - 8")
        self.assertEqual(sr.ligne_wifi("Café", "motdepasse", 1)[:15], "wifi 436166C3A9")
        with self.assertRaises(ValueError):
            sr.ligne_wifi("X", "court", 1)


if __name__ == "__main__":
    unittest.main()
```

- [x] **Step 2: Vérifier l'échec**

Run : `python3 -m unittest discover -s outils/test -p "test_sonde_reseau.py" 2>&1 | tail -3`
Expected : `ModuleNotFoundError: No module named 'sonde_reseau'`.

- [x] **Step 3: Implémenter**

`outils/sonde_reseau.py` :

```python
#!/usr/bin/env python3
"""Client de la sonde Zigbee 1.1.0 par le reseau (spec sonde Wi-Fi, section 6), pour le banc.

  python3 outils/sonde_reseau.py wifi
      USB : demande le nom du Wi-Fi (visible) et le mot de passe (masque), les envoie a la sonde, qui
      redemarre. Rien n'est affiche du mot de passe.
  python3 outils/sonde_reseau.py cle
      USB : nouvelle cle d'acces ; rangee dans outils/cle_reseau.local (droits 600, ignore par git),
      jamais affichee : seule l'empreinte l'est.
  python3 outils/sonde_reseau.py [--hote H] bonjour | etat | voisins | table <cible> | routes <cible>
  python3 outils/sonde_reseau.py [--hote H] ecoute <secondes>
      Reseau : poignee de main H1 sur <hote>:5481 (par defaut sonde-z1.local, le nom de la sonde en
      minuscules), puis la commande ; ecoute compte les lignes signal recues.

Port USB : "port" de outils/sonde.local.json. Aucun agent ne lance cet outil (il ouvre un port serie et
utilise la vraie cle).
"""
import getpass
import hashlib
import hmac
import json
import os
import secrets
import socket
import sys
import time

ICI = os.path.dirname(os.path.abspath(__file__))
FICHIER_CLE = os.path.join(ICI, "cle_reseau.local")
PORT = 5481


def _mac(cle, texte):
    return hmac.new(cle, texte, hashlib.sha256).digest()[:16].hex().upper()


def kid(psk):
    return hashlib.sha256(psk).hexdigest()[:8].upper()


def salut(psk, na):
    k, n = kid(psk), na.hex().upper()
    return f"H1 SALUT {k} {n} {_mac(psk, f'H1|SALUT|{k}|{n}'.encode())}"


def verifier_defi(ligne, psk, na):
    champs = ligne.split(" ")
    if len(champs) != 5 or champs[:2] != ["H1", "DEFI"]:
        return None
    sid, nc, mac = champs[2], champs[3], champs[4]
    attendu = _mac(psk, f"H1|DEFI|{kid(psk)}|{na.hex().upper()}|{nc}|{sid}".encode())
    return (sid, nc) if hmac.compare_digest(attendu, mac) else None


class Session:
    def __init__(self, psk, na, nc, sid):
        self.sid = sid
        self.ks = hmac.new(psk, f"H1|SESSION|{na.hex().upper()}|{nc}|{sid}".encode(), hashlib.sha256).digest()
        self.ctr = 0
        self.haut, self.bits = 0, 0

    def sceller(self, charge):
        self.ctr += 1
        mac = _mac(self.ks, f"A|{self.sid}|{self.ctr}|".encode() + charge.encode())
        return f"H1 {self.sid} {self.ctr} {mac} {charge}"

    def ouvrir(self, ligne):
        champs = ligne.split(" ", 4)
        if len(champs) != 5 or champs[0] != "H1" or champs[1] != self.sid:
            return None
        c = champs[2]
        if not c.isdigit() or c.startswith("0"):
            return None
        ctr = int(c)
        if not hmac.compare_digest(_mac(self.ks, f"C|{self.sid}|{ctr}|".encode() + champs[4].encode()), champs[3]):
            return None
        if ctr > self.haut:
            saut = ctr - self.haut
            self.bits = (0 if saut >= 32 else (self.bits << saut) & 0xFFFFFFFF) | 1
            self.haut = ctr
        else:
            recul = self.haut - ctr
            if recul >= 32 or self.bits & (1 << recul):
                return None
            self.bits |= 1 << recul
        return champs[4]


def couper_rid(charge):
    rid, _, json_ = charge.partition(" ")
    if not rid.isdigit() or not json_:
        return None
    return int(rid), json_


def ligne_wifi(nom, mdp, id_):
    n = nom.encode("utf-8")
    m = mdp.encode("utf-8")
    if not 1 <= len(n) <= 32 or (m and not 8 <= len(m) <= 63) or b"\x00" in n + m:
        raise ValueError("nom de 1 a 32 octets, mot de passe vide ou de 8 a 63 octets")
    return f"wifi {n.hex().upper()} {m.hex().upper() if m else '-'} {id_}"


# --- USB --------------------------------------------------------------------

def _sonde_usb():
    import sonde_usb  # noqa: E402 (meme dossier)

    with open(os.path.join(ICI, "sonde.local.json")) as f:
        port = json.load(f)["port"]
    s = sonde_usb.Sonde(sonde_usb.ouvrir(port))
    s.verifier()
    return s


def cmd_wifi():
    nom = input("Nom du Wi-Fi (2,4 GHz) : ")
    mdp = getpass.getpass("Mot de passe (vide : reseau ouvert) : ")
    try:
        ligne = ligne_wifi(nom, mdp, 1)
    finally:
        mdp = None
    r = _sonde_usb().commande(ligne, ("wifi", "erreur"))
    del ligne
    print("Wi-Fi :", "enregistre, la sonde redemarre" if r and r.get("configure") else r)


def cmd_cle():
    alea = secrets.token_bytes(32)
    r = _sonde_usb().commande(f"cle nouvelle {alea.hex().upper()} 1", ("cle", "erreur"))
    if not r or r.get("t") != "cle" or "cle" not in r:
        print("Echec :", r)
        return 1
    cle = r["cle"]
    if kid(bytes.fromhex(cle)) != r.get("empreinte"):
        print("Empreinte fausse : cle ignoree")
        return 1
    ancien = os.umask(0o077)
    try:
        with open(FICHIER_CLE, "w") as f:
            f.write(cle + "\n")
    finally:
        os.umask(ancien)
    print("Cle rangee dans outils/cle_reseau.local, empreinte", r["empreinte"])
    return 0


# --- Reseau -----------------------------------------------------------------

class Client:
    def __init__(self, hote, psk):
        self.s = socket.create_connection((hote, PORT), timeout=10)
        self.tampon = b""
        na = secrets.token_bytes(16)
        self._ecrire(salut(psk, na))
        defi = verifier_defi(self._lire(5.0), psk, na)
        if not defi:
            raise RuntimeError("poignee de main refusee (cle ?)")
        self.session = Session(psk, na, defi[1], defi[0])
        self.rid = 0

    def _ecrire(self, ligne):
        self.s.sendall(ligne.encode() + b"\n")

    def _lire(self, attente):
        self.s.settimeout(attente)
        while b"\n" not in self.tampon:
            d = self.s.recv(4096)
            if not d:
                raise ConnectionError("connexion fermee par la sonde")
            self.tampon += d
        ligne, self.tampon = self.tampon.split(b"\n", 1)
        return ligne.decode()

    def commande(self, texte, delai=15.0):
        """Lignes JSON de la reponse (jusqu'a "suite": false pour une liste)."""
        self.rid += 1
        self._ecrire(self.session.sceller(f"{self.rid} {texte}"))
        lignes, fin = [], time.time() + delai
        while time.time() < fin:
            charge = self.session.ouvrir(self._lire(max(0.1, fin - time.time())))
            r = couper_rid(charge) if charge else None
            if not r or r[0] != self.rid:
                continue
            j = json.loads(r[1])
            lignes.append(j)
            if not j.get("suite"):
                return lignes
        return lignes

    def ecouter(self, secondes):
        n, fin = 0, time.time() + secondes
        while time.time() < fin:
            try:
                charge = self.session.ouvrir(self._lire(max(0.1, fin - time.time())))
            except socket.timeout:
                break
            r = couper_rid(charge) if charge else None
            if r and r[0] == 0:
                n += 1
        return n


def _psk():
    with open(FICHIER_CLE) as f:
        return bytes.fromhex(f.read().strip())


def main(argv):
    hote = "sonde-z1.local"
    if argv[:1] == ["--hote"] and len(argv) >= 2:
        hote, argv = argv[1], argv[2:]
    if not argv:
        print(__doc__)
        return 2
    if argv == ["wifi"]:
        return cmd_wifi()
    if argv == ["cle"]:
        return cmd_cle()
    c = Client(hote, _psk())
    if argv[0] == "ecoute" and len(argv) == 2:
        print(c.ecouter(float(argv[1])), "lignes signal")
        return 0
    if argv[0] in ("table", "routes") and len(argv) == 2:
        texte = f"{argv[0]} {argv[1].upper()} 1"
    elif argv[0] in ("bonjour", "etat", "voisins") and len(argv) == 1:
        texte = argv[0]
    else:
        print(__doc__)
        return 2
    for j in c.commande(texte, delai=130.0 if argv[0] in ("table", "routes") else 15.0):
        print(json.dumps(j, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
```

Dans `.gitignore`, après `outils/sonde.local.json` : `outils/cle_reseau.local`.

- [x] **Step 4: Vérifier**

Run : `python3 -m unittest discover -s outils/test -p "test_sonde_reseau.py" 2>&1 | tail -3; git check-ignore outils/cle_reseau.local; sh outils/tester.sh 2>&1 | tail -3`
Expected : `OK` ; `outils/cle_reseau.local` ; tous les tests sans carte passent, garde `aucun dans les fichiers suivis`.

- [x] **Step 5: Commit**

```bash
git add outils/sonde_reseau.py outils/test/test_sonde_reseau.py .gitignore
git commit -m "Ajouter l'outil de banc de la sonde par le reseau

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Banc de la sonde 1.1.0 (avec Djoko)

Rien à coder. Chaque étape se fait dans un onglet du Terminal de l'app, doublé d'un guetteur en arrière-plan ; Maillage Zigbee est quitté avant tout flash.

- [x] **Step 1: Flash sans effacement**, `python3 outils/flasher.py` ; puis `python3 outils/essai_sonde.py etat` toutes les 8 s jusqu'à `"membre":true` (2 min au plus). Attendu : la sonde reste membre (nouvelle table de partitions, `zb_storage` en place), `bonjour.version` = `1.1.0`, `bonjour.reseau` = `false`, pas d'objet `reseau` dans `etat`.
- [x] **Step 2: Clé**, `python3 outils/sonde_reseau.py cle` : attendu « Cle rangee… empreinte XXXXXXXX ».
- [x] **Step 3: Wi-Fi**, Djoko lance lui-même `python3 outils/sonde_reseau.py wifi` dans un onglet du Terminal (saisie masquée) ; la sonde redémarre ; `etat` par l'USB : `reseau.connecte` = `true`, canal et signal présents, la sonde est membre.
- [x] **Step 4: Réseau**, `python3 outils/sonde_reseau.py etat`, puis `table 0000` : réponses complètes ; `ecoute 600` pendant une tournée de l'outil USB : des lignes signal arrivent.
- [x] **Step 5: Refus**, à la main avec le client Python (`c.commande("oubli")`) : attendu `{"v":1,"t":"erreur","erreur":"refuse"}`, la sonde reste membre.
- [x] **Step 6: Chargeur mural**, Djoko débranche la sonde du Mac et la branche sur un chargeur ; `etat` et `table 0000` par le réseau ; `membre` vrai.
- [x] **Step 7: Bilan** dans la mémoire du projet ; la partie 2 commence.

---

# Partie 2 — L'app 1.1.0

Avant la tâche 11 : la partie 1 est fusionnée et la sonde du banc est en 1.1.0, avec clé et Wi-Fi (tâche 10).

### Task 11: Enveloppe H1 côté app

**Files:**
- Create (copie) : `MaillageCoeur/Reseau/EnveloppeH1.swift` depuis `~/Documents/Dev/esp32/benq/apps/macos/HaloProtocole/Reseau/EnveloppeH1.swift`
- Create (copie adaptée) : `MaillageCoeurTests/EnveloppeH1Tests.swift` depuis `~/Documents/Dev/esp32/benq/apps/macos/HaloProtocoleTests/EnveloppeH1Tests.swift`

**Interfaces:**
- Produces (module `MaillageCoeur`, publics) : `enum H1` (`hexa(_:)`, `octets(hexa:)`, `aleatoire(_:)`, `kid(cle:)`, `salut(cle:na:)`, `verifierDefi(_:cle:na:)`, `cleSession(cle:na:nc:sid:)` ; internes : `mac(_:_:)`, `estHexa`, `egaux`), `struct FenetreAntiRejeu`, `struct SessionH1` (`init(sid:ks:)`, `sceller(_:) -> Data`, `ouvrir(_:) -> Data?`, `ecartes`).

- [x] **Step 1: Copier**

```bash
B=~/Documents/Dev/esp32/benq/apps/macos
mkdir -p MaillageCoeur/Reseau
cp $B/HaloProtocole/Reseau/EnveloppeH1.swift MaillageCoeur/Reseau/EnveloppeH1.swift
cp $B/HaloProtocoleTests/EnveloppeH1Tests.swift MaillageCoeurTests/EnveloppeH1Tests.swift
```

- [x] **Step 2: Adapter**

Dans `MaillageCoeurTests/EnveloppeH1Tests.swift` : `@testable import HaloProtocole` → `@testable import MaillageCoeur` ; le commentaire `/// Vecteurs de docs/PROTOCOLE-JSON.md 10.4 (les memes que tools/host_tests/test_h1.cpp).` → `/// Vecteurs du pont Halo (benq 3a1ad2f, docs/PROTOCOLE-JSON.md 10.4), les memes que sonde/test/test_h1.cpp.`

En tête de `MaillageCoeur/Reseau/EnveloppeH1.swift`, après les `import` :

```swift
// Repris tel quel du pont Halo (depot benq, commit 3a1ad2f). Maillage Zigbee : un message H1 est
// une ligne TCP (spec sonde Wi-Fi, 3.3 ; CanalReseau). Ne pas changer les regles d'ici sans
// changer le pont Halo et Maillage Thread.
```

Si un nom de type entre en conflit dans `MaillageCoeur` (vérifier : `grep -rn "enum H1\|struct SessionH1\|FenetreAntiRejeu" MaillageCoeur MaillageZigbee`), le signaler au contrôleur sans renommer.

- [x] **Step 3: Lancer les tests**

Run : `outils/tester-app.sh MaillageCoeurTests/EnveloppeH1Tests`
Expected : `** TEST SUCCEEDED **`, 10 tests (ceux du pont).

- [x] **Step 4: Commit**

```bash
git add MaillageCoeur/Reseau/EnveloppeH1.swift MaillageCoeurTests/EnveloppeH1Tests.swift
git commit -m "Reprendre l'enveloppe H1 du pont Halo dans le coeur de l'app

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Protocole : `reseau`, `wifi` et `cle`

**Files:**
- Modify : `MaillageCoeur/Sonde/ProtocoleSonde.swift`
- Test : `MaillageCoeurTests/ProtocoleSondeTests.swift`

**Interfaces:**
- Consumes : `H1.hexa(_:)`, `H1.octets(hexa:)` (tâche 11).
- Produces :
  - `Bonjour.reseau: Bool?` (init `reseau: Bool? = nil`, dernier paramètre) ; `Bonjour.accepteReseau: Bool` (version ≥ 1.1.0).
  - `public struct ReseauSonde: Hashable, Sendable, Codable { connecte: Bool; canal: Int?; rssi: Int?; raison: Int?; sessions: Int?; envois: Int?; echecs: Int?; reconnexions: Int? }` ; `EtatSonde.reseau: ReseauSonde?` (init `reseau: ReseauSonde? = nil`, dernier paramètre).
  - `public struct WifiSonde: Hashable, Sendable, Codable { id: Int?; configure: Bool; nom: String? ; nomTexte: String? }`.
  - `public struct CleSonde: Hashable, Sendable, Codable { id: Int?; cle: String?; empreinte: String? }`.
  - `MessageSonde.wifi(WifiSonde)`, `MessageSonde.cle(CleSonde)`.
  - `CommandeSonde.wifi(nom: Data, motDePasse: Data, id: Int)`, `CommandeSonde.cleNouvelle(alea: Data, id: Int)`.

- [x] **Step 1: Écrire les tests**

Ajouter à `MaillageCoeurTests/ProtocoleSondeTests.swift` (dans la suite existante, ou une nouvelle `@Suite("Protocole de la sonde : acces par le reseau")`) :

```swift
@Suite("Protocole de la sonde : acces par le reseau")
struct ProtocoleReseauTests {
    @Test func bonjourReseau() throws {
        let l = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false,"reseau":true}"#
        guard case .bonjour(let b)? = MessageSonde.lire(Data(l.utf8)) else { Issue.record("bonjour"); return }
        #expect(b.reseau == true)
        #expect(b.accepteReseau)
    }

    @Test func versionsAcceptees() {
        #expect(!Bonjour(produit: "sonde-zigbee", version: "1.0.0").accepteReseau)
        #expect(!Bonjour(produit: "sonde-zigbee", version: "1.0.9").accepteReseau)
        #expect(Bonjour(produit: "sonde-zigbee", version: "1.1.0").accepteReseau)
        #expect(Bonjour(produit: "sonde-zigbee", version: "1.10.2").accepteReseau)
        #expect(Bonjour(produit: "sonde-zigbee", version: "2.0.0").accepteReseau)
        #expect(!Bonjour(produit: "sonde-zigbee", version: "x").accepteReseau)
    }

    @Test func etatReseau() throws {
        let l = #"{"v":1,"t":"etat","membre":true,"recherche":false,"court":"5E6F","ieee":"A000000000000001","role":"final","parent":null,"pan":"1234","epid":"A0000000000000FF","canal":25,"suspendue":false,"pile":"1.6.8","reseau":{"connecte":true,"canal":6,"rssi":-58,"raison":0,"sessions":1,"envois":12,"echecs":0,"reconnexions":2}}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(l.utf8)) else { Issue.record("etat"); return }
        #expect(e.reseau == ReseauSonde(connecte: true, canal: 6, rssi: -58, raison: 0, sessions: 1, envois: 12, echecs: 0,
                                        reconnexions: 2))
    }

    @Test func etatSansReseau() throws {
        let l = #"{"v":1,"t":"etat","membre":false,"suspendue":false}"#
        guard case .etat(let e)? = MessageSonde.lire(Data(l.utf8)) else { Issue.record("etat"); return }
        #expect(e.reseau == nil)
    }

    @Test func wifi() throws {
        let l = #"{"v":1,"t":"wifi","id":7,"configure":true,"nom":"4D6F6E2057696669"}"#
        guard case .wifi(let w)? = MessageSonde.lire(Data(l.utf8)) else { Issue.record("wifi"); return }
        #expect(w.id == 7 && w.configure && w.nomTexte == "Mon Wifi")
    }

    @Test func cle() throws {
        let l = #"{"v":1,"t":"cle","id":3,"cle":"62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D","empreinte":"91CB5C39"}"#
        guard case .cle(let c)? = MessageSonde.lire(Data(l.utf8)) else { Issue.record("cle"); return }
        #expect(c.id == 3 && c.empreinte == "91CB5C39" && c.cle?.count == 64)
    }

    @Test func wifiHexaUtf8() {
        let c = CommandeSonde.wifi(nom: Data("Café 2,4".utf8), motDePasse: Data("motdepasse".utf8), id: 7)
        #expect(c.ligne == "wifi 436166C3A920322C34 6D6F7464657061737365 7\n")
        #expect(CommandeSonde.wifi(nom: Data("Ouvert".utf8), motDePasse: Data(), id: 8).ligne == "wifi 4F7576657274 - 8\n")
    }

    @Test func cleNouvelle() {
        let c = CommandeSonde.cleNouvelle(alea: Data((0..<32).map { UInt8($0) }), id: 3)
        #expect(c.ligne == "cle nouvelle 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F 3\n")
    }
}
```

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageCoeurTests/ProtocoleReseauTests`
Expected : erreurs de compilation (`reseau`, `ReseauSonde`, `.wifi`, `.cle`, `accepteReseau` inconnus).

- [x] **Step 3: Implémenter**

Dans `ProtocoleSonde.swift` :

1. `Bonjour` : ajouter la propriété `/// Wi-Fi configure (sonde 1.1.0 et plus) ; nil avant. public let reseau: Bool?`, le paramètre `reseau: Bool? = nil` en fin d'`init` (et `self.reseau = reseau`), et :

```swift
    /// Firmware 1.1.0 ou plus : l'acces par le reseau existe (spec sonde Wi-Fi, 4.3).
    public var accepteReseau: Bool {
        let n = version.split(separator: ".").map { Int($0) }
        guard n.count >= 2, let majeur = n[0], let mineur = n[1] else { return false }
        return majeur > 1 || (majeur == 1 && mineur >= 1)
    }
```

2. Avant `public struct EtatSonde` :

```swift
/// Acces par le reseau de la sonde (`etat.reseau`, firmware 1.1.0, Wi-Fi configure) :
/// `{"connecte":true,"canal":6,"rssi":-58,"raison":0,"sessions":1,"envois":12,"echecs":0,"reconnexions":2}`.
public struct ReseauSonde: Hashable, Sendable, Codable {
    public let connecte: Bool
    public let canal: Int?
    public let rssi: Int?
    /// Derniere raison de deconnexion du Wi-Fi (`wifi_err_reason_t`), 0 : aucune.
    public let raison: Int?
    public let sessions: Int?
    public let envois: Int?
    public let echecs: Int?
    public let reconnexions: Int?

    public init(connecte: Bool, canal: Int? = nil, rssi: Int? = nil, raison: Int? = nil, sessions: Int? = nil,
                envois: Int? = nil, echecs: Int? = nil, reconnexions: Int? = nil) {
        self.connecte = connecte
        self.canal = canal
        self.rssi = rssi
        self.raison = raison
        self.sessions = sessions
        self.envois = envois
        self.echecs = echecs
        self.reconnexions = reconnexions
    }
}
```

3. `EtatSonde` : propriété `public let reseau: ReseauSonde?`, paramètre `reseau: ReseauSonde? = nil` en fin d'`init` (`self.reseau = reseau`), `reseau` ajouté à `CodingKeys` (`case membre, recherche, court, ieee, role, parent, pan, epid, canal, suspendue, pile, reseau`), et dans `init(from:)` : `reseau = try c.decodeIfPresent(ReseauSonde.self, forKey: .reseau)`.

4. Avant `public enum MessageSonde` :

```swift
/// Reponse a `wifi` (USB) : `{"v":1,"t":"wifi","id":7,"configure":true,"nom":"4D6F6E2057696669"}` ; le nom du Wi-Fi en
/// hexadecimal, jamais le mot de passe.
public struct WifiSonde: Hashable, Sendable, Codable {
    public let id: Int?
    public let configure: Bool
    public let nom: String?

    public init(id: Int? = nil, configure: Bool, nom: String? = nil) {
        self.id = id
        self.configure = configure
        self.nom = nom
    }

    /// Le nom en texte (UTF-8) ; nil s'il n'y en a pas ou s'il n'est pas lisible.
    public var nomTexte: String? {
        nom.flatMap { H1.octets(hexa: $0) }.flatMap { String(data: $0, encoding: .utf8) }
    }
}

/// Reponse a `cle nouvelle` (la seule fois ou la cle sort de la carte) ou a `cle` (empreinte seule).
public struct CleSonde: Hashable, Sendable, Codable {
    public let id: Int?
    public let cle: String?
    public let empreinte: String?

    public init(id: Int? = nil, cle: String? = nil, empreinte: String? = nil) {
        self.id = id
        self.cle = cle
        self.empreinte = empreinte
    }
}
```

5. `MessageSonde` : cas `case wifi(WifiSonde)` et `case cle(CleSonde)` (après `case oubli(Bool)`), et dans `lire` : `case "wifi": return (try? d.decode(WifiSonde.self, from: json)).map { .wifi($0) }` et `case "cle": return (try? d.decode(CleSonde.self, from: json)).map { .cle($0) }`.

6. `CommandeSonde` : compléter le commentaire (« sauf `wifi` et `cle nouvelle`, envoyees par l'USB a la mise en service ») et ajouter :

```swift
    /// Wi-Fi de la sonde (USB seulement) : nom et mot de passe en hexadecimal, `-` pour un reseau ouvert.
    case wifi(nom: Data, motDePasse: Data, id: Int)
    /// Nouvelle cle de l'acces par le reseau (USB seulement) : l'alea de l'app, 32 octets.
    case cleNouvelle(alea: Data, id: Int)
```

et dans `ligne` :

```swift
        case let .wifi(nom, mdp, id): "wifi \(H1.hexa(nom)) \(mdp.isEmpty ? "-" : H1.hexa(mdp)) \(id)\n"
        case let .cleNouvelle(alea, id): "cle nouvelle \(H1.hexa(alea)) \(id)\n"
```

- [x] **Step 4: Vérifier**

Run : `outils/tester-app.sh MaillageCoeurTests/ProtocoleReseauTests MaillageCoeurTests`
Expected : `** TEST SUCCEEDED **` (les tests existants du protocole passent toujours).

- [x] **Step 5: Commit**

```bash
git add MaillageCoeur/Sonde/ProtocoleSonde.swift MaillageCoeurTests/ProtocoleSondeTests.swift
git commit -m "Lire l'acces reseau de la sonde et ecrire les commandes wifi et cle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: `CanalReseau` : TCP, H1 et rid

**Files:**
- Create : `MaillageZigbee/Sonde/CanalReseau.swift`
- Test : `MaillageZigbeeTests/CanalReseauTests.swift`

**Interfaces:**
- Consumes : `CanalSonde` (protocole de `SondeUSB.swift`), `H1`, `SessionH1` (tâche 11).
- Produces :

```swift
protocol TransportLignes: Sendable {
    /// Lignes recues, sans LF ; le flux finit quand la connexion se ferme ou echoue.
    func ouvrir() -> AsyncStream<Data>
    /// Une ligne, sans LF (le transport l'ajoute).
    func envoyer(_ ligne: Data)
    func fermer()
}
final class CanalReseau: CanalSonde {
    init(transport: any TransportLignes, cle: Data, delaiPoigneeDeMain: Duration = .seconds(5))
}
final class TransportTCP: TransportLignes {
    init(service: String, type: String = "_maillage-zigbee._tcp", delaiConnexion: Duration = .seconds(10))
}
struct DecoupeurLF: Sendable { mutating func ajouter(_ d: Data) -> (lignes: [Data], tropLongue: Bool) }  // 4 200 octets au plus
```

Règles : le SALUT part à l'ouverture ; sans DEFI valable dans `delaiPoigneeDeMain`, le transport est fermé (le flux finit) ; les commandes envoyées avant la poignée de main attendent et partent ensuite, dans l'ordre ; chaque commande reçoit un rid croissant à partir de 1 ; une ligne remonte si son rid est 0 (signal) ou un rid déjà envoyé sur cette connexion, sinon elle est ignorée.

- [x] **Step 1: Écrire les tests**

`MaillageZigbeeTests/CanalReseauTests.swift` :

```swift
import CryptoKit
import Foundation
@testable import MaillageCoeur
import Synchronization
import Testing
@testable import MaillageZigbee

/// La sonde cote reseau, faite avec les briques H1 : repond au SALUT par un DEFI (sid et nc fixes), ouvre les messages
/// de l'app, scelle les siens. `repondre` rend les lignes JSON a renvoyer pour une commande.
final class TransportFactice: TransportLignes {
    struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var recus: [String] = []       // charges ouvertes : « <rid> <commande> »
        var ks: Data?
        var ctrC: UInt32 = 0
        var fenetre = FenetreAntiRejeu()
        var ferme = false
    }

    static let sid = "1234ABCD"
    static let nc = "505152535455565758595A5B5C5D5E5F"
    let cle: Data
    let repondre: @Sendable (String) -> [String]
    let muet: Bool
    let etat = Mutex(Etat())

    init(cle: Data, muet: Bool = false, repondre: @escaping @Sendable (String) -> [String] = { _ in [] }) {
        self.cle = cle
        self.muet = muet
        self.repondre = repondre
    }

    func ouvrir() -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        return flux
    }

    func envoyer(_ ligne: Data) {
        let texte = String(decoding: ligne, as: UTF8.self)
        let champs = texte.split(separator: " ", maxSplits: 4, omittingEmptySubsequences: false).map(String.init)
        if champs.count == 5, champs[1] == "SALUT" {
            guard !muet, let na = H1.octets(hexa: champs[3]) else { return }
            let mac = H1.mac(SymmetricKey(data: cle),
                             Data("H1|DEFI|\(H1.kid(cle: cle))|\(H1.hexa(na))|\(Self.nc)|\(Self.sid)".utf8))
            let ks = H1.cleSession(cle: cle, na: na, nc: Self.nc, sid: Self.sid).withUnsafeBytes { Data($0) }
            etat.withLock { e in
                e.ks = ks
                e.suite?.yield(Data("H1 DEFI \(Self.sid) \(Self.nc) \(mac)".utf8))
            }
            return
        }
        guard champs.count == 5, champs[0] == "H1", champs[1] == Self.sid, let ctr = UInt32(champs[2]) else { return }
        let reponses: [String]? = etat.withLock { e in
            guard let ks = e.ks else { return nil }
            let attendu = H1.mac(SymmetricKey(data: ks), Data("A|\(Self.sid)|\(ctr)|".utf8) + Data(champs[4].utf8))
            guard attendu == champs[3], e.fenetre.accepter(ctr) else { return nil }
            e.recus.append(champs[4])
            return []
        }
        guard reponses != nil else { return }
        let (rid, _, commande) = Self.couper(champs[4])
        for json in repondre(commande) { emettre(rid: rid, json) }
    }

    /// Une ligne de la sonde : « <rid> <json> », scellee (sens C).
    func emettre(rid: String, _ json: String) {
        etat.withLock { e in
            guard let ks = e.ks else { return }
            e.ctrC += 1
            let charge = "\(rid) \(json)"
            let mac = H1.mac(SymmetricKey(data: ks), Data("C|\(Self.sid)|\(e.ctrC)|\(charge)".utf8))
            e.suite?.yield(Data("H1 \(Self.sid) \(e.ctrC) \(mac) \(charge)".utf8))
        }
    }

    func fermer() {
        etat.withLock { e in
            e.ferme = true
            e.suite?.finish()
        }
    }

    var recus: [String] { etat.withLock { $0.recus } }

    static func couper(_ charge: String) -> (String, Character, String) {
        guard let i = charge.firstIndex(of: " ") else { return (charge, " ", "") }
        return (String(charge[..<i]), " ", String(charge[charge.index(after: i)...]))
    }
}

@Suite("Canal reseau : poignee de main H1, rid, signaux", .timeLimit(.minutes(1)))
struct CanalReseauTests {
    static let cle = Data((0..<32).map { UInt8($0) })

    /// Les n premieres lignes du flux (5 s au plus).
    static func lire(_ flux: AsyncStream<Data>, _ n: Int) async -> [String] {
        var lignes: [String] = []
        for await l in flux {
            lignes.append(String(decoding: l, as: UTF8.self))
            if lignes.count == n { break }
        }
        return lignes
    }

    @Test func commandeEtReponse() async throws {
        let t = TransportFactice(cle: Self.cle) { c in c == "etat" ? [#"{"v":1,"t":"etat","membre":true}"#] : [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"etat","membre":true}"#])
        #expect(t.recus == ["1 etat"])
    }

    @Test func ridsCroissantsEtFileAvantPoigneeDeMain() async throws {
        let t = TransportFactice(cle: Self.cle) { c in [#"{"v":1,"t":"x","c":"\#(c)"}"#] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("bonjour\n")
        canal.envoyer("etat\n")
        _ = await Self.lire(flux, 2)
        #expect(t.recus == ["1 bonjour", "2 etat"])
    }

    @Test func signalRemonte() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        try await Task.sleep(for: .milliseconds(50))
        t.emettre(rid: "0", #"{"v":1,"t":"signal"}"#)
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"signal"}"#])
    }

    @Test func ridInattenduIgnore() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("etat\n")
        try await Task.sleep(for: .milliseconds(50))
        t.emettre(rid: "99", #"{"v":1,"t":"etat","intrus":true}"#)
        t.emettre(rid: "1", #"{"v":1,"t":"etat","membre":true}"#)
        #expect(await Self.lire(flux, 1) == [#"{"v":1,"t":"etat","membre":true}"#])
    }

    @Test func mauvaiseCleFermeLeCanal() async throws {
        let t = TransportFactice(cle: Data(repeating: 0x80, count: 32)) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle, delaiPoigneeDeMain: .milliseconds(200))
        let flux = try canal.ouvrir()
        #expect(await Self.lire(flux, 1).isEmpty, "DEFI faux : le flux finit sans ligne")
    }

    @Test func sondeMuetteFermeLeCanal() async throws {
        let t = TransportFactice(cle: Self.cle, muet: true)
        let canal = CanalReseau(transport: t, cle: Self.cle, delaiPoigneeDeMain: .milliseconds(200))
        let flux = try canal.ouvrir()
        #expect(await Self.lire(flux, 1).isEmpty)
        #expect(t.etat.withLock { $0.ferme })
    }

    @Test func coupurePendantRequete() async throws {
        let t = TransportFactice(cle: Self.cle) { _ in [] }
        let canal = CanalReseau(transport: t, cle: Self.cle)
        let flux = try canal.ouvrir()
        canal.envoyer("table 1A2B 1\n")
        try await Task.sleep(for: .milliseconds(50))
        t.fermer()
        #expect(await Self.lire(flux, 1).isEmpty, "le flux finit : Sonde rend nil a la requete en cours")
    }

    @Test func decoupeurLF() {
        var d = DecoupeurLF()
        var r = d.ajouter(Data("ab\ncd".utf8))
        #expect(r.lignes == [Data("ab".utf8)] && !r.tropLongue)
        r = d.ajouter(Data("e\r\n".utf8))
        #expect(r.lignes == [Data("cde".utf8)])
        r = d.ajouter(Data(repeating: 0x41, count: DecoupeurLF.longueurMax + 1))
        #expect(r.tropLongue)
    }
}
```

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/CanalReseauTests`
Expected : erreurs de compilation (`TransportLignes`, `CanalReseau`, `DecoupeurLF` inconnus).

- [x] **Step 3: Implémenter**

`MaillageZigbee/Sonde/CanalReseau.swift` :

```swift
import Foundation
import MaillageCoeur
import Network
import Synchronization

/// Lignes d'une connexion TCP (LF), le reseau dans l'app, un faux dans les tests.
protocol TransportLignes: Sendable {
    /// Lignes recues, sans LF ; le flux finit quand la connexion se ferme ou echoue.
    func ouvrir() -> AsyncStream<Data>
    /// Une ligne, sans LF (le transport l'ajoute).
    func envoyer(_ ligne: Data)
    func fermer()
}

/// Decoupe un flux TCP en lignes (LF ; un CR final est retire). Au-dela de `longueurMax` octets sans LF : `tropLongue`
/// (spec sonde Wi-Fi, 3.3), et l'appelant ferme la connexion.
struct DecoupeurLF: Sendable {
    static let longueurMax = 4200
    private var tampon = Data()

    mutating func ajouter(_ d: Data) -> (lignes: [Data], tropLongue: Bool) {
        var lignes: [Data] = []
        for o in d {
            if o == 0x0A {
                var l = tampon
                if l.last == 0x0D { l.removeLast() }
                lignes.append(l)
                tampon.removeAll(keepingCapacity: true)
            } else if tampon.count == Self.longueurMax {
                return (lignes, true)
            } else {
                tampon.append(o)
            }
        }
        return (lignes, false)
    }
}

/// La sonde par le reseau (spec sonde Wi-Fi, 4.1) : poignee de main H1 a l'ouverture, puis chaque commande dans un
/// message `H1 <sid> <ctr> <mac> <rid> <commande>` ; les lignes JSON remontent sans leur rid, comme celles de l'USB.
/// Une ligne remonte si son rid est 0 (signal) ou un rid deja envoye sur cette connexion ; sinon elle est ignoree.
final class CanalReseau: CanalSonde {
    private struct Etat {
        var session: SessionH1?
        var enAttente: [String] = []
        var dernierRid: UInt32 = 0
        var suite: AsyncStream<Data>.Continuation?
    }

    private let transport: any TransportLignes
    private let cle: Data
    private let delaiPoigneeDeMain: Duration
    private let etat = Mutex(Etat())

    init(transport: any TransportLignes, cle: Data, delaiPoigneeDeMain: Duration = .seconds(5)) {
        self.transport = transport
        self.cle = cle
        self.delaiPoigneeDeMain = delaiPoigneeDeMain
    }

    func ouvrir() throws -> AsyncStream<Data> {
        let (lignes, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        let recues = transport.ouvrir()
        let na = H1.aleatoire(16)
        transport.envoyer(H1.salut(cle: cle, na: na))
        let lecture = Task {
            for await l in recues { self.recevoir(l, na: na, cle: self.cle) }
            suite.finish()
        }
        let delai = delaiPoigneeDeMain
        Task { [transport] in
            try? await Task.sleep(for: delai)
            if self.etat.withLock({ $0.session == nil }) { transport.fermer() }
        }
        suite.onTermination = { [transport] _ in
            lecture.cancel()
            transport.fermer()
        }
        return lignes
    }

    func envoyer(_ ligne: String) {
        var texte = ligne
        if texte.hasSuffix("\n") { texte.removeLast() }
        let scelle: Data? = etat.withLock { e in
            e.dernierRid += 1
            let charge = "\(e.dernierRid) \(texte)"
            guard var s = e.session else {
                e.enAttente.append(charge)
                return nil
            }
            let d = s.sceller(Data(charge.utf8))
            e.session = s
            return d
        }
        if let scelle { transport.envoyer(scelle) }
    }

    func fermer() { transport.fermer() }

    private func recevoir(_ ligne: Data, na: Data, cle: Data) {
        let (aEnvoyer, json): ([Data], Data?) = etat.withLock { e in
            guard var s = e.session else {
                guard let (sid, nc) = H1.verifierDefi(ligne, cle: cle, na: na) else { return ([], nil) }
                var session = SessionH1(sid: sid, ks: H1.cleSession(cle: cle, na: na, nc: nc, sid: sid))
                let envois = e.enAttente.map { session.sceller(Data($0.utf8)) }
                e.enAttente = []
                e.session = session
                return (envois, nil)
            }
            let charge = s.ouvrir(ligne)
            e.session = s
            guard let charge, let espace = charge.firstIndex(of: 0x20),
                  let rid = UInt32(String(decoding: charge[charge.startIndex..<espace], as: UTF8.self)),
                  rid == 0 || rid <= e.dernierRid
            else { return ([], nil) }
            return ([], Data(charge[charge.index(after: espace)...]))
        }
        for d in aEnvoyer { transport.envoyer(d) }
        if let json { etat.withLock { $0.suite?.yield(json) } }
    }
}

/// TCP vers le service Bonjour de la sonde (Network.framework) : resolution par nom d'instance, sans adresse fixe.
/// Pas pret dans `delaiConnexion` : ferme.
final class TransportTCP: TransportLignes {
    private struct Etat {
        var suite: AsyncStream<Data>.Continuation?
        var decoupeur = DecoupeurLF()
    }

    private let connexion: NWConnection
    private let file = DispatchQueue(label: "fr.djoko.maillage.zigbee.sonde.tcp")
    private let delaiConnexion: Duration
    private let etat = Mutex(Etat())

    init(service: String, type: String = "_maillage-zigbee._tcp", delaiConnexion: Duration = .seconds(10)) {
        connexion = NWConnection(to: .service(name: service, type: type, domain: "local.", interface: nil), using: .tcp)
        self.delaiConnexion = delaiConnexion
    }

    func ouvrir() -> AsyncStream<Data> {
        let (flux, suite) = AsyncStream.makeStream(of: Data.self, bufferingPolicy: .unbounded)
        etat.withLock { $0.suite = suite }
        connexion.stateUpdateHandler = { [weak self] e in
            switch e {
            case .ready: self?.lire()
            case .failed, .cancelled: self?.finir()
            default: break
            }
        }
        connexion.start(queue: file)
        let delai = delaiConnexion
        Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard let self, self.connexion.state != .ready else { return }
            self.fermer()
        }
        return flux
    }

    func envoyer(_ ligne: Data) {
        connexion.send(content: ligne + Data([0x0A]), completion: .contentProcessed { _ in })
    }

    func fermer() {
        connexion.cancel()
        finir()
    }

    private func lire() {
        connexion.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] d, _, fin, erreur in
            guard let self else { return }
            if let d, !d.isEmpty {
                let (lignes, trop) = self.etat.withLock { $0.decoupeur.ajouter(d) }
                self.etat.withLock { e in lignes.forEach { e.suite?.yield($0) } }
                if trop { return self.fermer() }
            }
            if fin || erreur != nil { return self.fermer() }
            self.lire()
        }
    }

    private func finir() {
        etat.withLock { e in
            e.suite?.finish()
            e.suite = nil
        }
    }
}
```

`H1.mac` est interne au module `MaillageCoeur` : le fichier de test l'atteint par `@testable import MaillageCoeur`.

- [x] **Step 4: Vérifier**

Run : `outils/tester-app.sh MaillageZigbeeTests/CanalReseauTests`
Expected : `** TEST SUCCEEDED **`, 8 tests.

- [x] **Step 5: Commit**

```bash
git add MaillageZigbee/Sonde/CanalReseau.swift MaillageZigbeeTests/CanalReseauTests.swift
git commit -m "Ajouter le canal reseau de la sonde : TCP, poignee de main H1 et rid

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: `SondeUSB` devient `Sonde`, avec `configurerWifi` et `nouvelleCle`

**Files:**
- Rename : `MaillageZigbee/Sonde/SondeUSB.swift` → `MaillageZigbee/Sonde/Sonde.swift`
- Modify : `MaillageZigbee/Sonde/Sonde.swift`, `MaillageZigbee/Sonde/SondeMaillage.swift`, `MaillageZigbeeTests/SondeTests.swift`, `MaillageZigbeeTests/TourneeSondeTests.swift`

**Interfaces:**
- Consumes : `MessageSonde.wifi`, `MessageSonde.cle`, `CommandeSonde.wifi`, `CommandeSonde.cleNouvelle`, `WifiSonde`, `CleSonde` (tâche 12).
- Produces : `actor Sonde` (même interface que `SondeUSB`), plus :

```swift
func configurerWifi(nom: Data, motDePasse: Data) async throws -> WifiSonde
func nouvelleCle(alea: Data) async throws -> CleSonde
```

Une erreur générale (`{"t":"erreur",...}`) sert d'abord la requête réseau en cours, puis `cle nouvelle`, puis `wifi`, puis `etat`, puis `voisins`.

- [x] **Step 1: Renommer**

```bash
git mv MaillageZigbee/Sonde/SondeUSB.swift MaillageZigbee/Sonde/Sonde.swift
grep -rl "SondeUSB" MaillageZigbee MaillageZigbeeTests | xargs sed -i '' 's/SondeUSB/Sonde/g'
grep -rn "SondeUSB" MaillageZigbee MaillageZigbeeTests   # rien
```

Dans `Sonde.swift`, le commentaire de l'acteur : `/// Sonde branchee en USB : envoie...` → `/// La sonde, par l'USB ou par le reseau (le canal) : envoie...`. Le type imbriqué `FenetrePieces.Sonde` (une vue) ne gêne pas : la résolution lexicale le garde dans `FenetrePieces`.

Run : `outils/tester-app.sh MaillageZigbeeTests`
Expected : `** TEST SUCCEEDED **` (renommage seul).

- [x] **Step 2: Écrire les tests**

Ajouter à `MaillageZigbeeTests/SondeTests.swift` :

```swift
@Suite("Sonde : mise en service par l'USB (wifi, cle)", .timeLimit(.minutes(1)))
struct MiseEnServiceTests {
    @Test func nouvelleCle() async throws {
        let canal = CanalRejoue { l in
            l.hasPrefix("cle nouvelle ")
                ? [#"{"v":1,"t":"cle","id":1,"cle":"62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D","empreinte":"91CB5C39"}"#]
                : []
        }
        let s = Sonde(canal: canal)
        try await s.demarrer {}
        let c = try await s.nouvelleCle(alea: Data((0..<32).map { UInt8($0) }))
        #expect(c.empreinte == "91CB5C39")
        #expect(canal.envoyes == ["cle nouvelle 000102030405060708090A0B0C0D0E0F101112131415161718191A1B1C1D1E1F 1\n"])
    }

    @Test func configurerWifi() async throws {
        let canal = CanalRejoue { l in
            l.hasPrefix("wifi ") ? [#"{"v":1,"t":"wifi","id":1,"configure":true,"nom":"4D6F6E2057696669"}"#] : []
        }
        let s = Sonde(canal: canal)
        try await s.demarrer {}
        let w = try await s.configurerWifi(nom: Data("Mon Wifi".utf8), motDePasse: Data("motdepasse".utf8))
        #expect(w.configure && w.nomTexte == "Mon Wifi")
    }

    @Test func refusSertLaCommandeQuiAttend() async throws {
        let canal = CanalRejoue { l in l.hasPrefix("cle ") ? [#"{"v":1,"t":"erreur","erreur":"ecriture"}"#] : [] }
        let s = Sonde(canal: canal)
        try await s.demarrer {}
        await #expect(throws: Sonde.Erreur.refusee("ecriture")) {
            _ = try await s.nouvelleCle(alea: Data(repeating: 1, count: 32))
        }
    }

    @Test func sansReponse() async throws {
        let s = Sonde(canal: CanalRejoue { _ in [] }, delaiCommande: .milliseconds(100))
        try await s.demarrer {}
        await #expect(throws: Sonde.Erreur.sansReponse("wifi")) {
            _ = try await s.configurerWifi(nom: Data("X".utf8), motDePasse: Data())
        }
    }
}
```

- [x] **Step 3: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/MiseEnServiceTests`
Expected : `nouvelleCle` et `configurerWifi` inconnus.

- [x] **Step 4: Implémenter**

Dans `Sonde.swift`, après `private var attenteVoisins = ...` :

```swift
    private var attenteWifi = FileAttentes<Result<WifiSonde, Erreur>>()
    private var attenteCle = FileAttentes<Result<CleSonde, Erreur>>()
```

Après `voisins()` :

```swift
    /// Wi-Fi de la sonde (USB, mise en service) : elle repond puis redemarre pour l'appliquer.
    func configurerWifi(nom: Data, motDePasse: Data) async throws -> WifiSonde {
        guard !fermee else { throw Erreur.fermee }
        let jeton = nouveauJeton()
        let id = nouvelId()
        let r = await withCheckedContinuation { c in
            attenteWifi.ajouter(jeton, c)
            canal.envoyer(CommandeSonde.wifi(nom: nom, motDePasse: motDePasse, id: id).ligne)
            Task {
                try? await Task.sleep(for: self.delaiCommande)
                self.attenteWifi.expirer(jeton)
            }
        }
        guard let r else { throw fermee ? Erreur.fermee : Erreur.sansReponse("wifi") }
        return try r.get()
    }

    /// Nouvelle cle de l'acces par le reseau (USB, mise en service) : la seule fois ou la cle sort de la carte.
    func nouvelleCle(alea: Data) async throws -> CleSonde {
        guard !fermee else { throw Erreur.fermee }
        let jeton = nouveauJeton()
        let id = nouvelId()
        let r = await withCheckedContinuation { c in
            attenteCle.ajouter(jeton, c)
            canal.envoyer(CommandeSonde.cleNouvelle(alea: alea, id: id).ligne)
            Task {
                try? await Task.sleep(for: self.delaiCommande)
                self.attenteCle.expirer(jeton)
            }
        }
        guard let r else { throw fermee ? Erreur.fermee : Erreur.sansReponse("cle") }
        return try r.get()
    }
```

Dans `recevoir`, avant `case .erreur(let e)?:` :

```swift
        case .wifi(let w)?:
            attenteWifi.servir(.success(w))
        case .cle(let c)?:
            attenteCle.servir(.success(c))
```

et remplacer le corps du cas `.erreur` par :

```swift
            if let r = enCours {
                finirReseau(id: r.id, erreur: e)
            } else if !attenteCle.estVide {
                attenteCle.servir(.failure(Self.refus("cle", e)))
            } else if !attenteWifi.estVide {
                attenteWifi.servir(.failure(Self.refus("wifi", e)))
            } else if !attenteEtat.estVide {
                attenteEtat.servir(.failure(Self.refus("etat", e)))
            } else {
                attenteVoisins.servir(.failure(Self.refus("voisins", e)))
            }
```

Dans `clore()` : `attenteWifi.liberer()` et `attenteCle.liberer()`.

- [x] **Step 5: Vérifier**

Run : `outils/tester-app.sh MaillageZigbeeTests`
Expected : `** TEST SUCCEEDED **`.

- [x] **Step 6: Commit**

```bash
git add MaillageZigbee/Sonde/Sonde.swift MaillageZigbee/Sonde/SondeMaillage.swift MaillageZigbeeTests/SondeTests.swift MaillageZigbeeTests/TourneeSondeTests.swift
git commit -m "Renommer SondeUSB en Sonde et ajouter la mise en service wifi et cle

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Chemin de la sonde : réglage et décision

**Files:**
- Create : `MaillageZigbee/Sonde/CheminSonde.swift`
- Test : `MaillageZigbeeTests/CheminSondeTests.swift`

**Interfaces:**
- Produces :

```swift
enum ReglageChemin: String, CaseIterable, Sendable { case automatique, usb, reseau }
enum Acces: Equatable, Sendable { case usb, reseau }
enum CheminSonde {
    static let cleReglage = "sondeChemin"
    static func choisir(_ r: ReglageChemin, branchee: Bool, cleConnue: Bool, annoncee: Bool) -> Acces?
    static let serviceTrousseau = "fr.djoko.maillage.zigbee.sonde"
}
```

- [x] **Step 1: Écrire les tests**

`MaillageZigbeeTests/CheminSondeTests.swift` :

```swift
import Testing
@testable import MaillageZigbee

@Suite("Chemin de la sonde : USB ou reseau")
struct CheminSondeTests {
    @Test func automatique() {
        #expect(CheminSonde.choisir(.automatique, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminSonde.choisir(.automatique, branchee: true, cleConnue: false, annoncee: false) == .usb)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: true, annoncee: false) == nil)
        #expect(CheminSonde.choisir(.automatique, branchee: false, cleConnue: false, annoncee: true) == nil)
    }

    @Test func usbSeulement() {
        #expect(CheminSonde.choisir(.usb, branchee: true, cleConnue: true, annoncee: true) == .usb)
        #expect(CheminSonde.choisir(.usb, branchee: false, cleConnue: true, annoncee: true) == nil)
    }

    @Test func reseauSeulement() {
        #expect(CheminSonde.choisir(.reseau, branchee: true, cleConnue: true, annoncee: true) == .reseau)
        #expect(CheminSonde.choisir(.reseau, branchee: true, cleConnue: false, annoncee: true) == nil)
        #expect(CheminSonde.choisir(.reseau, branchee: false, cleConnue: true, annoncee: false) == nil)
    }

    @Test func reglageLu() {
        #expect(ReglageChemin(rawValue: "automatique") == .automatique)
        #expect(ReglageChemin(rawValue: "inconnu") == nil)
    }
}
```

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/CheminSondeTests`
Expected : `CheminSonde` inconnu.

- [x] **Step 3: Implémenter**

`MaillageZigbee/Sonde/CheminSonde.swift` :

```swift
import Foundation

/// Reglage « Chemin de la sonde » (spec sonde Wi-Fi, 4.2), garde dans les preferences.
enum ReglageChemin: String, CaseIterable, Sendable {
    case automatique, usb, reseau

    var libelle: String {
        switch self {
        case .automatique: String(localized: "Automatique")
        case .usb: String(localized: "USB seulement")
        case .reseau: String(localized: "Réseau seulement")
        }
    }
}

/// Par ou passe la sonde connectee.
enum Acces: Equatable, Sendable {
    case usb, reseau

    var libelle: String {
        switch self {
        case .usb: String(localized: "USB")
        case .reseau: String(localized: "Réseau")
        }
    }
}

enum CheminSonde {
    /// Cle des preferences du reglage.
    static let cleReglage = "sondeChemin"
    /// Trousseau des cles de l'acces par le reseau : compte = adresse longue de la sonde.
    static let serviceTrousseau = "fr.djoko.maillage.zigbee.sonde"

    /// Le chemin a prendre, ou nil (aucun possible). Automatique : l'USB si la sonde retenue est branchee, sinon le
    /// reseau si une cle est connue et la sonde annoncee par Bonjour.
    static func choisir(_ r: ReglageChemin, branchee: Bool, cleConnue: Bool, annoncee: Bool) -> Acces? {
        let reseau = cleConnue && annoncee
        switch r {
        case .automatique: return branchee ? .usb : reseau ? .reseau : nil
        case .usb: return branchee ? .usb : nil
        case .reseau: return reseau ? .reseau : nil
        }
    }
}
```

- [x] **Step 4: Vérifier**

Run : `outils/tester-app.sh MaillageZigbeeTests/CheminSondeTests`
Expected : `** TEST SUCCEEDED **`, 4 tests.

- [x] **Step 5: Commit**

```bash
git add MaillageZigbee/Sonde/CheminSonde.swift MaillageZigbeeTests/CheminSondeTests.swift
git commit -m "Decider du chemin de la sonde entre l'USB et le reseau

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: `SondeMaillage` : connexion par le réseau

**Files:**
- Modify : `MaillageZigbee/Sonde/SondeMaillage.swift`, `MaillageZigbee/MaillageZigbeeApp.swift` (si `SondeMaillage(...)` y est construit avec des arguments : vérifier que les valeurs par défaut suffisent)
- Test : `MaillageZigbeeTests/SondeReseauTests.swift`

**Interfaces:**
- Consumes : `Sonde` (tâche 14), `CanalReseau`, `TransportTCP` (tâche 13), `ReglageChemin`, `Acces`, `CheminSonde` (tâche 15), `TrousseauCles`, `TrousseauSysteme`, `TrousseauMemoire` (`Pont/Trousseau.swift`), `NavigateurBonjour` (`Pont/NavigateurBonjour.swift`), `Bonjour.accepteReseau` (tâche 12).
- Produces (sur `SondeMaillage`) :
  - `init(..., trousseau: any TrousseauCles = TrousseauSysteme(service: CheminSonde.serviceTrousseau), ouvrirReseau: @escaping (String, Data) -> any CanalSonde = { CanalReseau(transport: TransportTCP(service: $0), cle: $1) }, delaiReessaiReseau: Duration = .seconds(60), periodeEntretien: Duration = .seconds(240))` (paramètres ajoutés après `ouvrirCanal`).
  - `static let cleIeee = "sondeIeee"`.
  - `case injoignable` dans `Etat`.
  - `private(set) var acces: Acces?`, `private(set) var ieee: String?`, `private(set) var annoncee: Bool`.
  - `var reglageChemin: ReglageChemin { get set }` (préférence `CheminSonde.cleReglage`, `.automatique` par défaut ; écrire relance `reevaluer()`).
  - `var cleReseauConnue: Bool`.
  - `func annoncesChangees(_ noms: Set<String>)` (appelée par le navigateur Bonjour ; les tests l'appellent directement).
  - `func connecterReseau() async`.

Comportement :
- L'adresse longue de la sonde retenue (`bonjour.ieee`) est gardée dans `sondeIeee` dès qu'une connexion USB à la sonde retenue la donne ; « Oublier la sonde » l'efface, ainsi que la clé du trousseau pour cette adresse.
- `reevaluer()` est appelée à chaque changement de ports, d'annonces ou de réglage : elle applique `CheminSonde.choisir(reglageChemin, branchee:, cleConnue:, annoncee:)`. `.usb` : comportement actuel (connexion au port de la sonde retenue), y compris si la sonde est connectée par le réseau (bascule). `.reseau` : `connecterReseau()` si aucune connexion réseau n'est en place ni en cours. `nil` : `deconnecter(.absente)` si quelque chose est connecté ou en cours.
- `connecterReseau()` : `deconnecter(.connexion)`, puis `Sonde(canal: ouvrirReseau(nom, cle), delaiCommande: .seconds(3) + .seconds(3), delaiTable: delaiTable + .seconds(3))` ; `bonjour` doit dire la sonde Zigbee **et** `ieee` égal à `sondeIeee`, sinon `refusee` ; ensuite `acces = .reseau`, `etat = .connectee(b)`, `lireEtat`, première tournée, et une tâche d'entretien qui relit `etat` toutes les `periodeEntretien` hors tournée (la session H1 de la sonde est oubliée après 10 min sans message). Échec : `etat = .injoignable`, nouvel essai après `delaiReessaiReseau` tant que le réseau reste le chemin choisi.
- `deconnecter` remet `acces` à nil et annule l'entretien.

- [x] **Step 1: Écrire les tests**

`MaillageZigbeeTests/SondeReseauTests.swift` :

```swift
import Foundation
import MaillageCoeur
import Testing
@testable import MaillageZigbee

/// Valeurs inventees : la sonde « SONDE-01 », adresse longue A000000000000001, port USB de serie A0:00:00:00:00:01.
@MainActor
@Suite("Sonde par le reseau : choix du chemin, connexion, bascule", .timeLimit(.minutes(1)))
struct SondeReseauTests {
    static let bonjourReseau = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false,"reseau":true}"#
    static let bonjourAutre = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"B000000000000002","membre":true,"role":"final","suspendue":false,"reseau":true}"#
    static let cle = String(repeating: "AB", count: 32)

    static func sondeReseau(_ ligne: String) -> [String] {
        switch ligne {
        case "bonjour\n": [bonjourReseau]
        case "etat\n": [CanalRejoue.etatAttache]
        default: []
        }
    }

    /// Une sonde retenue (serie, nom, adresse longue), la cle dans un trousseau en memoire.
    static func faire(_ p: UserDefaults, cle: Bool = true, reponses: @escaping @Sendable (String) -> [String] = sondeReseau,
                      muette: Bool = false, ouvertures: Compteur = Compteur()) -> SondeMaillage {
        p.set("A0:00:00:00:00:01", forKey: SondeMaillage.cleSerie)
        p.set("SONDE-01", forKey: SondeMaillage.cleNom)
        p.set("A000000000000001", forKey: SondeMaillage.cleIeee)
        let t = TrousseauMemoire(cle ? ["A000000000000001": Self.cle] : [:])
        return SondeMaillage(preferences: p, actif: true,
                             ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } },
                             trousseau: t,
                             ouvrirReseau: { nom, _ in
                                 ouvertures.ajouter(nom)
                                 return muette ? CanalFerme() : CanalRejoue(repondre: reponses)
                             },
                             delaiReessaiReseau: .milliseconds(100),
                             delaiPremiereTournee: .seconds(3600))
    }

    @Test func reseauQuandDebranchee() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        guard case .connectee = s.etat else { Issue.record("etat \(s.etat)"); return }
        #expect(o.noms == ["SONDE-01"])
        await s.oublier()
    }

    @Test func usbPrioritaire() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        s.portsChanges([SondeMaillageTests.port])
        #expect(await SondeMaillageTests.sonder { s.acces == .usb })
        await s.oublier()
    }

    @Test func reglageUsbSeulement() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.reglageChemin = .usb
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(o.noms.isEmpty && s.etat == .absente)
        await s.oublier()
    }

    @Test func reglageReseauSeulement() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p)
        s.reglageChemin = .reseau
        s.annoncesChangees(["SONDE-01"])
        s.portsChanges([SondeMaillageTests.port])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        await s.oublier()
    }

    @Test func sansCle() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, cle: false, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        try await Task.sleep(for: .milliseconds(200))
        #expect(o.noms.isEmpty && s.etat == .absente && !s.cleReseauConnue)
        await s.oublier()
    }

    @Test func autreSondeRefusee() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = Self.faire(p, reponses: { $0 == "bonjour\n" ? [SondeReseauTests.bonjourAutre] : [] })
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { if case .refusee = s.etat { true } else { false } })
        #expect(s.acces == nil)
        await s.oublier()
    }

    @Test func injoignablePuisReessai() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, muette: true, ouvertures: o)  // connexion fermee aussitot : bonjour echoue
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.etat == .injoignable })
        #expect(await SondeMaillageTests.sonder { o.noms.count >= 2 }, "nouvel essai")
        await s.oublier()
    }

    @Test func reconnexionApresCoupure() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let o = Compteur()
        let s = Self.faire(p, ouvertures: o)
        s.portsChanges([])
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau })
        s.annoncesChangees([])
        #expect(await SondeMaillageTests.sonder { s.etat == .absente && s.acces == nil })
        s.annoncesChangees(["SONDE-01"])
        #expect(await SondeMaillageTests.sonder { s.acces == .reseau && o.noms.count == 2 })
        await s.oublier()
    }
}

/// Un canal qui se ferme des son ouverture (sonde injoignable).
struct CanalFerme: CanalSonde {
    func ouvrir() throws -> AsyncStream<Data> { AsyncStream { $0.finish() } }
    func envoyer(_ ligne: String) {}
    func fermer() {}
}

/// Noms des services ouverts par le reseau, dans l'ordre.
final class Compteur: @unchecked Sendable {
    private var valeurs: [String] = []
    private let verrou = NSLock()
    func ajouter(_ n: String) { verrou.withLock { valeurs.append(n) } }
    var noms: [String] { verrou.withLock { valeurs } }
}
```

`SondeMaillage.Etat` doit rester `Equatable` (le cas `injoignable` n'a pas de valeur associée).

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/SondeReseauTests`
Expected : erreurs de compilation (`trousseau`, `ouvrirReseau`, `annoncesChangees`, `acces`, `reglageChemin`, `injoignable` inconnus).

- [x] **Step 3: Implémenter**

Dans `SondeMaillage.swift` :

1. `Etat` : après `case absente`, `/// Le reseau est le chemin choisi, mais la sonde ne repond pas (Wi-Fi coupe, cle refusee). case injoignable`.
2. Constantes : `static let cleIeee = "sondeIeee"` ; `static let delaiReessaiReseau: Duration = .seconds(60)` ; `static let periodeEntretien: Duration = .seconds(240)`.
3. Propriétés observées :

```swift
    /// Par ou passe la sonde connectee ; nil sans sonde connectee.
    private(set) var acces: Acces?
    /// Adresse longue de la sonde retenue (compte de sa cle dans le trousseau) ; nil avant sa premiere connexion USB.
    private(set) var ieee: String?
    /// La sonde retenue est annoncee par Bonjour sur le reseau local.
    private(set) var annoncee = false
    var reglageChemin: ReglageChemin = .automatique {
        didSet {
            guard reglageChemin != oldValue else { return }
            if actif { preferences.set(reglageChemin.rawValue, forKey: CheminSonde.cleReglage) }
            reevaluer()
        }
    }
    /// Une cle de l'acces par le reseau est dans le trousseau pour la sonde retenue.
    var cleReseauConnue: Bool { cleReseau() != nil }
```

4. Propriétés ignorées : `trousseau: any TrousseauCles`, `ouvrirReseau: (String, Data) -> any CanalSonde`, `delaiReessaiReseau: Duration`, `periodeEntretien: Duration`, `reessaiReseau: Task<Void, Never>?`, `entretien: Task<Void, Never>?`, `navigateur: NavigateurBonjour?`.
5. `init` : ajouter les paramètres listés dans **Interfaces** (après `ouvrirCanal`), les ranger ; lire `ieee = actif ? preferences.string(forKey: Self.cleIeee) : nil` ; `reglageChemin = actif ? ReglageChemin(rawValue: preferences.string(forKey: CheminSonde.cleReglage) ?? "") ?? .automatique : .automatique` (dans l'`init`, `didSet` ne se déclenche pas).
6. `demarrer()` : après `portsChanges(PortsUSB.lister())`, lancer le navigateur :

```swift
        let n = NavigateurBonjour(type: "_maillage-zigbee._tcp")
        n.surChangement = { [weak self, weak n] in
            guard let self, let n else { return }
            self.annoncesChangees(Set(n.instances.keys))
        }
        n.demarrer()
        navigateur = n
```

7. Nouvelles fonctions :

```swift
    /// Les instances `_maillage-zigbee._tcp` vues sur le reseau local (navigateur Bonjour ; les tests l'appellent).
    func annoncesChangees(_ noms: Set<String>) {
        let vue = nom.map { noms.contains($0) } ?? false
        guard vue != annoncee || (vue && acces == nil && etat != .connexion) else { return }
        annoncee = vue
        reevaluer()
    }

    /// La cle de l'acces par le reseau de la sonde retenue, depuis le trousseau ; nil sans sonde, sans adresse longue
    /// ou sans cle.
    private func cleReseau() -> Data? {
        guard let ieee, let hexa = try? trousseau.lire(identifiant: ieee) else { return nil }
        return H1.octets(hexa: hexa)
    }

    /// Applique le chemin choisi (spec sonde Wi-Fi, 4.2) apres un changement de ports, d'annonces ou de reglage.
    private func reevaluer() {
        guard actif, serie != nil else { return }
        let port = ports.first { $0.serie == serie }
        switch CheminSonde.choisir(reglageChemin, branchee: port != nil, cleConnue: cleReseauConnue, annoncee: annoncee) {
        case .usb?:
            guard let port, acces != .usb, etat != .connexion else { return }
            lancerConnexion(port, choisi: false)
        case .reseau?:
            guard acces != .reseau, etat != .connexion else { return }
            deconnecter(.connexion)
            serieEtat = serie
            let n = essai
            Task {
                guard n == essai else { return }
                await connecterReseau()
            }
        case nil:
            if (sonde != nil || etat == .connexion || etat == .injoignable) && !versUnAutrePort { deconnecter(.absente) }
        }
    }

    /// Connexion par le reseau a la sonde retenue (spec sonde Wi-Fi, 4.1 et 4.2) : `bonjour` doit dire la sonde Zigbee et
    /// son adresse longue celle retenue.
    func connecterReseau() async {
        guard actif, let nom, let cle = cleReseau() else { return }
        deconnecter(.connexion)
        // La connexion concerne la sonde retenue (sans port) : `versUnAutrePort` reste faux, `nomEtat` donne son nom.
        serieEtat = serie
        let n = essai
        await fermetures?.value
        guard n == essai else { return }
        let s = Sonde(canal: ouvrirReseau(nom, cle), delaiCommande: Sonde.delaiCommandeUSB + .seconds(3),
                      delaiTable: delaiTable + .seconds(3))
        enConnexion = s
        do {
            try await s.demarrer { [weak self] in
                Task { @MainActor in self?.liaisonFermee(s) }
            }
            let b = try await s.bonjour()
            guard n == essai else {
                await s.fermer()
                return
            }
            guard b.estSonde, b.ieee == ieee else {
                await s.fermer()
                guard n == essai else { return }
                enConnexion = nil
                etat = .refusee(String(localized: "la sonde du réseau n'est pas la sonde retenue"))
                return
            }
            enConnexion = nil
            sonde = s
            acces = .reseau
            etat = .connectee(b)
            retenirNom(b.nom)
            await lireEtat(s)
            guard n == essai, s === sonde else { return }
            planifierTournee(dans: delaiPremiereTournee)
            entretenir(s)
        } catch {
            await s.fermer()
            guard n == essai else { return }
            enConnexion = nil
            etat = .injoignable
            planifierReessaiReseau()
        }
    }

    /// Relit `etat` toutes les `periodeEntretien` hors tournee : la session H1 de la sonde reste vivante entre deux
    /// tournees (elle est oubliee apres 10 min sans message).
    private func entretenir(_ s: Sonde) {
        entretien?.cancel()
        let periode = periodeEntretien
        entretien = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: periode)
                guard let self, !Task.isCancelled, s === self.sonde else { return }
                if !self.tourneeEnCours { await self.lireEtat(s) }
            }
        }
    }

    private func planifierReessaiReseau() {
        reessaiReseau?.cancel()
        let n = essai
        let delai = delaiReessaiReseau
        reessaiReseau = Task { [weak self] in
            try? await Task.sleep(for: delai)
            guard !Task.isCancelled, let self, n == self.essai, self.etat == .injoignable else { return }
            self.etat = .absente
            self.reevaluer()
        }
    }
```

8. `portsChanges` : remplacer le corps après `guard let serie else { return }` par :

```swift
        if reglageChemin != .reseau, let p = ports.first(where: { $0.serie == serie }) {
            // `lancerConnexion` passe tout de suite a `.connexion` : un second appel n'en lance pas d'autre.
            if (sonde == nil || acces == .reseau) && etat != .connexion { lancerConnexion(p, choisi: false) }
        } else if acces != .reseau && !versUnAutrePort {
            if sonde != nil || etat != .absente { deconnecter(.absente) }
            reevaluer()
        }
```

9. `connecter(_:choisi:dernierEssai:)` : après `cheminConnecte = port.chemin`, `acces = .usb` ; après `retenirNom(retenue ? b.nom : nil)` :

```swift
            if retenue, let i = b.ieee {
                preferences.set(i, forKey: Self.cleIeee)
                ieee = i
            }
```

10. `deconnecter` : `acces = nil`, `entretien?.cancel()`, `entretien = nil`, `reessaiReseau?.cancel()`, `reessaiReseau = nil`.
11. `oublier()` : avant `preferences.removeObject(forKey: Self.cleSerie)` :

```swift
        if let ieee { try? trousseau.oublier(identifiant: ieee) }
        preferences.removeObject(forKey: Self.cleIeee)
        ieee = nil
        annoncee = false
```

12. `liaisonFermee(_:)` : après `deconnecter(.absente)`, `reevaluer()` (une sonde réseau coupée est retentée si elle reste annoncée).

- [x] **Step 4: Vérifier**

Run : `outils/tester-app.sh MaillageZigbeeTests`
Expected : `** TEST SUCCEEDED **` : les 8 tests de `SondeReseauTests` et tous les tests existants de la sonde (le chemin USB n'a pas changé de comportement sans clé ni annonce).

- [x] **Step 5: Commit**

```bash
git add MaillageZigbee/Sonde/SondeMaillage.swift MaillageZigbeeTests/SondeReseauTests.swift
git commit -m "Connecter la sonde par le reseau quand l'USB n'est pas la, avec reglage manuel

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: Mise en service par l'USB depuis l'app

**Files:**
- Modify : `MaillageZigbee/Sonde/SondeMaillage.swift`
- Test : `MaillageZigbeeTests/SondeReseauTests.swift`

**Interfaces:**
- Consumes : `Sonde.nouvelleCle(alea:)`, `Sonde.configurerWifi(nom:motDePasse:)` (tâche 14), `H1.aleatoire`, `H1.kid(cle:)`, `H1.octets(hexa:)`, `H1.hexa` (tâche 11), `trousseau` (tâche 16).
- Produces :

```swift
/// nil si la mise en service a reussi ; sinon le message a montrer.
func autoriserReseau(nomWifi: String, motDePasse: String) async -> String?
var miseEnServicePossible: Bool  // sonde retenue connectee par l'USB, firmware 1.1.0+, hors tournee, adresse longue connue
```

Ordre : **la clé d'abord, le Wi-Fi ensuite.** `wifi` fait redémarrer la sonde, ce qui ferme la liaison USB ; créer la clé avant garde toute la mise en service sur une seule connexion (précision de la spec 4.3, qui décrivait l'ordre inverse sans dire comment franchir le redémarrage). Le mot de passe ne passe que par les paramètres de la fonction : jamais gardé, jamais journalisé.

- [x] **Step 1: Écrire les tests**

Ajouter à `SondeReseauTests` :

```swift
    static let bonjourUsb = #"{"v":1,"t":"bonjour","produit":"sonde-zigbee","version":"1.1.0","nom":"SONDE-01","ieee":"A000000000000001","membre":true,"role":"final","suspendue":false,"reseau":false}"#
    static let reponseCle = #"{"v":1,"t":"cle","id":1,"cle":"62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D","empreinte":"91CB5C39"}"#

    @Test func miseEnService() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let t = TrousseauMemoire()
        let canal = CanalRejoue { l in
            switch l {
            case "bonjour\n": [SondeReseauTests.bonjourUsb]
            case "etat\n": [CanalRejoue.etatAttache]
            case let x where x.hasPrefix("cle nouvelle "): [SondeReseauTests.reponseCle]
            case let x where x.hasPrefix("wifi "): [#"{"v":1,"t":"wifi","id":2,"configure":true,"nom":"4D6F6E2057696669"}"#]
            default: []
            }
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, trousseau: t,
                              delaiPremiereTournee: .seconds(3600))
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(s.miseEnServicePossible)
        let erreur = await s.autoriserReseau(nomWifi: "Mon Wifi", motDePasse: "motdepasse")
        #expect(erreur == nil)
        #expect(try t.lire(identifiant: "A000000000000001") == "62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D")
        #expect(canal.envoyes.contains("wifi 4D6F6E2057696669 6D6F7464657061737365 2\n"))
        #expect(s.cleReseauConnue)
        await s.oublier()
        #expect(t.identifiants.isEmpty, "oublier la sonde efface sa cle de ce Mac")
    }

    @Test func empreinteFausseRefusee() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let t = TrousseauMemoire()
        let canal = CanalRejoue { l in
            switch l {
            case "bonjour\n": [SondeReseauTests.bonjourUsb]
            case "etat\n": [CanalRejoue.etatAttache]
            case let x where x.hasPrefix("cle nouvelle "): [SondeReseauTests.reponseCle.replacingOccurrences(of: "91CB5C39", with: "00000000")]
            default: []
            }
        }
        let s = SondeMaillage(preferences: p, actif: true, ouvrirCanal: { _ in canal }, trousseau: t,
                              delaiPremiereTournee: .seconds(3600))
        await s.connecter(SondeMaillageTests.port, choisi: true)
        let erreur = await s.autoriserReseau(nomWifi: "Mon Wifi", motDePasse: "motdepasse")
        #expect(erreur != nil)
        #expect(t.identifiants.isEmpty)
        #expect(!canal.envoyes.contains { $0.hasPrefix("wifi ") }, "pas de Wi-Fi sans cle valable")
        await s.oublier()
    }

    @Test func sonde100NonEligible() async throws {
        let (p, d) = try SondeMaillageTests.preferences()
        defer { SondeMaillageTests.nettoyer(p, d) }
        let s = SondeMaillage(preferences: p, actif: true,
                              ouvrirCanal: { _ in CanalRejoue { CanalRejoue.sondeMinimale($0) } },
                              trousseau: TrousseauMemoire(), delaiPremiereTournee: .seconds(3600))
        await s.connecter(SondeMaillageTests.port, choisi: true)
        #expect(!s.miseEnServicePossible, "firmware 1.0.0")
        #expect(await s.autoriserReseau(nomWifi: "X", motDePasse: "motdepasse") != nil)
        await s.oublier()
    }
```

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/SondeReseauTests`
Expected : `autoriserReseau` et `miseEnServicePossible` inconnus.

- [x] **Step 3: Implémenter**

Dans `SondeMaillage.swift` :

```swift
    /// La mise en service par l'USB est possible : la sonde retenue y est connectee, en firmware 1.1.0 ou plus, hors
    /// tournee, son adresse longue connue.
    var miseEnServicePossible: Bool {
        guard acces == .usb, !tourneeEnCours, ieee != nil, case .connectee(let b) = etat else { return false }
        return b.accepteReseau && serieEtat == serie
    }

    /// Mise en service de l'acces par le reseau (spec sonde Wi-Fi, 4.3), la cle d'abord (le Wi-Fi fait redemarrer la
    /// sonde) : alea de l'app, cle derivee par la carte, empreinte verifiee, cle rangee dans le trousseau ; puis le
    /// Wi-Fi. nil si tout a reussi ; sinon le message a montrer.
    func autoriserReseau(nomWifi: String, motDePasse: String) async -> String? {
        guard miseEnServicePossible, let s = sonde, let ieee else {
            return String(localized: "Branchez la sonde 1.1.0 en USB, hors tournée.")
        }
        let nom = Data(nomWifi.utf8), mdp = Data(motDePasse.utf8)
        guard (1...32).contains(nom.count), mdp.isEmpty || (8...63).contains(mdp.count) else {
            return String(localized: "Nom du Wi-Fi de 1 à 32 octets, mot de passe vide ou de 8 à 63 caractères.")
        }
        do {
            let c = try await s.nouvelleCle(alea: H1.aleatoire(32))
            guard let hexa = c.cle, let cle = H1.octets(hexa: hexa), cle.count == 32, H1.kid(cle: cle) == c.empreinte else {
                return String(localized: "La sonde a rendu une clé invalide : rien n'a été enregistré.")
            }
            try trousseau.ranger(identifiant: ieee, cle: hexa)
            let w = try await s.configurerWifi(nom: nom, motDePasse: mdp)
            guard w.configure else { return String(localized: "La sonde n'a pas enregistré le Wi-Fi.") }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
```

- [x] **Step 4: Vérifier**

Run : `outils/tester-app.sh MaillageZigbeeTests`
Expected : `** TEST SUCCEEDED **`.

- [x] **Step 5: Commit**

```bash
git add MaillageZigbee/Sonde/SondeMaillage.swift MaillageZigbeeTests/SondeReseauTests.swift
git commit -m "Mettre la sonde en service par l'USB : cle au trousseau, puis Wi-Fi

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: Réglages › Sonde, textes et autorisations macOS

**Files:**
- Modify : `MaillageZigbee/Vues/FenetreReglages.swift`, `MaillageZigbee/Vues/MenuBarre.swift`, `project.yml`, `MaillageZigbee/Ressources/Localizable.xcstrings`, `MaillageZigbee/Ressources/InfoPlist.xcstrings`
- Test : `MaillageZigbeeTests/AffichageSondeTests.swift`

**Interfaces:**
- Consumes : `SondeMaillage.reglageChemin`, `.acces`, `.cleReseauConnue`, `.miseEnServicePossible`, `.autoriserReseau(nomWifi:motDePasse:)`, `.etatSonde?.reseau`, `Etat.injoignable` (tâches 16-17) ; `ReglageChemin.libelle`, `Acces.libelle` (tâche 15).
- Produces : `static func texteReseauSonde(_ r: ReseauSonde) -> String` sur la vue des Réglages ; l'état `.injoignable` affiché « Réseau — sonde injoignable ».

- [x] **Step 1: Écrire les tests**

Ajouter à `MaillageZigbeeTests/AffichageSondeTests.swift` (dans la suite existante des textes de la sonde) :

```swift
    @Test func texteInjoignable() {
        #expect(FenetreReglages.texteEtatSonde(.injoignable, nom: "SONDE-01") == "SONDE-01 · Réseau — sonde injoignable")
    }

    @Test func texteReseauSonde() {
        #expect(FenetreReglages.texteReseauSonde(ReseauSonde(connecte: true, canal: 6, rssi: -58)) == "connecté · canal 6 · −58 dBm")
        #expect(FenetreReglages.texteReseauSonde(ReseauSonde(connecte: false, raison: 201)) == "non connecté (raison 201)")
    }
```

(Si la vue des Réglages porte un autre nom que `FenetreReglages`, prendre celui qui définit `texteEtatSonde` : `grep -n "static func texteEtatSonde" MaillageZigbee/Vues/*.swift`.)

- [x] **Step 2: Vérifier l'échec**

Run : `outils/tester-app.sh MaillageZigbeeTests/AffichageSondeTests`
Expected : `texteReseauSonde` inconnu ; `switch` non exhaustif sur `.injoignable` dans `texteEtatSonde` et dans `MenuBarre.swift`.

- [x] **Step 3: Implémenter les textes**

Dans `texteEtatSonde`, après `case .absente:` : `case .injoignable: String(localized: "Réseau — sonde injoignable")`.
Dans `MenuBarre.swift`, après `case .absente: return String(localized: "\(n) : absente")` : `case .injoignable: return String(localized: "\(n) : injoignable")`.

Après `texteEtatSonde` :

```swift
    /// Wi-Fi de la sonde (`etat.reseau`) : « connecté · canal 6 · −58 dBm » ; « non connecté (raison 201) ».
    static func texteReseauSonde(_ r: ReseauSonde) -> String {
        guard r.connecte else {
            if let raison = r.raison, raison != 0 { return String(localized: "non connecté (raison \(raison))") }
            return String(localized: "non connecté")
        }
        var parties = [String(localized: "connecté")]
        if let c = r.canal { parties.append(String(localized: "canal \(c)")) }
        if let s = r.rssi { parties.append("\(s.formatted()) dBm".replacingOccurrences(of: "-", with: "−")) }
        return parties.joined(separator: " · ")
    }
```

- [x] **Step 4: Implémenter la vue**

Dans la vue des Réglages : `@State private var nomWifi = ""`, `@State private var motDePasseWifi = ""`, `@State private var messageReseau: String?`, `@State private var miseEnService = false`.

Dans `reglagesSonde`, après `LabeledContent("État", ...)` :

```swift
                if let a = sonde.acces {
                    LabeledContent("Chemin", value: a.libelle)
                }
                Picker("Chemin de la sonde", selection: Binding(get: { sonde.reglageChemin },
                                                                set: { sonde.reglageChemin = $0 })) {
                    ForEach(ReglageChemin.allCases, id: \.self) { Text($0.libelle).tag($0) }
                }
```

Puis, après le bouton « Oublier la sonde » et avant la note sur les ports, une nouvelle `Section("Accès par le réseau")` (à placer en sœur de la `Section` actuelle dans `page { reglagesSonde }` si la page n'accepte qu'une section : regrouper les deux dans un `Group`) :

```swift
        Section("Accès par le réseau") {
            if case .connectee(let b) = sonde.etat, !b.accepteReseau {
                Text("Sonde 1.1.0 requise.").foregroundStyle(.secondary)
            } else {
                TextField("Nom du Wi-Fi (2,4 GHz)", text: $nomWifi)
                SecureField("Mot de passe", text: $motDePasseWifi)
                Button(sonde.cleReseauConnue ? "Régénérer la clé" : "Autoriser l'accès réseau") {
                    miseEnService = true
                    let nom = nomWifi, mdp = motDePasseWifi
                    motDePasseWifi = ""
                    Task {
                        messageReseau = await sonde.autoriserReseau(nomWifi: nom, motDePasse: mdp)
                            ?? String(localized: "Accès réseau autorisé : la sonde redémarre et rejoint le Wi-Fi.")
                        miseEnService = false
                    }
                }
                .disabled(!sonde.miseEnServicePossible || nomWifi.isEmpty || miseEnService)
                if let r = sonde.etatSonde?.reseau {
                    LabeledContent("Wi-Fi de la sonde", value: Self.texteReseauSonde(r))
                }
                if let messageReseau {
                    Text(messageReseau).font(.caption).foregroundStyle(.secondary)
                }
                Text("Sonde branchée en USB, hors tournée. Le mot de passe va directement à la sonde : l'app ne le garde pas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
```

- [x] **Step 5: Autorisations et textes**

`project.yml`, dans `info.properties` :

```yaml
        NSLocalNetworkUsageDescription: "Maillage Zigbee cherche le pont Hue et la sonde sur le réseau local, pour lire les noms et les pièces de vos appareils et interroger la sonde sans câble."
        NSBonjourServices:
          - _hue._tcp
          - _maillage-zigbee._tcp
```

`InfoPlist.xcstrings` : mettre à jour la clé `NSLocalNetworkUsageDescription` (français, et l'anglais : « Maillage Zigbee looks for the Hue bridge and the probe on the local network, to read the names and rooms of your devices and to query the probe without a cable. »).

`Localizable.xcstrings` : ajouter l'anglais de chaque nouvelle chaîne (« Automatique » → « Automatic », « USB seulement » → « USB only », « Réseau seulement » → « Network only », « Réseau » → « Network », « Chemin » → « Path », « Chemin de la sonde » → « Probe path », « Réseau — sonde injoignable » → « Network — probe unreachable », « %@ : injoignable » → « %@: unreachable », « Accès par le réseau » → « Network access », « Sonde 1.1.0 requise. » → « Probe 1.1.0 required. », « Nom du Wi-Fi (2,4 GHz) » → « Wi-Fi name (2.4 GHz) », « Mot de passe » → « Password », « Régénérer la clé » → « Regenerate key », « Autoriser l'accès réseau » → « Allow network access », « Wi-Fi de la sonde » → « Probe Wi-Fi », les messages de `autoriserReseau` et de `texteReseauSonde`, la note de bas de section). Lancer `outils/synchroniser-textes.sh` si le dépôt l'utilise pour extraire les clés (voir son en-tête), puis vérifier qu'aucune chaîne nouvelle n'est restée sans anglais : `grep -c '"state" : "new"' MaillageZigbee/Ressources/Localizable.xcstrings` doit rendre 0.

- [x] **Step 6: Vérifier**

Run : `outils/tester-app.sh`
Expected : `** TEST SUCCEEDED **` (toute l'app, y compris les tests de traduction existants).

- [x] **Step 7: Commit**

```bash
git add MaillageZigbee/Vues/FenetreReglages.swift MaillageZigbee/Vues/MenuBarre.swift project.yml MaillageZigbee/Ressources/Localizable.xcstrings MaillageZigbee/Ressources/InfoPlist.xcstrings MaillageZigbeeTests/AffichageSondeTests.swift
git commit -m "Ajouter le chemin et l'acces par le reseau aux Reglages de la sonde

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 19: Version 1.1.0 et notes de version

**Files:**
- Modify : `project.yml` (`MARKETING_VERSION: "1.1.0"`, `CURRENT_PROJECT_VERSION` +1), `MaillageZigbeeTests/MisesAJourTests.swift`, `NOTES-VERSIONS.md`

- [x] **Step 1: Débloquer le test de version**

Dans `MisesAJourTests.swift`, remplacer l'attente figée `#expect(info["CFBundleShortVersionString"] as? String == "1.0.0")` par une forme qui suit `project.yml` : la version doit être de la forme `X.Y.Z` (`#expect((info["CFBundleShortVersionString"] as? String)?.split(separator: ".").count == 3)`), pour ne plus casser à chaque version.

- [x] **Step 2: Versions**

`project.yml` : `MARKETING_VERSION: "1.1.0"` ; `CURRENT_PROJECT_VERSION` : la valeur actuelle + 1.

- [x] **Step 3: Notes**

En tête de `NOTES-VERSIONS.md`, une section `## 1.1.0` avec un bloc **English** puis un bloc **Français**, même contenu : la sonde peut vivre sur un chargeur et être interrogée par le réseau local (firmware de sonde 1.1.0) ; mise en service par l'USB dans Réglages › Sonde (nom et mot de passe du Wi-Fi, clé d'accès rangée dans le trousseau) ; chemin automatique ou manuel (USB, réseau) ; échanges signés, non chiffrés ; une sonde 1.0.0 reste servie par l'USB.

- [x] **Step 4: Vérifier et commiter**

Run : `outils/tester-app.sh && sh outils/tester.sh`
Expected : tout passe.

```bash
git add project.yml MaillageZigbeeTests/MisesAJourTests.swift NOTES-VERSIONS.md
git commit -m "Passer l'app en 1.1.0 et ecrire ses notes de version

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 20: Banc de l'app 1.1.0 (avec Djoko)

- [x] **Step 1:** l'app compilée de la branche est lancée ; macOS demande l'accès au réseau local : Djoko l'accorde.
- [x] **Step 2:** sonde branchée en USB : Réglages › Sonde, chemin « Automatique », « Autoriser l'accès réseau » avec le Wi-Fi saisi par Djoko ; la sonde redémarre ; l'app la retrouve par l'USB ; « Wi-Fi de la sonde : connecté · canal … ».
- [x] **Step 3:** Djoko débranche la sonde et la met sur un chargeur mural : l'état passe à « Réseau », une tournée complète passe par le réseau, le journal reçoit les signaux.
- [x] **Step 4:** réglage « USB seulement » : la sonde sur chargeur devient « absente » ; retour à « Automatique » : « Réseau » de nouveau.
- [x] **Step 5:** on rebranche la sonde en USB : l'app bascule sur l'USB.
- [ ] **Step 6:** une nuit sonde sur chargeur, l'app en marche ; comparaison avec E6 (pertes de parent par tournée, tables reçues).
  Fait en partie (12/10) : 4 h 30 en Wi-Fi, 19 tournées toutes complètes, aucun changement de parent de la sonde ; la comparaison avec E6 reste impossible tant que l'app ne journalise pas les pertes de parent (backlog).
- [x] **Step 7:** relecture finale de la branche par Opus, puis fusion et publication commune sonde 1.1.0 + app 1.1.0 (`outils/publier.sh`), avec les règles de push du dépôt.
