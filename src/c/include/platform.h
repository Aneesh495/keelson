#ifndef KEELSON_PLATFORM_H
#define KEELSON_PLATFORM_H

#include <stdint.h>
#include <stddef.h>

// Returns the current monotonic clock timestamp in nanoseconds.
uint64_t platform_monotonic_ns(void);

// Returns current resident set size (RSS) in bytes.
size_t platform_resident_memory_bytes(void);

// Sleeps the current thread for the specified milliseconds.
void platform_sleep_ms(uint32_t ms);

// Writes a buffer to a file atomically via temporary file and rename.
int platform_atomic_write(const char *path, const void *buf, size_t len);

#endif // KEELSON_PLATFORM_H
