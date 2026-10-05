#pragma once
// Verifications des tests hote de la sonde (sh sonde/test/lancer.sh) : chaque
// CHECK compte, un echec s'affiche avec sa ligne, et bilan() rend le code de
// sortie du programme de test.
#include <stdio.h>

static int gChecks = 0, gFails = 0;
#define CHECK(cond, ...)                            \
  do {                                              \
    gChecks++;                                      \
    if (!(cond)) {                                  \
      gFails++;                                     \
      printf("ECHEC %s:%d : ", __FILE__, __LINE__); \
      printf(__VA_ARGS__);                          \
      printf("\n");                                 \
    }                                               \
  } while (0)

static inline int bilan(const char *nom) {
  printf("%s : %d verifications, %d echec(s)\n", nom, gChecks, gFails);
  return gFails ? 1 : 0;
}
