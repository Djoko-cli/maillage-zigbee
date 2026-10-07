#pragma once
// Options de compilation de la sonde, posees par platformio.ini (build_flags)
// ou par sonde/test/lancer.sh. Par defaut, celles de la sonde 1.0.0, decidees
// apres l'essai (spec de la sonde, section 8) : routes gardee (E4), echecs
// retiree (E5), lignes signal gardees. 0 retire une commande avec sa place
// dans la liste blanche ; le code d'echecs reste, teste par lancer.sh.
#ifndef SONDE_ROUTES
#define SONDE_ROUTES 1  // commande routes (Mgmt_Rtg_req en trame APS brute)
#endif
#ifndef SONDE_ECHECS
#define SONDE_ECHECS 0  // commande echecs (Mgmt_NWK_Update_req, balayage d'energie)
#endif
#ifndef SONDE_SIGNAUX
#define SONDE_SIGNAUX 1  // lignes « signal » : chaque signal de la pile, pour le journal
#endif
