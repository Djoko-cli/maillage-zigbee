// Colle avec la pile Zigbee d'Espressif : voir zigbee.h.
#include "zigbee.h"

#include <esp_err.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>
#include <string.h>

#include <atomic>

#include "aps/esp_zigbee_aps.h"
#include "esp_zigbee_core.h"
#include "ha/esp_zigbee_ha_standard.h"
#include "liste_blanche.h"
#include "nwk/esp_zigbee_nwk.h"
#include "esp_zigbee_version.h"
#include "options.h"
#include "version.h"
#include "zdo/esp_zigbee_zdo_command.h"

// Cle de liaison du centre de confiance Hue : fichier local, jamais dans le
// depot (spec, section 1 ; sonde/README.md). La variante de verification
// (verif) compile avec une cle factice : elle ne rejoindrait aucun pont, et
// outils/flasher.py refuse de la flasher.
#if defined(SONDE_CLE_FACTICE)
static constexpr uint8_t kCleHue[16] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                                        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10};
#elif __has_include("cle_hue.local.h")
#include "cle_hue.local.h"
#else
#error "sonde/cle_hue.local.h absent : copier sonde/cle_hue.exemple.h et y mettre la cle de liaison Hue (sonde/README.md)"
#endif

static constexpr bool cleRemplie(const uint8_t (&c)[16], int i = 0) {
  return i < 16 && (c[i] != 0 || cleRemplie(c, i + 1));
}
static_assert(cleRemplie(kCleHue), "sonde/cle_hue.local.h : la cle est encore a zero (sonde/README.md)");

