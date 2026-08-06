#ifndef STRATUM_CLIENT_H
#define STRATUM_CLIENT_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    char host[96];
    uint16_t port;
    char user[128];
    char password[64];
} stratum_config_t;

void stratum_client_start(void);
void stratum_client_set_config(const stratum_config_t *config);
void stratum_client_get_config(stratum_config_t *config);
void stratum_client_request_connect(void);
void stratum_client_request_disconnect(void);
bool stratum_client_is_connected(void);

#endif
