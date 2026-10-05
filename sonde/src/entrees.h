#pragma once
// ===========================================================================
//  Entrees des tables, en champs bruts et en objets JSON (spec de la sonde,
//  section 2)
//
//  - EntreeVoisin : une entree de Mgmt_Lqi_rsp (table des voisins d'un
//    routeur), recopiee de la reponse que la pile Zigbee a decoupee ;
//  - VoisinSonde : une entree de la table des voisins de la sonde
//    (esp_zb_nwk_get_next_neighbor) ;
//  - EntreeRoute et PageRoutes : Mgmt_Rtg_rsp, lue ici dans la trame brute
//    (la pile n'a pas de requete de table de routage : section 4, E4).
//
//  Adresse longue : 8 octets dans l'ordre du reseau (poids faible d'abord),
//  ecrite en 16 hexa majuscules, poids fort d'abord. Adresse courte : 4 hexa
//  majuscules.
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_entrees.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

struct EntreeVoisin {
  uint8_t ieee[8] = {0};
  uint16_t court = 0;
  uint8_t type = 3;       // 0 coordinateur, 1 routeur, 2 final, 3 inconnu
  uint8_t ecoute = 2;     // recepteur allume au repos : 0 non, 1 oui, 2 inconnu
  uint8_t relation = 3;   // 0 parent, 1 enfant, 2 frere, 3 aucune, 4 ancien enfant,
                          // 5 enfant pas encore authentifie
  uint8_t admission = 2;  // accepte des adhesions : 0 non, 1 oui, 2 inconnu
  uint8_t profondeur = 0;
  uint8_t lqi = 0;
};

struct VoisinSonde {
  uint8_t ieee[8] = {0};
  uint16_t court = 0;
  uint8_t type = 3;
  uint8_t relation = 3;
  uint8_t lqi = 0;
  int8_t rssi = 0;
  uint8_t coutSortant = 0;
  uint8_t age = 0;
};

struct EntreeRoute {
  uint16_t destination = 0;
  uint8_t etat = 0;  // 0 active, 1 decouverte, 2 echec de decouverte, 3 inactive, 4 validation
  bool memoireLimitee = false;
  bool plusieursVersUn = false;
  bool enregistrement = false;  // un Route Record doit preceder le prochain envoi
  uint16_t prochain = 0;
};

// Mgmt_Rtg_rsp : tsn, statut, puis (statut 0 seulement) total, index de
// depart, nombre d'entrees et 5 octets par entree.
static constexpr size_t kRoutesParPageMax = 16;
struct PageRoutes {
  uint8_t tsn = 0;
  uint8_t statut = 0;
  uint8_t total = 0;
  uint8_t debut = 0;
  uint8_t nombre = 0;  // entrees gardees (au plus kRoutesParPageMax)
  EntreeRoute entrees[kRoutesParPageMax];
};

// Lit une Mgmt_Rtg_rsp brute ; false si la trame est trop courte ou annonce
// plus d'entrees qu'elle n'en porte. Au-dela de kRoutesParPageMax entrees,
// seules les premieres sont gardees (la page suivante reprendra la).
bool lirePageRoutes(const uint8_t *asdu, size_t n, PageRoutes *p);
// Mgmt_Rtg_req brute : tsn, puis index de depart.
void requeteRoutes(uint8_t tsn, uint8_t debut, uint8_t asdu[2]);

const char *texteType(uint8_t type);
const char *texteRelation(uint8_t relation);
const char *texteEtatRoute(uint8_t etat);
void texteIeee(const uint8_t ieee[8], char sortie[17]);

// Objets JSON ; rendent leur longueur, ou 0 si la sortie est trop petite.
size_t jsonEntreeVoisin(const EntreeVoisin &e, char *sortie, size_t taille);
size_t jsonVoisinSonde(const VoisinSonde &v, char *sortie, size_t taille);
size_t jsonEntreeRoute(const EntreeRoute &r, char *sortie, size_t taille);
