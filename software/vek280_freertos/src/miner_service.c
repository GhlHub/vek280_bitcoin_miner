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

typedef struct {
    miner_result_t result;
    miner_job_t job;
} miner_result_event_t;

typedef void (*miner_irq_handler_t)(void *);
extern BaseType_t xPortInstallInterruptHandler(uint8_t ucInterruptID,
                                               miner_irq_handler_t pxHandler,
                                               void *pvCallBackRef);
extern void vPortEnableInterrupt(uint8_t ucInterruptID);

static void miner_irq_handler(void *arg)
{
    BaseType_t higher_priority_task_woken = pdFALSE;

    (void)arg;
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

static void miner_task(void *arg)
{
    (void)arg;

    miner_init(MINER_AXI_BASEADDR);
    miner_install_irq();

    for (;;) {
        miner_job_t job;

        if (xQueueReceive(g_job_queue, &job, pdMS_TO_TICKS(25)) == pdTRUE) {
            g_active_job = job;
            g_have_active_job = true;
            miner_program_job(job.midstate, job.header_tail, job.target);
            miner_start_range(job.nonce_start, job.nonce_count);
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

            (void)xQueueSend(g_result_queue, &event, 0);
        }
    }
}

void miner_service_start(void)
{
    g_job_queue = xQueueCreate(1, sizeof(miner_job_t));
    g_result_queue = xQueueCreate(8, sizeof(miner_result_event_t));
    g_irq_sem = xSemaphoreCreateBinary();
    g_result_lock = xSemaphoreCreateMutex();
    configASSERT(g_job_queue != NULL);
    configASSERT(g_result_queue != NULL);
    configASSERT(g_irq_sem != NULL);
    configASSERT(g_result_lock != NULL);
    xTaskCreate(miner_task, "miner", 1024, NULL, 4, NULL);
}

void miner_service_submit_job(const miner_job_t *job)
{
    (void)xQueueOverwrite(g_job_queue, job);
}

void miner_service_stop_scan(void)
{
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
    return miner_status();
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
