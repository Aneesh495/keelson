#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include "platform.h"

int main(void) {
    printf("=== Test: C Native Platform Primitives ===\n");

    // 1. Monotonic clock
    uint64_t t1 = platform_monotonic_ns();
    platform_sleep_ms(10);
    uint64_t t2 = platform_monotonic_ns();

    assert(t2 > t1);
    assert((t2 - t1) >= 8000000ULL); // At least 8ms
    printf("  [OK] Monotonic clock advanced by %llu ns\n", (unsigned long long)(t2 - t1));

    // 2. Memory query
    size_t rss = platform_resident_memory_bytes();
    assert(rss > 0);
    printf("  [OK] Resident memory size: %zu bytes\n", rss);

    // 3. Atomic file write
    const char *test_path = "/tmp/keelson_atomic_test.txt";
    const char *payload = "keelson atomic payload\n";
    int rc = platform_atomic_write(test_path, payload, strlen(payload));
    assert(rc == 0);

    FILE *f = fopen(test_path, "rb");
    assert(f != NULL);
    char buf[64];
    size_t r = fread(buf, 1, sizeof(buf) - 1, f);
    buf[r] = '\0';
    fclose(f);
    assert(strcmp(buf, payload) == 0);
    unlink(test_path);
    printf("  [OK] Atomic write-rename verified with byte match\n");

    printf("All C Platform tests passed successfully.\n");
    return 0;
}
