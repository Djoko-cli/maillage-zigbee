#pragma once
// ===========================================================================
//  Liste blanche des requetes de la sonde (spec de la sonde, section 3)
//
//  La sonde n'emet, d'elle-meme ou sur commande, que des requetes ZDO de
//  lecture : Mgmt_Lqi_req, Mgmt_Rtg_req (si SONDE_ROUTES) et
//  Mgmt_NWK_Update_req en balayage d'energie seulement (si SONDE_ECHECS),
//  avec une duree 0 et le seul canal courant. Jamais de changement de canal
//  (duree 0xFE) ni de gestionnaire du reseau (0xFF), et toujours vers un seul
//  appareil : jamais vers une adresse de diffusion (FFF8 a FFFF). Chaque
//  envoi de zigbee.cpp passe par ces fonctions, la voie APS brute comprise.
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_cadence.cpp).
// ===========================================================================
#include <stdint.h>

#include "options.h"

static constexpr uint16_t kZdoMgmtLqi = 0x0031;
static constexpr uint16_t kZdoMgmtRtg = 0x0032;
static constexpr uint16_t kZdoMgmtNwkUpdate = 0x0038;

// Une requete ZDO (profil 0, point d'acces 0) que la sonde peut emettre vers
// cette cible ?
inline bool requetePermise(uint16_t cluster, uint16_t cible) {
  if (cible >= 0xFFF8) return false;  // diffusion
  if (cluster == kZdoMgmtLqi) return true;
  if (cluster == kZdoMgmtRtg) return SONDE_ROUTES != 0;
  if (cluster == kZdoMgmtNwkUpdate) return SONDE_ECHECS != 0;
  return false;
}

// Mgmt_NWK_Update_req : balayage d'energie de duree 0, sur le seul canal
// courant (11 a 26).
inline bool balayagePermis(uint32_t masqueCanaux, uint8_t duree, uint8_t canalCourant) {
  if (!requetePermise(kZdoMgmtNwkUpdate, 0x0000)) return false;
  if (canalCourant < 11 || canalCourant > 26) return false;
  return duree == 0 && masqueCanaux == (1u << canalCourant);
}
