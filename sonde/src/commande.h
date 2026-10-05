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
  kInconnue,
  kSyntaxe,
};

static constexpr size_t kNomMax = 32;
static constexpr uint32_t kDelaiDefautMs = 5000;
static constexpr uint32_t kDelaiMinMs = 500;
static constexpr uint32_t kDelaiMaxMs = 5000;
static constexpr uint16_t kCibleMax = 0xFFF7;  // FFF8 a FFFF : diffusions

struct Commande {
  TypeCommande type = TypeCommande::kInconnue;
  uint16_t cible = 0;                // table, routes, echecs
  uint32_t id = 0;                   // table, routes, echecs
  uint32_t delaiMs = kDelaiDefautMs; // table, routes, echecs
  char nom[kNomMax + 1] = {0};       // nom
};

// 1 a 32 caracteres parmi les lettres ASCII, les chiffres, « - », « _ » et
// « . » : rien a echapper dans le JSON.
bool nomValide(const char *s);

// Decimal sans signe, 1 a 10 chiffres, au plus 4 294 967 295. Refuse : v
// intact.
bool lireEntier(const char *s, uint32_t *v);

// Exactement 4 hexa, majuscules ou minuscules. Refuse : v intact.
bool lireCourt(const char *s, uint16_t *v);

Commande lireCommande(const char *ligne);
