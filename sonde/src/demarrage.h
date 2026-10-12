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
  // La pile Zigbee a ete lancee (ou va l'etre dans le meme tour de loop()).
  bool lancee() const { return etat_ == Etat::kLancee; }

 private:
  // kAvant : pas commencee ; kFinie : rien a attendre, pas encore rendue.
  enum class Etat : uint8_t { kAvant, kAttente, kFinie, kLancee };
  Etat etat_ = Etat::kAvant;
  uint32_t debut_ = 0;
};

// La recherche d'un reseau Zigbee n'est visible (voyant bleu) que pendant que la
// pile tourne : pendant l'attente du Wi-Fi, l'adhesion est a son etat de
// demarrage (cherche() vrai) sans que rien ne cherche, et le voyant montre
// l'orange lent « Wi-Fi configure, pas connecte » (N5 de la re-relecture finale).
inline bool rechercheAMontrer(const AttenteWifi &attente, bool adhesionCherche) {
  return attente.lancee() && adhesionCherche;
}
