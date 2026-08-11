#include "app_memory.h"

#include "FreeRTOS.h"
#include "app_config.h"
#include "xil_mpu.h"
#include "xreg_cortexr5.h"
#include "xstatus.h"

#define DDR_TEST_WORDS 256U

#if APP_USE_DDR_HEAP
uint8_t ucHeap[ configTOTAL_HEAP_SIZE ] __attribute__( ( section( ".ddr_heap" ), aligned( 64 ) ) );

static uint32_t ddr_test_buffer[ DDR_TEST_WORDS ] __attribute__( ( section( ".ddr_bss" ), aligned( 64 ) ) );
#endif

uintptr_t app_freertos_heap_addr(void)
{
#if APP_USE_DDR_HEAP
    return (uintptr_t)ucHeap;
#else
    return 0U;
#endif
}

uint32_t app_freertos_heap_size(void)
{
#if APP_USE_DDR_HEAP
    return (uint32_t)sizeof(ucHeap);
#else
    return (uint32_t)configTOTAL_HEAP_SIZE;
#endif
}

bool app_ddr_configure_mpu(void)
{
    u32 status = Xil_SetMPURegion((INTPTR)APP_DDR_MPU_BASE,
                                  APP_DDR_MPU_SIZE,
                                  NORM_NSHARED_NCACHE | PRIV_RW_USER_RW);

    return status == XST_SUCCESS;
}

bool app_ddr_smoke_test(void)
{
#if APP_USE_DDR_HEAP
    volatile uint32_t *test_buffer = ddr_test_buffer;
#else
    volatile uint32_t *test_buffer = (volatile uint32_t *)(uintptr_t)APP_DDR_TEST_BASE;
#endif

    for (uint32_t i = 0; i < DDR_TEST_WORDS; ++i) {
        test_buffer[i] = 0xa5a50000U ^ (i * 0x01010101U);
    }

    for (uint32_t i = 0; i < DDR_TEST_WORDS; ++i) {
        uint32_t expected = 0xa5a50000U ^ (i * 0x01010101U);

        if (test_buffer[i] != expected) {
            return false;
        }
    }

    for (uint32_t i = 0; i < DDR_TEST_WORDS; ++i) {
        test_buffer[i] = 0x5a5affffU ^ (i * 0x11111111U);
    }

    for (uint32_t i = 0; i < DDR_TEST_WORDS; ++i) {
        uint32_t expected = 0x5a5affffU ^ (i * 0x11111111U);

        if (test_buffer[i] != expected) {
            return false;
        }
    }

    return true;
}
