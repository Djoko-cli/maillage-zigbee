// ===========================================================================
//  Sonde de maillage Zigbee, firmware 1.0.0 (spec :
//  docs/superpowers/specs/2026-10-05-maillage-zigbee-sonde-design.md)
//
//  ESP32-C6 membre du reseau Hue : appareil final non endormi, jamais
//  routeur, point d'acces « lampe » (endpoint 11). Il ne relaie rien,
//  n'envoie aucune commande aux lampes, et
//  n'emet que les requetes ZDO de lecture de la liste blanche
//  (liste_blanche.h) : il donne par l'USB la table des voisins de n'importe
//  quel routeur, et la sienne. L'app (Maillage Zigbee) orchestre la tournee,
//  decode et dessine.
//
//  USB : une commande par ligne ; chaque reponse est une ligne machine,
//  RS (0x1E) + JSON compact + LF, 4095 octets au plus (ligne.h).
//    bonjour                          produit, version, nom, adresse longue,
//                                     membre, role, suspendue (aussi au
//                                     demarrage)
//    nom <texte>                      change le nom et le garde ; bonjour a
//                                     jour, ou erreur syntaxe / ecriture
//    etat                             membre, recherche, adresses, parent,
//                                     PAN, EPID, canal, suspendue,
//                                     refus_cadence, version de la pile
//    voisins                          table des voisins de la sonde
//    table <cible> <id> [<delai ms>]  table complete des voisins d'un
//                                     routeur (Mgmt_Lqi_req, page par page)
//    routes <cible> <id> [<delai ms>] table de routage (Mgmt_Rtg_req en APS
//                                     brute ; si SONDE_ROUTES, essai E4)
//    echecs <cible> <id> [<delai ms>] emissions et echecs d'un routeur
//                                     (Mgmt_NWK_Update_req ; si
//                                     SONDE_ECHECS, retiree de la 1.0.0 :
//                                     les lampes Hue ne repondent pas, E5)
//    suspendre | reprendre            garde l'etat ; repond par etat
//    oubli                            quitter le reseau et l'oublier ; la
//                                     sonde redemarre, et son bonjour de
//                                     demarrage suit
//  Une seule requete reseau a la fois (sinon « occupee »), garde-fou de
//  cadence (cadence.h), une seule nouvelle tentative par page ; une requete
//  en cours s'arrete en « non_membre » si la sonde quitte le reseau.
//  Si SONDE_SIGNAUX : une ligne « signal » pour chaque signal de la pile
//  (type, nom, statut, detail), gardee pour le journal de l'app.
//
//  Dans l'app Hue, la sonde est une lampe : on/off et identification ne
//  pilotent que la LED, jamais la suspension (« Tout eteindre » ne doit pas
//  la suspendre).
// ===========================================================================

#include <Arduino.h>
#include <Preferences.h>
#include <esp_log.h>
#include <esp_system.h>

#include "adhesion.h"
#include "cadence.h"
#include "commande.h"
#include "entrees.h"
#include "ligne.h"
#include "options.h"
#include "pagination.h"
#include "version.h"
#include "voyant.h"
#include "zigbee.h"

// ---------------------------------------------------------------------------
//  Etat
// ---------------------------------------------------------------------------

static Preferences sPreferences;  // espace « sonde » : nom, suspendue
static const char *const kCleNom = "nom";
static const char *const kCleSuspendue = "suspendue";
static const char *const kNomDefaut = "SONDE-Z1";
static char sNom[kNomMax + 1] = "SONDE-Z1";
static bool sSuspendue = false;

static Adhesion sAdhesion;
static Cadence sCadence;
static Voyant sVoyant;
static Ligne sLigne;
static uint32_t sAdhesionsVues = 0;
static uint32_t sFinEffet = 0;  // fin de l'effet d'identification en cours
static bool sEffet = false;

static uint8_t sIeee[8] = {0};
static bool sIeeeConnu = false;
static uint32_t sDernierConstat = 0;  // dernier constat de la pile (Adhesion::constater)

