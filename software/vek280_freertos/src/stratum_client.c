#include "stratum_client.h"

#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "FreeRTOS.h"
#include "FreeRTOS_DNS.h"
#include "FreeRTOS_IP.h"
#include "FreeRTOS_Sockets.h"
#include "semphr.h"
#include "task.h"
#include "xil_printf.h"

#include "app_config.h"
#include "miner_service.h"
#include "sha256_sw.h"

typedef struct {
    char job_id[STRATUM_JOB_ID_BYTES];
    char prevhash[65];
    char coinb1[(STRATUM_COINBASE_BYTES * 2U) + 1U];
    char coinb2[(STRATUM_COINBASE_BYTES * 2U) + 1U];
    char merkle[STRATUM_MERKLE_BRANCHES][65];
    uint32_t merkle_count;
    char version[9];
    char nbits[9];
    char ntime[9];
    bool clean_jobs;
} stratum_notify_t;

typedef struct {
    char extranonce1[(STRATUM_EXTRANONCE1_BYTES * 2U) + 1U];
    uint32_t extranonce2_size;
    uint32_t extranonce2_counter;
    uint32_t target[8];
    stratum_notify_t pending_notify;
    stratum_notify_t current_notify;
    bool subscribed;
    bool authorized;
    bool have_target;
    bool have_pending_notify;
    bool have_current_notify;
} stratum_state_t;

static stratum_config_t g_config = {
    .host = STRATUM_DEFAULT_HOST,
    .port = STRATUM_DEFAULT_PORT,
    .user = STRATUM_DEFAULT_USER,
    .password = STRATUM_DEFAULT_PASSWORD,
};

static SemaphoreHandle_t g_config_lock;
static SemaphoreHandle_t g_debug_lock;
static volatile bool g_connect_requested;
static volatile bool g_disconnect_requested;
static volatile bool g_connected;
static stratum_debug_t g_debug;

static void stratum_debug_set_event(const char *fmt, ...)
{
    va_list ap;

    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    va_start(ap, fmt);
    (void)vsnprintf(g_debug.last_event, sizeof(g_debug.last_event), fmt, ap);
    va_end(ap);
    xSemaphoreGive(g_debug_lock);

    xil_printf("stratum: %s\r\n", g_debug.last_event);
}

static void stratum_debug_set_rx_line(const char *line)
{
    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    (void)snprintf(g_debug.last_rx, sizeof(g_debug.last_rx), "%s", line);
    xSemaphoreGive(g_debug_lock);
}

static void stratum_debug_set_tx_line(const char *line)
{
    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    (void)snprintf(g_debug.last_tx, sizeof(g_debug.last_tx), "%s", line);
    xSemaphoreGive(g_debug_lock);
}

static void stratum_debug_inc(uint32_t *counter)
{
    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    ++*counter;
    xSemaphoreGive(g_debug_lock);
}

static void stratum_debug_set_recv_status(BaseType_t status)
{
    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    g_debug.last_recv_status = (int32_t)status;
    xSemaphoreGive(g_debug_lock);
}

static void stratum_debug_set_send_status(BaseType_t status)
{
    if ((g_debug_lock == NULL) ||
        (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) != pdTRUE)) {
        return;
    }

    g_debug.last_send_status = (int32_t)status;
    xSemaphoreGive(g_debug_lock);
}

static int hex_value(char ch)
{
    if ((ch >= '0') && (ch <= '9')) {
        return ch - '0';
    }
    if ((ch >= 'a') && (ch <= 'f')) {
        return 10 + ch - 'a';
    }
    if ((ch >= 'A') && (ch <= 'F')) {
        return 10 + ch - 'A';
    }
    return -1;
}

