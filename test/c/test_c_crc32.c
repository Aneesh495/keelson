#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "crc32.h"

int main(void) {
    printf("=== Test: C Native CRC32 Integrity ===\n");

    // Test vector 1: Standard ASCII "123456789" -> CRC32 0xCBF43926
    const char *test_str = "123456789";
    uint32_t crc1 = keelson_crc32(0, test_str, strlen(test_str));
    assert(crc1 == 0xCBF43926);
    printf("  [OK] Standard vector '123456789' matches 0xCBF43926\n");

    // Test vector 2: Empty buffer -> 0
    uint32_t crc_empty = keelson_crc32(0, "", 0);
    assert(crc_empty == 0);
    printf("  [OK] Empty buffer returns 0\n");

    // Test vector 3: Chunked calculation matches single pass
    const char *part1 = "1234";
    const char *part2 = "56789";
    uint32_t crc_chunk = keelson_crc32(0, part1, strlen(part1));
    crc_chunk = keelson_crc32(crc_chunk, part2, strlen(part2));
    assert(crc_chunk == crc1);
    printf("  [OK] Chunked calculation matches contiguous stream\n");

    printf("All C CRC32 tests passed successfully.\n");
    return 0;
}
