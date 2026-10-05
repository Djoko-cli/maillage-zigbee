#pragma once
// ===========================================================================
//  Pagination d'une table distante (spec de la sonde, section 2)
//
//  La sonde demande les pages une a une (Mgmt_Lqi_req ou Mgmt_Rtg_req) a
//  partir de l'index 0, et garde les entrees :
//  - une page sans reponse dans le delai (ou rendue par la pile avec le
//    statut 0x85, delai depasse) est redemandee une fois ; un second silence
//    termine la table en « delai » ;
//  - un total qui change d'une page a l'autre, ou une page qui ne commence
//    pas a l'index demande : la table recommence au debut une fois, puis se
//    termine avec ce qu'elle a, « partielle » ;
//  - une page vide avant le total, ou plus d'entrees que la place :
//    « partielle » ;
//  - 120 s au plus en tout : au-dela, « delai ».
//  Un autre statut ZDO que 0 et 0x85 termine la table en « statut ».
//
//  Chaque envoi porte un numero : une reponse tardive a un envoi precedent
//  (meme page redemandee, ou table precedente) est ecartee.
//
//  Usage, a chaque tour de loop() :
//    if (p.aEnvoyer(t)) { envoyer la page p.index() avec le numero
//                         p.numeroAEnvoyer() ; si l'envoi part : p.envoyee(t) }
//    pour chaque page recue : p.page(numero, statut, total, debut, nombre, entrees, t)
//    if (!p.actif()) : la table est finie, p.issue() dit comment.
//
//  Pur, sans Arduino, tout dans cet en-tete : teste sur l'hote
//  (sonde/test/test_pagination.cpp). Instants de millis() : des ecarts non
//  signes, justes a travers le retour a zero.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

enum class Issue : uint8_t { kEnCours, kOk, kDelai, kStatut, kCadence, kEnvoi, kSuspendue, kNonMembre };

template <typename Entree, size_t N>
class Pagination {
 public:
  static constexpr uint32_t kDureeMaxMs = 120000;
  static constexpr uint8_t kStatutDelai = 0x85;  // ZDP : delai depasse

  void commencer(uint32_t maintenant, uint32_t delaiPageMs) {
    actif_ = true;
    attente_ = false;
    debutMs_ = maintenant;
    finMs_ = maintenant;
    delaiPageMs_ = delaiPageMs;
    recommence_ = false;
    partielle_ = false;
    issue_ = Issue::kEnCours;
    statut_ = 0;
    vider(0, false);
  }

  bool actif() const { return actif_; }

  // Une page doit-elle partir maintenant ? Verifie aussi les delais.
  bool aEnvoyer(uint32_t maintenant) {
    if (!actif_) return false;
    if (maintenant - debutMs_ >= kDureeMaxMs) {
      finir(Issue::kDelai, maintenant);
      return false;
    }
    if (attente_ && maintenant - envoiMs_ >= delaiPageMs_) sansReponse(maintenant);
    return actif_ && !attente_;
  }

  uint8_t index() const { return index_; }
  uint32_t numeroAEnvoyer() const { return numero_ + 1; }

  void envoyee(uint32_t maintenant) {
    numero_++;
    attente_ = true;
    envoiMs_ = maintenant;
  }

  void page(uint32_t numero, uint8_t statut, uint8_t total, uint8_t debut, uint8_t nombre, const Entree *entrees,
            uint32_t maintenant) {
    if (!actif_ || !attente_ || numero != numero_) return;
    attente_ = false;
    if (statut == kStatutDelai) {
      sansReponse(maintenant);
      return;
    }
    if (statut != 0) {
      statut_ = statut;
      finir(Issue::kStatut, maintenant);
      return;
    }
    if (!totalConnu_) {
      total_ = total;
      totalConnu_ = true;
    }
    if (total != total_ || debut != index_) {
      if (!recommence_) {
        recommence_ = true;
        vider(total, true);
      } else {
        partielle_ = true;
        finir(Issue::kOk, maintenant);
      }
      return;
    }
    reessai_ = false;
    pages_++;
    if (nombre == 0 && index_ < total_) {
      partielle_ = true;
      finir(Issue::kOk, maintenant);
      return;
    }
    for (uint8_t i = 0; i < nombre; i++) {
      if (nombre_ == N) {
        partielle_ = true;
        finir(Issue::kOk, maintenant);
        return;
      }
      entrees_[nombre_++] = entrees[i];
    }
    index_ = (uint8_t)(index_ + nombre);
    if (index_ >= total_) finir(Issue::kOk, maintenant);
  }

  // Fin imposee par l'appelant : cadence, envoi refuse, suspension, sonde
  // sortie du reseau.
  void abandonner(Issue issue, uint32_t maintenant) {
    if (actif_) finir(issue, maintenant);
  }

  Issue issue() const { return issue_; }
  uint8_t statut() const { return statut_; }
  bool partielle() const { return partielle_; }
  uint8_t total() const { return total_; }
  uint8_t pages() const { return pages_; }
  size_t nombre() const { return nombre_; }
  const Entree &entree(size_t i) const { return entrees_[i]; }
  uint32_t dureeMs() const { return finMs_ - debutMs_; }

 private:
  void vider(uint8_t total, bool totalConnu) {
    index_ = 0;
    total_ = total;
    totalConnu_ = totalConnu;
    reessai_ = false;
    pages_ = 0;
    nombre_ = 0;
  }

  void sansReponse(uint32_t maintenant) {
    if (!reessai_) {
      reessai_ = true;
      attente_ = false;
    } else {
      finir(Issue::kDelai, maintenant);
    }
  }

  void finir(Issue issue, uint32_t maintenant) {
    actif_ = false;
    attente_ = false;
    issue_ = issue;
    finMs_ = maintenant;
  }

  bool actif_ = false;
  bool attente_ = false;  // une page est partie, sa reponse est attendue
  uint32_t debutMs_ = 0;
  uint32_t finMs_ = 0;
  uint32_t envoiMs_ = 0;
  uint32_t delaiPageMs_ = 0;
  uint32_t numero_ = 0;  // numero du dernier envoi
  uint8_t index_ = 0;
  uint8_t total_ = 0;
  bool totalConnu_ = false;
  bool recommence_ = false;
  bool reessai_ = false;  // la page en cours a deja ete redemandee
  bool partielle_ = false;
  uint8_t pages_ = 0;
  Issue issue_ = Issue::kEnCours;
  uint8_t statut_ = 0;
  size_t nombre_ = 0;
  Entree entrees_[N];
};