static bool hex_to_bytes(const char *hex, uint8_t *bytes, size_t max_bytes, size_t *out_len)
{
    size_t hex_len = strlen(hex);

    if (((hex_len & 1U) != 0U) || ((hex_len / 2U) > max_bytes)) {
        return false;
    }

    for (size_t i = 0; i < (hex_len / 2U); ++i) {
        int hi = hex_value(hex[i * 2U]);
        int lo = hex_value(hex[(i * 2U) + 1U]);

        if ((hi < 0) || (lo < 0)) {
            return false;
        }
        bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    if (out_len != NULL) {
        *out_len = hex_len / 2U;
    }
    return true;
}

static uint32_t hex_u32(const char *hex)
{
    return (uint32_t)strtoul(hex, NULL, 16);
}

static void store_le32(uint8_t *dst, uint32_t value)
{
    dst[0] = (uint8_t)value;
    dst[1] = (uint8_t)(value >> 8);
    dst[2] = (uint8_t)(value >> 16);
    dst[3] = (uint8_t)(value >> 24);
}

static void reverse_copy(uint8_t *dst, const uint8_t *src, size_t len)
{
    for (size_t i = 0; i < len; ++i) {
        dst[i] = src[len - 1U - i];
    }
}

static void bytes_to_hex(const uint8_t *bytes, size_t len, char *hex, size_t hex_size)
{
    static const char k_hex[] = "0123456789abcdef";

    if (hex_size == 0U) {
        return;
    }

    for (size_t i = 0; (i < len) && (((i * 2U) + 1U) < hex_size); ++i) {
        hex[i * 2U] = k_hex[bytes[i] >> 4];
        hex[(i * 2U) + 1U] = k_hex[bytes[i] & 0x0fU];
    }
    hex[((len * 2U) < hex_size) ? (len * 2U) : (hex_size - 1U)] = '\0';
}

static void double_sha256(const uint8_t *data, size_t len, uint8_t digest[32])
{
    sha256_ctx_t ctx;
    uint8_t first[32];

    sha256_init(&ctx);
    sha256_update(&ctx, data, len);
    sha256_final(&ctx, first);
    sha256_init(&ctx);
    sha256_update(&ctx, first, sizeof(first));
    sha256_final(&ctx, digest);
}

static const char *skip_ws(const char *s)
{
    while ((*s == ' ') || (*s == '\t') || (*s == '\r') || (*s == '\n')) {
        ++s;
    }
    return s;
}

static const char *skip_json_string(const char *s)
{
    if (*s != '"') {
        return NULL;
    }
    ++s;
    while (*s != '\0') {
        if (*s == '\\') {
            if (s[1] == '\0') {
                return NULL;
            }
            s += 2;
        } else if (*s == '"') {
            return s + 1;
        } else {
            ++s;
        }
    }
    return NULL;
}

static bool read_json_string(const char **cursor, char *dst, size_t dst_size)
{
    const char *s = skip_ws(*cursor);
    size_t used = 0;

    if ((*s != '"') || (dst_size == 0U)) {
        return false;
    }
    ++s;

    while (*s != '\0') {
        char ch = *s++;

        if (ch == '\\') {
            if (*s == '\0') {
                return false;
            }
            ch = *s++;
        } else if (ch == '"') {
            dst[used] = '\0';
            *cursor = s;
            return true;
        }

        if ((used + 1U) < dst_size) {
            dst[used++] = ch;
        }
    }

    return false;
}

static const char *skip_json_value(const char *s)
{
    int depth = 0;
    bool in_string = false;

    s = skip_ws(s);
    while (*s != '\0') {
        if (in_string) {
            if (*s == '\\') {
                s += (s[1] != '\0') ? 2 : 1;
            } else if (*s == '"') {
                in_string = false;
                ++s;
            } else {
                ++s;
            }
        } else if (*s == '"') {
            in_string = true;
            ++s;
        } else if ((*s == '[') || (*s == '{')) {
            ++depth;
            ++s;
        } else if ((*s == ']') || (*s == '}')) {
            if (depth == 0) {
                return s;
            }
            --depth;
            ++s;
        } else if ((*s == ',') && (depth == 0)) {
            return s;
        } else {
            ++s;
        }
    }
    return s;
}

static const char *find_params_array(const char *line)
{
    const char *p = strstr(line, "\"params\"");

    if (p == NULL) {
        return NULL;
    }
    p = strchr(p, '[');
    return (p != NULL) ? (p + 1) : NULL;
}

static bool json_has_id(const char *line, uint32_t id)
{
    const char *p = line;

    while ((p = strstr(p, "\"id\"")) != NULL) {
        p += 4;
        p = skip_ws(p);
        if (*p != ':') {
            continue;
        }
        ++p;
        p = skip_ws(p);
        if ((uint32_t)strtoul(p, NULL, 10) == id) {
            return true;
        }
    }
    return false;
}

static bool json_method_is(const char *line, const char *method)
{
    const char *p = strstr(line, "\"method\"");
    char parsed[64];

    if (p == NULL) {
        return false;
    }
    p += 8;
    p = skip_ws(p);
    if (*p != ':') {
        return false;
    }
    ++p;
    return read_json_string(&p, parsed, sizeof(parsed)) &&
           (strcmp(parsed, method) == 0);
}

static bool params_string(const char **cursor, char *dst, size_t dst_size)
{
    const char *s = skip_ws(*cursor);

    if (!read_json_string(&s, dst, dst_size)) {
        return false;
    }
    s = skip_ws(s);
    if (*s == ',') {
        ++s;
    }
    *cursor = s;
    return true;
}

static bool params_bool(const char **cursor, bool *value)
{
    const char *s = skip_ws(*cursor);

    if (strncmp(s, "true", 4) == 0) {
        *value = true;
        s += 4;
    } else if (strncmp(s, "false", 5) == 0) {
        *value = false;
        s += 5;
    } else {
        return false;
    }

    s = skip_ws(s);
    if (*s == ',') {
        ++s;
    }
    *cursor = s;
    return true;
}

static bool params_merkle_array(const char **cursor, stratum_notify_t *notify)
{
    const char *s = skip_ws(*cursor);

    if (*s != '[') {
        return false;
    }
    ++s;
    notify->merkle_count = 0;

    for (;;) {
        s = skip_ws(s);
        if (*s == ']') {
            ++s;
            break;
        }
        if (notify->merkle_count >= STRATUM_MERKLE_BRANCHES) {
            return false;
        }
        if (!read_json_string(&s, notify->merkle[notify->merkle_count], sizeof(notify->merkle[0]))) {
            return false;
        }
        ++notify->merkle_count;
        s = skip_ws(s);
        if (*s == ',') {
            ++s;
        } else if (*s != ']') {
            return false;
        }
    }

    s = skip_ws(s);
    if (*s == ',') {
        ++s;
    }
    *cursor = s;
    return true;
}

static bool parse_notify(const char *line, stratum_notify_t *notify)
{
    const char *p = find_params_array(line);

    if (p == NULL) {
        return false;
    }
    memset(notify, 0, sizeof(*notify));

    return params_string(&p, notify->job_id, sizeof(notify->job_id)) &&
           params_string(&p, notify->prevhash, sizeof(notify->prevhash)) &&
           params_string(&p, notify->coinb1, sizeof(notify->coinb1)) &&
           params_string(&p, notify->coinb2, sizeof(notify->coinb2)) &&
           params_merkle_array(&p, notify) &&
           params_string(&p, notify->version, sizeof(notify->version)) &&
           params_string(&p, notify->nbits, sizeof(notify->nbits)) &&
           params_string(&p, notify->ntime, sizeof(notify->ntime)) &&
           params_bool(&p, &notify->clean_jobs);
}

static bool parse_difficulty(const char *line, double *difficulty)
{
    const char *p = find_params_array(line);

    if (p == NULL) {
        return false;
    }
    *difficulty = strtod(p, NULL);
    return (*difficulty > 0.0);
}

static bool parse_target(const char *line, uint32_t target[8])
{
    const char *p = find_params_array(line);
    char target_hex[65];
    uint8_t bytes[32];
    size_t target_len = 0;

    if (p == NULL) {
        return false;
    }
    if (!params_string(&p, target_hex, sizeof(target_hex))) {
        return false;
    }
    if (!hex_to_bytes(target_hex, bytes, sizeof(bytes), &target_len) ||
        (target_len != sizeof(bytes))) {
        return false;
    }

    for (uint32_t i = 0; i < 8U; ++i) {
        target[i] = ((uint32_t)bytes[i * 4U] << 24) |
                    ((uint32_t)bytes[(i * 4U) + 1U] << 16) |
                    ((uint32_t)bytes[(i * 4U) + 2U] << 8) |
                    bytes[(i * 4U) + 3U];
    }

    return true;
}

static bool parse_subscribe_response(const char *line, stratum_state_t *state)
{
    const char *result = strstr(line, "\"result\"");
    const char *s;
    char last_string[(STRATUM_EXTRANONCE1_BYTES * 2U) + 1U] = "";
    uint32_t last_number = 0;
    int depth = 0;

    if ((result == NULL) || !json_has_id(line, 1U)) {
        return false;
    }

    s = strchr(result, '[');
    if (s == NULL) {
        return false;
    }

    while (*s != '\0') {
        s = skip_ws(s);
        if (*s == '"') {
            if (!read_json_string(&s, last_string, sizeof(last_string))) {
                return false;
            }
        } else if (*s == '[') {
            ++depth;
            ++s;
        } else if (*s == ']') {
            if (depth <= 1) {
                break;
            }
            --depth;
            ++s;
        } else if (isdigit((unsigned char)*s)) {
            last_number = (uint32_t)strtoul(s, (char **)&s, 10);
        } else {
            ++s;
        }
    }

    if ((last_string[0] == '\0') || (last_number > STRATUM_EXTRANONCE2_BYTES)) {
        return false;
    }

    (void)snprintf(state->extranonce1, sizeof(state->extranonce1), "%s", last_string);
    state->extranonce2_size = last_number;
    state->subscribed = true;
    return true;
}

static bool parse_authorize_response(const char *line, stratum_state_t *state)
{
    const char *result = strstr(line, "\"result\"");

    if ((result == NULL) || !json_has_id(line, 2U)) {
        return false;
    }
    if (strstr(result, "true") != NULL) {
        state->authorized = true;
        return true;
    }
    return false;
}

static void compact_target_for_difficulty(double difficulty, uint32_t target[8])
{
    uint8_t bytes[32] = {
        0x00, 0x00, 0x00, 0x00, 0xff, 0xff, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    };
    uint32_t divisor = (uint32_t)((difficulty < 1.0) ? 1.0 : difficulty);
    uint64_t rem = 0;

    for (uint32_t i = 0; i < 32U; ++i) {
        uint64_t value = (rem << 8) | bytes[i];
        bytes[i] = (uint8_t)(value / divisor);
        rem = value % divisor;
    }

    for (uint32_t i = 0; i < 8U; ++i) {
        target[i] = ((uint32_t)bytes[i * 4U] << 24) |
                    ((uint32_t)bytes[(i * 4U) + 1U] << 16) |
                    ((uint32_t)bytes[(i * 4U) + 2U] << 8) |
                    bytes[(i * 4U) + 3U];
    }
}

static bool make_extranonce2(stratum_state_t *state, char *hex, size_t hex_size)
{
    uint8_t bytes[STRATUM_EXTRANONCE2_BYTES];
    uint32_t value = state->extranonce2_counter++;

    if (((state->extranonce2_size * 2U) + 1U) > hex_size) {
        return false;
    }

    memset(bytes, 0, sizeof(bytes));
    for (uint32_t i = 0; (i < state->extranonce2_size) && (i < 4U); ++i) {
        bytes[state->extranonce2_size - 1U - i] = (uint8_t)(value >> (i * 8U));
    }
    bytes_to_hex(bytes, state->extranonce2_size, hex, hex_size);
    return true;
}

static bool build_job(const stratum_notify_t *notify, stratum_state_t *state, miner_job_t *job)
{
    uint8_t coinbase[STRATUM_COINBASE_BYTES];
    uint8_t tmp[64];
    uint8_t hash_be[32];
    uint8_t merkle_internal[32];
    uint8_t header[80];
    size_t coinbase_len = 0;
    size_t part_len = 0;
    char extranonce2[(STRATUM_EXTRANONCE2_BYTES * 2U) + 1U];

    if (!state->have_target || !state->subscribed || !state->authorized) {
        return false;
    }
    if (!make_extranonce2(state, extranonce2, sizeof(extranonce2))) {
        return false;
    }

    if (!hex_to_bytes(notify->coinb1, coinbase, sizeof(coinbase), &coinbase_len)) {
        return false;
    }
    if (!hex_to_bytes(state->extranonce1, &coinbase[coinbase_len],
                      sizeof(coinbase) - coinbase_len, &part_len)) {
        return false;
    }
    coinbase_len += part_len;
    if (!hex_to_bytes(extranonce2, &coinbase[coinbase_len],
                      sizeof(coinbase) - coinbase_len, &part_len)) {
        return false;
    }
    coinbase_len += part_len;
    if (!hex_to_bytes(notify->coinb2, &coinbase[coinbase_len],
                      sizeof(coinbase) - coinbase_len, &part_len)) {
        return false;
    }
    coinbase_len += part_len;

    double_sha256(coinbase, coinbase_len, hash_be);
    reverse_copy(merkle_internal, hash_be, sizeof(merkle_internal));

    for (uint32_t i = 0; i < notify->merkle_count; ++i) {
        memcpy(tmp, merkle_internal, 32U);
        if (!hex_to_bytes(notify->merkle[i], &tmp[32], 32U, &part_len) || (part_len != 32U)) {
            return false;
        }
        double_sha256(tmp, sizeof(tmp), hash_be);
        reverse_copy(merkle_internal, hash_be, sizeof(merkle_internal));
    }

    memset(header, 0, sizeof(header));
    store_le32(&header[0], hex_u32(notify->version));
    if (!hex_to_bytes(notify->prevhash, tmp, 32U, &part_len) || (part_len != 32U)) {
        return false;
    }
    reverse_copy(&header[4], tmp, 32U);
    memcpy(&header[36], merkle_internal, 32U);
    store_le32(&header[68], hex_u32(notify->ntime));
    store_le32(&header[72], hex_u32(notify->nbits));

    memset(job, 0, sizeof(*job));
    bitcoin_header_midstate(header, job->midstate);
    bitcoin_header_tail_words(header, job->header_tail);
    memcpy(job->target, state->target, sizeof(job->target));
    job->nonce_start = 0;
    job->nonce_count = STRATUM_SCAN_NONCE_COUNT;
    (void)snprintf(job->job_id, sizeof(job->job_id), "%s", notify->job_id);
    (void)snprintf(job->extranonce2, sizeof(job->extranonce2), "%s", extranonce2);
    (void)snprintf(job->ntime, sizeof(job->ntime), "%s", notify->ntime);
    return true;
}

static bool dispatch_notify_work(const stratum_notify_t *notify, stratum_state_t *state)
{
    miner_job_t job;

    if (!build_job(notify, state, &job)) {
        stratum_debug_inc(&g_debug.job_dispatch_fail);
        stratum_debug_set_event("job materialization failed");
        return false;
    }

    miner_service_submit_job(&job);
    stratum_debug_inc(&g_debug.job_dispatch_ok);
    if (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) == pdTRUE) {
        g_debug.last_job_tick = (uint32_t)xTaskGetTickCount();
        xSemaphoreGive(g_debug_lock);
    }
    stratum_debug_set_event("job dispatched id=%s", job.job_id);
    return true;
}

