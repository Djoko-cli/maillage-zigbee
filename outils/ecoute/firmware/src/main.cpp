// Essai jetable : ecoute passive 802.15.4, sans jamais emettre.
//
// Sortie USB, une ligne par evenement :
//   F <canal> <rssi> <lqi> <t_us> <hex>   trame recue (sans le FCS)
//   S <canal> <recues> <perdues> <ack_tx> <enh_ack>   etat, toutes les 5 s
//   I <texte>                             information
// Entree USB : "c <11..26>" change de canal.
//
// Surete : le pilote acquitte par defaut toute trame qui demande un accuse,
// meme en mode promiscuite. On coupe l'acquittement automatique (simple et
// ameliore) apres esp_ieee802154_enable(), qui remet la PIB a ses defauts,
// et on le verifie dans chaque ligne S. La sonde n'appelle jamais transmit.

#include <Arduino.h>
#include "esp_ieee802154.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"

extern "C" {
// Definies dans libieee802154.a, absentes de l'en-tete public.
esp_err_t esp_ieee802154_set_auto_ack_tx(bool enable);
bool esp_ieee802154_get_auto_ack_tx(void);
void ieee802154_pib_set_enhance_ack_tx(bool enable);
bool ieee802154_pib_get_enhance_ack_tx(void);
}

struct Trame {
  uint8_t len;
  uint8_t canal;
  int8_t rssi;
  uint8_t lqi;
  uint64_t t_us;
  uint8_t data[127];
};

static QueueHandle_t s_file;
static volatile uint32_t s_recues = 0;
static volatile uint32_t s_perdues = 0;
static uint8_t s_canal = 11;

static void IRAM_ATTR rx_done(uint8_t *frame, esp_ieee802154_frame_info_t *info) {
  Trame t;
  uint8_t len = frame[0];
  if (len > 127) len = 127;
  t.len = len;
  t.canal = info->channel;
  t.rssi = info->rssi;
  t.lqi = info->lqi;
  t.t_us = info->timestamp;
  memcpy(t.data, frame + 1, len);
  esp_ieee802154_receive_handle_done(frame);
  s_recues++;
  BaseType_t reveil = pdFALSE;
  if (xQueueSendFromISR(s_file, &t, &reveil) != pdTRUE) s_perdues++;
  portYIELD_FROM_ISR(reveil);
}

static void regler_radio() {
  esp_ieee802154_set_auto_ack_tx(false);
  ieee802154_pib_set_enhance_ack_tx(false);
  esp_ieee802154_set_promiscuous(true);
  esp_ieee802154_set_coordinator(false);
  esp_ieee802154_set_rx_when_idle(true);
  esp_ieee802154_set_channel(s_canal);
  esp_ieee802154_receive();
}

static void ecrire_etat() {
  Serial.printf("S %u %lu %lu %d %d\n", s_canal, (unsigned long)s_recues,
                (unsigned long)s_perdues, esp_ieee802154_get_auto_ack_tx() ? 1 : 0,
                ieee802154_pib_get_enhance_ack_tx() ? 1 : 0);
}

void setup() {
  Serial.begin(115200);
  s_file = xQueueCreate(128, sizeof(Trame));
  esp_ieee802154_event_cb_list_t cbs = {};
  cbs.rx_done_cb = rx_done;
  esp_ieee802154_event_callback_list_register(cbs);
  esp_ieee802154_enable();
  regler_radio();
  delay(200);
  Serial.println("I ecoute-802154 essai 0.1");
  ecrire_etat();
}

static char s_ligne[32];
static size_t s_pos = 0;

static void lire_commandes() {
  while (Serial.available()) {
    int c = Serial.read();
    if (c == '\n' || c == '\r') {
      s_ligne[s_pos] = 0;
      if (s_ligne[0] == 'c' && s_ligne[1] == ' ') {
        int n = atoi(s_ligne + 2);
        if (n >= 11 && n <= 26) {
          s_canal = (uint8_t)n;
          regler_radio();
          ecrire_etat();
        } else {
          Serial.println("I canal refuse");
        }
      }
      s_pos = 0;
    } else if (s_pos < sizeof(s_ligne) - 1) {
      s_ligne[s_pos++] = (char)c;
    }
  }
}

void loop() {
  static const char hexa[] = "0123456789ABCDEF";
  static char sortie[300];
  static uint32_t dernier_etat = 0;
  Trame t;
  while (xQueueReceive(s_file, &t, pdMS_TO_TICKS(20)) == pdTRUE) {
    int n = snprintf(sortie, sizeof(sortie), "F %u %d %u %llu ", t.canal, t.rssi, t.lqi,
                     (unsigned long long)t.t_us);
    uint8_t utile = t.len >= 2 ? t.len - 2 : 0;
    for (uint8_t i = 0; i < utile && n < (int)sizeof(sortie) - 3; i++) {
      sortie[n++] = hexa[t.data[i] >> 4];
      sortie[n++] = hexa[t.data[i] & 0xF];
    }
    sortie[n++] = '\n';
    Serial.write((const uint8_t *)sortie, n);
  }
  lire_commandes();
  if (millis() - dernier_etat > 5000) {
    dernier_etat = millis();
    ecrire_etat();
  }
}
