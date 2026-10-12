#include "reseau.h"

#include <Arduino.h>
#include <ESPmDNS.h>
#include <Preferences.h>
#include <WiFi.h>
#include <esp_coexist.h>
#include <esp_random.h>
#include <esp_sleep.h>
#include <esp_system.h>
#include <errno.h>
#include <esp_wifi.h>
#include <lwip/sockets.h>

#include "h1_proto.h"

namespace reseau {
namespace {

const char *const kEspace = "reseau";
const char *const kCleNom = "nom";
const char *const kCleMdp = "mdp";
const char *const kCleH1 = "cle";

Portail sPortail;
WiFiServer sServeur(kPort);
WiFiClient sClients[Portail::kConnexions];
// Place occupee : un WiFiClient deconnecte vaut false, mais sa place n'est
// liberee (Portail::fermee) qu'ici.
bool sOccupe[Portail::kConnexions] = {};
// Connexion coupee par envoyer() (ecriture incomplete) : Portail::fermee n'est
// appelee qu'au tour suivant, jamais depuis l'interieur d'une methode du Portail.
bool sAFermer[Portail::kConnexions] = {};
bool sLance = false;    // demarrer() : connexion au Wi-Fi lancee
bool sDemarre = false;  // ouvrir() : serveur et Bonjour
bool sMdns = false;
// Dernier essai de MDNS.begin en echec : un nouvel essai toutes les kRelanceMdnsMs, pas a chaque tour de loop().
bool sMdnsEchoue = false;
uint32_t sMdnsEssai = 0;
constexpr uint32_t kRelanceMdnsMs = 10000;
char sNomSonde[33] = {0};
char sHote[40] = {0};
uint8_t sNomWifi[32];
size_t sNomWifiLong = 0;
uint32_t sConnexions = 0;  // adresses obtenues ; reconnexions = connexions - 1
uint32_t sRaison = 0;
uint32_t sEchecs = 0;      // ecritures TCP incompletes

void aleatoire(void *p, size_t n) { esp_fill_random(p, n); }

struct SortieTcp : Portail::Sortie {
  void envoyer(uint8_t c, const uint8_t *o, size_t n) override {
    if (c >= Portail::kConnexions || !sOccupe[c]) return;
    if (sClients[c].write(o, n) != n) {
      sEchecs++;
      sClients[c].stop();
      sOccupe[c] = false;
      sAFermer[c] = true;
    }
  }
  // Appele par Portail, qui fait lui-meme sa fermee().
  void fermer(uint8_t c) override {
    if (c >= Portail::kConnexions) return;
    sClients[c].stop();
    sOccupe[c] = false;
    sAFermer[c] = false;
  }
};
SortieTcp sSortie;

void surEvenement(arduino_event_id_t e, arduino_event_info_t info) {
  if (e == ARDUINO_EVENT_WIFI_STA_GOT_IP) sConnexions++;
  if (e == ARDUINO_EVENT_WIFI_STA_DISCONNECTED) sRaison = info.wifi_sta_disconnected.reason;
}

// Nom d'hote mDNS : le nom de la sonde en minuscules, « _ » et « . » en « - ».
void nomHote(const char *nom) {
  size_t i = 0;
  for (; nom[i] && i < sizeof(sHote) - 1; i++) {
    const char c = nom[i];
    sHote[i] = (c >= 'A' && c <= 'Z') ? (char)(c - 'A' + 'a') : (c == '_' || c == '.') ? '-' : c;
  }
  sHote[i] = 0;
}

void annoncer() {
  if (sMdns || WiFi.status() != WL_CONNECTED) return;
  const uint32_t maintenant = millis();
  if (sMdnsEchoue && maintenant - sMdnsEssai < kRelanceMdnsMs) return;
  sMdnsEssai = maintenant;
  sMdnsEchoue = !MDNS.begin(sHote);
  if (sMdnsEchoue) return;
  MDNS.setInstanceName(sNomSonde);
  MDNS.addService("_maillage-zigbee", "_tcp", kPort);
  MDNS.addServiceTxt("_maillage-zigbee", "_tcp", "v", "1");
  sMdns = true;
}

// true si le pair a ferme (FIN lu, ou erreur autre que « rien a lire »).
bool fermeParLePair(WiFiClient &c) {
  const int fd = c.fd();
  if (fd < 0) return true;
  uint8_t octet;
  const int r = recv(fd, &octet, 1, MSG_PEEK | MSG_DONTWAIT);
  if (r > 0) return false;
  if (r == 0) return true;
  return errno != EAGAIN && errno != EWOULDBLOCK;
}

}  // namespace

bool configure() {
  Preferences p;
  if (!p.begin(kEspace, true)) return false;
  const bool oui = p.isKey(kCleNom);
  p.end();
  return oui;
}

bool connecte() { return WiFi.status() == WL_CONNECTED; }

void gardeDemarrage() {
  if (!configure()) return;
  const esp_reset_reason_t r = esp_reset_reason();
  if (r == ESP_RST_POWERON || r == ESP_RST_DEEPSLEEP) return;
  esp_sleep_enable_timer_wakeup(200000);
  esp_deep_sleep_start();
}

void demarrer(const char *nomSonde) {
  if (!configure()) return;
  snprintf(sNomSonde, sizeof(sNomSonde), "%s", nomSonde);
  nomHote(nomSonde);
  Preferences p;
  p.begin(kEspace, true);
  sNomWifiLong = p.getBytes(kCleNom, sNomWifi, sizeof(sNomWifi));
  char nom[33] = {0}, mdp[64] = {0};
  memcpy(nom, sNomWifi, sNomWifiLong);
  const size_t nMdp = p.getBytes(kCleMdp, mdp, sizeof(mdp) - 1);
  mdp[nMdp] = 0;
  p.end();

  esp_coex_wifi_i154_enable();
  WiFi.persistent(false);  // ni nom ni mot de passe gardes par le pilote : la NVS « reseau » les a
  WiFi.mode(WIFI_STA);
  WiFi.setHostname(sHote);
  WiFi.setAutoReconnect(true);
  WiFi.onEvent(surEvenement);
  WiFi.begin(nom, nMdp ? mdp : nullptr);
  h1::wipe(mdp, sizeof(mdp));
  sLance = true;
}

void ouvrir() {
  if (!sLance || sDemarre) return;
  esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
  sServeur.begin();
  sServeur.setNoDelay(true);
  Preferences p;
  uint8_t cle[32];
  const bool aCle = p.begin(kEspace, true) && p.getBytes(kCleH1, cle, sizeof(cle)) == sizeof(cle);
  p.end();
  if (aCle) sPortail.cle(cle);
  h1::wipe(cle, sizeof(cle));
  annoncer();
  sDemarre = true;
}

void tour(uint32_t maintenant) {
  if (!sDemarre) return;
  annoncer();
  // Connexions coupees par une ecriture incomplete : le Portail les apprend
  // avant qu'une place soit reprise.
  for (uint8_t i = 0; i < Portail::kConnexions; i++) {
    if (!sAFermer[i]) continue;
    sAFermer[i] = false;
    sPortail.fermee(i);
  }
  // Fermeture propre du pair (FIN) : connected() la prend pour une connexion
  // ouverte, recv() rend alors 0.
  for (uint8_t i = 0; i < Portail::kConnexions; i++) {
    if (!sOccupe[i] || !fermeParLePair(sClients[i])) continue;
    sClients[i].stop();
    sOccupe[i] = false;
    sPortail.fermee(i);
  }
  WiFiClient nouveau = sServeur.accept();
  if (nouveau) {
    uint8_t libre = Portail::kAucune;
    for (uint8_t i = 0; i < Portail::kConnexions && libre == Portail::kAucune; i++)
      if (!sOccupe[i]) libre = i;
    if (libre == Portail::kAucune) {
      nouveau.stop();
    } else {
      sClients[libre] = nouveau;
      sClients[libre].setNoDelay(true);
      sOccupe[libre] = true;
      sPortail.ouverte(libre, maintenant);
    }
  }
  static uint8_t tampon[512];
  for (uint8_t i = 0; i < Portail::kConnexions; i++) {
    if (!sOccupe[i]) continue;
    if (!sClients[i].connected()) {
      sClients[i].stop();
      sOccupe[i] = false;
      sPortail.fermee(i);
      continue;
    }
    int n;
    while ((n = sClients[i].read(tampon, sizeof(tampon))) > 0)
      sPortail.recevoir(i, tampon, (size_t)n, maintenant, aleatoire, sSortie);
  }
  sPortail.expirer(maintenant, sSortie);
}

void renommer(const char *nomSonde) {
  snprintf(sNomSonde, sizeof(sNomSonde), "%s", nomSonde);
  nomHote(nomSonde);
  // L'annonce porte le nom de la sonde : elle est refaite sous le nouveau (au tour suivant), sans quoi l'app, qui
  // cherche l'instance par le nom de bonjour, ne trouverait plus la sonde par le reseau.
  if (sMdns) MDNS.end();
  sMdns = false;
  sMdnsEchoue = false;
}

bool requete(Portail::Requete *r) { return sDemarre && sPortail.requete(r); }

void repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n) {
  if (sDemarre) sPortail.repondre(session, rid, ligne, n, sSortie);
}