namespace zigbee {
namespace {

constexpr uint8_t kPointAcces = 11;
// Canaux possibles d'un reseau Hue : 11, 15, 20 et 25.
constexpr uint32_t kCanauxHue = (1u << 11) | (1u << 15) | (1u << 20) | (1u << 25);
// Appareil final : maintien aupres du parent toutes les 10 s ; le parent
// l'oublie apres 64 minutes de silence.
constexpr uint32_t kMaintienMs = 10000;

QueueHandle_t sEvenements = nullptr;
QueueHandle_t sReponses = nullptr;
// Posee au premier signal de la pile (tache Zigbee), lue par loop().
std::atomic<bool> sPrete{false};

// Chaines ZCL : la longueur d'abord.
char sFabricant[] = "\x08"
                    "Maillage";
char sModele[] = "\x0C"
                 "sonde-zigbee";
char sVersionLogiciel[1 + 16] = {0};
bool sScenesGlobales = true;
uint16_t sDureeAllumage = 0;
uint16_t sAttenteExtinction = 0;

void pousser(Signal s, bool ok) {
  Evenement e;
  e.signal = s;
  e.ok = ok;
  xQueueSend(sEvenements, &e, 0);  // file pleine : evenement perdu (32 places ; le constat d'Adhesion rattrape)
}

void pousserBrut(uint8_t brut, bool ok, uint8_t detail, const char *nom) {
  Evenement e;
  e.signal = Signal::kBrut;
  e.ok = ok;
  e.brut = brut;
  e.detail = detail;
  e.nom = nom;
  xQueueSend(sEvenements, &e, 0);
}

void pousserReponse(const Reponse &r) { xQueueSend(sReponses, &r, 0); }  // pleine : la page sera redemandee

// --- Rappels de la tache Zigbee --------------------------------------------

void surVoisins(const esp_zb_zdo_mgmt_lqi_rsp_t *rsp, void *ctx) {
  static Reponse r;  // tache Zigbee seulement : pas sur sa pile
  r = Reponse();
  r.genre = Genre::kVoisins;
  r.numero = (uint32_t)(uintptr_t)ctx;
  if (!rsp) {
    r.statut = 0x85;
    pousserReponse(r);
    return;
  }
  r.statut = rsp->status;
  r.total = rsp->neighbor_table_entries;
  r.debut = rsp->start_index;
  if (r.statut == 0 && rsp->neighbor_table_list) {
    const uint8_t n = rsp->neighbor_table_list_count;
    r.nombre = n > kVoisinsParPageMax ? (uint8_t)kVoisinsParPageMax : n;
    for (uint8_t i = 0; i < r.nombre; i++) {
      const esp_zb_zdo_neighbor_table_list_record_t &s = rsp->neighbor_table_list[i];
      EntreeVoisin &e = r.voisins[i];
      memcpy(e.ieee, s.extended_addr, 8);
      e.court = s.network_addr;
      e.type = s.device_type;
      e.ecoute = s.rx_when_idle;
      e.relation = s.relationship;
      e.admission = s.permit_join;
      e.profondeur = s.depth;
      e.lqi = s.lqi;
    }
  }
  pousserReponse(r);
}

#if SONDE_ROUTES
// Mgmt_Rtg_req en attente de reponse (posee sous le verrou, lue par la tache
// Zigbee, qui tient le verrou quand elle appelle ses rappels).
struct AttenteRoutes {
  bool actif = false;
  uint8_t tsn = 0;
  uint16_t cible = 0;
  uint32_t numero = 0;
};
AttenteRoutes sAttenteRoutes;
uint8_t sTsn = 0x80;

// Mgmt_Rtg_rsp (cluster 0x8032) de la cible : lue dans la trame brute.
bool surIndicationAps(esp_zb_apsde_data_ind_t ind) {
  if (ind.profile_id != 0 || ind.cluster_id != (0x8000 | kZdoMgmtRtg)) return false;
  // Toute Mgmt_Rtg_rsp est a la sonde (la pile n'envoie jamais de
  // Mgmt_Rtg_req) : gardee meme tardive, pour que la pile ne la prenne pas
  // pour la reponse d'une de ses requetes au meme numero de transaction.
  if (!sAttenteRoutes.actif || ind.src_short_addr != sAttenteRoutes.cible || !ind.asdu) return true;
  PageRoutes p;
  if (!lirePageRoutes(ind.asdu, ind.asdu_length, &p) || p.tsn != sAttenteRoutes.tsn) return true;
  sAttenteRoutes.actif = false;
  // Rendue a l'appelant seulement : la pile ne doit pas la confondre avec la
  // reponse d'une de ses requetes (meme numero de transaction).
  static Reponse r;
  r = Reponse();
  r.genre = Genre::kRoutes;
  r.numero = sAttenteRoutes.numero;
  r.statut = p.statut;
  r.total = p.total;
  r.debut = p.debut;
  r.nombre = p.nombre;
  for (uint8_t i = 0; i < p.nombre; i++) r.routes[i] = p.entrees[i];
  pousserReponse(r);
  return true;
}
#endif

#if SONDE_ECHECS
void surEchecs(const esp_zb_zdo_mgmt_update_notify_t *n, void *ctx) {
  static Reponse r;
  r = Reponse();
  r.genre = Genre::kEchecs;
  r.numero = (uint32_t)(uintptr_t)ctx;
  if (!n) {
    r.statut = 0x85;
  } else {
    r.statut = n->status;
    r.total = 1;
    r.nombre = n->status == 0 ? 1 : 0;
    r.emissions = n->total_transmission;
    r.echecs = n->transmission_failures;
    r.energie = n->scanned_channels_list_count ? n->energy_values[0] : 0;
  }
  pousserReponse(r);
}
#endif

esp_err_t surAction(esp_zb_core_action_callback_id_t id, const void *message) {
  if (!message) return ESP_OK;
  if (id == ESP_ZB_CORE_SET_ATTR_VALUE_CB_ID) {
    const esp_zb_zcl_set_attr_value_message_t *m = (const esp_zb_zcl_set_attr_value_message_t *)message;
    if (m->info.status == ESP_ZB_ZCL_STATUS_SUCCESS && m->info.dst_endpoint == kPointAcces &&
        m->info.cluster == ESP_ZB_ZCL_CLUSTER_ID_ON_OFF && m->attribute.id == ESP_ZB_ZCL_ATTR_ON_OFF_ON_OFF_ID &&
        m->attribute.data.type == ESP_ZB_ZCL_ATTR_TYPE_BOOL && m->attribute.data.value)
      pousser(Signal::kLampe, *(const bool *)m->attribute.data.value);
  } else if (id == ESP_ZB_CORE_IDENTIFY_EFFECT_CB_ID) {
    const esp_zb_zcl_identify_effect_message_t *m = (const esp_zb_zcl_identify_effect_message_t *)message;
    // 0xFE : finir l'effet ; 0xFF : l'arreter.
    pousser(Signal::kEffet, m->effect_id != 0xFE && m->effect_id != 0xFF);
  }
  return ESP_OK;
}

void surIdentification(uint8_t actif) { pousser(Signal::kIdentification, actif != 0); }

void tacheZigbee(void *) {
  ESP_ERROR_CHECK(esp_zb_start(false));
  // Apres esp_zb_start (en-tete de la pile) : alimentation secteur.
  esp_zb_set_node_descriptor_power_source(true);
  esp_zb_stack_main_loop();
}

void creerPointAcces() {
  const size_t n = strlen(SONDE_VERSION);
  sVersionLogiciel[0] = (char)n;
  memcpy(sVersionLogiciel + 1, SONDE_VERSION, n);

  esp_zb_on_off_light_cfg_t config = ESP_ZB_DEFAULT_ON_OFF_LIGHT_CONFIG();
  config.basic_cfg.power_source = ESP_ZB_ZCL_BASIC_POWER_SOURCE_MAINS_SINGLE_PHASE;
  esp_zb_cluster_list_t *grappes = esp_zb_on_off_light_clusters_create(&config);
  esp_zb_attribute_list_t *base =
      esp_zb_cluster_list_get_cluster(grappes, ESP_ZB_ZCL_CLUSTER_ID_BASIC, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_MANUFACTURER_NAME_ID, sFabricant);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_MODEL_IDENTIFIER_ID, sModele);
  esp_zb_basic_cluster_add_attr(base, ESP_ZB_ZCL_ATTR_BASIC_SW_BUILD_ID, sVersionLogiciel);
  // Le pont Hue envoie « Off with effect » : attributs de la grappe On/Off
  // qu'il attend (constate par d'autres avant nous).
  esp_zb_attribute_list_t *marche =
      esp_zb_cluster_list_get_cluster(grappes, ESP_ZB_ZCL_CLUSTER_ID_ON_OFF, ESP_ZB_ZCL_CLUSTER_SERVER_ROLE);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_GLOBAL_SCENE_CONTROL, &sScenesGlobales);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_ON_TIME, &sDureeAllumage);
  esp_zb_on_off_cluster_add_attr(marche, ESP_ZB_ZCL_ATTR_ON_OFF_OFF_WAIT_TIME, &sAttenteExtinction);

  esp_zb_endpoint_config_t pa = {};
  pa.endpoint = kPointAcces;
  pa.app_profile_id = ESP_ZB_AF_HA_PROFILE_ID;
  pa.app_device_id = ESP_ZB_HA_ON_OFF_LIGHT_DEVICE_ID;  // On/Off Light (0x0100), acceptee par le pont (E1)
  pa.app_device_version = 1;  // exige par le pont Hue
  esp_zb_ep_list_t *liste = esp_zb_ep_list_create();
  esp_zb_ep_list_add_ep(liste, grappes, pa);
  ESP_ERROR_CHECK(esp_zb_device_register(liste));
}

}  // namespace


