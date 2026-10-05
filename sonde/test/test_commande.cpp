// Tests hote de sonde/src/commande.{h,cpp} : lecture des commandes de l'USB.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "commande.h"
#include "verif.h"

static bool est(const char *ligne, TypeCommande t) { return lireCommande(ligne).type == t; }

int main() {
  // Noms
  CHECK(nomValide("SONDE-Z1"), "defaut");
  CHECK(nomValide("a"), "un caractere");
  CHECK(nomValide("Abc_def.1-2"), "permis");
  CHECK(nomValide("12345678901234567890123456789012"), "32 caracteres");
  CHECK(!nomValide("123456789012345678901234567890123"), "33 caracteres");
  CHECK(!nomValide(""), "vide");
  CHECK(!nomValide("a b"), "espace");
  CHECK(!nomValide("a\"b"), "guillemet");
  CHECK(!nomValide("caf\xc3\xa9"), "accent");

  // Entiers
  uint32_t v = 7;
  CHECK(lireEntier("0", &v) && v == 0, "0");
  CHECK(lireEntier("4294967295", &v) && v == 4294967295u, "max");
  v = 7;
  CHECK(!lireEntier("4294967296", &v) && v == 7, "trop grand, v intact");
  CHECK(!lireEntier("", &v) && v == 7, "vide");
  CHECK(!lireEntier("-1", &v) && v == 7, "signe");
  CHECK(!lireEntier("+1", &v) && v == 7, "plus");
  CHECK(!lireEntier("12a", &v) && v == 7, "lettre");
  CHECK(!lireEntier("00000000001", &v) && v == 7, "11 chiffres");

  // Adresses courtes
  uint16_t c = 9;
  CHECK(lireCourt("1A2B", &c) && c == 0x1A2B, "majuscules");
  CHECK(lireCourt("ffff", &c) && c == 0xFFFF, "minuscules");
  CHECK(lireCourt("0000", &c) && c == 0, "pont");
  c = 9;
  CHECK(!lireCourt("1A2", &c) && c == 9, "3 hexa");
  CHECK(!lireCourt("1A2B3", &c) && c == 9, "5 hexa");
  CHECK(!lireCourt("0x1A", &c) && c == 9, "prefixe");
  CHECK(!lireCourt("1G2B", &c) && c == 9, "G");

  // Commandes sans argument
  CHECK(est("bonjour", TypeCommande::kBonjour), "bonjour");
  CHECK(est("  etat  ", TypeCommande::kEtat), "espaces autour");
  CHECK(est("voisins", TypeCommande::kVoisins), "voisins");
  CHECK(est("suspendre", TypeCommande::kSuspendre), "suspendre");
  CHECK(est("reprendre", TypeCommande::kReprendre), "reprendre");
  CHECK(est("oubli", TypeCommande::kOubli), "oubli");
  CHECK(est("etat 1", TypeCommande::kSyntaxe), "argument en trop");
  CHECK(est("Etat", TypeCommande::kInconnue), "casse");
  CHECK(est("diag 0400 0,1 5", TypeCommande::kInconnue), "commande de la sonde Thread");
  CHECK(est("", TypeCommande::kInconnue), "vide");
  CHECK(est("   ", TypeCommande::kInconnue), "blanc");

  // nom
  Commande n = lireCommande("nom SONDE-Z2");
  CHECK(n.type == TypeCommande::kNom && strcmp(n.nom, "SONDE-Z2") == 0, "nom");
  CHECK(est("nom", TypeCommande::kSyntaxe), "nom sans texte");
  CHECK(est("nom a b", TypeCommande::kSyntaxe), "nom avec espace");
  CHECK(est("nom 123456789012345678901234567890123", TypeCommande::kSyntaxe), "nom trop long");

  // table
  Commande t = lireCommande("table 1a2b 7");
  CHECK(t.type == TypeCommande::kTable && t.cible == 0x1A2B && t.id == 7 && t.delaiMs == kDelaiDefautMs, "table");
  t = lireCommande("table FFF7 4294967295 5000");
  CHECK(t.type == TypeCommande::kTable && t.cible == 0xFFF7 && t.id == 4294967295u && t.delaiMs == 5000,
        "bornes hautes");
  t = lireCommande("table   0000   1   500  ");
  CHECK(t.type == TypeCommande::kTable && t.delaiMs == 500, "espaces en trop, delai minimal");
  CHECK(est("table 0000 1 499", TypeCommande::kSyntaxe), "delai trop court");
  CHECK(est("table 0000 1 5001", TypeCommande::kSyntaxe), "delai au-dela de la borne de la pile");
  CHECK(est("table FFF8 1", TypeCommande::kSyntaxe), "diffusion FFF8");
  CHECK(est("table FFFC 1", TypeCommande::kSyntaxe), "diffusion aux routeurs");
  CHECK(est("table FFFD 1", TypeCommande::kSyntaxe), "diffusion aux recepteurs allumes");
  CHECK(est("table ffff 1", TypeCommande::kSyntaxe), "diffusion a tous");
  CHECK(est("table 0000", TypeCommande::kSyntaxe), "sans id");
  CHECK(est("table", TypeCommande::kSyntaxe), "sans cible");
  CHECK(est("table 000 1", TypeCommande::kSyntaxe), "cible courte");
  CHECK(est("table 0000 x", TypeCommande::kSyntaxe), "id non decimal");
  CHECK(est("table 0000 1 5000 9", TypeCommande::kSyntaxe), "argument en trop");
  CHECK(est("table 0000 1 5000 9 9", TypeCommande::kSyntaxe), "deux arguments en trop");

  // routes et echecs : actives par defaut ; coupes (SONDE_ROUTES=0,
  // SONDE_ECHECS=0), ils n'existent pas et repondent « inconnue ».
#if SONDE_ROUTES
  Commande r = lireCommande("routes 3C4D 8 1000");
  CHECK(r.type == TypeCommande::kRoutes && r.cible == 0x3C4D && r.id == 8 && r.delaiMs == 1000, "routes");
  CHECK(est("routes FFFF 8", TypeCommande::kSyntaxe), "routes vers une diffusion");
#else
  CHECK(est("routes 3C4D 8 1000", TypeCommande::kInconnue), "routes coupee");
#endif
#if SONDE_ECHECS
  Commande e = lireCommande("echecs 3C4D 9");
  CHECK(e.type == TypeCommande::kEchecs && e.cible == 0x3C4D && e.id == 9, "echecs");
  CHECK(est("echecs 3C4D", TypeCommande::kSyntaxe), "echecs sans id");
  CHECK(est("echecs FFFD 9", TypeCommande::kSyntaxe), "echecs vers une diffusion");
#else
  CHECK(est("echecs 3C4D 9", TypeCommande::kInconnue), "echecs coupee");
#endif

  // Ligne trop longue
  char longue[300];
  memset(longue, 'a', sizeof(longue) - 1);
  longue[sizeof(longue) - 1] = 0;
  CHECK(est(longue, TypeCommande::kSyntaxe), "ligne de 299 caracteres");

  return bilan("commande");
}
