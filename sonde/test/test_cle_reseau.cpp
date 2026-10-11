// Tests hote de sonde/src/cle_reseau.{h,cpp} : derivation de la cle de l'acces par
// le reseau. Vecteur calcule en Python (hmac, hashlib) le 11/10/2026.
// Lancer : sh sonde/test/lancer.sh
#include <string.h>

#include "cle_reseau.h"
#include "h1_proto.h"
#include "verif.h"

int main() {
  uint8_t app[32], carte[32], cle[32];
  for (int i = 0; i < 32; i++) {
    app[i] = (uint8_t)i;
    carte[i] = (uint8_t)(32 + i);
  }
  CHECK(deriverCle(app, carte, cle), "derivation");
  char hexa[65];
  h1::toHex(cle, 32, hexa);
  CHECK(strcmp(hexa, "62215DE7BDDCEA7E2C4047FF6BB94F8D18262FC8B3F3648134BB7D44158FF84D") == 0, "cle : %s", hexa);
  char kid[9];
  CHECK(h1::keyId(cle, kid) && strcmp(kid, "91CB5C39") == 0, "empreinte : %s", kid);
  return bilan("test_cle_reseau");
}