// La requete reseau en cours (une seule a la fois).
enum class Travail : uint8_t { kAucun, kTable, kRoutes, kEchecs };
static Travail sTravail = Travail::kAucun;
static uint16_t sCible = 0;
static uint32_t sId = 0;
static constexpr size_t kEntreesMax = 64;
static Pagination<EntreeVoisin, kEntreesMax> sTable;
#if SONDE_ROUTES
// Une table de routage annonce sa place (254 au pont Hue) et en remplit plus
// de 64 (essai E4) : la sonde en garde 255, le plus grand total possible.
static constexpr size_t kRoutesMax = 255;
static Pagination<EntreeRoute, kRoutesMax> sRoutes;
#endif
#if SONDE_ECHECS
struct ResultatEchecs {
  uint16_t emissions;
  uint16_t echecs;
  uint8_t energie;
};
static Pagination<ResultatEchecs, 1> sEchecs;  // une « table » d'une entree
#endif

// ---------------------------------------------------------------------------
//  Sorties
// ---------------------------------------------------------------------------

static void ecrire(void *, const uint8_t *octets, size_t n) { Serial.write(octets, n); }

static void finir() {
  size_t n = 0;
  const uint8_t *o = sLigne.fin(&n);
  ecrire(nullptr, o, n);
}

static void repondreErreur(const char *erreur) {
  sLigne.debut("erreur");
  sLigne.ajoute(",\"erreur\":\"%s\"", erreur);
  finir();
}

static void ajouteIeee(const char *cle, const uint8_t ieee[8]) {
  char t[17];
  texteIeee(ieee, t);
  sLigne.ajoute(",\"%s\":\"%s\"", cle, t);
}

// Adresse longue de la sonde, lue une fois sous le verrou.
static void lireIeee(uint32_t attenteMs) {
  if (sIeeeConnu || !zigbee::verrou(attenteMs)) return;
  zigbee::ieee(sIeee);
  zigbee::libere();
  sIeeeConnu = true;
}

static const char *texteRole() {
  if (!sAdhesion.membre()) return nullptr;
  return "final";  // jamais routeur
}

// ---------------------------------------------------------------------------
//  Commandes simples
// ---------------------------------------------------------------------------

static void cmdBonjour() {
  lireIeee(200);
  sLigne.debut("bonjour");
  sLigne.ajoute(",\"produit\":\"sonde-zigbee\",\"version\":\"%s\",\"nom\":\"%s\"", SONDE_VERSION, sNom);
  if (sIeeeConnu) ajouteIeee("ieee", sIeee);
  else sLigne.ajoute(",\"ieee\":null");
  const char *role = texteRole();
  sLigne.ajoute(",\"membre\":%s", sAdhesion.membre() ? "true" : "false");
  if (role) sLigne.ajoute(",\"role\":\"%s\"", role);
  else sLigne.ajoute(",\"role\":null");
  sLigne.ajoute(",\"suspendue\":%s", sSuspendue ? "true" : "false");
  finir();
}

static void cmdNom(const char *nom) {
  // putString rend le nombre d'octets ecrits : 0 si la NVS refuse.
  if (sPreferences.putString(kCleNom, nom) == 0) return repondreErreur("ecriture");
  snprintf(sNom, sizeof(sNom), "%s", nom);
  cmdBonjour();
}

