#pragma once
// Options de compilation de la sonde, posees par platformio.ini (build_flags)
// ou par sonde/test/lancer.sh. Par defaut, les deux commandes de l'essai
// (spec de la sonde, section 4 : E4 et E5) sont actives ; 0 les retire, avec
// leur place dans la liste blanche. Le journal des signaux de la pile est
// actif aussi pendant l'essai ; la tache 9 du plan decide de le garder.
#ifndef SONDE_ROUTES
#define SONDE_ROUTES 1  // commande routes (Mgmt_Rtg_req en trame APS brute)
#endif
#ifndef SONDE_ECHECS
#define SONDE_ECHECS 1  // commande echecs (Mgmt_NWK_Update_req, balayage d'energie)
#endif
#ifndef SONDE_SIGNAUX
#define SONDE_SIGNAUX 1  // lignes « signal » : chaque signal de la pile, pour l'essai
#endif
