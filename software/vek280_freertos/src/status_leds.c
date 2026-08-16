#include "status_leds.h"

#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"

#include "app_config.h"

#ifdef __has_include
#if __has_include("xil_io.h")
#include "xil_io.h"
#define STATUS_LEDS_HAVE_XIL_IO 1
#endif
#endif

#define AXI_GPIO_DATA_OFFSET 0x0U
#define STATUS_LED_ALL_MASK  ((1U << 4U) - 1U)

static uint32_t g_status_led_state;

static void status_leds_write(uint32_t state)
{
#ifdef STATUS_LEDS_HAVE_XIL_IO
    Xil_Out32(STATUS_LED_AXI_BASEADDR + AXI_GPIO_DATA_OFFSET, state);
#else
    volatile uint32_t *reg =
        (volatile uint32_t *)(STATUS_LED_AXI_BASEADDR + AXI_GPIO_DATA_OFFSET);
    *reg = state;
#endif
}

static void status_leds_update(uint32_t set_mask, uint32_t toggle_mask)
{
    taskENTER_CRITICAL();
    g_status_led_state ^= toggle_mask;
    g_status_led_state |= set_mask;
    g_status_led_state &= STATUS_LED_ALL_MASK;
    status_leds_write(g_status_led_state);
    taskEXIT_CRITICAL();
}

void status_leds_init(void)
{
    taskENTER_CRITICAL();
    g_status_led_state = 0U;
    status_leds_write(g_status_led_state);
    taskEXIT_CRITICAL();
}

void status_leds_set_pool_r5_connected(bool connected)
{
    const uint32_t mask = 1U << STATUS_LED_POOL_R5_CONNECTED;

    taskENTER_CRITICAL();
    if (connected) {
        g_status_led_state |= mask;
    } else {
        g_status_led_state &= ~mask;
    }
    status_leds_write(g_status_led_state);
    taskEXIT_CRITICAL();
}

void status_leds_set_pool_attached(bool attached)
{
    const uint32_t mask = 1U << STATUS_LED_POOL_ATTACHED;

    taskENTER_CRITICAL();
    if (attached) {
        g_status_led_state |= mask;
    } else {
        g_status_led_state &= ~mask;
    }
    status_leds_write(g_status_led_state);
    taskEXIT_CRITICAL();
}

void status_leds_toggle_job_received(void)
{
    status_leds_update(0U, 1U << STATUS_LED_JOB_RECEIVED);
}

void status_leds_toggle_irq_processed(void)
{
    status_leds_update(0U, 1U << STATUS_LED_IRQ_PROCESSED);
}
