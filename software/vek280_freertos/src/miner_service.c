#include "miner_service.h"

#include <string.h>

#include "FreeRTOS.h"
#include "portmacro.h"
#include "queue.h"
#include "semphr.h"
#include "task.h"

#include "app_config.h"

static QueueHandle_t g_job_queue;
static QueueHandle_t g_result_queue;
static SemaphoreHandle_t g_irq_sem;
static SemaphoreHandle_t g_result_lock;
static miner_result_t g_last_result;
static miner_job_t g_last_result_job;
static miner_job_t g_active_job;
static volatile bool g_have_result;
static volatile bool g_have_active_job;
static miner_service_stats_t g_stats;
static bool g_range_active;
static volatile bool g_stop_requested;

typedef struct {
    miner_result_t result;
    miner_job_t job;
} miner_result_event_t;

typedef struct {
    miner_job_t job;
    bool clean_job;
} miner_job_request_t;

enum {
    MINER_RANGE_COMPLETE = 1U,
    MINER_RANGE_PREEMPTED = 2U,
    MINER_RANGE_STOPPED = 3U,
};

typedef void (*miner_irq_handler_t)(void *);
extern BaseType_t xPortInstallInterruptHandler(uint16_t ucInterruptID,
                                               miner_irq_handler_t pxHandler,
                                               void *pvCallBackRef);
extern void vPortEnableInterrupt(uint8_t ucInterruptID);

static void miner_irq_handler(void *arg)
{
    BaseType_t higher_priority_task_woken = pdFALSE;

    (void)arg;
    ++g_stats.irq_count;
    xSemaphoreGiveFromISR(g_irq_sem, &higher_priority_task_woken);
    portYIELD_FROM_ISR(higher_priority_task_woken);
}

static void miner_install_irq(void)
{
    BaseType_t ok;

    ok = xPortInstallInterruptHandler((uint8_t)MINER_IRQ_ID, miner_irq_handler, NULL);
    configASSERT(ok == pdPASS);
    vPortEnableInterrupt((uint8_t)MINER_IRQ_ID);
}

static void miner_finish_range(uint32_t reason)
{
    uint32_t elapsed_ticks;
    uint64_t estimated;

    if (!g_range_active) {
        return;
    }

    elapsed_ticks = (uint32_t)xTaskGetTickCount() - g_stats.active_job_tick;
    estimated = ((uint64_t)elapsed_ticks * (uint64_t)MINER_HASHRATE_HS) /
                (uint64_t)configTICK_RATE_HZ;
    if (estimated > g_stats.active_nonce_count) {
        estimated = g_stats.active_nonce_count;
    }
    if (reason == MINER_RANGE_COMPLETE) {
        estimated = g_stats.active_nonce_count;
        ++g_stats.ranges_completed;
    } else if (reason == MINER_RANGE_PREEMPTED) {
        ++g_stats.ranges_preempted;
    } else {
        ++g_stats.ranges_stopped;
    }

    g_stats.nonce_candidates_completed_estimate += estimated;
    g_stats.last_range_elapsed_ticks = elapsed_ticks;
    g_stats.last_range_reason = reason;
    g_range_active = false;
    g_stop_requested = false;
}

