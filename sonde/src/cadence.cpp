#include "cadence.h"

void Cadence::oublierAnciens(uint32_t maintenant) {
  while (nombre_ > 0 && maintenant - instants_[premier_] >= kFenetreMs) {
    premier_ = (uint16_t)((premier_ + 1) % kEnvoisMax);
    nombre_--;
  }
}

Cadence::Avis Cadence::avis(uint32_t maintenant) {
  oublierAnciens(maintenant);
  if (nombre_ >= kEnvoisMax) return Avis::kRefus;
  if (!aucunEnvoi_ && maintenant - dernier_ < kEcartMinMs) return Avis::kAttendre;
  return Avis::kOui;
}

void Cadence::compter(uint32_t maintenant) {
  oublierAnciens(maintenant);
  if (nombre_ == kEnvoisMax) {  // ne devrait pas arriver : avis() refuse avant
    premier_ = (uint16_t)((premier_ + 1) % kEnvoisMax);
    nombre_--;
  }
  instants_[(premier_ + nombre_) % kEnvoisMax] = maintenant;
  nombre_++;
  aucunEnvoi_ = false;
  dernier_ = maintenant;
}