void demarrer() {
  sEvenements = xQueueCreate(32, sizeof(Evenement));
  sReponses = xQueueCreate(4, sizeof(Reponse));

  esp_zb_platform_config_t plateforme = {};
  plateforme.radio_config.radio_mode = ZB_RADIO_MODE_NATIVE;
  plateforme.host_config.host_connection_mode = ZB_HOST_CONNECTION_MODE_NONE;
  ESP_ERROR_CHECK(esp_zb_platform_config(&plateforme));

  esp_zb_cfg_t config = {};
  config.install_code_policy = false;
  // Appareil final, jamais routeur : la sonde ne relaie le trafic de
  // personne (decision de Majid, 07/10).
  config.esp_zb_role = ESP_ZB_DEVICE_TYPE_ED;
  config.nwk_cfg.zed_cfg.ed_timeout = ESP_ZB_ED_AGING_TIMEOUT_64MIN;
  config.nwk_cfg.zed_cfg.keep_alive = kMaintienMs;
  esp_zb_init(&config);

  creerPointAcces();
  esp_zb_core_action_handler_register(surAction);
  esp_zb_identify_notify_handler_register(kPointAcces, surIdentification);
#if SONDE_ROUTES
  esp_zb_aps_data_indication_handler_register(surIndicationAps);
#endif
  ESP_ERROR_CHECK(esp_zb_set_primary_network_channel_set(kCanauxHue));
  // Le jeu secondaire vaut par defaut les autres canaux (BDB) : sans cela, le rattachement pourrait
  // rejoindre un reseau ouvert etranger hors des canaux Hue.
  ESP_ERROR_CHECK(esp_zb_set_secondary_network_channel_set(kCanauxHue));
  // Adhesion au pont Hue : la cle de liaison de Signify (ZLL).
  esp_zb_enable_joining_to_distributed(true);
  esp_zb_secur_TC_standard_distributed_key_set((uint8_t *)kCleHue);
  esp_zb_set_rx_on_when_idle(true);  // appareil final non endormi

  xTaskCreate(tacheZigbee, "zigbee", 8192, nullptr, 5, nullptr);
}

