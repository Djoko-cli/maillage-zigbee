#pragma once
// ===========================================================================
//  Cle de l'acces par le reseau (spec sonde Wi-Fi, 3.5)
//
//  cle = HMAC-SHA256(cle = alea de l'app, message = alea de la carte). L'app
//  tire le sien, la carte le sien : ni l'une ni l'autre ne fixe seule la cle.
//  Empreinte : le kid H1 (h1::keyId, 8 hexa de SHA-256 de la cle).
//
//  Pur : teste sur l'hote (sonde/test/test_cle_reseau.cpp).
// ===========================================================================
#include <stdint.h>

bool deriverCle(const uint8_t aleaApp[32], const uint8_t aleaCarte[32], uint8_t cle[32]);
