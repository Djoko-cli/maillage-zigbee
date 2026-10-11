#include "cle_reseau.h"

#include "h1_proto.h"

bool deriverCle(const uint8_t aleaApp[32], const uint8_t aleaCarte[32], uint8_t cle[32]) {
  const h1::Part part = {aleaCarte, 32};
  return h1::hmacSha256(aleaApp, 32, &part, 1, cle);
}
