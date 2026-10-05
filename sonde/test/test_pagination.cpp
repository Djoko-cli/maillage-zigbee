// Tests hote de sonde/src/pagination.h : pages, reprises, delais, total qui
// change, entrees en trop. Les entrees sont des entiers.
// Lancer : sh sonde/test/lancer.sh
#include "pagination.h"
#include "verif.h"

using P = Pagination<int, 8>;

// Envoie la page attendue (aEnvoyer doit dire oui) et rend son numero.
static uint32_t envoyer(P &p, uint32_t t) {
  if (!p.aEnvoyer(t)) return 0;
  const uint32_t n = p.numeroAEnvoyer();
  p.envoyee(t);
  return n;
}

int main() {
  const int e[] = {10, 11, 12, 13, 14, 15, 16, 17, 18, 19};
  P p;
  CHECK(!p.actif() && !p.aEnvoyer(0), "inactive au depart");

  // Deux pages : 3 puis 2 entrees sur 5.
  p.commencer(1000, 5000);
  CHECK(p.actif() && p.index() == 0, "commencee");
  uint32_t n = envoyer(p, 1000);
  CHECK(n == 1 && !p.aEnvoyer(1001), "page 0 partie, attente");
  p.page(n, 0, 5, 0, 3, e, 1100);
  CHECK(p.actif() && p.index() == 3, "page 0 recue");
  n = envoyer(p, 1200);
  CHECK(n == 2, "page 3 partie");
  p.page(n, 0, 5, 3, 2, e + 3, 1300);
  CHECK(!p.actif() && p.issue() == Issue::kOk && !p.partielle() && p.nombre() == 5 && p.pages() == 2 &&
            p.total() == 5 && p.dureeMs() == 300,
        "finie");
  CHECK(p.entree(0) == 10 && p.entree(4) == 14, "entrees dans l'ordre");
  p.page(n, 0, 5, 3, 2, e, 1400);
  CHECK(p.nombre() == 5, "page apres la fin ignoree");

  // Table vide.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 0, 0, 0, e, 10);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 0 && !p.partielle(), "table vide");

  // Delai : une page redemandee une fois, la reponse tardive ecartee.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  CHECK(!p.aEnvoyer(4999), "avant le delai");
  CHECK(p.aEnvoyer(5000), "delai : redemander");
  const uint32_t n2 = envoyer(p, 5000);
  CHECK(n2 == n + 1, "nouveau numero");
  p.page(n, 0, 2, 0, 2, e, 5100);
  CHECK(p.actif() && p.nombre() == 0, "reponse tardive ecartee");
  p.page(n2, 0, 2, 0, 2, e, 5200);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 2, "reponse a la seconde demande");

  // Deux silences : delai.
  p.commencer(0, 1000);
  envoyer(p, 0);
  envoyer(p, 1000);
  CHECK(!p.aEnvoyer(2000) && !p.actif() && p.issue() == Issue::kDelai && p.dureeMs() == 2000, "deux silences");

  // La nouvelle tentative est permise de nouveau apres une page reussie.
  p.commencer(0, 1000);
  envoyer(p, 0);
  n = envoyer(p, 1000);
  p.page(n, 0, 4, 0, 2, e, 1100);
  envoyer(p, 1200);
  n = envoyer(p, 2200);
  CHECK(n != 0 && p.actif(), "seconde page redemandee");
  p.page(n, 0, 4, 2, 2, e + 2, 2300);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.nombre() == 4, "reprise par page");

  // Statut 0x85 de la pile : comme un silence.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0x85, 0, 0, 0, e, 10);
  CHECK(p.actif() && p.aEnvoyer(11), "0x85 : redemander");
  n = envoyer(p, 11);
  p.page(n, 0x85, 0, 0, 0, e, 20);
  CHECK(!p.actif() && p.issue() == Issue::kDelai, "deux 0x85 : delai");

  // Autre statut : fin en « statut ».
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0x84, 0, 0, 0, e, 10);
  CHECK(!p.actif() && p.issue() == Issue::kStatut && p.statut() == 0x84, "statut 0x84");

  // Total qui change : recommencer une fois, puis partielle.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 7, 3, 3, e + 3, 30);
  CHECK(p.actif() && p.index() == 0 && p.nombre() == 0 && p.pages() == 0, "total change : on recommence");
  n = envoyer(p, 40);
  p.page(n, 0, 7, 0, 3, e, 50);
  n = envoyer(p, 60);
  p.page(n, 0, 8, 3, 3, e + 3, 70);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 3, "change encore : partielle");

  // Page qui ne commence pas a l'index demande : comme un total qui change.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 6, 2, 3, e + 2, 30);
  CHECK(p.actif() && p.index() == 0, "index decale : on recommence");

  // Page vide avant le total : partielle.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 6, 0, 3, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 6, 3, 0, e, 30);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 3, "page vide : partielle");

  // Plus d'entrees que la place (8) : partielle avec les 8 premieres.
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.page(n, 0, 10, 0, 5, e, 10);
  n = envoyer(p, 20);
  p.page(n, 0, 10, 5, 5, e + 5, 30);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.partielle() && p.nombre() == 8 && p.entree(7) == 17,
        "trop d'entrees : partielle");

  // 120 s au plus, meme quand chaque page repond dans son delai.
  p.commencer(0, 30000);
  uint32_t t = 0;
  for (int i = 0; i < 4 && p.actif(); i++) {
    n = envoyer(p, t);
    t += 29000;
    p.page(n, 0, 200, (uint8_t)(i * 2), 2, e, t);
  }
  CHECK(p.actif(), "116 s : encore en cours");
  CHECK(!p.aEnvoyer(120000) && !p.actif() && p.issue() == Issue::kDelai, "120 s : delai");

  // Abandon par l'appelant.
  p.commencer(0, 5000);
  p.abandonner(Issue::kCadence, 5);
  CHECK(!p.actif() && p.issue() == Issue::kCadence && p.dureeMs() == 5, "abandon en cadence");
  p.abandonner(Issue::kEnvoi, 9);
  CHECK(p.issue() == Issue::kCadence, "abandon d'une table finie : rien");
  p.commencer(0, 5000);
  n = envoyer(p, 0);
  p.abandonner(Issue::kNonMembre, 7);
  p.page(n, 0, 1, 0, 1, e, 8);
  CHECK(!p.actif() && p.issue() == Issue::kNonMembre && p.nombre() == 0, "sortie du reseau : la page tardive ignoree");

  // Retour a zero de millis().
  const uint32_t presque = 0xFFFFFF00u;
  p.commencer(presque, 1000);
  n = envoyer(p, presque);
  CHECK(!p.aEnvoyer(presque + 999), "avant le delai, a travers zero");
  CHECK(p.aEnvoyer(presque + 1000), "delai a travers zero");
  n = envoyer(p, presque + 1000);
  p.page(n, 0, 1, 0, 1, e, presque + 1100);
  CHECK(!p.actif() && p.issue() == Issue::kOk && p.dureeMs() == 1100, "duree a travers zero");

  return bilan("pagination");
}
