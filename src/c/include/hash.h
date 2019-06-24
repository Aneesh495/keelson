#ifndef KEELSON_HASH_H
#define KEELSON_HASH_H

#include <stdint.h>
#include <stddef.h>

// Calculates 64-bit FNV-1a hash of a buffer.
uint64_t keelson_hash64(const void *data, size_t len);

// Formats a 64-bit hash as a 16-character hexadecimal string with null terminator.
void keelson_hash_to_hex(uint64_t hash, char out_hex[17]);

#endif // KEELSON_HASH_H
