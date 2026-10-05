#pragma once
// ===========================================================================
//  Garde-fou de cadence (spec de la sonde, section 3)
//
//  Toute requete que la sonde emet dans le reseau (une page de table ou de
//  routes, une requete d'echecs) passe ici :
//  - au moins 100 ms entre deux envois : sinon, attendre ;
//  - au plus 600 envois par fenetre glissante de 10 minutes : au-dela, refus
//    (la table ou la requete se termine en « cadence », sans rien emettre),
//    compte depuis le demarrage (refus_cadence de la commande etat).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_cadence.cpp).
//  Instants de millis() : des ecarts non signes, justes a travers le retour a
//  zero.
// ===========================================================================
#include <stdint.h>

class Cadence {
 public:
  static constexpr uint32_t kEcartMinMs = 100;
  static constexpr uint32_t kFenetreMs = 600000;
  static constexpr uint16_t kEnvoisMax = 600;

  enum class Avis : uint8_t { kOui, kAttendre, kRefus };

  // Peut-on envoyer maintenant ?
  Avis avis(uint32_t maintenant);
  // Un envoi vient de partir.
  void compter(uint32_t maintenant);
  // Compte un refus (l'appelant abandonne la requete).
  void refuser() { refus_++; }
  uint32_t refus() const { return refus_; }

 private:
  void oublierAnciens(uint32_t maintenant);
  uint32_t instants_[kEnvoisMax] = {0};  // anneau des envois de la fenetre
  uint16_t premier_ = 0;
  uint16_t nombre_ = 0;
  bool aucunEnvoi_ = true;
  uint32_t dernier_ = 0;
  uint32_t refus_ = 0;
};
