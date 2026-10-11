// Tests hote de sonde/src/canaux.{h,cpp} : liste blanche du reseau, requetes
// « <rid> <commande> » et reponses « <rid> <ligne> » (spec sonde Wi-Fi, 3.3).
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "canaux.h"
#include "commande.h"
#include "verif.h"

static bool lire(const char *s, uint32_t *rid, char *cmd) {
  return lireRequete((const uint8_t *)s, strlen(s), rid, cmd);
}

int main() {
  // listeBlanche
  CHECK(distanceAutorisee(TypeCommande::kBonjour), "bonjour");
  CHECK(distanceAutorisee(TypeCommande::kEtat), "etat");
  CHECK(distanceAutorisee(TypeCommande::kVoisins), "voisins");
  CHECK(distanceAutorisee(TypeCommande::kTable), "table");
  CHECK(distanceAutorisee(TypeCommande::kRoutes), "routes");
  CHECK(distanceAutorisee(TypeCommande::kSuspendre), "suspendre");
  CHECK(distanceAutorisee(TypeCommande::kReprendre), "reprendre");
  CHECK(!distanceAutorisee(TypeCommande::kNom), "nom");
  CHECK(!distanceAutorisee(TypeCommande::kOubli), "oubli");
  CHECK(!distanceAutorisee(TypeCommande::kEchecs), "echecs");
  CHECK(!distanceAutorisee(TypeCommande::kWifi), "wifi");
  CHECK(!distanceAutorisee(TypeCommande::kWifiLire), "wifi lire");
  CHECK(!distanceAutorisee(TypeCommande::kWifiEfface), "wifi efface");
  CHECK(!distanceAutorisee(TypeCommande::kCleNouvelle), "cle nouvelle");
  CHECK(!distanceAutorisee(TypeCommande::kCleLire), "cle");
  CHECK(!distanceAutorisee(TypeCommande::kCleEfface), "cle efface");
  CHECK(!distanceAutorisee(TypeCommande::kInconnue), "inconnue");
  CHECK(!distanceAutorisee(TypeCommande::kSyntaxe), "syntaxe");
  CHECK(lireCommande("  oubli  ").type == TypeCommande::kOubli && !distanceAutorisee(lireCommande("  oubli  ").type),
        "oubli entoure d'espaces : toujours refuse");

  // Requetes
  uint32_t rid = 0;
  char cmd[kCommandeMax + 1];
  CHECK(lire("7 etat", &rid, cmd) && rid == 7 && strcmp(cmd, "etat") == 0, "simple");
  CHECK(lire("4294967295 table 1A2B 3", &rid, cmd) && rid == 4294967295u && strcmp(cmd, "table 1A2B 3") == 0, "max");
  rid = 9;
  CHECK(!lire("0 etat", &rid, cmd) && rid == 9, "rid 0 (reserve aux signaux)");
  CHECK(!lire("07 etat", &rid, cmd), "zero de tete");
  CHECK(!lire("4294967296 etat", &rid, cmd), "rid trop grand");
  CHECK(!lire("7", &rid, cmd), "sans commande");
  CHECK(!lire("7 ", &rid, cmd), "commande vide");
  CHECK(!lire("etat", &rid, cmd), "sans rid");
  CHECK(!lire("7 et\x01t", &rid, cmd), "caractere de controle");
  CHECK(!lire("7 caf\xc3\xa9", &rid, cmd), "non ASCII");
  char longue[300];
  memset(longue, 'a', sizeof(longue));
  memcpy(longue, "7 ", 2);
  longue[2 + 255] = 0;
  CHECK(lire(longue, &rid, cmd) && strlen(cmd) == 255, "255 caracteres");
  longue[2 + 255] = 'a';
  longue[2 + 256] = 0;
  CHECK(!lire(longue, &rid, cmd), "256 caracteres");

  // Reponses
  uint8_t s[64];
  const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
  size_t n = chargeReponse(12, (const uint8_t *)l, strlen(l), s, sizeof(s));
  CHECK(n == strlen("12 {\"v\":1,\"t\":\"etat\"}") && memcmp(s, "12 {\"v\":1,\"t\":\"etat\"}", n) == 0, "rid 12");
  n = chargeReponse(0, (const uint8_t *)l, strlen(l), s, sizeof(s));
  CHECK(n == strlen("0 {\"v\":1,\"t\":\"etat\"}") && memcmp(s, "0 ", 2) == 0, "rid 0 : signal");
  CHECK(chargeReponse(12, (const uint8_t *)l, strlen(l), s, 10) == 0, "trop petit");
  const char *sansRs = "{\"v\":1}\n";
  n = chargeReponse(1, (const uint8_t *)sansRs, strlen(sansRs), s, sizeof(s));
  CHECK(n == strlen("1 {\"v\":1}") && memcmp(s, "1 {\"v\":1}", n) == 0, "sans RS");
  return bilan("test_canaux");
}