static void cmdEtat() {
  if (!zigbee::verrou(200)) {
    sLigne.debut("etat");
    sLigne.ajoute(",\"erreur\":\"occupee\"");
    return finir();
  }
  const bool membre = sAdhesion.membre();
  uint8_t ieee[8], epid[8];
  zigbee::ieee(ieee);
  zigbee::epid(epid);
  const uint16_t court = zigbee::court();
  const uint16_t pan = zigbee::pan();
  const uint8_t canal = zigbee::canal();
  VoisinSonde parent;
  bool parentConnu = false;
  if (membre) {
    uint16_t it = 0;
    VoisinSonde v;
    while (!parentConnu && zigbee::voisinSuivant(&it, &v)) {
      if (v.relation == 0) {
        parent = v;
        parentConnu = true;
      }
    }
  }
  char pile[24];
  zigbee::versionPile(pile, sizeof(pile));
  zigbee::libere();

  sLigne.debut("etat");
  sLigne.ajoute(",\"membre\":%s,\"recherche\":%s", membre ? "true" : "false", sAdhesion.cherche() ? "true" : "false");
  if (membre) sLigne.ajoute(",\"court\":\"%04X\"", court);
  else sLigne.ajoute(",\"court\":null");
  ajouteIeee("ieee", ieee);
  const char *role = texteRole();
  if (role) sLigne.ajoute(",\"role\":\"%s\"", role);
  else sLigne.ajoute(",\"role\":null");
  if (parentConnu) {
    char t[17];
    texteIeee(parent.ieee, t);
    sLigne.ajoute(",\"parent\":{\"court\":\"%04X\",\"ieee\":\"%s\",\"lqi\":%u,\"rssi\":%d}", parent.court, t,
                  parent.lqi, parent.rssi);
  } else {
    sLigne.ajoute(",\"parent\":null");
  }
  if (membre) {
    sLigne.ajoute(",\"pan\":\"%04X\"", pan);
    ajouteIeee("epid", epid);
    sLigne.ajoute(",\"canal\":%u", canal);
  } else {
    sLigne.ajoute(",\"pan\":null,\"epid\":null,\"canal\":null");
  }
  sLigne.ajoute(",\"suspendue\":%s,\"refus_cadence\":%lu,\"rattachements_echoues\":%lu,\"pile\":\"%s\"",
                sSuspendue ? "true" : "false", (unsigned long)sCadence.refus(),
                (unsigned long)sAdhesion.echecsRattachement(), pile);
  finir();
}

static void cmdVoisins() {
  if (!zigbee::verrou(200)) {
    sLigne.debut("voisins");
    sLigne.ajoute(",\"erreur\":\"occupee\"");
    return finir();
  }
  // Copie sous le verrou, ecriture apres.
  static VoisinSonde voisins[kEntreesMax];
  size_t n = 0;
  uint16_t it = 0;
  while (n < kEntreesMax && zigbee::voisinSuivant(&it, &voisins[n])) n++;
  zigbee::libere();
  ListeDecoupee liste(sLigne, ecrire, nullptr);
  liste.commencer("voisins", "");
  char objet[256];
  for (size_t i = 0; i < n; i++) {
    if (jsonVoisinSonde(voisins[i], objet, sizeof(objet))) liste.ajouter(objet);
  }
  liste.terminer();
}

static void cmdSuspendre(bool suspendue) {
  sSuspendue = suspendue;
  sPreferences.putBool(kCleSuspendue, suspendue);
  cmdEtat();
}

// ---------------------------------------------------------------------------
//  Requetes reseau : table, routes, echecs
// ---------------------------------------------------------------------------

static const char *texteIssue(Issue i) {
  switch (i) {
    case Issue::kDelai: return "delai";
    case Issue::kStatut: return "statut";
    case Issue::kCadence: return "cadence";
    case Issue::kEnvoi: return "envoi";
    case Issue::kSuspendue: return "suspendue";
    case Issue::kNonMembre: return "non_membre";
    default: return "envoi";
  }
}

static const char *typeTravail(Travail t) {
  switch (t) {
    case Travail::kRoutes: return "routes";
    case Travail::kEchecs: return "echecs";
    default: return "table";
  }
}

// Echec avant ou pendant une requete : une ligne, sans liste.
static void repondreEchec(Travail t, uint32_t id, uint16_t cible, const char *erreur, int statut = -1) {
  sLigne.debut(typeTravail(t));
  sLigne.ajoute(",\"id\":%lu,\"cible\":\"%04X\",\"ok\":false,\"erreur\":\"%s\"", (unsigned long)id, cible, erreur);
  if (statut >= 0) sLigne.ajoute(",\"statut\":\"0x%02X\"", statut);
  finir();
}

