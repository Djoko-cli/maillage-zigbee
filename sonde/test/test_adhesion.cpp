// Tests hote de sonde/src/adhesion.{h,cpp} : recherche, rattachement, depart.
// Lancer : sh sonde/test/lancer.sh
#include "adhesion.h"
#include "verif.h"

using A = Adhesion::Action;
using E = Adhesion::Etat;

int main() {
  // Premier demarrage (usine) : chercher tout de suite, puis toutes les 30 s.
  Adhesion a;
  CHECK(a.etat() == E::kDemarrage && a.cherche() && !a.membre() && a.tour(0) == A::kRien, "au demarrage");
  a.premierDemarrage(true, 100);
  CHECK(a.etat() == E::kRecherche && a.tour(100) == A::kChercher, "chercher tout de suite");
  CHECK(a.tour(100) == A::kRien, "rendue une seule fois");
  a.recherche(false, 2000);
  CHECK(a.etat() == E::kAttente && a.cherche(), "aucun reseau ouvert : attente");
  CHECK(a.tour(31999) == A::kRien && a.tour(32000) == A::kChercher, "30 s plus tard, chercher encore");
  CHECK(a.tour(91999) == A::kRien && a.tour(92000) == A::kChercher, "filet : sans signal, encore 60 s plus tard");
  a.recherche(true, 93000);
  CHECK(a.membre() && !a.cherche() && a.adhesions() == 1 && a.tour(200000) == A::kRien, "adhesion");

  // Parent perdu : 10 s pour que la pile se rattache seule, puis rattacher
  // toutes les 30 s.
  a.parentPerdu(300000);
  CHECK(a.etat() == E::kRattachement && !a.membre() && a.cherche(), "parent perdu");
  a.parentPerdu(305000);
  CHECK(a.tour(309999) == A::kRien && a.tour(310000) == A::kRattacher, "rattacher 10 s apres la premiere perte");
  CHECK(a.tour(339999) == A::kRien && a.tour(340000) == A::kRattacher, "puis toutes les 30 s");
  a.redemarrage(true, 341000);
  CHECK(a.membre() && a.adhesions() == 2 && a.tour(400000) == A::kRien, "rattachee");

  // La pile se rattache seule avant les 10 s : rien a faire.
  a.parentPerdu(500000);
  a.rattachementTc(true, 503000);
  CHECK(a.membre() && a.tour(510000) == A::kRien && a.adhesions() == 3, "rattachement seul");
  a.parentPerdu(600000);
  a.rattachementTc(false, 601000);
  CHECK(a.etat() == E::kRattachement && a.tour(630999) == A::kRien && a.tour(631000) == A::kRattacher,
        "rattachement TC en echec : relance 30 s plus tard");
  CHECK(a.echecsRattachement() == 1, "echec compte");
  a.redemarrage(true, 632000);
  CHECK(a.echecsRattachement() == 0, "remis a zero une fois membre");

  // Redemarrage avec un reseau en memoire, en echec : rattacher toutes les
  // 30 s, sans jamais oublier le reseau ; les echecs sont comptes.
  Adhesion r;
  r.redemarrage(false, 0);
  CHECK(r.etat() == E::kRattachement && r.tour(29999) == A::kRien && r.tour(30000) == A::kRattacher,
        "redemarrage en echec");
  r.redemarrage(false, 31000);
  r.rattachementTc(false, 32000);
  CHECK(r.echecsRattachement() == 3 && r.etat() == E::kRattachement, "trois echecs, toujours en rattachement");
  CHECK(r.tour(61999) == A::kRien && r.tour(62000) == A::kRattacher, "jamais d'oubli de soi-meme");
  r.redemarrage(true, 63000);
  CHECK(r.membre() && r.adhesions() == 1 && r.echecsRattachement() == 0, "redemarrage reussi");

  // Premier demarrage en echec : reinitialiser 1 s plus tard.
  Adhesion p;
  p.premierDemarrage(false, 0);
  CHECK(p.etat() == E::kDemarrage && p.tour(999) == A::kRien && p.tour(1000) == A::kInitialiser,
        "premier demarrage en echec");
  CHECK(p.tour(30999) == A::kRien && p.tour(31000) == A::kInitialiser, "filet de reinitialisation");

  // Depart : sans retour, oublier ; avec retour, redemarrer. Plus aucun
  // signal n'y change rien.
  Adhesion d;
  d.recherche(true, 0);
  d.depart(false, 10);
  CHECK(d.etat() == E::kDepart && !d.membre() && !d.cherche() && d.tour(10) == A::kOublier, "depart sans retour");
  d.recherche(true, 20);
  d.redemarrage(true, 20);
  d.parentPerdu(20);
  CHECK(d.etat() == E::kDepart && d.tour(30) == A::kRien, "plus rien apres le depart");
  Adhesion dr;
  dr.recherche(true, 0);
  dr.depart(true, 10);
  CHECK(dr.tour(10) == A::kRedemarrer, "depart avec retour");

  // Commande oubli : filet a 15 s ; le depart qui la suit redemarre sans
  // tout effacer (la pile a deja oublie le reseau, et garde le compteur de
  // trames).
  Adhesion o;
  o.recherche(true, 0);
  o.oubli(1000);
  CHECK(o.etat() == E::kDepart && o.tour(15999) == A::kRien && o.tour(16000) == A::kOublier, "filet d'oubli");
  Adhesion o2;
  o2.recherche(true, 0);
  o2.oubli(1000);
  o2.depart(false, 2000);
  CHECK(o2.tour(2000) == A::kRedemarrer && o2.tour(16000) == A::kRien, "depart apres oubli : redemarrer");

  // Constat de la pile : un signal d'adhesion perdu est rattrape.
  Adhesion c;
  c.constater(true, 0);
  CHECK(c.membre() && c.adhesions() == 1, "au demarrage");
  Adhesion c2;
  c2.premierDemarrage(true, 0);
  c2.constater(false, 5000);
  CHECK(c2.etat() == E::kRecherche, "pas rattachee : rien");
  c2.constater(true, 10000);
  CHECK(c2.membre(), "pendant une recherche");
  c2.parentPerdu(20000);
  c2.constater(true, 21000);
  CHECK(c2.etat() == E::kRattachement, "le constat ne dit rien du parent : rattachement garde");
  Adhesion c3;
  c3.recherche(true, 0);
  c3.oubli(100);
  c3.constater(true, 200);
  CHECK(c3.etat() == E::kDepart, "rien apres le depart");

  // Retour a zero de millis().
  Adhesion z;
  z.recherche(false, 0xFFFFF000u);
  CHECK(z.tour(0xFFFFF000u + 29999) == A::kRien && z.tour(0xFFFFF000u + 30000) == A::kChercher, "a travers zero");

  return bilan("adhesion");
}
