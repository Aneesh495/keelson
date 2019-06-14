#ifndef KEELSON_WAL_H
#define KEELSON_WAL_H

#include <stdint.h>
#include <stddef.h>
#include <stdio.h>

#define KEELSON_WAL_MAGIC 0x4B45454CU // 'KEEL' in big-endian ASCII
#define KEELSON_WAL_VERSION 1U
#define KEELSON_WAL_HEADER_SIZE 32U

typedef enum {
    WAL_SYNC_NONE = 0,
    WAL_SYNC_BATCH = 1,
    WAL_SYNC_IMMEDIATE = 2
} wal_sync_mode_t;

typedef struct {
    uint32_t magic;
    uint32_t version;
    uint64_t lsn;
    uint64_t timestamp_ns;
    uint32_t payload_len;
    uint32_t crc32;
} wal_header_t;

typedef struct {
    FILE *file;
    char path[512];
    uint64_t last_lsn;
    uint64_t total_records;
    wal_sync_mode_t sync_mode;
} wal_t;

// Callback signature for replaying records during recovery.
// Returning 0 continues replay, non-zero stops.
typedef int (*wal_record_fn)(const wal_header_t *header, const void *payload, void *user_data);

// Opens or creates a WAL segment file.
wal_t *wal_open(const char *path, wal_sync_mode_t sync_mode);

// Appends a record to the WAL.
int wal_append(wal_t *wal, uint64_t lsn, uint64_t timestamp_ns, const void *payload, uint32_t len);

// Recovers and replays all valid records from the WAL, verifying CRC32 checksums.
int wal_recover(wal_t *wal, wal_record_fn callback, void *user_data);

// Closes and flushes the WAL.
void wal_close(wal_t *wal);

#endif // KEELSON_WAL_H
