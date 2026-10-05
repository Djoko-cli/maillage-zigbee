#include "commande.h"

#include <string.h>

bool nomValide(const char *s) {
  const size_t n = strlen(s);
  if (n == 0 || n > kNomMax) return false;
  for (size_t i = 0; i < n; i++) {
    const char c = s[i];
    const bool permis = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' ||
                        c == '_' || c == '.';
    if (!permis) return false;
  }
  return true;
}

bool lireEntier(const char *s, uint32_t *v) {
  const size_t n = strlen(s);
  if (n == 0 || n > 10) return false;
  uint64_t x = 0;
  for (size_t i = 0; i < n; i++) {
    if (s[i] < '0' || s[i] > '9') return false;
    x = x * 10 + (uint64_t)(s[i] - '0');
  }
  if (x > 0xFFFFFFFFull) return false;
  *v = (uint32_t)x;
  return true;
}

bool lireCourt(const char *s, uint16_t *v) {
  if (strlen(s) != 4) return false;
  uint16_t x = 0;
  for (size_t i = 0; i < 4; i++) {
    const char c = s[i];
    uint16_t chiffre;
    if (c >= '0' && c <= '9') chiffre = (uint16_t)(c - '0');
    else if (c >= 'A' && c <= 'F') chiffre = (uint16_t)(c - 'A' + 10);
    else if (c >= 'a' && c <= 'f') chiffre = (uint16_t)(c - 'a' + 10);
    else return false;
    x = (uint16_t)(x * 16 + chiffre);
  }
  *v = x;
  return true;
}

namespace {

constexpr size_t kLigneMax = 255;  // au-dela : syntaxe
constexpr size_t kMotsMax = 5;

// Coupe la copie de la ligne en mots (au plus kMotsMax ; un mot de plus
// compte pour « trop de mots »). Rend le nombre de mots, kMotsMax + 1 s'il y
// en a trop.
size_t couper(char *copie, char *mots[kMotsMax]) {
  size_t n = 0;
  char *p = copie;
  while (*p) {
    while (*p == ' ') p++;
    if (!*p) break;
    if (n == kMotsMax) return kMotsMax + 1;
    mots[n++] = p;
    while (*p && *p != ' ') p++;
    if (*p) *p++ = 0;
  }
  return n;
}

// table, routes et echecs : <cible> <id> [<delai ms>].
Commande cibleIdDelai(TypeCommande type, char *mots[kMotsMax], size_t n) {
  Commande c;
  c.type = TypeCommande::kSyntaxe;
  if (n < 3 || n > 4) return c;
  uint16_t cible;
  uint32_t id;
  uint32_t delai = kDelaiDefautMs;
  if (!lireCourt(mots[1], &cible) || cible > kCibleMax || !lireEntier(mots[2], &id)) return c;
  if (n == 4 && (!lireEntier(mots[3], &delai) || delai < kDelaiMinMs || delai > kDelaiMaxMs)) return c;
  c.type = type;
  c.cible = cible;
  c.id = id;
  c.delaiMs = delai;
  return c;
}

}  // namespace

Commande lireCommande(const char *ligne) {
  Commande c;
  if (strlen(ligne) > kLigneMax) {
    c.type = TypeCommande::kSyntaxe;
    return c;
  }
  char copie[kLigneMax + 1];
  strcpy(copie, ligne);
  char *mots[kMotsMax] = {};
  const size_t n = couper(copie, mots);
  if (n == 0) return c;  // ligne vide : kInconnue (l'appelant n'en envoie pas)
  const char *m = mots[0];

  struct Simple {
    const char *mot;
    TypeCommande type;
  };
  static const Simple kSimples[] = {
      {"bonjour", TypeCommande::kBonjour},     {"etat", TypeCommande::kEtat},
      {"voisins", TypeCommande::kVoisins},     {"suspendre", TypeCommande::kSuspendre},
      {"reprendre", TypeCommande::kReprendre}, {"oubli", TypeCommande::kOubli},
  };
  for (const Simple &s : kSimples) {
    if (strcmp(m, s.mot) == 0) {
      c.type = n == 1 ? s.type : TypeCommande::kSyntaxe;
      return c;
    }
  }
  if (strcmp(m, "nom") == 0) {
    if (n != 2 || !nomValide(mots[1])) {
      c.type = TypeCommande::kSyntaxe;
      return c;
    }
    c.type = TypeCommande::kNom;
    strcpy(c.nom, mots[1]);
    return c;
  }
  if (strcmp(m, "table") == 0) return cibleIdDelai(TypeCommande::kTable, mots, n);
#if SONDE_ROUTES
  if (strcmp(m, "routes") == 0) return cibleIdDelai(TypeCommande::kRoutes, mots, n);
#endif
#if SONDE_ECHECS
  if (strcmp(m, "echecs") == 0) return cibleIdDelai(TypeCommande::kEchecs, mots, n);
#endif
  return c;  // kInconnue
}