static void commencer(const Commande &c, Travail t, uint32_t maintenant) {
#if !SONDE_ROUTES
  if (t == Travail::kRoutes) return repondreErreur("inconnue");
#endif
#if !SONDE_ECHECS
  if (t == Travail::kEchecs) return repondreErreur("inconnue");
#endif
  if (sTravail != Travail::kAucun) return repondreEchec(t, c.id, c.cible, "occupee");
  if (sSuspendue) return repondreEchec(t, c.id, c.cible, "suspendue");
  if (!sAdhesion.membre()) return repondreEchec(t, c.id, c.cible, "non_membre");
  sTravail = t;
  sCible = c.cible;
  sId = c.id;
  if (t == Travail::kTable) sTable.commencer(maintenant, c.delaiMs);
#if SONDE_ROUTES
  if (t == Travail::kRoutes) sRoutes.commencer(maintenant, c.delaiMs);
#endif
#if SONDE_ECHECS
  if (t == Travail::kEchecs) sEchecs.commencer(maintenant, c.delaiMs);
#endif
}

// En-tete d'une reponse reussie, repris sur chaque ligne de la liste.
template <typename P>
static void entete(const P &p, char *sortie, size_t taille) {
  snprintf(sortie, taille, ",\"id\":%lu,\"cible\":\"%04X\",\"ok\":true,\"ms\":%lu,\"pages\":%u,\"total\":%u,\"partielle\":%s",
           (unsigned long)sId, sCible, (unsigned long)p.dureeMs(), p.pages(), p.total(),
           p.partielle() ? "true" : "false");
}

// Ecrit le resultat d'une table finie.
template <typename P, typename F>
static void rendre(const P &p, F json) {
  if (p.issue() != Issue::kOk) {
    return repondreEchec(sTravail, sId, sCible, texteIssue(p.issue()),
                         p.issue() == Issue::kStatut ? (int)p.statut() : -1);
  }
  char tete[ListeDecoupee::kEnteteMax + 1];
  entete(p, tete, sizeof(tete));
  ListeDecoupee liste(sLigne, ecrire, nullptr);
  liste.commencer(typeTravail(sTravail), tete);
  char objet[256];
  for (size_t i = 0; i < p.nombre(); i++) {
    if (json(p.entree(i), objet, sizeof(objet))) liste.ajouter(objet);
  }
  liste.terminer();
}

#if SONDE_ECHECS
static void rendreEchecs() {
  if (sEchecs.issue() != Issue::kOk || sEchecs.nombre() == 0) {
    const Issue i = sEchecs.issue() == Issue::kOk ? Issue::kStatut : sEchecs.issue();
    return repondreEchec(Travail::kEchecs, sId, sCible, texteIssue(i),
                         i == Issue::kStatut ? (int)sEchecs.statut() : -1);
  }
  const ResultatEchecs &r = sEchecs.entree(0);
  sLigne.debut("echecs");
  sLigne.ajoute(",\"id\":%lu,\"cible\":\"%04X\",\"ok\":true,\"ms\":%lu,\"emissions\":%u,\"echecs\":%u,\"energie\":%u",
                (unsigned long)sId, sCible, (unsigned long)sEchecs.dureeMs(), r.emissions, r.echecs, r.energie);
  finir();
}
#endif

// Envoie la page attendue si la cadence le permet ; envoyer(index, numero)
// sous le verrou.
template <typename P, typename Envoi>
static void pousserPage(P &p, uint32_t maintenant, Envoi envoyer) {
  if (!p.aEnvoyer(maintenant)) return;
  switch (sCadence.avis(maintenant)) {
    case Cadence::Avis::kAttendre: return;
    case Cadence::Avis::kRefus:
      sCadence.refuser();
      p.abandonner(Issue::kCadence, maintenant);
      return;
    case Cadence::Avis::kOui: break;
  }
  if (!zigbee::verrou(50)) return;  // pile occupee : au prochain tour
  const bool parti = envoyer(p.index(), p.numeroAEnvoyer());
  zigbee::libere();
  if (!parti) return p.abandonner(Issue::kEnvoi, maintenant);
  sCadence.compter(maintenant);
  p.envoyee(maintenant);
}

// Arret impose a la requete en cours (suspendue, sortie du reseau) : rien si
// aucune ; la fin est ecrite par progresser().
static void arreter(Issue issue, uint32_t maintenant) {
  sTable.abandonner(issue, maintenant);
#if SONDE_ROUTES
  sRoutes.abandonner(issue, maintenant);
#endif
#if SONDE_ECHECS
  sEchecs.abandonner(issue, maintenant);
#endif
}

