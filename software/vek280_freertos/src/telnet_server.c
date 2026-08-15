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
#include "telemetry.h"

enum {
    TELNET_IAC = 255,
    TELNET_DONT = 254,
    TELNET_DO = 253,
    TELNET_WONT = 252,
    TELNET_WILL = 251,
    TELNET_SB = 250,
    TELNET_SE = 240,
    TELNET_OPT_ECHO = 1,
    TELNET_OPT_SUPPRESS_GO_AHEAD = 3,
};

typedef enum {
    TELNET_PARSE_DATA,
    TELNET_PARSE_IAC,
    TELNET_PARSE_OPTION,
    TELNET_PARSE_SUBNEGOTIATION,
    TELNET_PARSE_SUBNEGOTIATION_IAC,
} telnet_parse_state_t;

static void sock_send_all(Socket_t sock, const void *data, size_t len)
{
    const uint8_t *cursor = data;

    while (len > 0U) {
        BaseType_t sent = FreeRTOS_send(sock, cursor, len, 0);

        if (sent <= 0) {
            break;
        }
        cursor += (size_t)sent;
        len -= (size_t)sent;
    }
}

static void sock_printf(Socket_t sock, const char *fmt, ...)
{
    char buf[TELNET_TX_BUFFER_BYTES];
    va_list ap;
    int len;

    va_start(ap, fmt);
    len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);

    if (len > 0) {
        size_t send_len = (len < (int)sizeof(buf)) ? (size_t)len : (sizeof(buf) - 1U);
        sock_send_all(sock, buf, send_len);
    }
}

static void telnet_send_command(Socket_t sock, uint8_t command, uint8_t option)
{
    const uint8_t bytes[] = { TELNET_IAC, command, option };

    sock_send_all(sock, bytes, sizeof(bytes));
}

static void telnet_negotiate(Socket_t sock)
{
    /* Keep input echo local to the client terminal. */
    telnet_send_command(sock, TELNET_WONT, TELNET_OPT_ECHO);
    telnet_send_command(sock, TELNET_WILL, TELNET_OPT_SUPPRESS_GO_AHEAD);
    telnet_send_command(sock, TELNET_DO, TELNET_OPT_SUPPRESS_GO_AHEAD);
}

