#include "telnet_server.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"
#include "FreeRTOS_IP.h"
#include "FreeRTOS_Sockets.h"
#include "task.h"

#include "app_config.h"
#include "miner_regs.h"
#include "miner_service.h"
#include "stratum_client.h"

static void sock_printf(Socket_t sock, const char *fmt, ...)
{
    char buf[TELNET_TX_BUFFER_BYTES];
    va_list ap;
    int len;

    va_start(ap, fmt);
    len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (len > 0) {
        size_t send_len = (len < (int)sizeof(buf)) ? (size_t)len : sizeof(buf);
        (void)FreeRTOS_send(sock, buf, send_len, 0);
    }
}

static char *next_token(char **cursor)
{
    char *s = *cursor;
    char *start;

    while ((*s == ' ') || (*s == '\t')) {
        ++s;
    }

    if (*s == '\0') {
        *cursor = s;
        return NULL;
    }

    start = s;
    while ((*s != '\0') && (*s != ' ') && (*s != '\t')) {
        ++s;
    }

    if (*s != '\0') {
        *s++ = '\0';
    }

    *cursor = s;
    return start;
}

static uint32_t parse_u32_hex(const char *s)
{
    return (uint32_t)strtoul(s, NULL, 16);
}

static void print_hash(Socket_t sock, const uint32_t hash[8])
{
    for (uint32_t i = 0; i < 8U; ++i) {
        sock_printf(sock, "%08lx", (unsigned long)hash[i]);
    }
}

static void handle_command(Socket_t sock, char *line)
{
    char *cursor = line;
    char *cmd = next_token(&cursor);

    if (cmd == NULL) {
        return;
    }

    if (strcmp(cmd, "help") == 0) {
        sock_printf(sock,
                    "commands:\r\n"
                    "  help\r\n"
                    "  status\r\n"
                    "  stratum\r\n"
                    "  regs\r\n"
                    "  start <nonce_start_hex> <nonce_count_hex>\r\n"
                    "  stop\r\n"
                    "  clear\r\n"
                    "  pool <host> <port> <user> [pass]\r\n"
                    "  connect\r\n"
                    "  disconnect\r\n");
    } else if (strcmp(cmd, "status") == 0) {
        miner_result_t result;
        uint32_t status = miner_service_status();
        stratum_config_t cfg;

        stratum_client_get_config(&cfg);
        sock_printf(sock, "miner status=0x%08lx engines=%lu stratum=%s pool=%s:%u user=%s\r\n",
                    (unsigned long)status,
                    (unsigned long)miner_num_engines(),
                    stratum_client_is_connected() ? "connected" : "disconnected",
                    cfg.host,
                    cfg.port,
                    cfg.user);

        if (miner_service_get_last_result(&result)) {
            sock_printf(sock, "last result nonce=%08lx engine=%lu status=0x%08lx (nonce-only capture)\r\n",
                        (unsigned long)result.nonce,
                        (unsigned long)result.engine,
                        (unsigned long)result.status);
        }
    } else if (strcmp(cmd, "stratum") == 0) {
        stratum_debug_t dbg;

        memset(&dbg, 0, sizeof(dbg));
        stratum_client_get_debug(&dbg);
        sock_printf(sock,
                    "stratum attempts=%lu successes=%lu disconnects=%lu tx=%lu rx=%lu notify=%lu diff=%lu target=%lu sub=%lu auth=%lu job_ok=%lu job_fail=%lu recv=%ld send=%ld\r\n",
                    (unsigned long)dbg.connect_attempts,
                    (unsigned long)dbg.connect_successes,
                    (unsigned long)dbg.disconnects,
                    (unsigned long)dbg.tx_lines,
                    (unsigned long)dbg.rx_lines,
                    (unsigned long)dbg.notify_count,
                    (unsigned long)dbg.difficulty_count,
                    (unsigned long)dbg.target_count,
                    (unsigned long)dbg.subscribe_ok,
                    (unsigned long)dbg.authorize_ok,
                    (unsigned long)dbg.job_dispatch_ok,
                    (unsigned long)dbg.job_dispatch_fail,
                    (long)dbg.last_recv_status,
                    (long)dbg.last_send_status);
        sock_printf(sock, "event: %s\r\n", dbg.last_event);
        sock_printf(sock, "last_tx: %s\r\n", dbg.last_tx);
        sock_printf(sock, "last_rx: %s\r\n", dbg.last_rx);
    } else if (strcmp(cmd, "regs") == 0) {
        sock_printf(sock, "aggregate STATUS=0x%08lx NUM_ENGINES=%lu\r\n",
                    (unsigned long)miner_status(),
                    (unsigned long)miner_num_engines());
        for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
            sock_printf(sock,
                        "miner%lu base=0x%08lx STATUS=0x%08lx NUM_ENGINES=%lu RESULT_STATUS=0x%08lx\r\n",
                        (unsigned long)inst,
                        (unsigned long)(MINER_AXI_BASEADDR + (inst * MINER_AXI_INSTANCE_STRIDE)),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_STATUS),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_NUM_ENGINES),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_RESULT_STATUS));
        }
    } else if (strcmp(cmd, "start") == 0) {
        char *nonce_s = next_token(&cursor);
        char *count_s = next_token(&cursor);

        if ((nonce_s == NULL) || (count_s == NULL)) {
            sock_printf(sock, "usage: start <nonce_start_hex> <nonce_count_hex>\r\n");
        } else {
            miner_start_range(parse_u32_hex(nonce_s), parse_u32_hex(count_s));
            sock_printf(sock, "started\r\n");
        }
    } else if (strcmp(cmd, "stop") == 0) {
        miner_service_stop_scan();
        sock_printf(sock, "stopped\r\n");
    } else if (strcmp(cmd, "clear") == 0) {
        miner_service_clear();
        sock_printf(sock, "cleared\r\n");
    } else if (strcmp(cmd, "pool") == 0) {
        char *host = next_token(&cursor);
        char *port = next_token(&cursor);
        char *user = next_token(&cursor);
        char *pass = next_token(&cursor);
        stratum_config_t cfg;

        if ((host == NULL) || (port == NULL) || (user == NULL)) {
            sock_printf(sock, "usage: pool <host> <port> <user> [pass]\r\n");
        } else {
            memset(&cfg, 0, sizeof(cfg));
            (void)snprintf(cfg.host, sizeof(cfg.host), "%s", host);
            cfg.port = (uint16_t)strtoul(port, NULL, 10);
            (void)snprintf(cfg.user, sizeof(cfg.user), "%s", user);
            (void)snprintf(cfg.password, sizeof(cfg.password), "%s", (pass != NULL) ? pass : "x");
            stratum_client_set_config(&cfg);
            sock_printf(sock, "pool set\r\n");
        }
    } else if (strcmp(cmd, "connect") == 0) {
        stratum_client_request_connect();
        sock_printf(sock, "connect requested\r\n");
    } else if (strcmp(cmd, "disconnect") == 0) {
        stratum_client_request_disconnect();
        sock_printf(sock, "disconnect requested\r\n");
    } else {
        sock_printf(sock, "unknown command: %s\r\n", cmd);
    }
}

