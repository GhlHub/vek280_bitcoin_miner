#ifndef MINER_SERVICE_H
#define MINER_SERVICE_H

#include <stdbool.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "app_config.h"
#include "miner_regs.h"

typedef struct {
    uint32_t midstate[8];
    uint32_t header_tail[4];
    uint32_t target[8];
    uint32_t nonce_start;
    uint32_t nonce_count;
    char job_id[STRATUM_JOB_ID_BYTES];
    char extranonce2[(STRATUM_EXTRANONCE2_BYTES * 2U) + 1U];
    char ntime[9];
} miner_job_t;

void miner_service_start(void);
void miner_service_submit_job(const miner_job_t *job);
void miner_service_stop_scan(void);
void miner_service_clear(void);
uint32_t miner_service_status(void);
bool miner_service_get_last_result(miner_result_t *result);
bool miner_service_take_result(miner_result_t *result, miner_job_t *job, TickType_t timeout);

#endif
