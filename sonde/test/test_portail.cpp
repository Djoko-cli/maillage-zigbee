// Tests hote de sonde/src/portail.{h,cpp} : H1 par lignes TCP (spec sonde Wi-Fi,
// 3.3). Le client des tests est ecrit avec les briques de h1_proto.h.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include <string>
#include <vector>

#include "h1_proto.h"
#include "portail.h"
#include "verif.h"

namespace {

uint8_t gCle[32];
uint8_t gAutre[32];
uint8_t gCompteur = 0x50;

void aleatoire(void *p, size_t n) {
  uint8_t *o = (uint8_t *)p;
  for (size_t i = 0; i < n; i++) o[i] = gCompteur++;
}

struct Fausse : Portail::Sortie {
  std::vector<std::string> lignes[Portail::kConnexions];
  bool fermee[Portail::kConnexions] = {};
  void envoyer(uint8_t c, const uint8_t *o, size_t n) override { lignes[c].emplace_back((const char *)o, n); }
  void fermer(uint8_t c) override { fermee[c] = true; }
};

// Un client H1 : poignee de main, messages scelles, reponses ouvertes.
struct Client {
  const uint8_t *cle;
  std::string sid = "";
  uint8_t ks[32] = {};
  uint32_t ctr = 0;

  std::string salut(const char *na) {
    char kid[9];
    h1::keyId(cle, kid);
    uint8_t mac[16];
    h1::salutMac(cle, kid, na, mac);
    char m[33];
    h1::toHex(mac, 16, m);
    return std::string("H1 SALUT ") + kid + " " + na + " " + m + "\n";
  }
  bool defi(const std::string &ligne, const char *na) {
    const h1::Parsed p = h1::parse((const uint8_t *)ligne.data(), ligne.size() - 1);
    if (p.kind != h1::Kind::Defi) return false;
    char kid[9];
    h1::keyId(cle, kid);
    uint8_t mac[16];
    if (!h1::defiMac(cle, kid, na, p.nc, p.sidHex, mac) || memcmp(mac, p.mac, 16) != 0) return false;
    sid = p.sidHex;
    return h1::sessionKey(cle, na, p.nc, p.sidHex, ks);
  }
  std::string message(const std::string &charge) {
    ctr++;
    uint8_t mac[16];
    h1::messageMac(ks, 'A', sid.c_str(), ctr, (const uint8_t *)charge.data(), charge.size(), mac);
    char m[33];
    h1::toHex(mac, 16, m);
    return "H1 " + sid + " " + std::to_string(ctr) + " " + m + " " + charge + "\n";
  }
  // Charge d'une ligne de la carte, MAC verifie ; "" sinon.
  std::string ouvrir(const std::string &ligne) {
    const h1::Parsed p = h1::parse((const uint8_t *)ligne.data(), ligne.size() - 1);
    if (p.kind != h1::Kind::Data || sid != p.sidHex) return "";
    uint8_t mac[16];
    h1::messageMac(ks, 'C', p.sidHex, p.ctr, p.payload, p.payloadLen, mac);
    if (memcmp(mac, p.mac, 16) != 0) return "";
    return std::string((const char *)p.payload, p.payloadLen);
  }
};

const char *kNa1 = "A0A1A2A3A4A5A6A7A8A9AAABACADAEAF";
const char *kNa2 = "B0B1B2B3B4B5B6B7B8B9BABBBCBDBEBF";
const char *kNa3 = "C0C1C2C3C4C5C6C7C8C9CACBCCCDCECF";

void recevoir(Portail &p, uint8_t c, const std::string &s, uint32_t now, Fausse &f) {
  p.recevoir(c, (const uint8_t *)s.data(), s.size(), now, aleatoire, f);
}

// Poignee de main complete sur la connexion c ; true si la session est etablie.
bool etablir(Portail &p, Fausse &f, Client &cl, uint8_t c, const char *na, uint32_t now) {
  p.ouverte(c, now);
  const size_t avant = f.lignes[c].size();
  recevoir(p, c, cl.salut(na), now, f);
  if (f.lignes[c].size() != avant + 1 || !cl.defi(f.lignes[c].back(), na)) return false;
  recevoir(p, c, cl.message("1 bonjour"), now + 1, f);
  Portail::Requete r;
  return p.requete(&r) && r.rid == 1 && strcmp(r.commande, "bonjour") == 0;
}

}  // namespace

