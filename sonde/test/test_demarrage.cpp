// Tests hote de sonde/src/demarrage.h : l'attente du Wi-Fi au demarrage, qui ne
// bloque pas la boucle (l'USB repond pendant ce temps) et ne laisse demarrer la
// pile Zigbee qu'apres le Wi-Fi connecte ou l'abandon de l'attente.
// Lancer : sh sonde/test/lancer.sh
#include "demarrage.h"
#include "verif.h"

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

  static_assert(AttenteWifi::kMaxMs == 15000, "spec sonde Wi-Fi, 3.2 : 15 s au plus");
  return bilan("demarrage");
}
