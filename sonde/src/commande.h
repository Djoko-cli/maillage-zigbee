#pragma once
// ===========================================================================
//  Commandes de l'USB (spec de la sonde, section 2)
//
//  Une ligne, sans sa fin de ligne, devient une Commande. Mots separes par
//  des espaces ; les espaces en trop au debut, a la fin et entre les mots
//  sont ignores. Un premier mot inconnu donne kInconnue ; des arguments mal
//  formes, kSyntaxe.
//
//    bonjour | etat | voisins | suspendre | reprendre | oubli   (sans argument)
//    nom <texte>                                1 a 32 caracteres permis
//    table <cible> <id> [<delai ms>]            cible : 4 hexa ; id : decimal
//    routes <cible> <id> [<delai ms>]           (si SONDE_ROUTES)
//    echecs <cible> <id> [<delai ms>]           (si SONDE_ECHECS)
//    wifi <NOM HEXA> <MDP HEXA | -> <id>        Wi-Fi (spec sonde Wi-Fi, 3.5) ;
//                                               « - » : reseau ouvert
//    wifi | wifi efface                         lire, oublier
//    cle nouvelle <64 HEXA> <id> | cle | cle efface
//  Hexa : MAJUSCULES, nombre pair de chiffres ; nom 1 a 32 octets, mot de
//  passe 8 a 63 octets, alea 32 octets ; un octet nul est refuse.
//
//  Cible : une adresse d'appareil, jamais une adresse de diffusion (FFF8 a
//  FFFF : syntaxe). Delai : de 500 a 5000 ms, 5000 par defaut (par page pour
//  table et routes ; pour la requete unique d'echecs). La pile Zigbee borne
//  elle-meme une requete ZDO a 5 s : au-dela, le delai ne changerait rien.
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_commande.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "options.h"

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

// 1 a 32 caracteres parmi les lettres ASCII, les chiffres, « - », « _ » et
// « . » : rien a echapper dans le JSON.
bool nomValide(const char *s);

// Decimal sans signe, 1 a 10 chiffres, au plus 4 294 967 295. Refuse : v
// intact.
bool lireEntier(const char *s, uint32_t *v);

// Exactement 4 hexa, majuscules ou minuscules. Refuse : v intact.
bool lireCourt(const char *s, uint16_t *v);

// Hexadecimal MAJUSCULE, nombre pair de chiffres, 1 a max octets. Refuse : n
// intact.
bool lireHexa(const char *s, uint8_t *out, size_t max, size_t *n);

Commande lireCommande(const char *ligne);
