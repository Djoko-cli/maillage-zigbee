#pragma once
// ===========================================================================
//  LED de la carte (WS2812 de la SuperMini, sur IO8 ; spec de la sonde,
//  section 1)
//
//  La teinte a montrer a chaque instant, par ordre de priorite :
//  1. identification demandee par l'app Hue : blanc, 500 ms allume, 500 ms
//     eteint ;
//  2. recherche d'un reseau ou rattachement : pulsation bleue lente (2 s) ;
//  3. adhesion : deux eclairs verts rapides (100 ms, pause, 100 ms) ;
//  4. suspendue : un bref eclair orange (100 ms) toutes les 5 s, le premier
//     tout de suite, aussi apres un redemarrage ;
//  5. sinon, la lampe Hue : blanc tres faible si allumee, eteinte sinon.
//  main.cpp la pilote dans loop() seulement, jamais depuis un rappel de la
//  pile Zigbee (qui ne fait que poser des drapeaux).
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_voyant.cpp). Instants de millis() : des ecarts non
//  signes ; une sequence finie est oubliee au premier appel qui la voit
//  finie, si bien que le retour a zero de millis() ne ranime rien.
// ===========================================================================
#include <stdint.h>

class Voyant {
 public:
  enum Couleur : uint8_t { kNoire, kBlanche, kBleue, kVerte, kOrange, kVeille };
  static constexpr uint32_t kIdentMs = 500;     // demi-periode du clignotement d'identification
  static constexpr uint32_t kPulsationMs = 2000;  // periode de la pulsation bleue
  static constexpr uint32_t kVertMs = 100;      // chaque eclair vert, et la pause entre eux
  static constexpr uint32_t kBrefMs = 100;      // bref eclair orange de la suspension...
  static constexpr uint32_t kPeriodeMs = 5000;  // ... toutes les 5 s

  struct Teinte {
    Couleur couleur;
    uint8_t niveau;  // 0 a 255 : fraction de l'intensite maximale de la couleur
  };

  void identifier(bool actif, uint32_t t) {
    if (actif && !ident_) debutIdent_ = t;
    ident_ = actif;
  }
  void chercher(bool actif, uint32_t t) {
    if (actif && !cherche_) debutPulsation_ = t;
    cherche_ = actif;
  }
  void adherer(uint32_t t) {
    adhesion_ = true;
    debutAdhesion_ = t;
  }
  void suspendre(bool actif, uint32_t t) {
    if (actif && !suspendue_) prochain_ = t;
    suspendue_ = actif;
  }
  void allumer(bool actif) { lampe_ = actif; }

  Teinte teinte(uint32_t t) {
    if (ident_) return {((t - debutIdent_) / kIdentMs) % 2 == 0 ? kBlanche : kNoire, 255};
    if (cherche_) {
      const uint32_t phase = (t - debutPulsation_) % kPulsationMs;
      const uint32_t demi = kPulsationMs / 2;
      const uint32_t montee = phase < demi ? phase : kPulsationMs - phase;
      return {kBleue, (uint8_t)(montee * 255 / demi)};
    }
    if (adhesion_) {
      const uint32_t e = t - debutAdhesion_;
      if (e < 3 * kVertMs) return {e / kVertMs == 1 ? kNoire : kVerte, 255};
      adhesion_ = false;
    }
    if (suspendue_) {
      // Ecart depuis le prochain bref eclair : au-dela de 2^31 ms, il est
      // encore a venir (prochain_ n'est jamais a plus d'une periode en avance).
      const uint32_t e = t - prochain_;
      if (e < 0x80000000u) {
        if (e % kPeriodeMs < kBrefMs) return {kOrange, 255};
        // Eclair fini (plusieurs si loop() a ete retenue) : le suivant, sur la
        // meme grille de 5 s.
        prochain_ += (e / kPeriodeMs + 1) * kPeriodeMs;
      }
    }
    return {lampe_ ? kVeille : kNoire, 255};
  }

 private:
  bool ident_ = false;
  uint32_t debutIdent_ = 0;
  bool cherche_ = false;
  uint32_t debutPulsation_ = 0;
  bool adhesion_ = false;
  uint32_t debutAdhesion_ = 0;
  bool suspendue_ = false;
  uint32_t prochain_ = 0;  // debut du prochain bref eclair, ou de celui en cours
  bool lampe_ = false;
};