static void try_dispatch_pending_notify(stratum_state_t *state)
{
    if (!state->have_pending_notify) {
        return;
    }

    if (state->pending_notify.clean_jobs) {
        miner_service_clear();
    }

    if (dispatch_notify_work(&state->pending_notify, state)) {
        state->current_notify = state->pending_notify;
        state->have_current_notify = true;
        state->have_pending_notify = false;
    }
}

static void refill_if_idle(stratum_state_t *state)
{
    if (!state->have_current_notify) {
        return;
    }

    if ((miner_service_status() & MINER_STATUS_RUNNING) == 0U) {
        (void)dispatch_notify_work(&state->current_notify, state);
    }
}

static BaseType_t send_line(Socket_t sock, const char *line)
{
    size_t len = strlen(line);
    size_t sent = 0;

    stratum_debug_set_tx_line(line);

    while (sent < len) {
        BaseType_t rc = FreeRTOS_send(sock, &line[sent], len - sent, 0);

        stratum_debug_set_send_status(rc);
        if (rc <= 0) {
            stratum_debug_set_event("send failed rc=%ld", (long)rc);
            return rc;
        }
        sent += (size_t)rc;
    }

    stratum_debug_inc(&g_debug.tx_lines);
    return (BaseType_t)sent;
}

static void send_subscribe_authorize(Socket_t sock, const stratum_config_t *config)
{
    char line[384];

    (void)snprintf(line, sizeof(line),
                   "{\"id\":1,\"method\":\"mining.subscribe\",\"params\":[\"vek280_bitcoin_miner/0.1\"]}\n");
    stratum_debug_inc(&g_debug.share_submits);
    if (send_line(sock, line) <= 0) {
        stratum_debug_inc(&g_debug.share_send_failures);
    }
    if (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) == pdTRUE) {
        g_debug.last_share_tick = (uint32_t)xTaskGetTickCount();
        xSemaphoreGive(g_debug_lock);
    }
    stratum_debug_set_event("tx subscribe");

    (void)snprintf(line, sizeof(line),
                   "{\"id\":2,\"method\":\"mining.authorize\",\"params\":[\"%s\",\"%s\"]}\n",
                   config->user, config->password);
    (void)send_line(sock, line);
    stratum_debug_set_event("tx authorize");
}

