// Tests hote de sonde/src/cadence.{h,cpp} (garde-fou de cadence) et de
// sonde/src/liste_blanche.h. Compile trois fois par lancer.sh : options par
// defaut (routes oui, echecs non), SONDE_ECHECS=1, puis les deux a 0.
// Lancer : sh sonde/test/lancer.sh
#include "cadence.h"
#include "liste_blanche.h"
#include "verif.h"

int main() {
  // 100 ms entre deux envois.
  Cadence c;
  CHECK(c.avis(0) == Cadence::Avis::kOui, "premier envoi");
  c.compter(0);
  CHECK(c.avis(99) == Cadence::Avis::kAttendre, "99 ms");
  CHECK(c.avis(100) == Cadence::Avis::kOui, "100 ms");

  // 600 envois en 60 s : le 601e est refuse jusqu'a ce que le premier sorte
  // de la fenetre de 10 minutes.
  Cadence d;
  uint32_t t = 0;
  for (int i = 0; i < 600; i++, t += 100) {
    CHECK(d.avis(t) == Cadence::Avis::kOui, "envoi %d", i);
    d.compter(t);
  }
  CHECK(d.avis(t) == Cadence::Avis::kRefus, "601e refuse");
  CHECK(d.avis(599999) == Cadence::Avis::kRefus, "encore refuse juste avant 10 min");
  CHECK(d.avis(600000) == Cadence::Avis::kOui, "le premier sort de la fenetre a 10 min");
  d.compter(600000);
  CHECK(d.avis(600100) == Cadence::Avis::kOui, "le deuxieme sort a son tour");
  d.compter(600100);
  CHECK(d.avis(600150) == Cadence::Avis::kRefus, "fenetre de nouveau pleine : le refus passe avant l'ecart");
  CHECK(d.avis(600200) == Cadence::Avis::kOui, "le troisieme sort a son tour");
  CHECK(d.refus() == 0, "rien de compte sans refuser()");
  d.refuser();
  d.refuser();
  CHECK(d.refus() == 2, "refus comptes");

  // Retour a zero de millis().
  Cadence z;
  z.compter(0xFFFFFFC0u);
  CHECK(z.avis(0xFFFFFFC0u + 99) == Cadence::Avis::kAttendre, "a travers zero : 99 ms");
  CHECK(z.avis(0xFFFFFFC0u + 100) == Cadence::Avis::kOui, "a travers zero : 100 ms");

  // Liste blanche.
  CHECK(requetePermise(kZdoMgmtLqi, 0x1A2B) && requetePermise(kZdoMgmtLqi, 0x0000), "Mgmt_Lqi_req");
  CHECK(requetePermise(kZdoMgmtLqi, 0xFFF7), "derniere adresse d'appareil");
  CHECK(!requetePermise(kZdoMgmtLqi, 0xFFF8) && !requetePermise(kZdoMgmtLqi, 0xFFFC) &&
            !requetePermise(kZdoMgmtLqi, 0xFFFD) && !requetePermise(kZdoMgmtLqi, 0xFFFF),
        "jamais vers une diffusion");
  CHECK(requetePermise(kZdoMgmtRtg, 0x1A2B) == (SONDE_ROUTES != 0), "Mgmt_Rtg_req selon SONDE_ROUTES");
  CHECK(requetePermise(kZdoMgmtNwkUpdate, 0x1A2B) == (SONDE_ECHECS != 0), "Mgmt_NWK_Update_req selon SONDE_ECHECS");
  CHECK(!requetePermise(kZdoMgmtNwkUpdate, 0xFFFD), "balayage vers une diffusion");
  CHECK(!requetePermise(0x0034, 0x1A2B), "Mgmt_Leave_req interdite");
  CHECK(!requetePermise(0x0036, 0x1A2B), "Mgmt_Permit_Joining_req interdite");
  CHECK(!requetePermise(0x0021, 0x1A2B), "Bind_req interdite");
  CHECK(!requetePermise(0x0006, 0x1A2B), "Match_Desc_req interdite");
  CHECK(!requetePermise(0x8031, 0x1A2B), "une reponse n'est pas une requete");
  CHECK(balayagePermis(1u << 25, 0, 25) == (SONDE_ECHECS != 0), "canal courant, duree 0");
  CHECK(!balayagePermis(1u << 25, 1, 25), "duree 1");
  CHECK(!balayagePermis(1u << 25, 0xFE, 25), "changement de canal");
  CHECK(!balayagePermis(1u << 25, 0xFF, 25), "changement de gestionnaire");
  CHECK(!balayagePermis((1u << 25) | (1u << 11), 0, 25), "deux canaux");
  CHECK(!balayagePermis(1u << 24, 0, 25), "un autre canal");
  CHECK(!balayagePermis(0x07FFF800u, 0, 25), "tous les canaux");
  CHECK(!balayagePermis(1u << 10, 0, 10), "canal 10 hors bande");

  return bilan("cadence");
}
