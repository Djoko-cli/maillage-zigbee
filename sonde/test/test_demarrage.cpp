// Tests hote de sonde/src/demarrage.h : l'attente du Wi-Fi au demarrage, qui ne
// bloque pas la boucle (l'USB repond pendant ce temps) et ne laisse demarrer la
// pile Zigbee qu'apres le Wi-Fi connecte ou l'abandon de l'attente.
// Lancer : sh sonde/test/lancer.sh
#include "demarrage.h"
#include "verif.h"
#include "voyant.h"

int main() {
  {  // sansWifi : rien a attendre, la pile demarre tout de suite (sonde 1.0.0)
    AttenteWifi a;
    a.commencer(false, 1000);
    CHECK(a.finir(false, 1000), "finie des le premier tour");
    CHECK(!a.finir(false, 1001), "une seule fois");
    CHECK(!a.enCours(), "plus en cours");
  }

  {  // avantCommencer : rien ne demarre
    AttenteWifi a;
    CHECK(!a.finir(true, 0), "pas commencee : pas finie");
    CHECK(!a.enCours(), "pas en cours");
  }

  {  // wifiConnecte : la pile demarre des la connexion, pas avant
    AttenteWifi a;
    a.commencer(true, 1000);
    CHECK(a.enCours(), "en cours");
    CHECK(!a.finir(false, 1000), "pas connecte : on attend");
    CHECK(!a.finir(false, 1000 + AttenteWifi::kMaxMs - 1), "toujours en attente juste avant l'abandon");
    CHECK(a.finir(true, 1000 + AttenteWifi::kMaxMs - 1), "connecte : finie");
    CHECK(!a.finir(true, 1000 + AttenteWifi::kMaxMs), "une seule fois");
  }

  {  // abandon : sans Wi-Fi apres kMaxMs, la pile demarre quand meme
    AttenteWifi a;
    a.commencer(true, 1000);
    CHECK(!a.finir(false, 1000 + AttenteWifi::kMaxMs - 1), "en attente");
    CHECK(a.finir(false, 1000 + AttenteWifi::kMaxMs), "abandon au bout de kMaxMs");
    CHECK(!a.enCours(), "plus en cours");
    CHECK(!a.finir(true, 1000 + AttenteWifi::kMaxMs + 1), "une seule fois, meme connecte ensuite");
  }

  {  // debordement de millis() : ecarts non signes
    AttenteWifi a;
    a.commencer(true, 0xFFFFFF00u);
    CHECK(!a.finir(false, 0x00000100u), "512 ms apres, malgre le debordement : en attente");
    CHECK(a.finir(false, 0xFFFFFF00u + AttenteWifi::kMaxMs), "abandon apres le debordement");
  }

  {  // voyant pendant l'attente : orange lent « Wi-Fi configure, pas connecte », jamais le bleu de la recherche
     // Zigbee, que la pile ne fait pas encore ; le bleu vient quand la pile demarre (N5 de la re-relecture finale)
    AttenteWifi a;
    Voyant v;
    const Voyant::Rgb orange{24, 6, 0};
    a.commencer(true, 0);
    bool sansBleu = true;
    for (uint32_t t = 0; t < AttenteWifi::kMaxMs; t += 10) {
      a.finir(false, t);
      // Adhesion en kDemarrage : cherche() est vrai des le premier tour.
      v.chercher(rechercheAMontrer(a, true), t, false);
      v.wifi(true, false, t);
      sansBleu = v.teinte(t).b == 0 && sansBleu;
    }
    CHECK(sansBleu, "aucun bleu pendant l'attente du Wi-Fi");
    CHECK(a.enCours(), "attente toujours en cours juste avant kMaxMs");
    v.chercher(rechercheAMontrer(a, true), 100, false);
    v.wifi(true, false, 100);
    CHECK(v.teinte(100) == orange, "orange allume");
    CHECK(v.teinte(1100) == Voyant::Rgb{}, "orange eteint la seconde suivante");
    // La pile demarre (abandon de l'attente) : la recherche se voit, en bleu.
    CHECK(a.finir(false, AttenteWifi::kMaxMs), "abandon");
    const uint32_t t0 = AttenteWifi::kMaxMs + 10;
    v.chercher(rechercheAMontrer(a, true), t0, false);
    v.wifi(true, false, t0);
    CHECK(v.teinte(t0 + 1000) == (Voyant::Rgb{0, 0, 24}), "pulsation bleue, au sommet, une fois la pile lancee");
    v.chercher(rechercheAMontrer(a, false), t0 + 2000, false);
    v.wifi(true, false, t0 + 2000);
    CHECK(v.teinte(t0 + 2000).b == 0, "membre : plus de bleu");
  }

  {  // sans Wi-Fi configure : la pile demarre tout de suite, la recherche se voit des le premier tour
    AttenteWifi a;
    a.commencer(false, 0);
    CHECK(!rechercheAMontrer(a, true), "avant le premier tour de finir()");
    a.finir(false, 0);
    CHECK(rechercheAMontrer(a, true) && !rechercheAMontrer(a, false), "pile lancee : suit l'adhesion");
  }

  static_assert(AttenteWifi::kMaxMs == 15000, "spec sonde Wi-Fi, 3.2 : 15 s au plus");
  return bilan("demarrage");
}
