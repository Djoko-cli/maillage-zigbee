// Tests hote de sonde/src/voyant.h : priorites et sequences de la LED.
// Lancer : sh sonde/test/lancer.sh
#include "verif.h"
#include "voyant.h"

using C = Voyant::Couleur;

// La couleur vaut c sur tout [de, a), lue a chaque milliseconde.
static bool partout(Voyant &v, uint32_t de, uint32_t a, C c) {
  bool ok = true;
  for (uint32_t t = de; t != a; t++) ok = v.teinte(t).couleur == c && ok;
  return ok;
}

int main() {
  Voyant v;
  CHECK(partout(v, 0, 100, C::kNoire), "eteinte par defaut");
  v.allumer(true);
  CHECK(partout(v, 100, 200, C::kVeille), "lampe Hue allumee : veille");
  v.allumer(false);

  // Recherche : pulsation bleue de 2 s, du noir au plein et retour.
  v.chercher(true, 1000);
  CHECK(v.teinte(1000).couleur == C::kBleue && v.teinte(1000).niveau == 0, "pulsation au creux");
  CHECK(v.teinte(2000).niveau == 255, "pulsation au sommet");
  CHECK(v.teinte(1500).niveau == 127 && v.teinte(2500).niveau == 127, "pulsation a mi-chemin");
  CHECK(v.teinte(3000).niveau == 0, "pulsation : periode de 2 s");
  CHECK(partout(v, 1000, 5000, C::kBleue), "bleue tant qu'elle cherche");

  // Adhesion : vert, pause, vert, puis la teinte d'en dessous.
  v.chercher(false, 6000);
  v.adherer(6000);
  CHECK(partout(v, 6000, 6100, C::kVerte) && partout(v, 6100, 6200, C::kNoire) &&
            partout(v, 6200, 6300, C::kVerte) && partout(v, 6300, 6400, C::kNoire),
        "deux eclairs verts");

  // Identification : passe devant tout, blanc 500 ms, eteint 500 ms.
  v.chercher(true, 7000);
  v.identifier(true, 7000);
  CHECK(partout(v, 7000, 7500, C::kBlanche) && partout(v, 7500, 8000, C::kNoire) &&
            partout(v, 8000, 8500, C::kBlanche),
        "identification devant la recherche");
  v.identifier(false, 9000);
  CHECK(v.teinte(9000).couleur == C::kBleue, "fin de l'identification : la recherche reprend");
  v.chercher(false, 9000);

  // Suspendue : bref eclair orange tout de suite, puis toutes les 5 s ; entre
  // deux, la lampe Hue.
  v.allumer(true);
  v.suspendre(true, 10000);
  CHECK(partout(v, 10000, 10100, C::kOrange) && partout(v, 10100, 15000, C::kVeille) &&
            partout(v, 15000, 15100, C::kOrange) && partout(v, 15100, 20000, C::kVeille),
        "eclairs de la suspension");
  // Boucle retenue 12 s : la grille de 5 s est gardee.
  CHECK(v.teinte(32000).couleur == C::kVeille && v.teinte(35000).couleur == C::kOrange, "grille gardee");
  v.suspendre(true, 35500);  // deja suspendue : la grille ne bouge pas
  CHECK(v.teinte(40050).couleur == C::kOrange, "grille gardee malgre un second appel");
  v.suspendre(false, 41000);
  CHECK(partout(v, 41000, 46000, C::kVeille), "reprise : plus d'eclair");

  // Retour a zero de millis() : une adhesion finie ne se ranime pas.
  Voyant z;
  z.adherer(0xFFFFFF00u);
  CHECK(z.teinte(0xFFFFFF00u + 50).couleur == C::kVerte, "eclair avant zero");
  CHECK(z.teinte(0xFFFFFF00u + 400).couleur == C::kNoire, "fini apres zero");
  CHECK(partout(z, 0xFFFFFF00u + 400, 0xFFFFFF00u + 2000, C::kNoire), "rien ne se ranime");

  return bilan("voyant");
}