static void submit_share(Socket_t sock, const stratum_config_t *config,
                         const miner_result_t *result, const miner_job_t *job)
{
    char line[512];

    if (job->job_id[0] == '\0') {
        return;
    }

    (void)snprintf(line, sizeof(line),
                   "{\"id\":4,\"method\":\"mining.submit\",\"params\":[\"%s\",\"%s\",\"%s\",\"%s\",\"%08lx\"]}\n",
                   config->user,
                   job->job_id,
                   job->extranonce2,
                   job->ntime,
                   (unsigned long)result->nonce);
    (void)send_line(sock, line);
    stratum_debug_set_event("tx submit nonce=%08lx", (unsigned long)result->nonce);
}

static void handle_stratum_line(const char *line, stratum_state_t *state)
{
    stratum_debug_inc(&g_debug.rx_lines);
    stratum_debug_set_rx_line(line);

    if (json_method_is(line, "mining.notify")) {
        stratum_notify_t notify;

        if (parse_notify(line, &notify)) {
            stratum_debug_inc(&g_debug.notify_count);
            stratum_debug_set_event("rx notify id=%s branches=%lu",
                                    notify.job_id,
                                    (unsigned long)notify.merkle_count);
            state->pending_notify = notify;
            state->have_pending_notify = true;
            try_dispatch_pending_notify(state);
        } else {
            stratum_debug_set_event("notify parse failed");
        }
    } else if (json_method_is(line, "mining.set_difficulty")) {
        double difficulty;

        if (parse_difficulty(line, &difficulty)) {
            stratum_debug_inc(&g_debug.difficulty_count);
            compact_target_for_difficulty(difficulty, state->target);
            state->have_target = true;
            if (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) == pdTRUE) {
                g_debug.target_word0 = state->target[0];
                xSemaphoreGive(g_debug_lock);
            }
            stratum_debug_set_event("rx difficulty");
            try_dispatch_pending_notify(state);
        } else {
            stratum_debug_set_event("difficulty parse failed");
        }
    } else if (json_method_is(line, "mining.set_target")) {
        if (parse_target(line, state->target)) {
            stratum_debug_inc(&g_debug.target_count);
            state->have_target = true;
            if (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(20)) == pdTRUE) {
                g_debug.target_word0 = state->target[0];
                xSemaphoreGive(g_debug_lock);
            }
            stratum_debug_set_event("rx target");
            try_dispatch_pending_notify(state);
        } else {
            stratum_debug_set_event("target parse failed");
        }
    } else {
        if (json_has_id(line, 4U)) {
            if (strstr(line, "\"result\":true") != NULL) {
                stratum_debug_inc(&g_debug.share_accepted);
                stratum_debug_set_event("share accepted");
            } else if ((strstr(line, "\"result\":false") != NULL) ||
                       (strstr(line, "\"error\":") != NULL)) {
                stratum_debug_inc(&g_debug.share_rejected);
                stratum_debug_set_event("share rejected");
            }
        }
        if (parse_subscribe_response(line, state)) {
            stratum_debug_inc(&g_debug.subscribe_ok);
            stratum_debug_set_event("rx subscribe ok extranonce2=%lu",
                                    (unsigned long)state->extranonce2_size);
        }
        if (parse_authorize_response(line, state)) {
            stratum_debug_inc(&g_debug.authorize_ok);
            stratum_debug_set_event("rx authorize ok");
        }
        try_dispatch_pending_notify(state);
    }
}