static void telnet_handle_option(Socket_t sock, uint8_t command, uint8_t option)
{
    if (command == TELNET_DO) {
        telnet_send_command(sock,
                            (option == TELNET_OPT_SUPPRESS_GO_AHEAD) ? TELNET_WILL : TELNET_WONT,
                            option);
    } else if (command == TELNET_WILL) {
        telnet_send_command(sock,
                            (option == TELNET_OPT_SUPPRESS_GO_AHEAD) ? TELNET_DO : TELNET_DONT,
                            option);
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

static void print_stats(Socket_t sock)
{
    miner_service_stats_t miner;
    stratum_debug_t stratum;
    uint32_t uptime = (uint32_t)xTaskGetTickCount();

    memset(&miner, 0, sizeof(miner));
    memset(&stratum, 0, sizeof(stratum));
    miner_service_get_stats(&miner);
    stratum_client_get_debug(&stratum);

    sock_printf(sock,
                "performance nominal_hashrate=%lu H/s engines=%lu uptime_ticks=%lu active_job_age_ticks=%lu issued=%llu estimated_completed=%llu jobs=%lu/%lu\r\n",
                (unsigned long)MINER_HASHRATE_HS,
                (unsigned long)miner_num_engines(),
                (unsigned long)uptime,
                (unsigned long)(uptime - miner.active_job_tick),
                (unsigned long long)miner.nonce_candidates_issued,
                (unsigned long long)miner.nonce_candidates_completed_estimate,
                (unsigned long)miner.jobs_started,
                (unsigned long)miner.jobs_queued);
    sock_printf(sock,
                "results candidates=%lu submits=%lu accepted=%lu rejected=%lu send_fail=%lu irq=%lu queue_drop=%lu overflow_polls=%lu last_result_age_ticks=%lu\r\n",
                (unsigned long)stratum.share_candidates,
                (unsigned long)stratum.share_submits,
                (unsigned long)stratum.share_accepted,
                (unsigned long)stratum.share_rejected,
                (unsigned long)stratum.share_send_failures,
                (unsigned long)miner.irq_count,
                (unsigned long)miner.result_queue_drops,
                (unsigned long)miner.overflow_polls,
                (unsigned long)(uptime - miner.last_result_tick));
    sock_printf(sock,
                "work notify=%lu dispatched=%lu failed=%lu target_word0=%08lx last_job_age_ticks=%lu\r\n",
                (unsigned long)stratum.notify_count,
                (unsigned long)stratum.job_dispatch_ok,
                (unsigned long)stratum.job_dispatch_fail,
                (unsigned long)stratum.target_word0,
                (unsigned long)(uptime - stratum.last_job_tick));
    sock_printf(sock,
                "ranges active_start=%08lx active_count=%08lx completed=%lu preempted=%lu clean_preempted=%lu stopped=%lu last_elapsed_ticks=%lu last_reason=%s\r\n",
                (unsigned long)miner.active_nonce_start,
                (unsigned long)miner.active_nonce_count,
                (unsigned long)miner.ranges_completed,
                (unsigned long)miner.ranges_preempted,
                (unsigned long)miner.ranges_preempted_clean_job,
                (unsigned long)miner.ranges_stopped,
                (unsigned long)miner.last_range_elapsed_ticks,
                (miner.last_range_reason == 1U) ? "completed" :
                (miner.last_range_reason == 2U) ? "new-job" :
                (miner.last_range_reason == 3U) ? "manual-stop" : "none");
}

static void print_health(Socket_t sock)
{
    telemetry_health_t health;

    if (!telemetry_get_health(&health) || !health.available) {
        sock_printf(sock, "health sysmon=unavailable\r\n");
        return;
    }

    sock_printf(sock,
                "health sysmon=ok temp=%ld.%02ldC min=%ld.%02ldC max=%ld.%02ldC alarms=0x%08lx\r\n",
                (long)(health.temperature_centi_c / 100),
                (long)labs(health.temperature_centi_c % 100),
                (long)(health.temperature_min_centi_c / 100),
                (long)labs(health.temperature_min_centi_c % 100),
                (long)(health.temperature_max_centi_c / 100),
                (long)labs(health.temperature_max_centi_c % 100),
                (unsigned long)health.alarm_status);
}

/* Returns false when the client requested that its console session close. */
static bool handle_command(Socket_t sock, char *line)
{
    char *cursor = line;
    char *cmd = next_token(&cursor);

    if (cmd == NULL) {
        return true;
    }

    if (strcmp(cmd, "help") == 0) {
        sock_printf(sock,
                    "commands:\r\n"
                    "  help\r\n"
                    "  status\r\n"
                    "  stats\r\n"
                    "  health\r\n"
                    "  stratum\r\n"
                    "  regs\r\n"
                    "  start <nonce_start_hex> <nonce_count_hex>\r\n"
                    "  stop\r\n"
                    "  clear\r\n"
                    "  pool <host> <port> <user> [pass]\r\n"
                    "  connect\r\n"
                    "  disconnect\r\n"
                    "  quit (or exit)\r\n");
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
        sock_printf(sock, "last_tx: <redacted; outbound Stratum messages may contain credentials>\r\n");
        sock_printf(sock, "last_rx: %s\r\n", dbg.last_rx);
    } else if (strcmp(cmd, "stats") == 0) {
        print_stats(sock);
    } else if (strcmp(cmd, "health") == 0) {
        print_health(sock);
    } else if (strcmp(cmd, "regs") == 0) {
        sock_printf(sock, "aggregate STATUS=0x%08lx NUM_ENGINES=%lu\r\n",
                    (unsigned long)miner_status(),
                    (unsigned long)miner_num_engines());
        for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
            sock_printf(sock,
                        "miner%lu base=0x%08lx STATUS=0x%08lx NUM_ENGINES=%lu RESULT_STATUS=0x%08lx IRQ_CONTROL=0x%08lx\r\n",
                        (unsigned long)inst,
                        (unsigned long)(MINER_AXI_BASEADDR + (inst * MINER_AXI_INSTANCE_STRIDE)),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_STATUS),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_NUM_ENGINES),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_RESULT_STATUS),
                        (unsigned long)miner_read_reg_instance(inst, MINER_REG_IRQ_CONTROL));
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
    } else if ((strcmp(cmd, "quit") == 0) || (strcmp(cmd, "exit") == 0)) {
        sock_printf(sock, "closing console session\r\n");
        return false;
    } else {
        sock_printf(sock, "unknown command: %s\r\n", cmd);
    }

    return true;
}

