// Tests hote de sonde/src/entrees.{h,cpp} : textes des champs, objets JSON des
// tables, lecture d'une Mgmt_Rtg_rsp brute. Valeurs inventees.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include <string>

#include "entrees.h"
#include "verif.h"

int main() {
  // Adresse longue : ordre du reseau (poids faible d'abord) -> poids fort d'abord.
  const uint8_t ieee[8] = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA0};
  char t[17];
  texteIeee(ieee, t);
  CHECK(strcmp(t, "A000000000000001") == 0, "ieee (%s)", t);

  CHECK(strcmp(texteType(0), "coordinateur") == 0 && strcmp(texteType(1), "routeur") == 0 &&
            strcmp(texteType(2), "final") == 0 && strcmp(texteType(3), "inconnu") == 0 &&
            strcmp(texteType(9), "inconnu") == 0,
        "types");
  CHECK(strcmp(texteRelation(0), "parent") == 0 && strcmp(texteRelation(1), "enfant") == 0 &&
            strcmp(texteRelation(2), "frere") == 0 && strcmp(texteRelation(3), "aucune") == 0 &&
            strcmp(texteRelation(4), "ancien_enfant") == 0 && strcmp(texteRelation(5), "enfant") == 0 &&
            strcmp(texteRelation(7), "aucune") == 0,
        "relations");
  CHECK(strcmp(texteEtatRoute(0), "active") == 0 && strcmp(texteEtatRoute(1), "decouverte") == 0 &&
            strcmp(texteEtatRoute(2), "echec_decouverte") == 0 && strcmp(texteEtatRoute(3), "inactive") == 0 &&
            strcmp(texteEtatRoute(4), "validation") == 0 && strcmp(texteEtatRoute(6), "inconnu") == 0,
        "etats de route");

  // Entree de Mgmt_Lqi_rsp : l'exemple de la spec (section 2).
  EntreeVoisin e;
  const uint8_t pont[8] = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xA0};
  memcpy(e.ieee, pont, 8);
  e.court = 0x0000;
  e.type = 0;
  e.ecoute = 1;
  e.relation = 3;
  e.admission = 0;
  e.profondeur = 0;
  e.lqi = 212;
  char o[256];
  size_t n = jsonEntreeVoisin(e, o, sizeof(o));
  const std::string attendu =
      "{\"court\":\"0000\",\"ieee\":\"A000000000000003\",\"type\":\"coordinateur\",\"relation\":\"aucune\","
      "\"ecoute\":true,\"profondeur\":0,\"admission\":false,\"lqi\":212}";
  CHECK(n == attendu.size() && attendu == o, "entree de table (%s)", o);
  e.ecoute = 2;
  e.admission = 7;
  jsonEntreeVoisin(e, o, sizeof(o));
  CHECK(strstr(o, "\"ecoute\":null") && strstr(o, "\"admission\":null"), "inconnus en null");
  CHECK(jsonEntreeVoisin(e, o, 20) == 0, "sortie trop petite");

  // Voisin de la sonde : l'exemple de la spec.
  VoisinSonde v;
  memcpy(v.ieee, ieee, 8);
  v.ieee[0] = 0x02;
  v.court = 0x1A2B;
  v.type = 1;
  v.relation = 0;
  v.lqi = 180;
  v.rssi = -71;
  v.coutSortant = 1;
  v.age = 0;
  n = jsonVoisinSonde(v, o, sizeof(o));
  const std::string attenduV =
      "{\"court\":\"1A2B\",\"ieee\":\"A000000000000002\",\"type\":\"routeur\",\"relation\":\"parent\",\"lqi\":180,"
      "\"rssi\":-71,\"cout_sortant\":1,\"age\":0}";
  CHECK(n == attenduV.size() && attenduV == o, "voisin de la sonde (%s)", o);

  // Mgmt_Rtg_req.
  uint8_t req[2];
  requeteRoutes(0x81, 6, req);
  CHECK(req[0] == 0x81 && req[1] == 6, "requete de routes");

  // Mgmt_Rtg_rsp : 2 entrees sur un total de 5, depuis l'index 3.
  const uint8_t rsp[] = {0x81, 0x00, 5, 3, 2,
                         0x2B, 0x1A, 0x00, 0x4D, 0x3C,   // 1A2B active, par 3C4D
                         0x6F, 0x5E, 0x3A, 0x00, 0x00};  // 5E6F : etat 2, memoire, plusieurs vers un, enregistrement
  PageRoutes p;
  CHECK(lirePageRoutes(rsp, sizeof(rsp), &p), "page lue");
  CHECK(p.tsn == 0x81 && p.statut == 0 && p.total == 5 && p.debut == 3 && p.nombre == 2, "en-tete de page");
  CHECK(p.entrees[0].destination == 0x1A2B && p.entrees[0].etat == 0 && p.entrees[0].prochain == 0x3C4D &&
            !p.entrees[0].memoireLimitee && !p.entrees[0].plusieursVersUn && !p.entrees[0].enregistrement,
        "premiere route");
  CHECK(p.entrees[1].destination == 0x5E6F && p.entrees[1].etat == 2 && p.entrees[1].memoireLimitee &&
            p.entrees[1].plusieursVersUn && p.entrees[1].enregistrement && p.entrees[1].prochain == 0,
        "seconde route");
  n = jsonEntreeRoute(p.entrees[0], o, sizeof(o));
  const std::string attenduR =
      "{\"destination\":\"1A2B\",\"etat\":\"active\",\"prochain\":\"3C4D\",\"memoire_limitee\":false,"
      "\"plusieurs_vers_un\":false,\"enregistrement\":false}";
  CHECK(n == attenduR.size() && attenduR == o, "route en JSON (%s)", o);

  // Statut d'echec : deux octets suffisent.
  const uint8_t refus[] = {0x82, 0x84};
  CHECK(lirePageRoutes(refus, sizeof(refus), &p) && p.statut == 0x84 && p.nombre == 0, "refus 0x84");
  // Trames abimees.
  CHECK(!lirePageRoutes(rsp, 1, &p), "un octet");
  CHECK(!lirePageRoutes(rsp, 4, &p), "en-tete coupe");
  CHECK(!lirePageRoutes(rsp, sizeof(rsp) - 1, &p), "entree coupee");
  // Plus de 16 entrees annoncees et portees : les 16 premieres gardees.
  uint8_t grande[5 + 5 * 20] = {0x83, 0x00, 40, 0, 20};
  for (int i = 0; i < 20; i++) grande[5 + 5 * i] = (uint8_t)i;
  CHECK(lirePageRoutes(grande, sizeof(grande), &p) && p.nombre == kRoutesParPageMax &&
            p.entrees[15].destination == 15,
        "16 entrees gardees");

  return bilan("entrees");
}
