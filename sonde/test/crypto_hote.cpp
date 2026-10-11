// Crypto de l'enveloppe H1 pour les tests hote : CommonCrypto (macOS). Sur la
// carte : mbedTLS (sonde/src/h1_crypto.cpp).
#include <CommonCrypto/CommonDigest.h>
#include <CommonCrypto/CommonHMAC.h>

#include "h1_proto.h"

namespace h1 {
bool hmacSha256(const uint8_t *key, size_t keyLen, const Part *parts, size_t nParts, uint8_t out[32]) {
  CCHmacContext c;
  CCHmacInit(&c, kCCHmacAlgSHA256, key, keyLen);
  for (size_t i = 0; i < nParts; i++) CCHmacUpdate(&c, parts[i].p, parts[i].n);
  CCHmacFinal(&c, out);
  return true;
}
bool sha256(const void *p, size_t n, uint8_t out[32]) {
  CC_SHA256(p, (CC_LONG)n, out);
  return true;
}
}  // namespace h1
