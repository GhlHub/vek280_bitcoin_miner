#ifndef APP_MEMORY_H
#define APP_MEMORY_H

#include <stdbool.h>
#include <stdint.h>

uintptr_t app_freertos_heap_addr(void);
uint32_t app_freertos_heap_size(void);
bool app_ddr_configure_mpu(void);
bool app_ddr_smoke_test(void);

#endif
