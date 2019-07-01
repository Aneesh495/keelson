#ifndef KEELSON_HTTP_SERVER_H
#define KEELSON_HTTP_SERVER_H

#include <stdint.h>
#include <stddef.h>

typedef struct http_server http_server_t;

typedef struct {
    const char *method;
    const char *path;
    const char *body;
    size_t body_len;
} http_request_t;

typedef struct {
    int status_code;
    const char *content_type;
    const char *body;
    size_t body_len;
} http_response_t;

// Route handler callback signature.
typedef void (*http_route_fn)(const http_request_t *req, http_response_t *res, void *user_data);

// Creates an HTTP server listening on the specified port.
http_server_t *http_server_create(uint16_t port);

// Registers a route handler for a method and path prefix.
int http_server_route(http_server_t *server, const char *method, const char *path, http_route_fn handler, void *user_data);

// Polls and processes incoming network events. Non-blocking with timeout in milliseconds.
int http_server_poll(http_server_t *server, int timeout_ms);

// Closes and releases server resources.
void http_server_destroy(http_server_t *server);

#endif // KEELSON_HTTP_SERVER_H
