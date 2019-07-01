#include "http_server.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

#define MAX_ROUTES 32
#define BUFFER_SIZE 8192

typedef struct {
    char method[16];
    char path[128];
    http_route_fn handler;
    void *user_data;
} route_entry_t;

struct http_server {
    int listen_fd;
    uint16_t port;
    route_entry_t routes[MAX_ROUTES];
    int route_count;
};

static void set_nonblocking(int fd) {
    int flags = fcntl(fd, F_GETFL, 0);
    if (flags != -1) {
        fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    }
}

http_server_t *http_server_create(uint16_t port) {
    http_server_t *server = (http_server_t *)malloc(sizeof(http_server_t));
    if (!server) return NULL;

    memset(server, 0, sizeof(http_server_t));
    server->port = port;

    server->listen_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server->listen_fd < 0) {
        free(server);
        return NULL;
    }

    int opt = 1;
    setsockopt(server->listen_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    set_nonblocking(server->listen_fd);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_ANY);
    addr.sin_port = htons(port);

    if (bind(server->listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(server->listen_fd);
        free(server);
        return NULL;
    }

    if (listen(server->listen_fd, 128) < 0) {
        close(server->listen_fd);
        free(server);
        return NULL;
    }

    return server;
}

int http_server_route(http_server_t *server, const char *method, const char *path, http_route_fn handler, void *user_data) {
    if (!server || server->route_count >= MAX_ROUTES) return -1;

    route_entry_t *r = &server->routes[server->route_count++];
    strncpy(r->method, method, sizeof(r->method) - 1);
    strncpy(r->path, path, sizeof(r->path) - 1);
    r->handler = handler;
    r->user_data = user_data;

    return 0;
}

static void handle_client(http_server_t *server, int client_fd) {
    char buf[BUFFER_SIZE];
    ssize_t bytes_read = read(client_fd, buf, sizeof(buf) - 1);
    if (bytes_read <= 0) {
        close(client_fd);
        return;
    }
    buf[bytes_read] = '\0';

    char method[16];
    char path[256];
    char proto[16];

    if (sscanf(buf, "%15s %255s %15s", method, path, proto) != 3) {
        close(client_fd);
        return;
    }

    char *body_start = strstr(buf, "\r\n\r\n");
    if (body_start) {
        body_start += 4;
    }

    http_request_t req;
    req.method = method;
    req.path = path;
    req.body = body_start;
    req.body_len = body_start ? strlen(body_start) : 0;

    http_response_t res;
    res.status_code = 404;
    res.content_type = "application/json";
    res.body = "{\"error\":\"Not Found\"}";
    res.body_len = strlen(res.body);

    // Route matching
    for (int i = 0; i < server->route_count; i++) {
        route_entry_t *r = &server->routes[i];
        if (strcmp(r->method, method) == 0 && strncmp(r->path, path, strlen(r->path)) == 0) {
            r->handler(&req, &res, r->user_data);
            break;
        }
    }

    // Send HTTP response
    char header_buf[512];
    int header_len = snprintf(header_buf, sizeof(header_buf),
        "HTTP/1.1 %d OK\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "Connection: close\r\n"
        "Access-Control-Allow-Origin: *\r\n"
        "\r\n",
        res.status_code, res.content_type, res.body_len);

    write(client_fd, header_buf, header_len);
    if (res.body_len > 0 && res.body != NULL) {
        write(client_fd, res.body, res.body_len);
    }

    close(client_fd);
}

int http_server_poll(http_server_t *server, int timeout_ms) {
    if (!server || server->listen_fd < 0) return -1;

    fd_set read_fds;
    FD_ZERO(&read_fds);
    FD_SET(server->listen_fd, &read_fds);

    struct timeval tv;
    tv.tv_sec = timeout_ms / 1000;
    tv.tv_usec = (timeout_ms % 1000) * 1000;

    int ready = select(server->listen_fd + 1, &read_fds, NULL, NULL, &tv);
    if (ready > 0 && FD_ISSET(server->listen_fd, &read_fds)) {
        struct sockaddr_in client_addr;
        socklen_t client_len = sizeof(client_addr);
        int client_fd = accept(server->listen_fd, (struct sockaddr *)&client_addr, &client_len);
        if (client_fd >= 0) {
            handle_client(server, client_fd);
            return 1;
        }
    }

    return 0;
}

void http_server_destroy(http_server_t *server) {
    if (!server) return;
    if (server->listen_fd >= 0) {
        close(server->listen_fd);
        server->listen_fd = -1;
    }
    free(server);
}