static void progresser(uint32_t maintenant) {
  // Les reponses d'abord : celles d'une requete finie ou d'un autre genre
  // sont ecartees par leur numero ou leur genre.
  static zigbee::Reponse r;
  while (zigbee::reponse(&r)) {
    if (r.genre == zigbee::Genre::kVoisins && sTravail == Travail::kTable)
      sTable.page(r.numero, r.statut, r.total, r.debut, r.nombre, r.voisins, maintenant);
#if SONDE_ROUTES
    if (r.genre == zigbee::Genre::kRoutes && sTravail == Travail::kRoutes)
      sRoutes.page(r.numero, r.statut, r.total, r.debut, r.nombre, r.routes, maintenant);
#endif
#if SONDE_ECHECS
    if (r.genre == zigbee::Genre::kEchecs && sTravail == Travail::kEchecs) {
      const ResultatEchecs e = {r.emissions, r.echecs, r.energie};
      sEchecs.page(r.numero, r.statut, r.total, 0, r.nombre, &e, maintenant);
    }
#endif
  }

  if (sTravail != Travail::kAucun && sSuspendue) arreter(Issue::kSuspendue, maintenant);
  if (sTravail != Travail::kAucun && !sAdhesion.membre()) arreter(Issue::kNonMembre, maintenant);
  switch (sTravail) {
    case Travail::kAucun: return;
    case Travail::kTable:
      pousserPage(sTable, maintenant,
                  [](uint8_t index, uint32_t numero) { return zigbee::envoyerVoisins(sCible, index, numero); });
      if (!sTable.actif()) {
        rendre(sTable, jsonEntreeVoisin);
        sTravail = Travail::kAucun;
      }
      return;
    case Travail::kRoutes:
#if SONDE_ROUTES
      pousserPage(sRoutes, maintenant,
                  [](uint8_t index, uint32_t numero) { return zigbee::envoyerRoutes(sCible, index, numero); });
      if (!sRoutes.actif()) {
        rendre(sRoutes, jsonEntreeRoute);
        sTravail = Travail::kAucun;
      }
#endif
      return;
    case Travail::kEchecs:
#if SONDE_ECHECS
      pousserPage(sEchecs, maintenant,
                  [](uint8_t, uint32_t numero) { return zigbee::envoyerEchecs(sCible, numero); });
      if (!sEchecs.actif()) {
        rendreEchecs();
        sTravail = Travail::kAucun;
      }
#endif
      return;
  }
}

// ---------------------------------------------------------------------------
//  Oubli
// ---------------------------------------------------------------------------

static void cmdOubli(uint32_t maintenant) {
  // Une requete en cours finit d'abord, en « non_membre ».
  if (sTravail != Travail::kAucun) {
    arreter(Issue::kNonMembre, maintenant);
    progresser(maintenant);
  }
  // Comme a la premiere mise en service : non suspendue ; le nom est garde.
  sSuspendue = false;
  sPreferences.putBool(kCleSuspendue, false);
  sLigne.debut("oubli");
  sLigne.ajoute(",\"ok\":true");
  finir();
  Serial.flush();
  sAdhesion.oubli(maintenant);
  if (!zigbee::verrou(1000)) return;  // le filet d'Adhesion oubliera dans 15 s
  // D'apres la pile, pas d'apres Adhesion : apres des rattachements echoues,
  // la sonde n'est plus membre mais la pile garde le reseau, et le depart
  // local garde le compteur de trames.
  if (zigbee::rattachee()) zigbee::quitter();  // signal de depart a la fin, puis redemarrer
  else zigbee::oublier();                       // redemarre
  zigbee::libere();
}

// ---------------------------------------------------------------------------
//  Commandes de l'USB
// ---------------------------------------------------------------------------

