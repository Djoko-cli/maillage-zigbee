#pragma once
// ===========================================================================
//  Colle avec la pile Zigbee d'Espressif (esp-zigbee-lib 1.6.8, ZBOSS 1.6.4)
//
//  Le seul fichier de la sonde qui parle a la pile. Il ne passe pas par la
//  bibliotheque Zigbee d'Arduino, qui envoie d'elle-meme des Match_Desc_req
//  quand un appareil s'annonce : la liste blanche l'interdit (spec, section
//  3).
//
//  Deux mondes :
//  - la tache Zigbee (creee par demarrer()) fait tourner la pile ; ses
//    rappels ne font que remplir deux files (evenements et reponses) ;
//  - loop() lit ces files, et appelle les fonctions « sous le verrou » apres
//    avoir pris le verrou de la pile (verrou(), 200 ms au plus), puis le
//    rend (libere()).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "entrees.h"

namespace zigbee {

// Signaux de la pile et commandes de la grappe lampe, pour loop().
enum class Signal : uint8_t {
  kPremierDemarrage,  // ok : statut de la pile
  kRedemarrage,       // ok : rattachee au reseau garde en memoire
  kRecherche,         // ok : adhesion reussie
  kRattachementTc,    // ok : rattachement par le centre de confiance reussi
  kParentPerdu,
  kDepart,            // ok : depart avec retour (rejoin)
  kIdentification,    // ok : identification en cours (attribut Identify Time)
  kEffet,             // ok : effet d'identification lance ; false : arrete
  kLampe,             // ok : lampe Hue allumee
  kBrut,              // tout signal de la pile, pour le journal de l'essai (SONDE_SIGNAUX)
};

struct Evenement {
  Signal signal;
  bool ok;
  uint8_t brut = 0;          // kBrut : type du signal de la pile
  uint8_t detail = 0;        // kBrut : statut NLME, ou type de depart
  const char *nom = nullptr; // kBrut : nom du signal (table constante de la pile)
};

// Reponse a une requete de la sonde, reperee par son numero.
enum class Genre : uint8_t { kVoisins, kRoutes, kEchecs };
static constexpr size_t kVoisinsParPageMax = 8;

struct Reponse {
  Genre genre = Genre::kVoisins;
  uint32_t numero = 0;
  uint8_t statut = 0;
  uint8_t total = 0;
  uint8_t debut = 0;
  uint8_t nombre = 0;
  EntreeVoisin voisins[kVoisinsParPageMax];  // kVoisins
  EntreeRoute routes[kRoutesParPageMax];     // kRoutes
  uint16_t emissions = 0;                    // kEchecs
  uint16_t echecs = 0;
  uint8_t energie = 0;
};

// Cree la pile, le point d'acces lampe et la tache Zigbee (dans setup()).
void demarrer();

// La pile a demarre (premier signal recu) : avant, aucun verrou n'est pris.
bool prete();
// Verrou de la pile, ms au plus ; toujours refuse avant prete().
bool verrou(uint32_t ms);
void libere();

// --- Sous le verrou -------------------------------------------------------
bool rattachee();              // esp_zb_bdb_dev_joined()
void ieee(uint8_t sortie[8]);  // ordre du reseau (poids faible d'abord)
uint16_t court();
uint16_t pan();
void epid(uint8_t sortie[8]);
uint8_t canal();
// Table des voisins de la sonde : *iterateur a 0 pour la premiere entree.
bool voisinSuivant(uint16_t *iterateur, VoisinSonde *v);
// Requetes (refusees par la liste blanche si elles n'y sont pas) ; la
// reponse arrive dans la file avec le meme numero.
bool envoyerVoisins(uint16_t cible, uint8_t index, uint32_t numero);  // Mgmt_Lqi_req
bool envoyerRoutes(uint16_t cible, uint8_t index, uint32_t numero);   // Mgmt_Rtg_req, APS brute
bool envoyerEchecs(uint16_t cible, uint32_t numero);                  // Mgmt_NWK_Update_req
// Mise en service (BDB) : initialisation (rattachement au reseau garde),
// recherche (network steering). Une recherche alors que la sonde est deja
// rattachee diffuserait un Mgmt_Permit_Joining_req (norme BDB) et ouvrirait
// le reseau Hue : chercher() ne la lance pas, et annonce la recherche reussie.
void initialiser();
void chercher();
// Quitter le reseau et effacer la memoire Zigbee (signal de depart a la fin).
void quitter();
// Effacer zb_storage et redemarrer.
void oublier();
// Version de la pile : « majeure.mineure.correctif ».
void versionPile(char *sortie, size_t taille);

// --- Hors verrou ----------------------------------------------------------
bool evenement(Evenement *e);
bool reponse(Reponse *r);

}  // namespace zigbee
