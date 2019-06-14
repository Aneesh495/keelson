#include <stdio.h>
#include <string.h>
#include <assert.h>
#include <unistd.h>
#include "wal.h"

typedef struct {
    int count;
    uint64_t last_lsn;
} test_context_t;

static int on_record(const wal_header_t *h, const void *payload, void *data) {
    test_context_t *ctx = (test_context_t *)data;
    ctx->count++;
    ctx->last_lsn = h->lsn;

    if (h->lsn == 1) {
        assert(strcmp((const char *)payload, "{\"event\":\"WorkflowStarted\"}") == 0);
    } else if (h->lsn == 2) {
        assert(strcmp((const char *)payload, "{\"event\":\"ActivityCompleted\",\"txId\":42}") == 0);
    }
    return 0;
}

int main(void) {
    printf("=== Test: C Native Binary WAL Engine ===\n");
    const char *wal_path = "/tmp/keelson_test.wal";
    unlink(wal_path);

    // 1. Open and append records
    wal_t *wal = wal_open(wal_path, WAL_SYNC_IMMEDIATE);
    assert(wal != NULL);

    const char *payload1 = "{\"event\":\"WorkflowStarted\"}";
    int rc1 = wal_append(wal, 1, 1000000000ULL, payload1, strlen(payload1) + 1);
    assert(rc1 == 0);

    const char *payload2 = "{\"event\":\"ActivityCompleted\",\"txId\":42}";
    int rc2 = wal_append(wal, 2, 1050000000ULL, payload2, strlen(payload2) + 1);
    assert(rc2 == 0);

    wal_close(wal);
    printf("  [OK] Successfully appended 2 binary records with CRC32 headers\n");

    // 2. Re-open and recover records
    wal = wal_open(wal_path, WAL_SYNC_NONE);
    assert(wal != NULL);

    test_context_t ctx = {0, 0};
    int recovered = wal_recover(wal, on_record, &ctx);

    assert(recovered == 2);
    assert(ctx.count == 2);
    assert(ctx.last_lsn == 2);
    printf("  [OK] Recovered 2 records with verified CRC32 checksums\n");

    wal_close(wal);
    unlink(wal_path);

    printf("All C Binary WAL tests passed successfully.\n");
    return 0;
}
