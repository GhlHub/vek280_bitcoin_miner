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

typedef struct {
    uint32_t connect_attempts;
    uint32_t connect_successes;
    uint32_t disconnects;
    uint32_t rx_lines;
    uint32_t tx_lines;
    uint32_t notify_count;
    uint32_t difficulty_count;
    uint32_t target_count;
    uint32_t subscribe_ok;
    uint32_t authorize_ok;
    uint32_t job_dispatch_ok;
    uint32_t job_dispatch_fail;
    uint32_t share_candidates;
    uint32_t share_submits;
    uint32_t share_accepted;
    uint32_t share_rejected;
    uint32_t share_send_failures;
    uint32_t last_job_tick;
    uint32_t last_share_tick;
    uint32_t target_word0;
    int32_t last_recv_status;
    int32_t last_send_status;
    char last_event[96];
    char last_tx[384];
    char last_rx[384];
} stratum_debug_t;

void stratum_client_start(void);
void stratum_client_set_config(const stratum_config_t *config);
void stratum_client_get_config(stratum_config_t *config);
void stratum_client_get_debug(stratum_debug_t *debug);
void stratum_client_request_connect(void);
void stratum_client_request_disconnect(void);
bool stratum_client_is_connected(void);

#endif