static void telnet_client(Socket_t sock)
{
    char line[TELNET_RX_BUFFER_BYTES];
    size_t used = 0;

    sock_printf(sock, "\r\nVEK280 miner telnet console\r\nNo authentication is enabled.\r\n> ");

    for (;;) {
        char ch;
        BaseType_t got = FreeRTOS_recv(sock, &ch, 1, 0);

        if (got <= 0) {
            break;
        }

        if ((ch == '\r') || (ch == '\n')) {
            line[used] = '\0';
            sock_printf(sock, "\r\n");
            handle_command(sock, line);
            used = 0;
            sock_printf(sock, "> ");
        } else if ((ch == 0x08) || (ch == 0x7f)) {
            if (used > 0U) {
                --used;
            }
        } else if (used < (sizeof(line) - 1U)) {
            line[used++] = ch;
        }
    }
}

static void telnet_task(void *arg)
{
    (void)arg;

    Socket_t listen_sock = FreeRTOS_socket(FREERTOS_AF_INET, FREERTOS_SOCK_STREAM, FREERTOS_IPPROTO_TCP);
    configASSERT(listen_sock != FREERTOS_INVALID_SOCKET);

    struct freertos_sockaddr bind_addr;
    memset(&bind_addr, 0, sizeof(bind_addr));
    bind_addr.sin_port = FreeRTOS_htons(TELNET_LISTEN_PORT);

    configASSERT(FreeRTOS_bind(listen_sock, &bind_addr, sizeof(bind_addr)) == 0);
    configASSERT(FreeRTOS_listen(listen_sock, 2) == 0);

    for (;;) {
        struct freertos_sockaddr client_addr;
        socklen_t addr_len = sizeof(client_addr);
        Socket_t client = FreeRTOS_accept(listen_sock, &client_addr, &addr_len);

        if (client != FREERTOS_INVALID_SOCKET) {
            telnet_client(client);
            FreeRTOS_closesocket(client);
        }
    }
}

void telnet_server_start(void)
{
    xTaskCreate(telnet_task, "telnet", 2048, NULL, 2, NULL);
}
