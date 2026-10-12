#pragma once
// ===========================================================================
//  LED de la carte (WS2812 de la SuperMini, sur IO8 ; spec de la sonde,
//  section 1)
//
//  La couleur a montrer a chaque instant, par ordre de priorite (meme voyant
//  que le pont Amaran : status_led.cpp, memes couleurs, memes durees) :
//  1. identification demandee par l'app Hue : arc-en-ciel (un tour de roue
//     en 2 s, par pas de 40 ms), pendant toute l'identification, et au moins
//     un tour complet : le pont Hue peut n'identifier qu'un instant (banc du
//     12/10 : un eclair rouge, puis la lueur du repos) ;
//  2. hors de son reseau, en bleu (« deux bleus », choix de Majid du 12/10,
//     commun aux quatre cartes) :
//     - jamais membre (sonde neuve, usine) : clignotement rapide, 250 ms
//       allume, 250 ms eteint, comme le pont Halo ;
//     - rattachement (parent perdu, redemarrage) : pulsation bleue lente,
//       0 -> 24 -> 0 sur 2 s ;
//  3. adhesion : deux eclairs verts rapides (100 ms, pause, 100 ms) ;
//  4. suspendue : un bref eclair orange (100 ms) toutes les 5 s, le premier
//     tout de suite, aussi apres un redemarrage ;
//  5. Wi-Fi configure mais non connecte : orange lent (1 s allume, 1 s
//     eteint), des le demarrage ; jamais sans Wi-Fi configure (sonde 1.0.0) ;
//  6. sinon, le repos :
//     - lampe Hue allumee : lueur blanche fixe tres faible (propre a Zigbee) ;
//     - lampe eteinte : brefs eclats blancs, une lueur de 600 ms (montee puis
//       descente, sommet 8/255) toutes les 10 s.
//  Choix d'ordre : la suspension et l'adhesion passent avant l'orange Wi-Fi.
//  Ce sont des evenements brefs et rares, lies a une action de l'utilisateur
//  ou a la pile Zigbee ; l'orange lent, lui, revient entre deux. Et sans
//  Wi-Fi la sonde garde son role, donc le message « suspendue » doit rester
//  lisible.
//  main.cpp la pilote dans loop() seulement, jamais depuis un rappel de la
//  pile Zigbee (qui ne fait que poser des drapeaux).
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_voyant.cpp). Instants de millis() : des ecarts non
//  signes ; une sequence finie est oubliee au premier appel qui la voit
//  finie, si bien que le retour a zero de millis() ne ranime rien.
// ===========================================================================
#include <stdint.h>

class Voyant {
 public:
  // Plafond par canal, comme Amaran (kMax) : faible intensite.
  static constexpr uint8_t kVoyantMax = 24;
  static constexpr uint8_t kLueurMax = 8;   // sommet de la lueur blanche
  static constexpr uint8_t kVeille = 2;     // lampe Hue allumee : blanc fixe tres faible
  static constexpr uint32_t kArcMs = 2000;  // un tour de roue de l'arc-en-ciel
  static constexpr uint32_t kPasMs = 40;    // pas de l'arc-en-ciel (25 images/s)
  static constexpr uint32_t kPulsationMs = 2000;  // periode de la pulsation bleue
  static constexpr uint32_t kNeuveMs = 250;       // sonde neuve : demi-periode du bleu rapide
  static constexpr uint32_t kVertMs = 100;      // chaque eclair vert, et la pause entre eux
  static constexpr uint32_t kBrefMs = 100;      // bref eclair orange de la suspension...
  static constexpr uint32_t kPeriodeMs = 5000;  // ... toutes les 5 s
  static constexpr uint32_t kSansWifiMs = 1000;  // orange lent : demi-periode
  static constexpr uint32_t kLueurPeriodeMs = 10000;  // une lueur toutes les 10 s...
  static constexpr uint32_t kLueurMs = 600;           // ... de 600 ms (montee puis descente)

  struct Rgb {
    uint8_t r = 0, g = 0, b = 0;
    bool operator==(const Rgb &o) const { return r == o.r && g == o.g && b == o.b; }
    bool operator!=(const Rgb &o) const { return !(*this == o); }
  };

  void identifier(bool actif, uint32_t t) {
    if (actif && !ident_) {
      debutIdent_ = t;
      tourIdent_ = true;
    }
    ident_ = actif;
  }
  void chercher(bool actif, uint32_t t, bool neuve = false) {
    if (actif && !cherche_) debutPulsation_ = t;
    cherche_ = actif;
    neuve_ = neuve;
  }
  void adherer(uint32_t t) {
    adhesion_ = true;
    debutAdhesion_ = t;
  }
  void suspendre(bool actif, uint32_t t) {
    if (actif && !suspendue_) prochain_ = t;
    suspendue_ = actif;
  }
  void allumer(bool actif) { lampe_ = actif; }
  // Wi-Fi configure (NVS) et connecte (adresse IP). L'orange lent commence par
  // un temps allume, des que la situation « configure, pas connecte » apparait.
  void wifi(bool configure, bool connecte, uint32_t t) {
    const bool sans = configure && !connecte;
    if (sans && !sansWifi_) debutSansWifi_ = t;
    sansWifi_ = sans;
  }

