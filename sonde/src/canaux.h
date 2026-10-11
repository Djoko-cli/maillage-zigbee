#pragma once
// ===========================================================================
//  Canaux de la sonde (spec sonde Wi-Fi, 3.3) : l'USB et les sessions reseau
//
//  Origine : qui a pose la question (l'USB, ou une session reseau et son rid) ;
//  la reponse ne va qu'a elle. Les signaux vont a tous (main.cpp).
//  Requete reseau : « <rid> <commande> », rid decimal 1..4294967295 sans zero
//  de tete, une espace, puis la commande de l'USB (1 a 255 caracteres ASCII
//  imprimables). Reponse : « <rid> » puis la ligne de l'USB sans RS ni LF.
//
//  Pur : teste sur l'hote (sonde/test/test_canaux.cpp).
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "commande.h"

static constexpr size_t kCommandeMax = 255;

struct Origine {
  bool reseau = false;  // false : l'USB
  uint8_t session = 0;  // emplacement de la session H1
  uint32_t rid = 0;
};

// Lecture et suspension seulement : ni nom, ni oubli, ni configuration.
bool distanceAutorisee(TypeCommande t);

bool lireRequete(const uint8_t *charge, size_t n, uint32_t *rid, char commande[kCommandeMax + 1]);

// 0 si la reponse ne tient pas dans taille octets.
size_t chargeReponse(uint32_t rid, const uint8_t *ligne, size_t n, uint8_t *sortie, size_t taille);
