#include "portail.h"

#include <string.h>

bool Portail::cle(const uint8_t *psk) {
  for (uint8_t &c : connexionDe_) c = kAucune;
  nombre_ = 0;
  return table_.setKey(psk);
}

void Portail::ouverte(uint8_t c, uint32_t maintenant) {
  if (c >= kConnexions) return;
  cx_[c].ouverte = true;
  cx_[c].long_ = 0;
  cx_[c].depuis = maintenant;
  cx_[c].activite = maintenant;
}

void Portail::couper(uint8_t c, Sortie &s) {
  fermetures_++;
  s.fermer(c);
  fermee(c);
}

bool Portail::aSession(uint8_t c) const {
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (connexionDe_[i] == c) return true;
  return false;
}

void Portail::fermee(uint8_t c) {
  if (c >= kConnexions) return;
  cx_[c].ouverte = false;
  cx_[c].long_ = 0;
  for (uint8_t i = 0; i < h1::kSlots; i++) {
    if (connexionDe_[i] == c) {
      connexionDe_[i] = kAucune;
      purger(i);
      table_.end(i);
    }
  }
}

void Portail::purger(uint8_t slot) {
  uint8_t k = 0;
  for (uint8_t i = 0; i < nombre_; i++) {
    const Requete &r = file_[(debut_ + i) % kFile];
    if (r.session == slot) continue;
    if (k != i) file_[(debut_ + k) % kFile] = r;
    k++;
  }
  nombre_ = k;
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
      couper(c, s);
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
  // Une session ne parle que sur la connexion ou elle a ete promue : une
  // place reprise (frais) prend la connexion et perd les requetes de l'ancienne,
  // dont la connexion est fermee (sa session n'existe plus : sans cela, son
  // client resterait connecte a une session muette).
  if (frais) {
    const uint8_t ancienne = connexionDe_[slot];
    connexionDe_[slot] = c;
    purger(slot);
    if (ancienne != kAucune && ancienne != c && cx_[ancienne].ouverte) couper(ancienne, s);
  } else if (connexionDe_[slot] != c) {
    refus_++;
    return;
  }
  cx_[c].activite = maintenant;
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

void Portail::expirer(uint32_t maintenant, Sortie &s) {
  const uint8_t liberes = table_.expire(maintenant);
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (liberes & (1u << i)) {
      const uint8_t c = connexionDe_[i];
      connexionDe_[i] = kAucune;
      purger(i);
      if (c != kAucune && cx_[c].ouverte) couper(c, s);
    }
  for (uint8_t c = 0; c < kConnexions; c++) {
    if (!cx_[c].ouverte) continue;
    const bool muette = aSession(c) ? maintenant - cx_[c].activite >= kMuetteMs
                                    : maintenant - cx_[c].depuis >= kSansSessionMs;
    if (muette) couper(c, s);
  }
}

uint8_t Portail::sessions() const {
  uint8_t n = 0;
  for (uint8_t i = 0; i < h1::kSlots; i++)
    if (connexionDe_[i] != kAucune && cx_[connexionDe_[i]].ouverte) n++;
  return n;
}