  Rgb teinte(uint32_t t) {
    // Identification finie, et son premier tour de roue aussi : oubliee.
    if (tourIdent_ && !ident_ && t - debutIdent_ >= kArcMs) tourIdent_ = false;
    if (ident_ || tourIdent_) {
      repos_ = false;
      // Par pas de kPasMs : la couleur ne change que 25 fois par seconde.
      const uint32_t phase = (t - debutIdent_) / kPasMs * kPasMs % kArcMs;
      return roue((uint16_t)(phase * 768 / kArcMs));
    }
    if (cherche_) {
      repos_ = false;
      if (neuve_) return {0, 0, ((t - debutPulsation_) / kNeuveMs) % 2 == 0 ? kVoyantMax : (uint8_t)0};
      const uint32_t phase = (t - debutPulsation_) % kPulsationMs;
      const uint32_t demi = kPulsationMs / 2;
      const uint32_t montee = phase < demi ? phase : kPulsationMs - phase;
      return {0, 0, (uint8_t)(montee * kVoyantMax / demi)};
    }
    if (adhesion_) {
      const uint32_t e = t - debutAdhesion_;
      if (e < 3 * kVertMs) {
        repos_ = false;
        return e / kVertMs == 1 ? Rgb{} : Rgb{0, kVoyantMax, 0};
      }
      adhesion_ = false;
    }
    if (suspendue_) {
      // Ecart depuis le prochain bref eclair : au-dela de 2^31 ms, il est
      // encore a venir (prochain_ n'est jamais a plus d'une periode en avance).
      const uint32_t e = t - prochain_;
      if (e < 0x80000000u) {
        if (e % kPeriodeMs < kBrefMs) {
          repos_ = false;
          return orange();
        }
        // Eclair fini (plusieurs si loop() a ete retenue) : le suivant, sur la
        // meme grille de 5 s.
        prochain_ += (e / kPeriodeMs + 1) * kPeriodeMs;
      }
    }
    if (sansWifi_) {
      repos_ = false;
      return (t - debutSansWifi_) / kSansWifiMs % 2 == 0 ? orange() : Rgb{};
    }
    // Repos. La premiere lueur vient tout de suite, comme « en ligne » chez
    // Amaran : au retour au repos (fin de l'orange, de l'identification...),
    // elle confirme que la sonde est rentree dans son etat normal. La grille de
    // 10 s part de ce moment.
    if (!repos_) {
      repos_ = true;
      debutRepos_ = t;
    }
    if (lampe_) return {kVeille, kVeille, kVeille};
    const uint32_t ph = (t - debutRepos_) % kLueurPeriodeMs;
    if (ph >= kLueurMs) return {};
    // Triangle 0 -> kLueurMax -> 0 sur kLueurMs.
    const uint32_t demi = kLueurMs / 2;
    const uint32_t x = ph < demi ? ph : kLueurMs - ph;
    const uint8_t v = (uint8_t)((kLueurMax * x + demi / 2) / demi);
    return {v, v, v};
  }

 private:
  // Orange : le vert d'une WS2812 parait bien plus fort que son rouge.
  static Rgb orange() { return {kVoyantMax, kVoyantMax / 4, 0}; }
  // Roue des couleurs a l'intensite kVoyantMax : hue 0..767 (rouge, vert, bleu).
  static Rgb roue(uint16_t hue) {
    hue %= 768;
    const uint8_t haut = (uint8_t)((hue % 256) * kVoyantMax / 255);
    const uint8_t bas = (uint8_t)(kVoyantMax - haut);
    switch (hue / 256) {
      case 0: return {bas, haut, 0};
      case 1: return {0, bas, haut};
      default: return {haut, 0, bas};
    }
  }

  bool ident_ = false;
  bool tourIdent_ = false;  // premier tour de roue pas encore fini
  uint32_t debutIdent_ = 0;
  bool cherche_ = false;
  bool neuve_ = false;  // recherche d'une sonde jamais membre : bleu rapide
  uint32_t debutPulsation_ = 0;
  bool adhesion_ = false;
  uint32_t debutAdhesion_ = 0;
  bool suspendue_ = false;
  uint32_t prochain_ = 0;  // debut du prochain bref eclair, ou de celui en cours
  bool sansWifi_ = false;
  uint32_t debutSansWifi_ = 0;
  bool repos_ = false;  // au repos au dernier appel
  uint32_t debutRepos_ = 0;
  bool lampe_ = false;
};