static Socket_t connect_socket(const stratum_config_t *config)
{
    struct freertos_sockaddr addr;
    Socket_t sock;
    uint32_t ip;

    ip = FreeRTOS_inet_addr(config->host);
    if (ip == 0U) {
        ip = FreeRTOS_gethostbyname(config->host);
    }
    if (ip == 0U) {
        stratum_debug_set_event("dns failed host=%s", config->host);
        return FREERTOS_INVALID_SOCKET;
    }
    stratum_debug_set_event("dns ok host=%s ip=%lu.%lu.%lu.%lu",
                            config->host,
                            (unsigned long)(ip & 0xffU),
                            (unsigned long)((ip >> 8) & 0xffU),
                            (unsigned long)((ip >> 16) & 0xffU),
                            (unsigned long)((ip >> 24) & 0xffU));

    sock = FreeRTOS_socket(FREERTOS_AF_INET, FREERTOS_SOCK_STREAM, FREERTOS_IPPROTO_TCP);
    if (sock == FREERTOS_INVALID_SOCKET) {
        stratum_debug_set_event("socket create failed");
        return sock;
    }

    TickType_t timeout = pdMS_TO_TICKS(100);
    (void)FreeRTOS_setsockopt(sock, 0, FREERTOS_SO_RCVTIMEO, &timeout, sizeof(timeout));
    (void)FreeRTOS_setsockopt(sock, 0, FREERTOS_SO_SNDTIMEO, &timeout, sizeof(timeout));

    memset(&addr, 0, sizeof(addr));
    addr.sin_address.ulIP_IPv4 = ip;
    addr.sin_port = FreeRTOS_htons(config->port);

    if (FreeRTOS_connect(sock, &addr, sizeof(addr)) != 0) {
        stratum_debug_set_event("connect failed");
        FreeRTOS_closesocket(sock);
        return FREERTOS_INVALID_SOCKET;
    }

    stratum_debug_set_event("connect ok");
    return sock;
}

