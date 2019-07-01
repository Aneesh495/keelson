#include <stdio.h>
#include <string.h>
#include <assert.h>
#include "http_server.h"

static void health_handler(const http_request_t *req, http_response_t *res, void *user_data) {
    (void)req;
    (void)user_data;
    res->status_code = 200;
    res->content_type = "application/json";
    res->body = "{\"status\":\"HEALTHY\",\"engine\":\"keelson\"}";
    res->body_len = strlen(res->body);
}

int main(void) {
    printf("=== Test: C Native Embedded HTTP Server ===\n");

    uint16_t test_port = 19876;
    http_server_t *server = http_server_create(test_port);
    assert(server != NULL);
    printf("  [OK] Server created and listening on port %u\n", test_port);

    int rc = http_server_route(server, "GET", "/health", health_handler, NULL);
    assert(rc == 0);
    printf("  [OK] Registered route GET /health\n");

    // Non-blocking poll timeout 5ms (no incoming client connected)
    int poll_rc = http_server_poll(server, 5);
    assert(poll_rc == 0);
    printf("  [OK] Non-blocking select poll timed out cleanly without errors\n");

    http_server_destroy(server);
    printf("  [OK] Server destroyed and resources released\n");

    printf("All C HTTP Server tests passed successfully.\n");
    return 0;
}