bool prete() { return sPrete; }
bool verrou(uint32_t ms) { return sPrete && esp_zb_lock_acquire(pdMS_TO_TICKS(ms)); }
void libere() { esp_zb_lock_release(); }

bool rattachee() { return esp_zb_bdb_dev_joined(); }
void ieee(uint8_t sortie[8]) { esp_zb_get_long_address(sortie); }
uint16_t court() { return esp_zb_get_short_address(); }
uint16_t pan() { return esp_zb_get_pan_id(); }
void epid(uint8_t sortie[8]) { esp_zb_get_extended_pan_id(sortie); }
uint8_t canal() { return esp_zb_get_current_channel(); }

bool voisinSuivant(uint16_t *iterateur, VoisinSonde *v) {
  esp_zb_nwk_info_iterator_t i = *iterateur;
  esp_zb_nwk_neighbor_info_t n = {};
  if (esp_zb_nwk_get_next_neighbor(&i, &n) != ESP_OK) return false;
  *iterateur = i;
  memcpy(v->ieee, n.ieee_addr, 8);
  v->court = n.short_addr;
  v->type = n.device_type;
  v->relation = n.relationship;
  v->lqi = n.lqi;
  v->rssi = n.rssi;
  v->coutSortant = n.outgoing_cost;
  v->age = n.age;
  return true;
}

bool envoyerVoisins(uint16_t cible, uint8_t index, uint32_t numero) {
  if (!requetePermise(kZdoMgmtLqi, cible)) return false;
  esp_zb_zdo_mgmt_lqi_req_param_t req = {};
  req.start_index = index;
  req.dst_addr = cible;
  esp_zb_zdo_mgmt_lqi_req(&req, surVoisins, (void *)(uintptr_t)numero);
  return true;
}

bool envoyerRoutes(uint16_t cible, uint8_t index, uint32_t numero) {
#if SONDE_ROUTES
  if (!requetePermise(kZdoMgmtRtg, cible)) return false;
  static uint8_t asdu[2];
  if (++sTsn < 0x80) sTsn = 0x80;  // 0x80 a 0xFF : loin des numeros de la pile
  requeteRoutes(sTsn, index, asdu);
  esp_zb_apsde_data_req_t req = {};
  req.dst_addr_mode = ESP_ZB_APS_ADDR_MODE_16_ENDP_PRESENT;
  req.dst_addr.addr_short = cible;
  req.dst_endpoint = 0;
  req.profile_id = 0;
  req.cluster_id = kZdoMgmtRtg;
  req.src_endpoint = 0;
  req.asdu_length = sizeof(asdu);
  req.asdu = asdu;
  req.tx_options = 0;
  req.use_alias = false;
  req.radius = 0;
  sAttenteRoutes.actif = true;
  sAttenteRoutes.tsn = sTsn;
  sAttenteRoutes.cible = cible;
  sAttenteRoutes.numero = numero;
  if (esp_zb_aps_data_request(&req) != ESP_OK) {
    sAttenteRoutes.actif = false;
    return false;
  }
  return true;
#else
  (void)cible;
  (void)index;
  (void)numero;
  return false;
#endif
}

