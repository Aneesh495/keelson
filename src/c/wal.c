#include "wal.h"
#include "crc32.h"
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

wal_t *wal_open(const char *path, wal_sync_mode_t sync_mode) {
    wal_t *wal = (wal_t *)malloc(sizeof(wal_t));
    if (!wal) return NULL;

    memset(wal, 0, sizeof(wal_t));
    strncpy(wal->path, path, sizeof(wal->path) - 1);
    wal->sync_mode = sync_mode;

    // Open for reading and writing (append mode)
    wal->file = fopen(path, "a+b");
    if (!wal->file) {
        free(wal);
        return NULL;
    }

    return wal;
}

int wal_append(wal_t *wal, uint64_t lsn, uint64_t timestamp_ns, const void *payload, uint32_t len) {
    if (!wal || !wal->file) return -1;

    uint32_t payload_crc = keelson_crc32(0, payload, len);

    wal_header_t header;
    header.magic = KEELSON_WAL_MAGIC;
    header.version = KEELSON_WAL_VERSION;
    header.lsn = lsn;
    header.timestamp_ns = timestamp_ns;
    header.payload_len = len;
    header.crc32 = payload_crc;

    // Seek to end
    fseek(wal->file, 0, SEEK_END);

    // Write header
    size_t written_h = fwrite(&header, sizeof(wal_header_t), 1, wal->file);
    if (written_h != 1) return -2;

    // Write payload
    if (len > 0 && payload != NULL) {
        size_t written_p = fwrite(payload, 1, len, wal->file);
        if (written_p != len) return -3;
    }

    fflush(wal->file);

    if (wal->sync_mode == WAL_SYNC_IMMEDIATE) {
        fsync(fileno(wal->file));
    }

    wal->last_lsn = lsn;
    wal->total_records++;

    return 0;
}

int wal_recover(wal_t *wal, wal_record_fn callback, void *user_data) {
    if (!wal || !wal->file) return -1;

    // Rewind to beginning of log
    fseek(wal->file, 0, SEEK_SET);

    uint64_t count = 0;

    while (1) {
        wal_header_t header;
        size_t read_h = fread(&header, sizeof(wal_header_t), 1, wal->file);
        if (read_h == 0) {
            // Clean EOF
            break;
        }
        if (read_h != 1) {
            // Partial header (torn write), stop recovery
            break;
        }

        // Validate magic and version
        if (header.magic != KEELSON_WAL_MAGIC || header.version != KEELSON_WAL_VERSION) {
            // Corrupted header
            break;
        }

        // Read payload
        uint8_t *payload_buf = NULL;
        if (header.payload_len > 0) {
            payload_buf = (uint8_t *)malloc(header.payload_len);
            if (!payload_buf) break;

            size_t read_p = fread(payload_buf, 1, header.payload_len, wal->file);
            if (read_p != header.payload_len) {
                // Partial payload (torn write)
                free(payload_buf);
                break;
            }

            // Verify CRC32
            uint32_t actual_crc = keelson_crc32(0, payload_buf, header.payload_len);
            if (actual_crc != header.crc32) {
                // CRC mismatch (corrupted record)
                free(payload_buf);
                break;
            }
        }

        count++;
        wal->last_lsn = header.lsn;
        wal->total_records = count;

        int stop = 0;
        if (callback) {
            stop = callback(&header, payload_buf, user_data);
        }

        if (payload_buf) {
            free(payload_buf);
        }

        if (stop != 0) {
            break;
        }
    }

    return (int)count;
}

void wal_close(wal_t *wal) {
    if (!wal) return;
    if (wal->file) {
        fflush(wal->file);
        if (wal->sync_mode != WAL_SYNC_NONE) {
            fsync(fileno(wal->file));
        }
        fclose(wal->file);
        wal->file = NULL;
    }
    free(wal);
}
