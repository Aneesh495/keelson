#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "hash.h"

int main(void) {
    printf("=== Test: C Native 64-bit Hash ===\n");

    const char *msg1 = "order-saga-100";
    const char *msg2 = "order-saga-101";

    uint64_t h1 = keelson_hash64(msg1, strlen(msg1));
    uint64_t h2 = keelson_hash64(msg2, strlen(msg2));

    assert(h1 != 0);
    assert(h2 != 0);
    assert(h1 != h2);

    char hex[17];
    keelson_hash_to_hex(h1, hex);
    assert(strlen(hex) == 16);

    printf("  [OK] Hash of '%s' -> %s\n", msg1, hex);
    printf("All C Hash tests passed successfully.\n");
    return 0;
}
