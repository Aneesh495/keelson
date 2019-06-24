#include "hash.h"
#include <stdio.h>

#define FNV_OFFSET_BASIS 14695981039346656037ULL
#define FNV_PRIME        1099511628211ULL

uint64_t keelson_hash64(const void *data, size_t len) {
    const uint8_t *bytes = (const uint8_t *)data;
    uint64_t hash = FNV_OFFSET_BASIS;

    for (size_t i = 0; i < len; i++) {
        hash ^= (uint64_t)bytes[i];
        hash *= FNV_PRIME;
    }

    return hash;
}

void keelson_hash_to_hex(uint64_t hash, char out_hex[17]) {
    snprintf(out_hex, 17, "%016llx", (unsigned long long)hash);
}
