// Tests hote de sonde/src/ligne.{h,cpp} : lignes machine et listes decoupees.
// Lancer : sh sonde/test/lancer.sh
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

#include "ligne.h"
#include "verif.h"

static std::vector<std::string> gLignes;
static void sortie(void *, const uint8_t *o, size_t n) { gLignes.emplace_back((const char *)o, n); }

static std::string texte(Ligne &l) {
  size_t n = 0;
  const uint8_t *o = l.fin(&n);
  return std::string((const char *)o, n);
}

// Nombre d'occurrences de motif dans s.
static size_t compte(const std::string &s, const std::string &motif) {
  size_t n = 0;
  for (size_t i = s.find(motif); i != std::string::npos; i = s.find(motif, i + 1)) n++;
  return n;
}

int main() {
  Ligne l;
  l.debut("bonjour");
  l.ajoute(",\"produit\":\"%s\"", "sonde-zigbee");
  CHECK(texte(l) == "\x1E{\"v\":1,\"t\":\"bonjour\",\"produit\":\"sonde-zigbee\"}\n", "ligne simple");

  // Exactement 4095 octets emis : RS + en-tete + remplissage + } + LF.
  l.debut("x");
  const size_t entete = 1 + strlen("{\"v\":1,\"t\":\"x\"");
  std::string plein(Ligne::kMax - 2 - entete, 'a');
  CHECK(l.tient(plein.size()) && !l.tient(plein.size() + 1), "tient a la limite");
  l.ajoute("%s", plein.c_str());
  CHECK(!l.tropLong(), "a la limite");
  std::string t = texte(l);
  CHECK(t.size() == Ligne::kMax && t.back() == '\n' && t[t.size() - 2] == '}', "4095 octets");

  // Un octet de plus : trop longue, remplacee par l'erreur.
  l.debut("x");
  l.ajoute("%s", plein.c_str());
  l.ajoute("b");
  CHECK(l.tropLong(), "debordement vu");
  l.ajoute("c");  // ignore
  CHECK(texte(l) == "\x1E{\"v\":1,\"t\":\"erreur\",\"erreur\":\"ligne trop longue\"}\n", "erreur de debordement");

  // Liste vide.
  ListeDecoupee liste(l, sortie, nullptr);
  gLignes.clear();
  liste.commencer("voisins", "");
  liste.terminer();
  CHECK(gLignes.size() == 1 && gLignes[0] == "\x1E{\"v\":1,\"t\":\"voisins\",\"liste\":[],\"suite\":false}\n",
        "liste vide");

  // Trois objets : une ligne.
  gLignes.clear();
  liste.commencer("table", ",\"id\":7,\"ok\":true");
  liste.ajouter("{\"a\":1}");
  liste.ajouter("{\"a\":2}");
  liste.ajouter("{\"a\":3}");
  liste.terminer();
  CHECK(gLignes.size() == 1 &&
            gLignes[0] == "\x1E{\"v\":1,\"t\":\"table\",\"id\":7,\"ok\":true,\"liste\":[{\"a\":1},{\"a\":2},{\"a\":3}],"
                          "\"suite\":false}\n",
        "trois objets");

  // 100 objets de 150 octets : plusieurs lignes, chacune complete et dans la
  // limite, l'en-tete repris, "suite":true sauf sur la derniere, l'ordre garde.
  gLignes.clear();
  liste.commencer("table", ",\"id\":42,\"cible\":\"1A2B\"");
  for (int i = 0; i < 100; i++) {
    char objet[160];
    snprintf(objet, sizeof(objet), "{\"n\":%03d,\"r\":\"%s\"}", i, std::string(150 - 16, 'r').c_str());
    CHECK(strlen(objet) == 150, "objet de 150 octets");
    liste.ajouter(objet);
  }
  liste.terminer();
  CHECK(gLignes.size() == 4, "4 lignes (%zu)", gLignes.size());
  size_t objets = 0;
  int attendu = 0;
  bool ordre = true;
  for (size_t i = 0; i < gLignes.size(); i++) {
    const std::string &g = gLignes[i];
    const bool derniere = i + 1 == gLignes.size();
    CHECK(g.size() <= Ligne::kMax, "ligne %zu dans la limite (%zu)", i, g.size());
    CHECK(g.rfind("\x1E{\"v\":1,\"t\":\"table\",\"id\":42,\"cible\":\"1A2B\",\"liste\":[", 0) == 0, "en-tete %zu", i);
    const std::string queue = derniere ? "],\"suite\":false}\n" : "],\"suite\":true}\n";
    CHECK(g.size() > queue.size() && g.compare(g.size() - queue.size(), queue.size(), queue) == 0, "queue %zu", i);
    objets += compte(g, "{\"n\":");
    for (size_t p = g.find("{\"n\":"); p != std::string::npos; p = g.find("{\"n\":", p + 1)) {
      ordre = ordre && atoi(g.c_str() + p + 5) == attendu;
      attendu++;
    }
  }
  CHECK(objets == 100 && ordre, "100 objets dans l'ordre");

  return bilan("ligne");
}
