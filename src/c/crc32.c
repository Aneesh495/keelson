#include "crc32.h"

// Precomputed CRC32 table for IEEE 802.3 polynomial (0xEDB88320)
static uint32_t s_crc_table[256];
static int s_table_initialized = 0;

static void init_crc_table(void) {
    for (uint32_t i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++) {
            if (c & 1) {
                c = 0xEDB88320L ^ (c >> 1);
            } else {
                c = c >> 1;
            }
        }
        s_crc_table[i] = c;
    }
    s_table_initialized = 1;
}

uint32_t keelson_crc32(uint32_t initial, const void *buf, size_t len) {
    if (!s_table_initialized) {
        init_crc_table();
    }

    const uint8_t *p = (const uint8_t *)buf;
    uint32_t c = initial ^ 0xFFFFFFFFL;

    for (size_t i = 0; i < len; i++) {
        c = s_crc_table[(c ^ p[i]) & 0xFF] ^ (c >> 8);
    }

    return c ^ 0xFFFFFFFFL;
}