int main() {
  for (int i = 0; i < 32; i++) {
    gCle[i] = (uint8_t)i;
    gAutre[i] = (uint8_t)(0x80 + i);
  }

  {  // poigneeDeMain, requete, reponse
    Portail p;
    Fausse f;
    CHECK(p.cle(gCle), "cle");
    Client cl{gCle};
    CHECK(etablir(p, f, cl, 0, kNa1, 1000), "session etablie");
    CHECK(p.sessions() == 1, "une session");
    Portail::Requete r;
    recevoir(p, 0, cl.message("2 table 1A2B 5"), 1004, f);
    CHECK(p.requete(&r) && r.rid == 2 && strcmp(r.commande, "table 1A2B 5") == 0, "requete table");
    CHECK(!p.requete(&r), "file vide");
    const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
    CHECK(p.repondre(r.session, 2, (const uint8_t *)l, strlen(l), f), "reponse partie");
    CHECK(cl.ouvrir(f.lignes[0].back()) == "2 {\"v\":1,\"t\":\"etat\"}", "reponse scellee");
    CHECK(p.envois() == 1, "un envoi");
  }

  {  // morceaux : une ligne arrive en plusieurs fois, CR ignore
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client cl{gCle};
    p.ouverte(1, 0);
    const std::string s = cl.salut(kNa1);
    recevoir(p, 1, s.substr(0, 10), 10, f);
    CHECK(f.lignes[1].empty(), "rien avant LF");
    recevoir(p, 1, s.substr(10, s.size() - 11) + "\r\n", 11, f);
    CHECK(f.lignes[1].size() == 1 && cl.defi(f.lignes[1].back(), kNa1), "DEFI apres LF");
  }

  {  // mauvaiseCle : silence
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client intrus{gAutre};
    p.ouverte(0, 0);
    recevoir(p, 0, intrus.salut(kNa1), 10, f);
    CHECK(f.lignes[0].empty(), "aucune reponse a une autre cle");
    CHECK(p.refus() == 1, "refus compte");
  }

  {  // sansCle : silence
    Portail p;
    Fausse f;
    Client cl{gCle};
    p.ouverte(0, 0);
    recevoir(p, 0, cl.salut(kNa1), 10, f);
    CHECK(f.lignes[0].empty(), "aucune reponse sans cle");
  }

  {  // ligneTropLongue : connexion fermee
    Portail p;
    Fausse f;
    p.cle(gCle);
    p.ouverte(2, 0);
    recevoir(p, 2, std::string(Portail::kLigneMax + 1, 'x'), 10, f);
    CHECK(f.fermee[2], "fermee");
    CHECK(p.fermetures() == 1, "fermeture comptee");
  }

  {  // ligne de exactement kLigneMax octets : pas fermee (refusee sans reponse)
    Portail p;
    Fausse f;
    p.cle(gCle);
    p.ouverte(2, 0);
    recevoir(p, 2, std::string(Portail::kLigneMax, 'x') + "\n", 10, f);
    CHECK(!f.fermee[2], "ligne a la limite non fermee");
    CHECK(p.fermetures() == 0, "pas de fermeture a la limite");
    CHECK(f.lignes[2].empty(), "ligne a la limite sans reponse");
  }

  {  // requeteInvalide : rid absent, refusee sans reponse
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client cl{gCle};
    CHECK(etablir(p, f, cl, 0, kNa1, 1000), "session");
    const size_t avant = f.lignes[0].size();
    recevoir(p, 0, cl.message("etat"), 1004, f);
    Portail::Requete r;
    CHECK(!p.requete(&r), "pas de requete");
    CHECK(f.lignes[0].size() == avant, "pas de reponse");
  }

  {  // deuxSessionsSeparees : chacun ses reponses, les deux recoivent les signaux
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle}, b{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    CHECK(etablir(p, f, b, 1, kNa2, 1100), "b");
    CHECK(p.sessions() == 2, "deux sessions");
    recevoir(p, 1, b.message("2 etat"), 1200, f);
    Portail::Requete r;
    CHECK(p.requete(&r) && r.rid == 2, "requete de b");
    const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
    const size_t na = f.lignes[0].size();
    p.repondre(r.session, r.rid, (const uint8_t *)l, strlen(l), f);
    CHECK(f.lignes[0].size() == na, "a ne recoit pas la reponse de b");
    CHECK(b.ouvrir(f.lignes[1].back()) == "2 {\"v\":1,\"t\":\"etat\"}", "b la recoit");
    const char *s = "\x1e{\"v\":1,\"t\":\"signal\"}\n";
    p.diffuser((const uint8_t *)s, strlen(s), f);
    CHECK(a.ouvrir(f.lignes[0].back()) == "0 {\"v\":1,\"t\":\"signal\"}", "signal a a");
    CHECK(b.ouvrir(f.lignes[1].back()) == "0 {\"v\":1,\"t\":\"signal\"}", "signal a b");
  }

  {  // fermeture : la session tombe avec sa connexion
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.fermee(0);
    CHECK(p.sessions() == 0, "plus de session");
    const char *l = "\x1e{}\n";
    CHECK(!p.repondre(0, 3, (const uint8_t *)l, strlen(l), f), "reponse impossible");
  }

  {  // changerDeCle : tout tombe
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.cle(gAutre);
    CHECK(p.sessions() == 0, "sessions tombees");
    CHECK(p.aCle(), "nouvelle cle");
    p.cle(nullptr);
    CHECK(!p.aCle(), "cle effacee");
  }

  {  // requeteFermee : une requete en file ne survit pas a sa connexion
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    recevoir(p, 0, a.message("2 etat"), 1004, f);
    p.fermee(0);
    Portail::Requete r;
    CHECK(!p.requete(&r), "requete de la connexion fermee purgee");
  }

  {  // mauvaiseConnexion : une session ne parle que sur la connexion ou elle a ete promue
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.ouverte(1, 0);
    const size_t n0 = f.lignes[0].size(), n1 = f.lignes[1].size();
    const uint32_t avant = p.refus();
    recevoir(p, 1, a.message("2 etat"), 1004, f);
    Portail::Requete r;
    CHECK(!p.requete(&r), "pas de requete de la mauvaise connexion");
    CHECK(f.lignes[0].size() == n0 && f.lignes[1].size() == n1, "aucune sortie");
    CHECK(p.refus() == avant + 1, "refus compte");
    recevoir(p, 0, a.message("3 etat"), 1008, f);
    CHECK(p.requete(&r) && r.rid == 3, "la session reste servie sur sa connexion");
  }

  {  // fermeePuisAutreConnexion : la session tombe avec sa connexion
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.fermee(0);
    p.ouverte(1, 0);
    const size_t n1 = f.lignes[1].size();
    const uint32_t avant = p.refus();
    recevoir(p, 1, a.message("2 etat"), 1004, f);
    Portail::Requete r;
    CHECK(!p.requete(&r), "pas de requete apres fermeture");
    CHECK(f.lignes[1].size() == n1, "aucune sortie");
    CHECK(p.refus() == avant + 1, "refus compte");
  }

  {  // placeReprise : la requete d'une session terminee ne part pas avec la place reprise
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle}, b{gCle}, d{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    CHECK(etablir(p, f, b, 1, kNa2, 1100), "b");
    recevoir(p, 0, a.message("2 etat"), 1200, f);
    p.fermee(0);
    p.ouverte(2, 0);
    const size_t avantD = f.lignes[2].size();
    recevoir(p, 2, d.salut(kNa3), 2300, f);  // hors de la fenetre des DEFI de a et b
    CHECK(f.lignes[2].size() == avantD + 1 && d.defi(f.lignes[2].back(), kNa3), "d etablit");
    recevoir(p, 2, d.message("1 bonjour"), 2301, f);
    Portail::Requete r;
    CHECK(p.requete(&r) && r.rid == 1 && r.session == 0 && strcmp(r.commande, "bonjour") == 0,
          "seule la requete de d");
    CHECK(!p.requete(&r), "rien d'autre en file");
  }

  {  // evincee : la requete d'une session evincee ne part pas avec la place prise
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle}, b{gCle}, d{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    CHECK(etablir(p, f, b, 1, kNa2, 1100), "b");
    recevoir(p, 0, a.message("2 etat"), 1004, f);
    p.ouverte(2, 0);
    const size_t avantD = f.lignes[2].size();
    recevoir(p, 2, d.salut(kNa3), 31010, f);
    CHECK(f.lignes[2].size() == avantD + 1 && d.defi(f.lignes[2].back(), kNa3), "d etablit");
    recevoir(p, 2, d.message("1 bonjour"), 31011, f);
    Portail::Requete r;
    CHECK(p.requete(&r) && r.rid == 1 && r.session == 0 && strcmp(r.commande, "bonjour") == 0,
          "requete de d seulement");
    CHECK(!p.requete(&r), "rien d'autre en file");
  }

  {  // oubliee : une session expiree ne laisse pas de requete en file
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    recevoir(p, 0, a.message("2 etat"), 1004, f);
    p.expirer(1004 + h1::kForgetMs, f);
    CHECK(p.sessions() == 0, "session oubliee");
    Portail::Requete r;
    CHECK(!p.requete(&r), "requete de la session oubliee purgee");
  }

  {  // oublieeFermee : la connexion d'une session oubliee est fermee (l'app voit la fin et se reconnecte)
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    const uint32_t avant = p.fermetures();
    p.expirer(1001 + h1::kForgetMs, f);
    CHECK(f.fermee[0], "connexion de la session oubliee fermee");
    CHECK(p.fermetures() == avant + 1, "fermeture comptee");
    recevoir(p, 0, a.message("2 etat"), 1005 + h1::kForgetMs, f);
    Portail::Requete r;
    CHECK(!p.requete(&r), "plus rien n'est lu sur la connexion fermee");
  }

  {  // repriseFermee : la connexion de la session evincee est fermee ; celle du nouveau client reste
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle}, b{gCle}, d{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    CHECK(etablir(p, f, b, 1, kNa2, 1100), "b");
    p.ouverte(2, 31000);
    recevoir(p, 2, d.salut(kNa3), 31010, f);
    CHECK(d.defi(f.lignes[2].back(), kNa3), "d recoit son DEFI");
    recevoir(p, 2, d.message("1 bonjour"), 31011, f);
    CHECK(f.fermee[0], "la connexion de a, evincee, est fermee");
    CHECK(!f.fermee[1] && !f.fermee[2], "b et d gardent la leur");
    CHECK(p.sessions() == 2, "deux sessions : b et d");
    const char *l = "\x1e{\"v\":1,\"t\":\"etat\"}\n";
    Portail::Requete r;
    CHECK(p.requete(&r) && r.session == 0, "la requete de d");
    CHECK(p.repondre(r.session, r.rid, (const uint8_t *)l, strlen(l), f), "d recoit sa reponse");
    CHECK(d.ouvrir(f.lignes[2].back()) == "1 {\"v\":1,\"t\":\"etat\"}", "reponse scellee pour d");
  }

  {  // sansPoigneeDeMain : une connexion sans session est fermee apres kSansSessionMs
    Portail p;
    Fausse f;
    p.cle(gCle);
    p.ouverte(1, 5000);
    p.expirer(5000 + Portail::kSansSessionMs - 1, f);
    CHECK(!f.fermee[1], "encore ouverte juste avant le delai");
    p.expirer(5000 + Portail::kSansSessionMs, f);
    CHECK(f.fermee[1], "fermee au delai");
    CHECK(p.fermetures() == 1, "fermeture comptee");
  }

  {  // salutSansSuite : un SALUT, un DEFI, puis plus rien : fermee comme sans poignee de main
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    p.ouverte(0, 5000);
    recevoir(p, 0, a.salut(kNa1), 5001, f);
    CHECK(f.lignes[0].size() == 1, "DEFI emis");
    p.expirer(5000 + Portail::kSansSessionMs, f);
    CHECK(f.fermee[0], "fermee sans premier message");
  }

  {  // mauvaiseCleFermee : un client sans la cle n'occupe pas une place
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client intrus{gAutre};
    p.ouverte(2, 5000);
    for (uint32_t t = 5000; t < 5000 + Portail::kSansSessionMs; t += 1000) recevoir(p, 2, intrus.salut(kNa1), t, f);
    p.expirer(5000 + Portail::kSansSessionMs, f);
    CHECK(f.fermee[2], "fermee malgre ses lignes");
  }

  {  // sessionGardee : une session etablie n'est pas fermee par le delai sans poignee de main
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");
    p.expirer(1000 + Portail::kSansSessionMs + 1, f);
    CHECK(!f.fermee[0], "session etablie gardee");
  }

  {  // muette : une session qui se tait depuis kMuetteMs perd sa connexion ; un message la garde
    static_assert(Portail::kMuetteMs > 240000, "au-dela de la periode d'entretien de l'app");
    static_assert(Portail::kMuetteMs < h1::kForgetMs, "avant l'oubli de la session");
    Portail p;
    Fausse f;
    p.cle(gCle);
    Client a{gCle};
    CHECK(etablir(p, f, a, 0, kNa1, 1000), "a");  // dernier message a 1001
    p.expirer(1001 + Portail::kMuetteMs - 1, f);
    CHECK(!f.fermee[0], "encore ouverte juste avant le delai");
    const uint32_t t = 1001 + Portail::kMuetteMs - 1;
    recevoir(p, 0, a.message("2 etat"), t, f);
    Portail::Requete r;
    CHECK(p.requete(&r) && r.rid == 2, "requete servie");
    p.expirer(t + Portail::kMuetteMs - 1, f);
    CHECK(!f.fermee[0], "le message a repousse le delai");
    p.expirer(t + Portail::kMuetteMs, f);
    CHECK(f.fermee[0], "fermee apres kMuetteMs de silence");
    CHECK(p.sessions() == 0, "la session tombe avec sa connexion");
  }
  return bilan("test_portail");
}