static void miner_task(void *arg)
{
    (void)arg;

    miner_init(MINER_AXI_BASEADDR);
    miner_install_irq();

    for (;;) {
        miner_job_request_t request;

        if (xQueueReceive(g_job_queue, &request, pdMS_TO_TICKS(25)) == pdTRUE) {
            if (g_range_active) {
                if (request.clean_job ||
                    ((miner_status() & MINER_STATUS_RUNNING) != 0U)) {
                    miner_finish_range(MINER_RANGE_PREEMPTED);
                    if (request.clean_job) {
                        ++g_stats.ranges_preempted_clean_job;
                    }
                } else {
                    miner_finish_range(MINER_RANGE_COMPLETE);
                }
            }
            g_active_job = request.job;
            g_have_active_job = true;
            miner_program_job(request.job.midstate, request.job.header_tail,
                              request.job.target);
            miner_start_range(request.job.nonce_start, request.job.nonce_count);
            ++g_stats.jobs_started;
            g_stats.nonce_candidates_issued += request.job.nonce_count;
            g_stats.active_nonce_start = request.job.nonce_start;
            g_stats.active_nonce_count = request.job.nonce_count;
            g_stats.active_job_tick = (uint32_t)xTaskGetTickCount();
            g_range_active = true;
            g_stop_requested = false;
        } else if (g_range_active &&
                   ((miner_status() & MINER_STATUS_RUNNING) == 0U)) {
            miner_finish_range(g_stop_requested ? MINER_RANGE_STOPPED :
                                                  MINER_RANGE_COMPLETE);
        }

        (void)xSemaphoreTake(g_irq_sem, pdMS_TO_TICKS(100));

        miner_result_t result;
        while (miner_read_result(&result)) {
            miner_result_event_t event;

            memset(&event, 0, sizeof(event));
            event.result = result;
            if (g_have_active_job) {
                event.job = g_active_job;
            }

            if (xSemaphoreTake(g_result_lock, pdMS_TO_TICKS(10)) == pdTRUE) {
                g_last_result = result;
                g_last_result_job = event.job;
                g_have_result = true;
                xSemaphoreGive(g_result_lock);
            }

            ++g_stats.result_count;
            g_stats.last_result_tick = (uint32_t)xTaskGetTickCount();
            if (xQueueSend(g_result_queue, &event, 0) != pdTRUE) {
                ++g_stats.result_queue_drops;
            }
        }
    }
}

void miner_service_start(void)
{
    g_job_queue = xQueueCreate(1, sizeof(miner_job_request_t));
    g_result_queue = xQueueCreate(8, sizeof(miner_result_event_t));
    g_irq_sem = xSemaphoreCreateBinary();
    g_result_lock = xSemaphoreCreateMutex();
    configASSERT(g_job_queue != NULL);
    configASSERT(g_result_queue != NULL);
    configASSERT(g_irq_sem != NULL);
    configASSERT(g_result_lock != NULL);
    xTaskCreate(miner_task, "miner", 1024, NULL, 4, NULL);
}

void miner_service_submit_job(const miner_job_t *job, bool clean_job)
{
    miner_job_request_t request;

    if (job == NULL) {
        return;
    }
    request.job = *job;
    request.clean_job = clean_job;
    ++g_stats.jobs_queued;
    (void)xQueueOverwrite(g_job_queue, &request);
}

void miner_service_stop_scan(void)
{
    g_stop_requested = true;
    miner_stop();
}

void miner_service_clear(void)
{
    miner_clear();
    if (xSemaphoreTake(g_result_lock, pdMS_TO_TICKS(10)) == pdTRUE) {
        memset(&g_last_result, 0, sizeof(g_last_result));
        memset(&g_last_result_job, 0, sizeof(g_last_result_job));
        g_have_result = false;
        xSemaphoreGive(g_result_lock);
    }
}

uint32_t miner_service_status(void)
{
    uint32_t status = miner_status();

    if ((status & MINER_STATUS_OVERFLOW) != 0U) {
        ++g_stats.overflow_polls;
    }
    return status;
}

void miner_service_get_stats(miner_service_stats_t *stats)
{
    if (stats != NULL) {
        *stats = g_stats;
    }
}

bool miner_service_get_last_result(miner_result_t *result)
{
    bool have_result = false;

    if (xSemaphoreTake(g_result_lock, pdMS_TO_TICKS(10)) == pdTRUE) {
        if (g_have_result) {
            *result = g_last_result;
            have_result = true;
        }
        xSemaphoreGive(g_result_lock);
    }

    return have_result;
}

bool miner_service_take_result(miner_result_t *result, miner_job_t *job, TickType_t timeout)
{
    miner_result_event_t event;

    if (xQueueReceive(g_result_queue, &event, timeout) != pdTRUE) {
        return false;
    }

    *result = event.result;
    *job = event.job;
    return true;
}
