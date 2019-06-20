#include "platform.h"
#include <time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/resource.h>

#ifdef __APPLE__
#include <mach/mach_time.h>
#endif

uint64_t platform_monotonic_ns(void) {
#ifdef __APPLE__
    static mach_timebase_info_data_t s_timebase;
    if (s_timebase.denom == 0) {
        mach_timebase_info(&s_timebase);
    }
    uint64_t t = mach_absolute_time();
    return (t * s_timebase.numer) / s_timebase.denom;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((uint64_t)ts.tv_sec * 1000000000ULL) + (uint64_t)ts.tv_nsec;
#endif
}

size_t platform_resident_memory_bytes(void) {
    struct rusage usage;
    if (getrusage(RUSAGE_SELF, &usage) == 0) {
#ifdef __APPLE__
        return (size_t)usage.ru_maxrss; // On macOS ru_maxrss is in bytes
#else
        return (size_t)usage.ru_maxrss * 1024; // On Linux ru_maxrss is in kilobytes
#endif
    }
    return 0;
}

void platform_sleep_ms(uint32_t ms) {
    usleep((useconds_t)ms * 1000);
}

int platform_atomic_write(const char *path, const void *buf, size_t len) {
    char tmp_path[512];
    snprintf(tmp_path, sizeof(tmp_path), "%s.tmp.%d", path, (int)getpid());

    FILE *f = fopen(tmp_path, "wb");
    if (!f) return -1;

    if (len > 0 && buf != NULL) {
        size_t written = fwrite(buf, 1, len, f);
        if (written != len) {
            fclose(f);
            unlink(tmp_path);
            return -2;
        }
    }

    fflush(f);
    fsync(fileno(f));
    fclose(f);

    if (rename(tmp_path, path) != 0) {
        unlink(tmp_path);
        return -3;
    }

    return 0;
}