static void executer(const char *ligne, uint32_t maintenant) {
  const Commande c = lireCommande(ligne);
  switch (c.type) {
    case TypeCommande::kBonjour: return cmdBonjour();
    case TypeCommande::kNom: return cmdNom(c.nom);
    case TypeCommande::kEtat: return cmdEtat();
    case TypeCommande::kVoisins: return cmdVoisins();
    case TypeCommande::kTable: return commencer(c, Travail::kTable, maintenant);
    case TypeCommande::kRoutes: return commencer(c, Travail::kRoutes, maintenant);
    case TypeCommande::kEchecs: return commencer(c, Travail::kEchecs, maintenant);
    case TypeCommande::kSuspendre: return cmdSuspendre(true);
    case TypeCommande::kReprendre: return cmdSuspendre(false);
    case TypeCommande::kOubli: return cmdOubli(maintenant);
    case TypeCommande::kSyntaxe: return repondreErreur("syntaxe");
    case TypeCommande::kInconnue: return repondreErreur("inconnue");
  }
}

// ---------------------------------------------------------------------------
//  Adhesion et signaux de la pile
// ---------------------------------------------------------------------------

// Redemarrage voulu : la sortie USB est tamponnee, on la vide d'abord, sans
// quoi la ligne signal qui explique le redemarrage (depart...) se perd.
static void redemarrer() {
  Serial.flush();
  delay(20);  // la FIFO materielle de l'USB se vide aussi
  esp_restart();
}

static void evenements(uint32_t maintenant) {
  zigbee::Evenement e;
  while (zigbee::evenement(&e)) {
    switch (e.signal) {
      case zigbee::Signal::kPremierDemarrage: sAdhesion.premierDemarrage(e.ok, maintenant); break;
      case zigbee::Signal::kRedemarrage: sAdhesion.redemarrage(e.ok, maintenant); break;
      case zigbee::Signal::kRecherche: sAdhesion.recherche(e.ok, maintenant); break;
      case zigbee::Signal::kRattachementTc: sAdhesion.rattachementTc(e.ok, maintenant); break;
      case zigbee::Signal::kParentPerdu: sAdhesion.parentPerdu(maintenant); break;
      case zigbee::Signal::kDepart: sAdhesion.depart(e.ok, maintenant); break;
      case zigbee::Signal::kIdentification: sVoyant.identifier(e.ok, maintenant); break;
      case zigbee::Signal::kEffet:
        // Un effet d'identification dure 3 s ; « finir » ou « arreter »
        // l'eteint tout de suite.
        sEffet = e.ok;
        sFinEffet = maintenant + 3000;
        sVoyant.identifier(e.ok, maintenant);
        break;
      case zigbee::Signal::kLampe: sVoyant.allumer(e.ok); break;
      case zigbee::Signal::kBrut:
#if SONDE_SIGNAUX
        sLigne.debut("signal");
        sLigne.ajoute(",\"signal\":\"0x%02X\",\"nom\":\"%s\",\"ok\":%s,\"detail\":%u", e.brut,
                      e.nom ? e.nom : "?", e.ok ? "true" : "false", e.detail);
        finir();
#endif
        break;
    }
  }
  // Constat de la pile toutes les 10 s (un signal d'adhesion perdu est
  // rattrape), sans attendre le verrou.
  if (maintenant - sDernierConstat >= 10000 && zigbee::verrou(0)) {
    const bool rattachee = zigbee::rattachee();
    zigbee::libere();
    sDernierConstat = maintenant;
    sAdhesion.constater(rattachee, maintenant);
  }
  if (sEffet && (int32_t)(maintenant - sFinEffet) >= 0) {
    sEffet = false;
    sVoyant.identifier(false, maintenant);
  }

  const Adhesion::Action a = sAdhesion.tour(maintenant);
  if (a == Adhesion::Action::kRien) return;
  if (a == Adhesion::Action::kRedemarrer) redemarrer();
  // Le verrou, 1 s au plus : une action perdue repart par les filets
  // d'Adhesion (sauf oublier, que le depart ne refait pas : on insiste).
  for (int essai = 0; essai < 5; essai++) {
    if (!zigbee::verrou(200)) continue;
    switch (a) {
      case Adhesion::Action::kInitialiser:
      case Adhesion::Action::kRattacher: zigbee::initialiser(); break;
      case Adhesion::Action::kChercher: zigbee::chercher(); break;
      case Adhesion::Action::kOublier: zigbee::oublier(); break;
      default: break;
    }
    zigbee::libere();
    return;
  }
  if (a == Adhesion::Action::kOublier) redemarrer();
}

