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
