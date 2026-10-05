#pragma once
// ===========================================================================
//  Lignes machine de l'USB (spec de la sonde, section 2)
//
//  RS (0x1E), JSON compact en ASCII, fin de ligne : 4095 octets emis au plus,
//  RS et fin de ligne compris. Une ligne qui deborde est remplacee par
//  {"v":1,"t":"erreur","erreur":"ligne trop longue"}.
//
//  ListeDecoupee ecrit une liste d'objets sur une ou plusieurs lignes :
//  chacune reprend le type et l'en-tete, porte "liste":[...] puis
//  "suite":true, sauf la derniere ("suite":false).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_ligne.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

class Ligne {
 public:
  static constexpr size_t kMax = 4095;  // octets emis au plus, RS et LF compris

  // RS puis {"v":1,"t":"<type>"
  void debut(const char *type);
  // Ajoute du texte (printf) ; au-dela de la place, la ligne est trop longue.
  void ajoute(const char *fmt, ...) __attribute__((format(printf, 2, 3)));
  // n octets de plus tiennent-ils, avant le « } » et la fin de ligne ?
  bool tient(size_t n) const;
  bool tropLong() const { return trop_; }
  // Ferme la ligne (« } » et LF) et rend ses octets, valables jusqu'au
  // prochain debut().
  const uint8_t *fin(size_t *n);

 private:
  char buf_[kMax + 1];  // + le 0 final de vsnprintf
  size_t long_ = 0;
  bool trop_ = false;
};

class ListeDecoupee {
 public:
  using Sortie = void (*)(void *ctx, const uint8_t *octets, size_t n);
  static constexpr size_t kEnteteMax = 255;

  ListeDecoupee(Ligne &ligne, Sortie sortie, void *ctx) : ligne_(ligne), sortie_(sortie), ctx_(ctx) {}
  // type : "table", "voisins"... ; entete : champs a reprendre sur chaque
  // ligne, chacun precede de sa virgule (",\"id\":7"), ou "".
  void commencer(const char *type, const char *entete);
  // Un objet JSON complet ("{...}").
  void ajouter(const char *objet);
  // Ferme la derniere ligne, avec "suite":false.
  void terminer();

 private:
  void ouvrir();
  void fermer(bool suite);
  Ligne &ligne_;
  Sortie sortie_;
  void *ctx_;
  const char *type_ = "";
  char entete_[kEnteteMax + 1] = {0};
  bool premier_ = true;  // aucun objet encore sur la ligne en cours
};
