#pragma once
// Modele de sonde/cle_hue.local.h (spec de la sonde, section 1).
//
// Copier ce fichier en sonde/cle_hue.local.h (ignore par git, jamais
// commite) et remplacer les zeros par les 16 octets de la cle de liaison du
// centre de confiance des ponts Hue (cle ZLL de Signify), puis l'ajouter a
// garde.local.txt. Tant que la cle est a zero, la compilation s'arrete
// (static_assert de sonde/src/zigbee.cpp).
#include <stdint.h>

static constexpr uint8_t kCleHue[16] = {
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
};
