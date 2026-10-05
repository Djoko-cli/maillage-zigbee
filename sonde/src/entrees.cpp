#include "entrees.h"

#include <stdio.h>

const char *texteType(uint8_t type) {
  switch (type) {
    case 0: return "coordinateur";
    case 1: return "routeur";
    case 2: return "final";
    default: return "inconnu";
  }
}

// 5 (enfant pas encore authentifie) compte comme un enfant ; les valeurs
// reservees, comme « aucune ».
const char *texteRelation(uint8_t relation) {
  switch (relation) {
    case 0: return "parent";
    case 1: return "enfant";
    case 2: return "frere";
    case 4: return "ancien_enfant";
    case 5: return "enfant";
    default: return "aucune";
  }
}

const char *texteEtatRoute(uint8_t etat) {
  switch (etat) {
    case 0: return "active";
    case 1: return "decouverte";
    case 2: return "echec_decouverte";
    case 3: return "inactive";
    case 4: return "validation";
    default: return "inconnu";
  }
}

void texteIeee(const uint8_t ieee[8], char sortie[17]) {
  static const char kHexa[] = "0123456789ABCDEF";
  for (int i = 0; i < 8; i++) {
    const uint8_t o = ieee[7 - i];
    sortie[2 * i] = kHexa[o >> 4];
    sortie[2 * i + 1] = kHexa[o & 0x0F];
  }
  sortie[16] = 0;
}

static const char *trois(uint8_t v) { return v == 0 ? "false" : v == 1 ? "true" : "null"; }

static size_t borne(int n, size_t taille) { return n < 0 || (size_t)n >= taille ? 0 : (size_t)n; }

size_t jsonEntreeVoisin(const EntreeVoisin &e, char *sortie, size_t taille) {
  char ieee[17];
  texteIeee(e.ieee, ieee);
  const int n = snprintf(sortie, taille,
                         "{\"court\":\"%04X\",\"ieee\":\"%s\",\"type\":\"%s\",\"relation\":\"%s\",\"ecoute\":%s,"
                         "\"profondeur\":%u,\"admission\":%s,\"lqi\":%u}",
                         e.court, ieee, texteType(e.type), texteRelation(e.relation), trois(e.ecoute),
                         e.profondeur, trois(e.admission), e.lqi);
  return borne(n, taille);
}

size_t jsonVoisinSonde(const VoisinSonde &v, char *sortie, size_t taille) {
  char ieee[17];
  texteIeee(v.ieee, ieee);
  const int n = snprintf(sortie, taille,
                         "{\"court\":\"%04X\",\"ieee\":\"%s\",\"type\":\"%s\",\"relation\":\"%s\",\"lqi\":%u,"
                         "\"rssi\":%d,\"cout_sortant\":%u,\"age\":%u}",
                         v.court, ieee, texteType(v.type), texteRelation(v.relation), v.lqi, v.rssi,
                         v.coutSortant, v.age);
  return borne(n, taille);
}

size_t jsonEntreeRoute(const EntreeRoute &r, char *sortie, size_t taille) {
  const int n = snprintf(sortie, taille,
                         "{\"destination\":\"%04X\",\"etat\":\"%s\",\"prochain\":\"%04X\",\"memoire_limitee\":%s,"
                         "\"plusieurs_vers_un\":%s,\"enregistrement\":%s}",
                         r.destination, texteEtatRoute(r.etat), r.prochain, r.memoireLimitee ? "true" : "false",
                         r.plusieursVersUn ? "true" : "false", r.enregistrement ? "true" : "false");
  return borne(n, taille);
}

bool lirePageRoutes(const uint8_t *asdu, size_t n, PageRoutes *p) {
  if (n < 2) return false;
  *p = PageRoutes();
  p->tsn = asdu[0];
  p->statut = asdu[1];
  if (p->statut != 0) return true;
  if (n < 5) return false;
  p->total = asdu[2];
  p->debut = asdu[3];
  const uint8_t annonce = asdu[4];
  if (n < 5 + 5 * (size_t)annonce) return false;
  p->nombre = annonce > kRoutesParPageMax ? (uint8_t)kRoutesParPageMax : annonce;
  for (uint8_t i = 0; i < p->nombre; i++) {
    const uint8_t *o = asdu + 5 + 5 * i;
    EntreeRoute &r = p->entrees[i];
    r.destination = (uint16_t)(o[0] | o[1] << 8);
    r.etat = o[2] & 0x07;
    r.memoireLimitee = (o[2] >> 3) & 1;
    r.plusieursVersUn = (o[2] >> 4) & 1;
    r.enregistrement = (o[2] >> 5) & 1;
    r.prochain = (uint16_t)(o[3] | o[4] << 8);
  }
  return true;
}

void requeteRoutes(uint8_t tsn, uint8_t debut, uint8_t asdu[2]) {
  asdu[0] = tsn;
  asdu[1] = debut;
}
