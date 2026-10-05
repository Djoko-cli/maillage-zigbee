#include "ligne.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

// Place a garder pour « } » et la fin de ligne.
static constexpr size_t kFin = 2;
// "],\"suite\":false" : la fermeture d'une ligne de liste.
static constexpr size_t kFermeture = 15;

void Ligne::debut(const char *type) {
  long_ = 0;
  trop_ = false;
  buf_[long_++] = 0x1E;
  ajoute("{\"v\":1,\"t\":\"%s\"", type);
}

void Ligne::ajoute(const char *fmt, ...) {
  if (trop_) return;
  const size_t reste = kMax - kFin - long_;
  va_list ap;
  va_start(ap, fmt);
  const int n = vsnprintf(buf_ + long_, reste + 1, fmt, ap);
  va_end(ap);
  if (n < 0 || (size_t)n > reste) {
    trop_ = true;
    return;
  }
  long_ += (size_t)n;
}

bool Ligne::tient(size_t n) const { return !trop_ && long_ + n <= kMax - kFin; }

const uint8_t *Ligne::fin(size_t *n) {
  if (trop_) {
    debut("erreur");
    ajoute(",\"erreur\":\"ligne trop longue\"");
  }
  buf_[long_++] = '}';
  buf_[long_++] = '\n';
  *n = long_;
  return (const uint8_t *)buf_;
}

void ListeDecoupee::commencer(const char *type, const char *entete) {
  type_ = type;
  snprintf(entete_, sizeof(entete_), "%s", entete);
  ouvrir();
}

void ListeDecoupee::ouvrir() {
  ligne_.debut(type_);
  ligne_.ajoute("%s,\"liste\":[", entete_);
  premier_ = true;
}

void ListeDecoupee::fermer(bool suite) {
  ligne_.ajoute("],\"suite\":%s", suite ? "true" : "false");
  size_t n = 0;
  const uint8_t *octets = ligne_.fin(&n);
  sortie_(ctx_, octets, n);
}

void ListeDecoupee::ajouter(const char *objet) {
  const size_t n = strlen(objet) + (premier_ ? 0 : 1);
  if (!premier_ && !ligne_.tient(n + kFermeture)) {
    fermer(true);
    ouvrir();
  }
  ligne_.ajoute("%s%s", premier_ ? "" : ",", objet);
  premier_ = false;
}

void ListeDecoupee::terminer() { fermer(false); }
