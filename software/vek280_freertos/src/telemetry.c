#include "telemetry.h"

#include <string.h>

#ifdef __has_include
#if __has_include("xsysmonpsv.h")
#include "xstatus.h"
#include "xsysmonpsv.h"
#define APP_HAVE_SYSMONPSV 1
#endif
#endif

#ifdef APP_HAVE_SYSMONPSV
static XSysMonPsv g_sysmon;
static bool g_sysmon_initialized;
static bool g_sysmon_available;

static int32_t q8p7_to_centi_c(uint32_t raw)
{
    int32_t q8p7 = (int32_t)(int16_t)(raw & 0xffffU);

    return (q8p7 * 100) / 128;
}

static bool sysmon_init_once(void)
{
    XSysMonPsv_Config *config;

    if (g_sysmon_initialized) {
        return g_sysmon_available;
    }

    g_sysmon_initialized = true;
    config = XSysMonPsv_LookupConfig();
    if ((config != NULL) && (XSysMonPsv_CfgInitialize(&g_sysmon, config) == XST_SUCCESS)) {
        g_sysmon_available = true;
    }

    return g_sysmon_available;
}
#endif

bool telemetry_get_health(telemetry_health_t *health)
{
    if (health == NULL) {
        return false;
    }

    memset(health, 0, sizeof(*health));

#ifdef APP_HAVE_SYSMONPSV
    if (!sysmon_init_once()) {
        return false;
    }

    health->available = true;
    health->temperature_centi_c = q8p7_to_centi_c(
        XSysMonPsv_ReadDeviceTemp(&g_sysmon, XSYSMONPSV_VAL));
    health->temperature_max_centi_c = q8p7_to_centi_c(
        XSysMonPsv_ReadDeviceTemp(&g_sysmon, XSYSMONPSV_VAL_MAX));
    health->temperature_min_centi_c = q8p7_to_centi_c(
        XSysMonPsv_ReadDeviceTemp(&g_sysmon, XSYSMONPSV_VAL_MIN));
    health->alarm_status = XSysMonPsv_IntrGetStatus(&g_sysmon);
    return true;
#else
    return false;
#endif
}
