#include "adhesion.h"

void Adhesion::devenirMembre() {
  etat_ = Etat::kMembre;
  prevue_ = Action::kRien;
  adhesions_++;
  echecs_ = 0;
}

void Adhesion::premierDemarrage(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    etat_ = Etat::kRecherche;
    prevoir(Action::kChercher, t);
  } else {
    etat_ = Etat::kDemarrage;
    prevoir(Action::kInitialiser, t + kReinitMs);
  }
}

void Adhesion::redemarrage(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kRattachement;
    echecs_++;
    prevoir(Action::kRattacher, t + kRelanceMs);
  }
}

void Adhesion::recherche(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kAttente;
    prevoir(Action::kChercher, t + kRechercheMs);
  }
}

void Adhesion::rattachementTc(bool ok, uint32_t t) {
  if (etat_ == Etat::kDepart) return;
  if (ok) {
    devenirMembre();
  } else {
    etat_ = Etat::kRattachement;
    echecs_++;
    prevoir(Action::kRattacher, t + kRelanceMs);
  }
}

void Adhesion::parentPerdu(uint32_t t) {
  if (etat_ != Etat::kMembre) return;
  etat_ = Etat::kRattachement;
  prevoir(Action::kRattacher, t + kRattachementMs);
}

void Adhesion::depart(bool retour, uint32_t t) {
  etat_ = Etat::kDepart;
  // Apres oubli, la pile a deja tout efface sauf le compteur de trames : un
  // simple redemarrage le garde (des voisins rejetteraient sinon les trames
  // de la sonde, revenue avec un compteur a zero).
  prevoir(retour || oubliDemande_ ? Action::kRedemarrer : Action::kOublier, t);
}

void Adhesion::oubli(uint32_t t) {
  etat_ = Etat::kDepart;
  oubliDemande_ = true;
  prevoir(Action::kOublier, t + kOubliMs);
}

void Adhesion::constater(bool rattachee, uint32_t t) {
  (void)t;
  if (!rattachee) return;
  if (etat_ == Etat::kDemarrage || etat_ == Etat::kRecherche || etat_ == Etat::kAttente) devenirMembre();
}

Adhesion::Action Adhesion::tour(uint32_t t) {
  if (prevue_ == Action::kRien) return Action::kRien;
  // Echeance atteinte : ecart non signe de moins de 2^31 ms.
  if (t - echeance_ >= 0x80000000u) return Action::kRien;
  const Action a = prevue_;
  prevue_ = Action::kRien;
  // Filets : si la pile ne repond par aucun signal, la meme action repart
  // plus tard. Un signal qui arrive entre-temps prevoit lui-meme la suite.
  if (a == Action::kRattacher) prevoir(Action::kRattacher, t + kRelanceMs);
  else if (a == Action::kChercher) prevoir(Action::kChercher, t + 2 * kRechercheMs);
  else if (a == Action::kInitialiser) prevoir(Action::kInitialiser, t + kRelanceMs);
  return a;
}