static void drain_share_results(Socket_t sock, const stratum_config_t *config, TickType_t timeout)
{
    miner_result_t result;
    miner_job_t job;

    if (miner_service_take_result(&result, &job, timeout)) {
        stratum_debug_inc(&g_debug.share_candidates);
        submit_share(sock, config, &result, &job);
        while (miner_service_take_result(&result, &job, 0) == true) {
            stratum_debug_inc(&g_debug.share_candidates);
            submit_share(sock, config, &result, &job);
        }
    }
}

static void stratum_task(void *arg)
{
    (void)arg;

    for (;;) {
        if (!g_connect_requested) {
            vTaskDelay(pdMS_TO_TICKS(250));
            continue;
        }

        stratum_config_t config;
        stratum_debug_inc(&g_debug.connect_attempts);

        if (xSemaphoreTake(g_config_lock, pdMS_TO_TICKS(100)) == pdTRUE) {
            config = g_config;
            xSemaphoreGive(g_config_lock);
        } else {
            stratum_debug_set_event("config lock timeout");
            vTaskDelay(pdMS_TO_TICKS(1000));
            continue;
        }
        stratum_debug_set_event("connect attempt host=%s port=%u", config.host, config.port);

        Socket_t sock = connect_socket(&config);
        if (sock == FREERTOS_INVALID_SOCKET) {
            vTaskDelay(pdMS_TO_TICKS(5000));
            continue;
        }

        stratum_state_t state;
        memset(&state, 0, sizeof(state));
        g_connected = true;
        stratum_debug_inc(&g_debug.connect_successes);
        g_disconnect_requested = false;
        send_subscribe_authorize(sock, &config);

        char line[STRATUM_LINE_BUFFER_BYTES];
        size_t used = 0;

        while (!g_disconnect_requested) {
            char ch;
            BaseType_t got = FreeRTOS_recv(sock, &ch, 1, 0);

            if (got == 0) {
                drain_share_results(sock, &config, pdMS_TO_TICKS(25));
                refill_if_idle(&state);
                continue;
            }
            if (got < 0) {
                if (got != -pdFREERTOS_ERRNO_EWOULDBLOCK) {
                    stratum_debug_set_recv_status(got);
                    stratum_debug_set_event("recv error rc=%ld", (long)got);
                    break;
                }
                drain_share_results(sock, &config, pdMS_TO_TICKS(25));
                refill_if_idle(&state);
                continue;
            }

            if (ch == '\n') {
                line[used] = '\0';
                handle_stratum_line(line, &state);
                used = 0;
                drain_share_results(sock, &config, 0);
                refill_if_idle(&state);
            } else if (ch != '\r') {
                if (used < (sizeof(line) - 1U)) {
                    line[used++] = ch;
                } else {
                    used = 0;
                    stratum_debug_set_event("rx line overflow");
                }
            }
        }

        FreeRTOS_closesocket(sock);
        g_connected = false;
        stratum_debug_inc(&g_debug.disconnects);

        if (!g_disconnect_requested) {
            vTaskDelay(pdMS_TO_TICKS(5000));
        }
    }
}

