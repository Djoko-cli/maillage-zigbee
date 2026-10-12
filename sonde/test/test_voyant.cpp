// Tests hote de sonde/src/voyant.h : priorites et sequences de la LED.
// Lancer : sh sonde/test/lancer.sh
#include "verif.h"
#include "voyant.h"

using Rgb = Voyant::Rgb;
static const Rgb kNoir{};
static const Rgb kBleu(uint8_t b) { return Rgb{0, 0, b}; }
static const Rgb kVert{0, 24, 0};
static const Rgb kOrange{24, 6, 0};
static const Rgb kVeille{2, 2, 2};

// La couleur vaut c sur tout [de, a), lue a chaque milliseconde.
static bool partout(Voyant &v, uint32_t de, uint32_t a, Rgb c) {
  bool ok = true;
  for (uint32_t t = de; t != a; t++) ok = v.teinte(t) == c && ok;
  return ok;
}

static bool grise(Rgb c) { return c.r == c.g && c.g == c.b; }

int main() {
  // Repos, lampe eteinte : une lueur blanche de 600 ms toutes les 10 s, la
  // premiere des l'arrivee au repos.
  {
    Voyant v;
    CHECK(v.teinte(0) == kNoir, "la lueur part de zero");
    CHECK(v.teinte(300) == (Rgb{8, 8, 8}), "sommet de la lueur : 8 au milieu des 600 ms");
    bool monte = true, descend = true;
    for (uint32_t t = 0; t < 300; t++) monte = v.teinte(t).r <= v.teinte(t + 1).r && monte;
    for (uint32_t t = 300; t < 600; t++) descend = v.teinte(t).r >= v.teinte(t + 1).r && descend;
    CHECK(monte && descend, "montee puis descente");
    bool blanche = true;
    for (uint32_t t = 0; t < 600; t++) blanche = grise(v.teinte(t)) && v.teinte(t).r <= 8 && blanche;
    CHECK(blanche, "blanche, 8 au plus");
    CHECK(v.teinte(600) == kNoir && partout(v, 600, 10000, kNoir), "noir en dehors de la lueur");
    CHECK(v.teinte(10300) == (Rgb{8, 8, 8}) && v.teinte(20300) == (Rgb{8, 8, 8}), "une lueur toutes les 10 s");
    CHECK(partout(v, 10600, 20000, kNoir), "noir entre deux lueurs");
    CHECK(v.teinte(30000) == kNoir && v.teinte(30001).r == v.teinte(29999 + 2).r, "grille reguliere");
  }
  // La premiere lueur suit le passage au repos, pas l'horloge : demarrage tardif.
  {
    Voyant v;
    CHECK(v.teinte(123456) == kNoir && v.teinte(123456 + 300) == (Rgb{8, 8, 8}), "lueur une fois au repos");
    CHECK(partout(v, 123456 + 600, 123456 + 10000, kNoir), "puis dix secondes de noir");
  }
  // Lampe Hue allumee : veille fixe, pas de lueur.
  {
    Voyant v;
    v.allumer(true);
    CHECK(partout(v, 0, 25000, kVeille), "lampe Hue allumee : veille (2,2,2), sans lueur");
    v.allumer(false);
    CHECK(v.teinte(25000) == kNoir, "lampe eteinte : plus de veille");
    CHECK(v.teinte(30300) == (Rgb{8, 8, 8}) && v.teinte(31000) == kNoir, "la lueur reprend, sur la meme grille");
  }

  // Identification : arc-en-ciel, tout au long de l'identification seulement.
  {
    Voyant v;
    v.identifier(true, 1000);
    CHECK(v.teinte(1000) == (Rgb{24, 0, 0}), "arc-en-ciel : part du rouge");
    CHECK(v.teinte(2000) == (Rgb{0, 12, 12}), "arc-en-ciel : vert-bleu a mi-tour");
    CHECK(v.teinte(3000) == v.teinte(1000) && v.teinte(5000) == v.teinte(1000), "tour de 2 s");
    bool nonNoir = true, borne = true, change = false;
    for (uint32_t t = 1000; t < 5000; t++) {
      const Rgb c = v.teinte(t);
      nonNoir = (c.r || c.g || c.b) && nonNoir;
      borne = c.r <= 24 && c.g <= 24 && c.b <= 24 && borne;
      change = c != v.teinte(t - 1 < 1000 ? 1000 : t - 1) || change;
    }
    CHECK(nonNoir && borne && change, "arc-en-ciel : jamais noir, plafonne, change avec le temps");
    CHECK(v.teinte(1039) == v.teinte(1000) && v.teinte(1040) != v.teinte(1000), "par pas de 40 ms");
    v.identifier(false, 5000);
    CHECK(v.teinte(5000) == kNoir && v.teinte(5300) == (Rgb{8, 8, 8}), "fin : retour au repos, lueur");
  }

  // Identification d'un instant (pont Hue, banc du 12/10) : un tour de roue
  // complet quand meme, puis le repos.
  {
    Voyant v;
    v.identifier(true, 1000);
    v.identifier(false, 1100);
    CHECK(v.teinte(2000) == (Rgb{0, 12, 12}), "identification breve : le tour continue");
    CHECK(v.teinte(2999) != kNoir && v.teinte(2999) != (Rgb{8, 8, 8}), "identification breve : jusqu'au bout du tour");
    CHECK(v.teinte(3000) == kNoir, "identification breve : repos apres un tour");
    v.identifier(true, 4000);
    CHECK(v.teinte(4000) == (Rgb{24, 0, 0}), "nouvelle identification : le tour repart du rouge");
  }

  // Sonde neuve (jamais membre) : bleu rapide 250/250 ; un rattachement
  // garde la pulsation lente.
  {
    Voyant n;
    n.chercher(true, 1000, true);
    CHECK(n.teinte(1000) == kBleu(24) && n.teinte(1249) == kBleu(24), "neuve : bleu 250 ms");
    CHECK(n.teinte(1250) == kNoir && n.teinte(1499) == kNoir && n.teinte(1500) == kBleu(24), "neuve : noir 250 ms, et ainsi de suite");
    n.chercher(true, 2000, false);
    // Meme debut (1000) : 1 s plus tard le sommet, 1,5 s plus tard la moitie.
    CHECK(n.teinte(2000) == kBleu(24) && n.teinte(2500) == kBleu(12), "rattachement : pulsation lente");
  }

  // Recherche : pulsation bleue de 2 s, du noir au plein et retour.
  Voyant v;
  v.chercher(true, 1000);
  CHECK(v.teinte(1000) == kBleu(0), "pulsation au creux");
  CHECK(v.teinte(2000) == kBleu(24), "pulsation au sommet");
  CHECK(v.teinte(1500) == kBleu(12) && v.teinte(2500) == kBleu(12), "pulsation a mi-chemin");
  CHECK(v.teinte(3000) == kBleu(0), "pulsation : periode de 2 s");
  bool bleue = true;
  for (uint32_t t = 1000; t < 5000; t++) bleue = v.teinte(t).r == 0 && v.teinte(t).g == 0 && bleue;
  CHECK(bleue, "bleue tant qu'elle cherche");

  // Adhesion : vert, pause, vert, puis la teinte d'en dessous.
  v.chercher(false, 6000);
  v.adherer(6000);
  CHECK(partout(v, 6000, 6100, kVert) && partout(v, 6100, 6200, kNoir) && partout(v, 6200, 6300, kVert),
        "deux eclairs verts");
  CHECK(v.teinte(6300) == kNoir, "apres l'adhesion : repos");

  // Identification devant la recherche.
  v.chercher(true, 7000);
  v.identifier(true, 7000);
  CHECK(v.teinte(7000) == (Rgb{24, 0, 0}) && v.teinte(8000) == (Rgb{0, 12, 12}), "identification devant la recherche");
  v.identifier(false, 9000);
  CHECK(v.teinte(9000).b == 24 || v.teinte(9000).b == 0, "fin de l'identification : la recherche reprend");
  CHECK(v.teinte(9000 + 1000) == kBleu(24), "pulsation de nouveau");
  v.chercher(false, 9000);

  // Suspendue : bref eclair orange tout de suite, puis toutes les 5 s ; entre
  // deux, la lampe Hue.
  v.allumer(true);
  v.suspendre(true, 10000);
  CHECK(partout(v, 10000, 10100, kOrange) && partout(v, 10100, 15000, kVeille) &&
            partout(v, 15000, 15100, kOrange) && partout(v, 15100, 20000, kVeille),
        "eclairs de la suspension");
  // Boucle retenue 12 s : la grille de 5 s est gardee.
  CHECK(v.teinte(32000) == kVeille && v.teinte(35000) == kOrange, "grille gardee");
  v.suspendre(true, 35500);  // deja suspendue : la grille ne bouge pas
  CHECK(v.teinte(40050) == kOrange, "grille gardee malgre un second appel");
  v.suspendre(false, 41000);
  CHECK(partout(v, 41000, 46000, kVeille), "reprise : plus d'eclair");

  // Orange lent : Wi-Fi configure mais non connecte, 1 s allume puis 1 s eteint.
  {
    Voyant w;
    w.wifi(false, false, 0);
    bool jamais = true;
    for (uint32_t t = 0; t < 30000; t++) jamais = w.teinte(t) != kOrange && jamais;
    CHECK(jamais, "sans Wi-Fi configure, aucun orange");

    Voyant x;
    x.wifi(true, false, 500);
    CHECK(partout(x, 500, 1500, kOrange) && partout(x, 1500, 2500, kNoir) && partout(x, 2500, 3500, kOrange) &&
              partout(x, 3500, 4500, kNoir),
          "orange 1 s, noir 1 s, des le debut");
    x.wifi(true, false, 4000);  // toujours non connecte : la phase ne bouge pas
    CHECK(x.teinte(4500) == kOrange && x.teinte(5499) == kOrange && x.teinte(5500) == kNoir, "phase gardee");
    x.wifi(true, true, 6000);
    CHECK(x.teinte(6000) != kOrange && x.teinte(6300) == (Rgb{8, 8, 8}), "connecte : plus d'orange, lueur de repos");
    x.wifi(true, false, 20000);
    CHECK(x.teinte(20000) == kOrange && x.teinte(21000) == kNoir, "connexion perdue : l'orange repart allume");
    x.wifi(false, false, 22000);  // Wi-Fi efface
    bool plus = true;
    for (uint32_t t = 22000; t < 40000; t++) plus = x.teinte(t) != kOrange && plus;
    CHECK(plus, "Wi-Fi efface : plus d'orange");
  }

  // Priorites autour de l'orange Wi-Fi.
  {
    Voyant p;
    p.wifi(true, false, 0);
    p.allumer(true);
    CHECK(p.teinte(0) == kOrange && p.teinte(1000) == kNoir, "orange devant la veille de la lampe");
    p.identifier(true, 2000);
    CHECK(p.teinte(2000) == (Rgb{24, 0, 0}), "identification devant l'orange");
    p.identifier(false, 4000);  // apres un tour complet
    p.chercher(true, 4000);
    CHECK(p.teinte(5000) == kBleu(24), "recherche devant l'orange");
    p.chercher(false, 6000);
    p.adherer(6000);
    CHECK(p.teinte(6000) == kVert && p.teinte(6100) == kNoir && p.teinte(6200) == kVert, "adhesion devant l'orange");
    p.suspendre(true, 10000);
    CHECK(p.teinte(10000) == kOrange && p.teinte(10100) == kOrange, "suspendue + orange");
    CHECK(p.teinte(11000) == kNoir && p.teinte(12000) == kOrange, "entre deux eclairs, l'orange lent continue");
    p.suspendre(false, 12500);
    p.wifi(true, true, 13000);
    CHECK(p.teinte(13000) == kVeille, "connecte, lampe allumee : veille");
  }

  // Retour a zero de millis() : rien ne se ranime.
  Voyant z;
  z.adherer(0xFFFFFF00u);
  CHECK(z.teinte(0xFFFFFF00u + 50) == kVert, "eclair avant zero");
  CHECK(z.teinte(0xFFFFFF00u + 400) == kNoir, "fini apres zero");
  bool aucunVert = true;
  for (uint32_t t = 0xFFFFFF00u + 300; t != 0x3000; t++) aucunVert = z.teinte(t).g != 24 && aucunVert;
  CHECK(aucunVert, "l'adhesion ne revient pas apres zero");
  // Orange et arc-en-ciel a travers zero : phases continues.
  Voyant y;
  y.wifi(true, false, 0xFFFFFC00u);
  CHECK(y.teinte(0xFFFFFC00u) == kOrange && y.teinte(0xFFFFFFFFu - 100) == kOrange, "orange avant zero");
  CHECK(y.teinte(0xFFFFFC00u + 1000) == kNoir && y.teinte(0xFFFFFC00u + 2000) == kOrange, "phases de 1 s");
  y.identifier(true, 0xFFFFFF00u);
  CHECK(y.teinte(0xFFFFFF00u) == (Rgb{24, 0, 0}) && y.teinte(0xFFFFFF00u + 1000) == (Rgb{0, 12, 12}),
        "arc-en-ciel a travers zero");
  y.identifier(false, 0xFFFFFF00u + 2000);  // apres un tour complet
  // 2768 ms apres le debut de l'orange : allumee ; 3000 : eteinte.
  CHECK(y.teinte(0xFFFFFF00u + 2000) == kOrange && y.teinte(0xFFFFFF00u + 2232) == kNoir, "retour a l'orange, phase gardee");

  return bilan("voyant");
}
