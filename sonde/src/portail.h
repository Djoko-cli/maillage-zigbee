#pragma once
// ===========================================================================
//  Portail : l'enveloppe H1 sur des lignes TCP (spec sonde Wi-Fi, 3.3)
//
//  Connexions numerotees 0..kConnexions-1 (reseau.cpp les relie aux sockets).
//  Une ligne terminee par LF = un message H1 ; CR ignore ; une ligne de plus
//  de kLigneMax octets ferme la connexion. La session H1 promue sur une
//  connexion lui est liee et tombe avec elle ; a l'inverse, une session oubliee
//  ou evincee ferme sa connexion (l'app voit la fin et se reconnecte), et une
//  connexion sans session (kSansSessionMs) ou muette (kMuetteMs) est fermee :
//  les kConnexions places ne restent pas prises. Un message refuse (forme, cle,
//  MAC, rejeu, requete mal formee) ne recoit rien : sans cle, la sonde se tait.
//
//  Pur : teste sur l'hote (sonde/test/test_portail.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "canaux.h"
#include "h1_proto.h"

class Portail {
 public:
  static constexpr uint8_t kConnexions = 3;
  static constexpr size_t kLigneMax = 4200;  // LF exclu
  static constexpr uint8_t kAucune = 0xFF;
  // Une connexion sans session etablie (pas de poignee de main reussie) est fermee apres kSansSessionMs ; une
  // connexion dont la session se tait depuis kMuetteMs aussi. kMuetteMs depasse la periode d'entretien de l'app
  // (SondeMaillage.periodeEntretien, 180 s : un `etat` hors tournee ; en tournee, 128 s au plus entre deux
  // requetes) : seule une app partie (Mac en veille, interface perdue) perd sa place.
  static constexpr uint32_t kSansSessionMs = 10000;
  static constexpr uint32_t kMuetteMs = 300000;

  struct Sortie {
    // Une ligne complete, LF compris.
    virtual void envoyer(uint8_t connexion, const uint8_t *octets, size_t n) = 0;
    virtual void fermer(uint8_t connexion) = 0;
  };

  struct Requete {
    uint8_t session = 0;
    uint32_t rid = 0;
    char commande[kCommandeMax + 1] = {0};
  };

  // nullptr : aucune cle. Changer de cle fait tomber toutes les sessions.
  bool cle(const uint8_t *psk);
  bool aCle() const { return table_.hasKey(); }

  void ouverte(uint8_t c, uint32_t maintenant);
  void fermee(uint8_t c);
  void recevoir(uint8_t c, const uint8_t *octets, size_t n, uint32_t maintenant, h1::Table::Random rnd, Sortie &s);
  // Une requete admise, la plus ancienne ; false s'il n'y en a pas.
  bool requete(Requete *r);
  // Reponse (rid > 0) ou signal (rid 0) a la session ; false si elle n'est
  // reliee a aucune connexion ouverte.
  bool repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n, Sortie &s);
  void diffuser(const uint8_t *ligne, size_t n, Sortie &s);
  // Oubli des sessions inactives (h1::kForgetMs) et fermeture des connexions sans session ou muettes.
  void expirer(uint32_t maintenant, Sortie &s);

  uint8_t sessions() const;
  uint32_t envois() const { return envois_; }
  uint32_t refus() const { return refus_; }
  uint32_t fermetures() const { return fermetures_; }

  Portail() {
    for (uint8_t &c : connexionDe_) c = kAucune;
  }

 private:
  struct Connexion {
    bool ouverte = false;
    size_t long_ = 0;
    uint32_t depuis = 0;    // ouverture
    uint32_t activite = 0;  // dernier message admis de sa session (ouverture avant le premier)
    uint8_t tampon[kLigneMax];
  };
  static constexpr uint8_t kFile = 4;

  void ligne(uint8_t c, const uint8_t *l, size_t n, uint32_t maintenant, h1::Table::Random rnd, Sortie &s);
  // Retire de la file les requetes de l'emplacement slot (place liberee ou reprise), ordre conserve.
  void purger(uint8_t slot);
  // Ferme la connexion c (comptee) : sa session tombe avec elle.
  void couper(uint8_t c, Sortie &s);
  bool aSession(uint8_t c) const;

  h1::Table table_;
  Connexion cx_[kConnexions];
  uint8_t connexionDe_[h1::kSlots];
  Requete file_[kFile];
  uint8_t debut_ = 0, nombre_ = 0;
  uint32_t envois_ = 0, refus_ = 0, fermetures_ = 0;
  uint8_t charge_[kLigneMax];
  uint8_t sortie_[kLigneMax + 1];
};