void stratum_client_start(void)
{
    g_config_lock = xSemaphoreCreateMutex();
    configASSERT(g_config_lock != NULL);
    g_debug_lock = xSemaphoreCreateMutex();
    configASSERT(g_debug_lock != NULL);
    xTaskCreate(stratum_task, "stratum", 4096, NULL, 3, NULL);
}

void stratum_client_set_config(const stratum_config_t *config)
{
    if (xSemaphoreTake(g_config_lock, pdMS_TO_TICKS(100)) == pdTRUE) {
        g_config = *config;
        xSemaphoreGive(g_config_lock);
    }
}

void stratum_client_get_config(stratum_config_t *config)
{
    if (xSemaphoreTake(g_config_lock, pdMS_TO_TICKS(100)) == pdTRUE) {
        *config = g_config;
        xSemaphoreGive(g_config_lock);
    }
}

void stratum_client_get_debug(stratum_debug_t *debug)
{
    if (xSemaphoreTake(g_debug_lock, pdMS_TO_TICKS(100)) == pdTRUE) {
        *debug = g_debug;
        xSemaphoreGive(g_debug_lock);
    }
}

void stratum_client_request_connect(void)
{
    g_connect_requested = true;
}

void stratum_client_request_disconnect(void)
{
    g_disconnect_requested = true;
    g_connect_requested = false;
}

bool stratum_client_is_connected(void)
{
    return g_connected;
}