void diffuser(const uint8_t *ligne, size_t n) {
  if (sDemarre) sPortail.diffuser(ligne, n, sSortie);
}

bool ecrireWifi(const uint8_t *nom, size_t nNom, const uint8_t *mdp, size_t nMdp) {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  const bool ok = p.putBytes(kCleNom, nom, nNom) == nNom && (nMdp ? p.putBytes(kCleMdp, mdp, nMdp) == nMdp
                                                                   : (p.remove(kCleMdp), true));
  p.end();
  return ok;
}

bool effacerWifi() {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  p.remove(kCleNom);
  p.remove(kCleMdp);
  p.end();
  return true;
}

void nomWifiHexa(char sortie[2 * 32 + 1]) {
  sortie[0] = 0;
  Preferences p;
  if (!p.begin(kEspace, true)) return;
  uint8_t nom[32];
  const size_t n = p.getBytes(kCleNom, nom, sizeof(nom));
  p.end();
  if (n) h1::toHex(nom, n, sortie);
}

bool nouvelleCle(const uint8_t cle[32]) {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  const bool ok = p.putBytes(kCleH1, cle, 32) == 32;
  p.end();
  if (ok) sPortail.cle(cle);  // les sessions ouvertes tombent
  return ok;
}

bool effacerCle() {
  Preferences p;
  if (!p.begin(kEspace, false)) return false;
  p.remove(kCleH1);
  p.end();
  sPortail.cle(nullptr);
  return true;
}

