#ifndef TELEMETRY_H
#define TELEMETRY_H

#include <stdbool.h>
#include <stdint.h>

typedef struct {
    bool available;
    int32_t temperature_centi_c;
    int32_t temperature_max_centi_c;
    int32_t temperature_min_centi_c;
    uint32_t alarm_status;
} telemetry_health_t;

bool telemetry_get_health(telemetry_health_t *health);

#endif
