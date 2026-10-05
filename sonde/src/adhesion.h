#pragma once
// ===========================================================================
//  Adhesion de la sonde au reseau Hue (spec de la sonde, sections 1 et 6)
//
//  zigbee.cpp relaie les signaux de la pile ; loop() appelle tour() et
//  execute l'action rendue, sous le verrou de la pile :
//  - premier demarrage (usine) : chercher un reseau (BDB network steering),
//    puis toutes les 30 s tant qu'aucun ne l'accepte ;
//  - redemarrage avec un reseau en memoire : la pile s'y rattache ; en cas
//    d'echec, rattacher (BDB initialization) toutes les 30 s, sans jamais
//    oublier le reseau de soi-meme (une longue coupure du pont ne doit pas
//    faire perdre l'adhesion) ; les echecs sont comptes (etat), pour que
//    l'app propose oubli ;
//  - parent perdu (appareil final) : si la pile ne s'est pas rattachee seule
//    en 10 s, rattacher, puis toutes les 30 s ;
//  - depart sans retour venu du reseau (le pont retire la sonde) : oublier
//    (effacer zb_storage et redemarrer) ; depart avec retour : redemarrer ;
//  - commande oubli : quitter le reseau (la pile efface sa memoire mais garde
//    le compteur de trames), puis, au depart, redemarrer sans tout effacer ;
//    si la sonde vit encore 15 s plus tard, oublier quand meme ;
//  - constat de la pile (toutes les 10 s) : rattachee alors qu'aucun signal
//    ne l'a dit (signal perdu) : membre.
//  « membre » : rattachee et en service ; « cherche » : ni membre ni sur le
//  depart (la LED pulse en bleu, etat dit recherche:true).
//
//  Pur et sans Arduino : teste sur l'hote (sonde/test/test_adhesion.cpp).
//  Instants de millis() : des ecarts non signes.
// ===========================================================================
#include <stdint.h>

class Adhesion {
 public:
  static constexpr uint32_t kRechercheMs = 30000;     // entre deux recherches
  static constexpr uint32_t kRattachementMs = 10000;  // apres un parent perdu
  static constexpr uint32_t kRelanceMs = 30000;       // entre deux rattachements
  static constexpr uint32_t kReinitMs = 1000;         // apres un premier demarrage en echec
  static constexpr uint32_t kOubliMs = 15000;         // filet de la commande oubli

  enum class Etat : uint8_t { kDemarrage, kRecherche, kAttente, kMembre, kRattachement, kDepart };
  enum class Action : uint8_t { kRien, kInitialiser, kChercher, kRattacher, kOublier, kRedemarrer };

  // Signaux de la pile.
  void premierDemarrage(bool ok, uint32_t t);  // ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START
  void redemarrage(bool ok, uint32_t t);       // ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT
  void recherche(bool ok, uint32_t t);         // ESP_ZB_BDB_SIGNAL_STEERING
  void rattachementTc(bool ok, uint32_t t);    // ESP_ZB_BDB_SIGNAL_TC_REJOIN_DONE
  void parentPerdu(uint32_t t);                // ESP_ZB_NLME_STATUS_INDICATION, parent perdu
  void depart(bool retour, uint32_t t);        // ESP_ZB_ZDO_SIGNAL_LEAVE
  // Commande oubli (zigbee.cpp vient de demander le depart).
  void oubli(uint32_t t);
  // Ce que la pile dit d'elle-meme (esp_zb_bdb_dev_joined), toutes les 10 s.
  void constater(bool rattachee, uint32_t t);

  // L'action a faire maintenant, rendue une seule fois.
  Action tour(uint32_t t);

  Etat etat() const { return etat_; }
  bool membre() const { return etat_ == Etat::kMembre; }
  bool cherche() const { return etat_ != Etat::kMembre && etat_ != Etat::kDepart; }
  // Nombre d'entrees dans l'etat membre depuis le demarrage (la LED montre
  // deux eclairs verts a chacune).
  uint32_t adhesions() const { return adhesions_; }
  // Rattachements echoues depuis la derniere fois que la sonde etait membre.
  uint32_t echecsRattachement() const { return echecs_; }

 private:
  void prevoir(Action a, uint32_t t) {
    prevue_ = a;
    echeance_ = t;
  }
  void devenirMembre();
  Etat etat_ = Etat::kDemarrage;
  Action prevue_ = Action::kRien;
  uint32_t echeance_ = 0;
  uint32_t adhesions_ = 0;
  uint32_t echecs_ = 0;
  bool oubliDemande_ = false;
};
