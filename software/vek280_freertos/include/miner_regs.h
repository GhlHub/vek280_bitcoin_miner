#ifndef MINER_REGS_H
#define MINER_REGS_H

#include <stdbool.h>
#include <stdint.h>

#define MINER_REG_CONTROL       0x000U
#define MINER_REG_STATUS        0x004U
#define MINER_REG_NUM_ENGINES   0x008U
#define MINER_REG_MIDSTATE0     0x020U
#define MINER_REG_HEADER_TAIL0  0x040U
#define MINER_REG_TARGET0       0x060U
#define MINER_REG_NONCE_START   0x080U
#define MINER_REG_NONCE_COUNT   0x084U
#define MINER_REG_RESULT_NONCE  0x090U
#define MINER_REG_RESULT_ENGINE 0x094U
#define MINER_REG_RESULT_STATUS 0x098U
#define MINER_REG_RESULT_HASH0  0x0a0U

#define MINER_CONTROL_START     (1U << 0)
#define MINER_CONTROL_STOP      (1U << 1)
#define MINER_CONTROL_CLEAR     (1U << 2)

#define MINER_STATUS_RUNNING    (1U << 0)
#define MINER_STATUS_RESULT     (1U << 1)
#define MINER_STATUS_DONE       (1U << 2)
#define MINER_STATUS_OVERFLOW   (1U << 3)

#define MINER_RESULT_STATUS_RESULT   (1U << 0)
#define MINER_RESULT_STATUS_OVERFLOW (1U << 1)

typedef struct {
    uint32_t nonce;
    uint32_t engine;
    uint32_t status;
    uint32_t hash[8];
} miner_result_t;

void miner_init(uintptr_t base_addr);
uint32_t miner_read_reg(uint32_t offset);
uint32_t miner_read_reg_instance(uint32_t instance, uint32_t offset);
void miner_write_reg(uint32_t offset, uint32_t value);
void miner_write_reg_instance(uint32_t instance, uint32_t offset, uint32_t value);
uint32_t miner_num_engines(void);
uint32_t miner_status(void);
void miner_clear(void);
void miner_stop(void);
void miner_program_job(const uint32_t midstate[8],
                       const uint32_t header_tail[4],
                       const uint32_t target[8]);
void miner_start_range(uint32_t nonce_start, uint32_t nonce_count);
bool miner_read_result(miner_result_t *result);

#endif
