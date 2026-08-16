#include <stdint.h>

#include "FreeRTOS.h"
#include "FreeRTOS_IP.h"
#include "task.h"

#include "app_memory.h"
#include "app_config.h"
#include "miner_service.h"
#include "status_leds.h"
#include "stratum_client.h"
#include "telnet_server.h"
#include "xiltimer.h"

#ifdef __has_include
#if __has_include("xil_printf.h")
#include "xil_printf.h"
#define APP_HAVE_XIL_PRINTF 1
#endif
#endif

uint32_t SystemCoreClock = 333333333U;
static volatile BaseType_t g_network_up;
static volatile BaseType_t g_dhcp_acquired;
static volatile BaseType_t g_dhcp_failed;

void __real_XTimer_SetHandler(XTimer_TickHandler func,
                              void *callback_ref,
                              uint8_t priority);

void __wrap_XTimer_SetHandler(XTimer_TickHandler func,
                              void *callback_ref,
                              uint8_t priority)
{
    const uint8_t max_api_priority = (uint8_t)(configMAX_API_CALL_INTERRUPT_PRIORITY << 3);

    if (priority > max_api_priority) {
        priority = max_api_priority;
    }

    __real_XTimer_SetHandler(func, callback_ref, priority);
}

uint32_t miner_platform_rand32(void)
{
    static uint32_t lfsr = 0x7a280001U;
    lfsr ^= lfsr << 13;
    lfsr ^= lfsr >> 17;
    lfsr ^= lfsr << 5;
    return lfsr;
}

void miner_platform_dhcp_succeeded(uint32_t ip_addr)
{
    (void)ip_addr;
    g_dhcp_acquired = pdTRUE;
    g_dhcp_failed = pdFALSE;
}

void miner_platform_dhcp_failed(uint32_t ip_addr)
{
    (void)ip_addr;
    g_dhcp_acquired = pdFALSE;
    g_dhcp_failed = pdTRUE;
}

static void app_log(const char *msg)
{
#ifdef APP_HAVE_XIL_PRINTF
    xil_printf("%s\r\n", msg);
#else
    (void)msg;
#endif
}

static void app_log_ipv4(const char *label, uint32_t addr)
{
#ifdef APP_HAVE_XIL_PRINTF
    uint32_t host_addr = FreeRTOS_ntohl(addr);

    xil_printf("%s%u.%u.%u.%u\r\n",
               label,
               (unsigned)((host_addr >> 24) & 0xffU),
               (unsigned)((host_addr >> 16) & 0xffU),
               (unsigned)((host_addr >> 8) & 0xffU),
               (unsigned)(host_addr & 0xffU));
#else
    (void)label;
    (void)addr;
#endif
}

#ifdef APP_HAVE_XIL_PRINTF
static void app_log_hex32(const char *label, uint32_t value)
{
    xil_printf("%s0x%08lx\r\n", label, (unsigned long)value);
}
#endif

static void app_log_network_config(void)
{
    uint32_t ip = 0;
    uint32_t netmask = 0;
    uint32_t gateway = 0;
    uint32_t dns = 0;

    FreeRTOS_GetAddressConfiguration(&ip, &netmask, &gateway, &dns);

#if NET_USE_DHCP
    if (g_dhcp_acquired == pdTRUE) {
        app_log("DHCP address acquired");
    } else if (g_dhcp_failed == pdTRUE) {
        app_log("DHCP failed; using fallback IP address");
    } else {
        app_log("network address configured");
    }
#else
    app_log("static IP address configured");
#endif

    app_log_ipv4("ip address: ", ip);
    app_log_ipv4("netmask: ", netmask);
    app_log_ipv4("gateway: ", gateway);
    app_log_ipv4("dns: ", dns);
}

void vApplicationMallocFailedHook(void)
{
    app_log("malloc failed");
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *name)
{
    (void)task;
    (void)name;
    app_log("stack overflow");
    taskDISABLE_INTERRUPTS();
    for (;;) {}
}

void vApplicationIPNetworkEventHook(eIPCallbackEvent_t event)
{
    if (event == eNetworkUp) {
        app_log("network event: up");
        g_network_up = pdTRUE;
    } else {
        app_log("network event: down");
        g_network_up = pdFALSE;
    }
}

const char *pcApplicationHostnameHook(void)
{
    return NET_HOSTNAME;
}

BaseType_t xApplicationGetRandomNumber(uint32_t *rnd)
{
    *rnd = miner_platform_rand32();
    return pdTRUE;
}

uint32_t ulApplicationGetNextSequenceNumber(uint32_t src_addr,
                                            uint16_t src_port,
                                            uint32_t dst_addr,
                                            uint16_t dst_port)
{
    return miner_platform_rand32() ^ src_addr ^ dst_addr ^ ((uint32_t)src_port << 16) ^ dst_port;
}

static void network_wait_task(void *arg)
{
    uint32_t waits = 0;

    (void)arg;

    app_log("netwait task running");

    while (g_network_up != pdTRUE) {
        if ((waits++ % 20U) == 0U) {
            app_log("waiting for network up");
        }
        vTaskDelay(pdMS_TO_TICKS(250));
    }

    app_log("network up");
    app_log_network_config();
    miner_service_start();
    stratum_client_start();
    telnet_server_start();

    vTaskDelete(NULL);
}

int main(void)
{
    BaseType_t task_status;

    app_log("VEK280 miner FreeRTOS app starting");
    status_leds_init();
    app_log(app_ddr_configure_mpu() ? "DDR MPU region configured" : "DDR MPU region failed");
#if APP_USE_DDR_HEAP
    app_log(app_ddr_smoke_test() ? "DDR smoke test passed" : "DDR smoke test failed");
    app_log_hex32("FreeRTOS heap base: ", (uint32_t)app_freertos_heap_addr());
    app_log_hex32("FreeRTOS heap size: ", app_freertos_heap_size());
#else
    app_log("DDR heap disabled; using OCM heap");
#if APP_DDR_SMOKE_AT_BOOT
    app_log_hex32("DDR smoke base: ", (uint32_t)APP_DDR_TEST_BASE);
    app_log(app_ddr_smoke_test() ? "DDR smoke test passed" : "DDR smoke test failed");
#endif
#endif

    FreeRTOS_IPInit(kStaticIpAddress,
                    kStaticNetmask,
                    kStaticGateway,
                    kStaticDns,
                    kDefaultMacAddress);
    app_log("FreeRTOS_IPInit returned");

    task_status = xTaskCreate(network_wait_task, "netwait", 1024, NULL, 3, NULL);
    if (task_status != pdPASS) {
        app_log("netwait task create failed");
    } else {
        app_log("netwait task created");
    }

    app_log("starting scheduler");
    vTaskStartScheduler();

    app_log("scheduler returned");
    for (;;) {}
}