static void telnet_client(Socket_t sock)
{
    char line[TELNET_RX_BUFFER_BYTES];
    size_t used = 0;
    bool ignore_lf_after_cr = false;
    bool line_overflowed = false;
    telnet_parse_state_t parse_state = TELNET_PARSE_DATA;
    uint8_t option_command = 0U;

    telnet_negotiate(sock);
    sock_printf(sock, "\r\nVEK280 miner telnet console\r\nNo authentication is enabled.\r\n> ");

    for (;;) {
        uint8_t ch;
        BaseType_t got = FreeRTOS_recv(sock, &ch, 1, 0);

        if (got <= 0) {
            break;
        }

        if (parse_state == TELNET_PARSE_IAC) {
            if (ch == TELNET_IAC) {
                parse_state = TELNET_PARSE_DATA;
            } else if ((ch == TELNET_DO) || (ch == TELNET_DONT) ||
                       (ch == TELNET_WILL) || (ch == TELNET_WONT)) {
                option_command = ch;
                parse_state = TELNET_PARSE_OPTION;
            } else if (ch == TELNET_SB) {
                parse_state = TELNET_PARSE_SUBNEGOTIATION;
            } else {
                parse_state = TELNET_PARSE_DATA;
            }
            continue;
        }

        if (parse_state == TELNET_PARSE_OPTION) {
            telnet_handle_option(sock, option_command, ch);
            parse_state = TELNET_PARSE_DATA;
            continue;
        }

        if (parse_state == TELNET_PARSE_SUBNEGOTIATION) {
            if (ch == TELNET_IAC) {
                parse_state = TELNET_PARSE_SUBNEGOTIATION_IAC;
            }
            continue;
        }

        if (parse_state == TELNET_PARSE_SUBNEGOTIATION_IAC) {
            parse_state = (ch == TELNET_SE) ? TELNET_PARSE_DATA : TELNET_PARSE_SUBNEGOTIATION;
            continue;
        }

        if (ch == TELNET_IAC) {
            parse_state = TELNET_PARSE_IAC;
            continue;
        }

        if (((ch == '\n') || (ch == '\0')) && ignore_lf_after_cr) {
            /* Treat both CRLF and Telnet's CR NUL as one line ending. */
            ignore_lf_after_cr = false;
            continue;
        }

        if ((ch == '\r') || (ch == '\n')) {
            line[used] = '\0';
            sock_printf(sock, "\r\n");
            if (line_overflowed) {
                sock_printf(sock, "input line too long; discarded\r\n");
            } else if (!handle_command(sock, line)) {
                break;
            }
            used = 0;
            line_overflowed = false;
            ignore_lf_after_cr = (ch == '\r');
            sock_printf(sock, "> ");
        } else if ((ch == 0x08) || (ch == 0x7f)) {
            ignore_lf_after_cr = false;
            if (used > 0U) {
                --used;
            }
        } else if (ch == 0x15) { /* Ctrl-U */
            used = 0;
            line_overflowed = false;
            ignore_lf_after_cr = false;
        } else if (ch == 0x03) { /* Ctrl-C */
            used = 0;
            line_overflowed = false;
            ignore_lf_after_cr = false;
        } else if (used < (sizeof(line) - 1U)) {
            ignore_lf_after_cr = false;
            if ((ch >= 0x20U) && (ch <= 0x7eU)) {
                line[used++] = (char)ch;
            }
        } else if (!line_overflowed) {
            line_overflowed = true;
            sock_printf(sock, "\a");
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
