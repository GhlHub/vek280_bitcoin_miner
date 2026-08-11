#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include <stdint.h>

#if defined(__has_include)
#if __has_include("xparameters.h")
#include "xparameters.h"
#endif
#endif

extern uint32_t SystemCoreClock;

#define configUSE_PREEMPTION                    1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION 0
#define configUSE_IDLE_HOOK                     0
#define configUSE_TICK_HOOK                     0
#define configCPU_CLOCK_HZ                      SystemCoreClock
#define configTICK_RATE_HZ                      1000
#define configMAX_PRIORITIES                    7
#define configMINIMAL_STACK_SIZE                256
#define configTOTAL_HEAP_SIZE                   (80U * 1024U)
#define configMAX_TASK_NAME_LEN                 16
#define configUSE_16_BIT_TICKS                  0
#define configIDLE_SHOULD_YIELD                 1
#define configUSE_MUTEXES                       1
#define configUSE_RECURSIVE_MUTEXES             1
#define configUSE_COUNTING_SEMAPHORES           1
#define configUSE_QUEUE_SETS                    0
#define configUSE_TASK_NOTIFICATIONS            1
#define configUSE_TIMERS                        1
#define configTIMER_TASK_PRIORITY               5
#define configTIMER_QUEUE_LENGTH                8
#define configTIMER_TASK_STACK_DEPTH            512
#define configCHECK_FOR_STACK_OVERFLOW          2
#define configUSE_MALLOC_FAILED_HOOK            1
#define configSUPPORT_DYNAMIC_ALLOCATION        1
#define configSUPPORT_STATIC_ALLOCATION         0

#define configUNIQUE_INTERRUPT_PRIORITIES       32
#define configMAX_API_CALL_INTERRUPT_PRIORITY   18

#ifndef configINTERRUPT_CONTROLLER_DEVICE_ID
#if defined(XPAR_SCUGIC_SINGLE_DEVICE_ID)
#define configINTERRUPT_CONTROLLER_DEVICE_ID    XPAR_SCUGIC_SINGLE_DEVICE_ID
#else
#define configINTERRUPT_CONTROLLER_DEVICE_ID    0
#endif
#endif

#ifndef configINTERRUPT_CONTROLLER_BASE_ADDRESS
#if defined(XPAR_SCUGIC_0_DIST_BASEADDR)
#define configINTERRUPT_CONTROLLER_BASE_ADDRESS XPAR_SCUGIC_0_DIST_BASEADDR
#else
#define configINTERRUPT_CONTROLLER_BASE_ADDRESS 0xF9000000UL
#endif
#endif

#ifndef configINTERRUPT_CONTROLLER_CPU_INTERFACE_OFFSET
#if defined(XPAR_SCUGIC_0_CPU_BASEADDR) && defined(XPAR_SCUGIC_0_DIST_BASEADDR)
#define configINTERRUPT_CONTROLLER_CPU_INTERFACE_OFFSET \
    (XPAR_SCUGIC_0_CPU_BASEADDR - XPAR_SCUGIC_0_DIST_BASEADDR)
#else
#define configINTERRUPT_CONTROLLER_CPU_INTERFACE_OFFSET 0x1000UL
#endif
#endif

#define configUSE_TRACE_FACILITY                0
#define configGENERATE_RUN_TIME_STATS           0
#define configUSE_STATS_FORMATTING_FUNCTIONS    0

#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_xTaskGetSchedulerState          1
#define INCLUDE_xTaskGetCurrentTaskHandle       1

#define configASSERT(x) do { if ((x) == 0) { taskDISABLE_INTERRUPTS(); for (;;) {} } } while (0)

#ifndef pdTICKS_TO_MS
#define pdTICKS_TO_MS(ticks) \
    ((TickType_t)(((uint64_t)(ticks) * 1000ULL) / (uint64_t)configTICK_RATE_HZ))
#endif

#endif
