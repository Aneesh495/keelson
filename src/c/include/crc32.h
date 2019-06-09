#ifndef KEELSON_CRC32_H
#define KEELSON_CRC32_H

#include <stddef.h>
#include <stdint.h>

// Calculates the 32-bit CRC (IEEE 802.3 standard polynomial 0xEDB88320)
// over a buffer of bytes. Used for binary WAL integrity validation.
uint32_t keelson_crc32(uint32_t initial, const void *buf, size_t len);

#endif // KEELSON_CRC32_H
