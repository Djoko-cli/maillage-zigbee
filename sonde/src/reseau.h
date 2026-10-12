#pragma once
// ===========================================================================
//  Acces par le reseau de la sonde (spec sonde Wi-Fi, sections 3.2 a 3.6)
//
//  NVS (espace « reseau ») : nom et mot de passe du Wi-Fi, cle H1. Sans Wi-Fi
//  configure, rien ne demarre : la sonde est celle de la 1.0.0.
//  Demarrage (Wi-Fi configure) : gardeDemarrage() d'abord (sommeil profond de
//  0,2 s apres une reinitialisation qui n'est ni une mise sous tension ni un
//  reveil : la pile Zigbee laisse la radio sans reception Wi-Fi, essai du
//  10/10), puis demarrer() : cohabitation, connexion au Wi-Fi lancee, sans
//  l'attendre. loop() tourne pendant l'attente (demarrage.h : 15 s au plus,
//  l'USB repond) ; a sa fin, ouvrir() (economie d'energie minimale, serveur TCP
//  5481, cle, Bonjour), puis seulement la pile Zigbee.
//  Tout se fait dans la tache loop, jamais sous le verrou de la pile Zigbee.
// ===========================================================================
#include <stddef.h>
#include <stdint.h>

#include "ligne.h"
#include "portail.h"

namespace reseau {

static constexpr uint16_t kPort = 5481;

void gardeDemarrage();
bool configure();
// Vrai si le Wi-Fi est connecte, adresse IP obtenue.
bool connecte();
// Lance la connexion au Wi-Fi configure, sans l'attendre ; rien sans Wi-Fi configure.
void demarrer(const char *nomSonde);
// Fin de l'attente du Wi-Fi (connecte ou abandonnee), avant la pile Zigbee : economie d'energie, serveur TCP, cle
// (relue de la NVS : une cle creee pendant l'attente compte), Bonjour.
void ouvrir();
void tour(uint32_t maintenant);
// Nouveau nom de la sonde (commande nom) : l'annonce Bonjour est refaite sous ce nom.
void renommer(const char *nomSonde);
bool requete(Portail::Requete *r);
void repondre(uint8_t session, uint32_t rid, const uint8_t *ligne, size_t n);
void diffuser(const uint8_t *ligne, size_t n);
bool ecrireWifi(const uint8_t *nom, size_t nNom, const uint8_t *mdp, size_t nMdp);
bool effacerWifi();
void nomWifiHexa(char sortie[2 * 32 + 1]);
bool nouvelleCle(const uint8_t cle[32]);
bool effacerCle();
bool empreinte(char kid[9]);
// ,"reseau":{...} si le Wi-Fi est configure, rien sinon.
void ajouterEtat(Ligne &l);
// ,"sessions":..,"envois":..,"refus":..,"fermetures":..
void ajouterCompteurs(Ligne &l);

}  // namespace reseau