bool envoyerEchecs(uint16_t cible, uint32_t numero) {
#if SONDE_ECHECS
  const uint8_t c = esp_zb_get_current_channel();
  if (c < 11 || c > 26) return false;
  esp_zb_zdo_mgmt_nwk_update_req_param_t req = {};
  req.scan_channels = 1u << c;
  req.scan_duration = 0;
  req.scan_count = 1;
  req.nwk_manager_addr = 0;
  req.dst_addr = cible;
  if (!requetePermise(kZdoMgmtNwkUpdate, cible) ||
      !balayagePermis(req.scan_channels, req.scan_duration, c))
    return false;
  esp_zb_zdo_mgmt_nwk_update_req(&req, surEchecs, (void *)(uintptr_t)numero);
  return true;
#else
  (void)cible;
  (void)numero;
  return false;
#endif
}

void initialiser() { esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION); }

void chercher() {
  if (esp_zb_bdb_dev_joined()) {
    pousser(Signal::kRecherche, true);
    return;
  }
  esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_NETWORK_STEERING);
}
void quitter() { esp_zb_bdb_reset_via_local_action(); }
void oublier() { esp_zb_factory_reset(); }

void versionPile(char *sortie, size_t taille) {
  snprintf(sortie, taille, "%d.%d.%d", ESP_ZB_VER_MAJOR, ESP_ZB_VER_MINOR, ESP_ZB_VER_PATCH);
}

bool evenement(Evenement *e) { return sEvenements && xQueueReceive(sEvenements, e, 0) == pdTRUE; }
bool reponse(Reponse *r) { return sReponses && xQueueReceive(sReponses, r, 0) == pdTRUE; }

}  // namespace zigbee

// Signaux de la pile (tache Zigbee) : l'initialisation repond tout de suite ;
// le reste part a loop() par la file.
extern "C" void esp_zb_app_signal_handler(esp_zb_app_signal_t *signal) {
  using zigbee::Signal;
  uint32_t *p = signal->p_app_signal;
  const bool ok = signal->esp_err_status == ESP_OK;
  const esp_zb_app_signal_type_t type = (esp_zb_app_signal_type_t)*p;
  uint8_t detail = 0;
  switch (type) {
    case ESP_ZB_ZDO_SIGNAL_SKIP_STARTUP:
      zigbee::sPrete = true;
      // Initialisation refusee : comme un premier demarrage en echec, relance
      // par Adhesion une seconde plus tard.
      if (esp_zb_bdb_start_top_level_commissioning(ESP_ZB_BDB_MODE_INITIALIZATION) != ESP_OK)
        zigbee::pousser(Signal::kPremierDemarrage, false);
      break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_FIRST_START: zigbee::pousser(Signal::kPremierDemarrage, ok); break;
    case ESP_ZB_BDB_SIGNAL_DEVICE_REBOOT: zigbee::pousser(Signal::kRedemarrage, ok); break;
    case ESP_ZB_BDB_SIGNAL_STEERING: zigbee::pousser(Signal::kRecherche, ok); break;
    case ESP_ZB_BDB_SIGNAL_TC_REJOIN_DONE: zigbee::pousser(Signal::kRattachementTc, ok); break;
    case ESP_ZB_NLME_STATUS_INDICATION: {
      const esp_zb_zdo_signal_nwk_status_indication_params_t *s =
          (const esp_zb_zdo_signal_nwk_status_indication_params_t *)esp_zb_app_signal_get_params(p);
      if (s) detail = s->status;
      if (s && s->status == ESP_ZB_NWK_COMMAND_STATUS_PARENT_LINK_FAILURE)
        zigbee::pousser(Signal::kParentPerdu, true);
      break;
    }
    case ESP_ZB_ZDO_SIGNAL_LEAVE: {
      const esp_zb_zdo_signal_leave_params_t *d =
          (const esp_zb_zdo_signal_leave_params_t *)esp_zb_app_signal_get_params(p);
      if (d) detail = d->leave_type;
      zigbee::pousser(Signal::kDepart, d && d->leave_type == ESP_ZB_NWK_LEAVE_TYPE_REJOIN);
      break;
    }
    default: break;
  }
  // Tout signal, pour le journal de l'essai : on y verra ce que la pile fait
  // a la perte du parent, au depart, au rattachement.
#if SONDE_SIGNAUX
  zigbee::pousserBrut((uint8_t)type, ok, detail, esp_zb_zdo_signal_to_string(type));
#endif
}
