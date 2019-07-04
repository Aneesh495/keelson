#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "wren_vm.h"
#include "wal.h"
#include "http_server.h"
#include "platform.h"

#define KEELSON_VERSION "1.0.0"

static void print_usage(void) {
    printf("Keelson: Resilient Durable Execution Engine (v%s)\n\n", KEELSON_VERSION);
    printf("Usage:\n");
    printf("  keelson run <script.wren>     Execute a Wren workflow script\n");
    printf("  keelson test                  Run all unit and integration test suites\n");
    printf("  keelson serve [--port <num>]  Start the HTTP API daemon\n");
    printf("  keelson recover <wal_path>    Inspect and recover binary WAL records\n");
    printf("  keelson version               Display engine version and build info\n");
}

static int wal_dump_cb(const wal_header_t *h, const void *payload, void *user_data) {
    (void)user_data;
    printf("  [LSN %llu] Timestamp: %lluns, Len: %u, CRC: 0x%08X\n",
           (unsigned long long)h->lsn,
           (unsigned long long)h->timestamp_ns,
           h->payload_len,
           h->crc32);
    if (payload && h->payload_len > 0) {
        printf("    Payload: %s\n", (const char *)payload);
    }
    return 0;
}

static void handle_health(const http_request_t *req, http_response_t *res, void *user_data) {
    (void)req;
    (void)user_data;
    res->status_code = 200;
    res->content_type = "application/json";
    res->body = "{\"status\":\"HEALTHY\",\"version\":\"" KEELSON_VERSION "\",\"engine\":\"keelson\"}";
    res->body_len = strlen(res->body);
}

int main(int argc, char **argv) {
    if (argc < 2) {
        print_usage();
        return 1;
    }

    const char *cmd = argv[1];

    if (strcmp(cmd, "version") == 0 || strcmp(cmd, "--version") == 0 || strcmp(cmd, "-v") == 0) {
        printf("keelson version %s (Wren VM 0.4.0, C99)\n", KEELSON_VERSION);
        return 0;
    }

    if (strcmp(cmd, "run") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: missing script path for 'run'\n");
            return 1;
        }
        keelson_vm_t *vm = keelson_vm_create("src/wren");
        if (!vm) {
            fprintf(stderr, "Failed to initialize Wren VM\n");
            return 2;
        }
        int rc = keelson_vm_run_file(vm, argv[2]);
        keelson_vm_destroy(vm);
        return rc;
    }

    if (strcmp(cmd, "test") == 0) {
        keelson_vm_t *vm = keelson_vm_create("src/wren");
        if (!vm) {
            fprintf(stderr, "Failed to initialize Wren VM\n");
            return 2;
        }
        int rc = keelson_vm_run_file(vm, "test/test_runner.wren");
        keelson_vm_destroy(vm);
        return rc;
    }

    if (strcmp(cmd, "recover") == 0) {
        if (argc < 3) {
            fprintf(stderr, "Error: missing WAL file path for 'recover'\n");
            return 1;
        }
        wal_t *wal = wal_open(argv[2], WAL_SYNC_NONE);
        if (!wal) {
            fprintf(stderr, "Could not open WAL file: %s\n", argv[2]);
            return 2;
        }
        printf("Inspecting binary WAL records from %s:\n", argv[2]);
        int count = wal_recover(wal, wal_dump_cb, NULL);
        printf("Recovery complete. Total verified records: %d\n", count);
        wal_close(wal);
        return 0;
    }

    if (strcmp(cmd, "serve") == 0) {
        uint16_t port = 8080;
        if (argc >= 4 && strcmp(argv[2], "--port") == 0) {
            port = (uint16_t)atoi(argv[3]);
        }
        http_server_t *server = http_server_create(port);
        if (!server) {
            fprintf(stderr, "Failed to bind HTTP server to port %u\n", port);
            return 3;
        }
        http_server_route(server, "GET", "/health", handle_health, NULL);
        http_server_route(server, "GET", "/api/v1/health", handle_health, NULL);

        printf("Keelson HTTP server listening on http://127.0.0.1:%u\n", port);
        printf("Press Ctrl+C to terminate.\n");

        while (1) {
            http_server_poll(server, 100);
        }

        http_server_destroy(server);
        return 0;
    }

    print_usage();
    return 1;
}