bool empreinte(char kid[9]) {
  Preferences p;
  if (!p.begin(kEspace, true)) return false;
  uint8_t cle[32];
  const bool aCle = p.getBytes(kCleH1, cle, sizeof(cle)) == sizeof(cle);
  p.end();
  const bool ok = aCle && h1::keyId(cle, kid);
  h1::wipe(cle, sizeof(cle));
  return ok;
}

void ajouterEtat(Ligne &l) {
  if (!configure()) return;
  const bool connecte = WiFi.status() == WL_CONNECTED;
  l.ajoute(",\"reseau\":{\"connecte\":%s", connecte ? "true" : "false");
  if (connecte) l.ajoute(",\"canal\":%d,\"rssi\":%d", (int)WiFi.channel(), (int)WiFi.RSSI());
  else l.ajoute(",\"canal\":null,\"rssi\":null");
  l.ajoute(",\"raison\":%lu,\"sessions\":%u,\"envois\":%lu,\"echecs\":%lu,\"reconnexions\":%lu}",
           (unsigned long)sRaison, sPortail.sessions(), (unsigned long)sPortail.envois(),
           (unsigned long)(sEchecs + sPortail.refus()), (unsigned long)(sConnexions > 0 ? sConnexions - 1 : 0));
}

void ajouterCompteurs(Ligne &l) {
  l.ajoute(",\"sessions\":%u,\"envois\":%lu,\"refus\":%lu,\"fermetures\":%lu", sPortail.sessions(),
           (unsigned long)sPortail.envois(), (unsigned long)sPortail.refus(), (unsigned long)sPortail.fermetures());
}

}  // namespace reseau