// ---------------------------------------------------------------------------
//  LED de la carte
// ---------------------------------------------------------------------------

// WS2812 de la SuperMini, sur IO8 : faible intensite, 24/255 au plus par
// canal, comme la sonde Thread ; orange : un quart de vert.
static constexpr uint8_t kBrocheVoyant = 8;
static constexpr uint8_t kVoyantMax = 24;
static uint32_t sVoyantEcrit = 0xFFFFFFFFu;  // RGB ecrit ; rien encore

static void ecrireVoyant(uint8_t r, uint8_t g, uint8_t b) {
  const uint32_t rgb = (uint32_t)r << 16 | (uint32_t)g << 8 | b;
  if (rgb == sVoyantEcrit) return;
  sVoyantEcrit = rgb;
  rgbLedWrite(kBrocheVoyant, r, g, b);
}

static void voyantTour(uint32_t maintenant) {
  if (sAdhesion.adhesions() != sAdhesionsVues) {
    sAdhesionsVues = sAdhesion.adhesions();
    sVoyant.adherer(maintenant);
  }
  sVoyant.chercher(sAdhesion.cherche(), maintenant);
  sVoyant.suspendre(sSuspendue, maintenant);
  const Voyant::Teinte t = sVoyant.teinte(maintenant);
  const uint8_t m = (uint8_t)(kVoyantMax * t.niveau / 255);
  switch (t.couleur) {
    case Voyant::kBlanche: ecrireVoyant(m, m, m); break;
    case Voyant::kBleue: ecrireVoyant(0, 0, m); break;
    case Voyant::kVerte: ecrireVoyant(0, m, 0); break;
    case Voyant::kOrange: ecrireVoyant(m, m / 4, 0); break;
    case Voyant::kVeille: ecrireVoyant(2, 2, 2); break;
    default: ecrireVoyant(0, 0, 0); break;
  }
}

// ---------------------------------------------------------------------------
//  setup et loop
// ---------------------------------------------------------------------------

static char sCommande[256];
static size_t sCmdLong = 0;
static bool sCmdTropLongue = false;  // plus de 255 caracteres : refusee en entier

void setup() {
  Serial.begin(115200);
  // Aucun journal de la pile ni d'Arduino : sur le meme USB, il couperait les
  // lignes machine (les signaux arrivent en lignes « signal »).
  esp_log_level_set("*", ESP_LOG_NONE);
  // LED au noir d'abord : une WS2812 garde sa couleur a travers un redemarrage.
  ecrireVoyant(0, 0, 0);
  sPreferences.begin("sonde", false);
  const String nom = sPreferences.getString(kCleNom, kNomDefaut);
  if (nomValide(nom.c_str())) snprintf(sNom, sizeof(sNom), "%s", nom.c_str());
  sSuspendue = sPreferences.getBool(kCleSuspendue, false);
  zigbee::demarrer();
  // La pile demarre dans sa tache : jusqu'a 2 s pour lire l'adresse longue
  // avant le bonjour du demarrage (sinon "ieee":null, et le suivant l'aura).
  for (int i = 0; i < 200 && !zigbee::prete(); i++) delay(10);
  lireIeee(200);
  cmdBonjour();
}

void loop() {
  while (Serial.available()) {
    const int o = Serial.read();
    if (o == '\n' || o == '\r') {
      sCommande[sCmdLong] = 0;
      if (sCmdTropLongue) repondreErreur("syntaxe");
      else if (sCmdLong) executer(sCommande, millis());
      sCmdLong = 0;
      sCmdTropLongue = false;
    } else if (o >= 0x20 && o < 0x7F) {
      if (sCmdLong < sizeof(sCommande) - 1) sCommande[sCmdLong++] = (char)o;
      else sCmdTropLongue = true;
    }
  }
  // L'heure relue a chaque etape : une commande ou une action d'adhesion peut
  // prendre jusqu'a 1 s.
  evenements(millis());
  progresser(millis());
  voyantTour(millis());
  delay(5);
}
