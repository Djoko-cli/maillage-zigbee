#pragma once
// ===========================================================================
//  Attente du Wi-Fi au demarrage (spec sonde Wi-Fi, 3.2), sans bloquer loop()
//
//  Wi-Fi configure : la connexion est attendue kMaxMs au plus, puis la pile
//  Zigbee demarre (Wi-Fi connecte d'abord : cohabitation, essai du 10/10).
//  Pendant l'attente, loop() tourne et l'USB repond : une sonde dont le Wi-Fi
//  est absent ou refuse reste joignable par l'USB, chemin du depannage
//  (constat 2 de la relecture finale ; avant, setup() bloquait 15 s).
//  Sans Wi-Fi configure, rien a attendre : la pile demarre tout de suite.
//
//  Pur : teste sur l'hote (sonde/test/test_demarrage.cpp). Instants de
//  millis() : des ecarts non signes.
// ===========================================================================
#include <stdint.h>

class AttenteWifi {
 public:
  static constexpr uint32_t kMaxMs = 15000;

  void commencer(bool configure, uint32_t maintenant) {
    etat_ = configure ? Etat::kAttente : Etat::kFinie;
    debut_ = maintenant;
  }

  // Vrai une seule fois : quand l'attente finit (Wi-Fi connecte, ou kMaxMs
  // ecoules), ou tout de suite sans Wi-Fi configure. L'appelant demarre alors
  // la pile Zigbee.
  bool finir(bool connecte, uint32_t maintenant) {
    if (etat_ == Etat::kFinie) {
      etat_ = Etat::kLancee;
      return true;
    }
    if (etat_ != Etat::kAttente) return false;
    if (!connecte && maintenant - debut_ < kMaxMs) return false;
    etat_ = Etat::kLancee;
    return true;
  }

  bool enCours() const { return etat_ == Etat::kAttente; }

 private:
  // kAvant : pas commencee ; kFinie : rien a attendre, pas encore rendue.
  enum class Etat : uint8_t { kAvant, kAttente, kFinie, kLancee };
  Etat etat_ = Etat::kAvant;
  uint32_t debut_ = 0;
};
