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
