#include "miner_regs.h"

#ifdef __has_include
#if __has_include("xil_io.h")
#include "xil_io.h"
#define MINER_HAVE_XIL_IO 1
#endif
#endif

static uintptr_t g_miner_base;

void miner_init(uintptr_t base_addr)
{
    g_miner_base = base_addr;
    miner_clear();
    miner_stop();
}

uint32_t miner_read_reg(uint32_t offset)
{
#ifdef MINER_HAVE_XIL_IO
    return Xil_In32(g_miner_base + offset);
#else
    volatile uint32_t *reg = (volatile uint32_t *)(g_miner_base + offset);
    return *reg;
#endif
}

void miner_write_reg(uint32_t offset, uint32_t value)
{
#ifdef MINER_HAVE_XIL_IO
    Xil_Out32(g_miner_base + offset, value);
#else
    volatile uint32_t *reg = (volatile uint32_t *)(g_miner_base + offset);
    *reg = value;
#endif
}

uint32_t miner_num_engines(void)
{
    return miner_read_reg(MINER_REG_NUM_ENGINES);
}

uint32_t miner_status(void)
{
    return miner_read_reg(MINER_REG_STATUS);
}

void miner_clear(void)
{
    miner_write_reg(MINER_REG_CONTROL, MINER_CONTROL_CLEAR);
    miner_write_reg(MINER_REG_RESULT_STATUS, MINER_STATUS_RESULT | MINER_STATUS_OVERFLOW);
}

void miner_stop(void)
{
    miner_write_reg(MINER_REG_CONTROL, MINER_CONTROL_STOP);
}

void miner_program_job(const uint32_t midstate[8],
                       const uint32_t header_tail[4],
                       const uint32_t target[8])
{
    for (uint32_t i = 0; i < 8U; ++i) {
        miner_write_reg(MINER_REG_MIDSTATE0 + (i * 4U), midstate[i]);
        miner_write_reg(MINER_REG_TARGET0 + (i * 4U), target[i]);
    }

    for (uint32_t i = 0; i < 4U; ++i) {
        miner_write_reg(MINER_REG_HEADER_TAIL0 + (i * 4U), header_tail[i]);
    }
}

void miner_start_range(uint32_t nonce_start, uint32_t nonce_count)
{
    miner_write_reg(MINER_REG_NONCE_START, nonce_start);
    miner_write_reg(MINER_REG_NONCE_COUNT, nonce_count);
    miner_write_reg(MINER_REG_CONTROL, MINER_CONTROL_START);
}

bool miner_read_result(miner_result_t *result)
{
    uint32_t result_status = miner_read_reg(MINER_REG_RESULT_STATUS);

    if ((result_status & MINER_STATUS_RESULT) == 0U) {
        return false;
    }

    result->nonce = miner_read_reg(MINER_REG_RESULT_NONCE);
    result->engine = miner_read_reg(MINER_REG_RESULT_ENGINE);
    result->status = result_status;

    for (uint32_t i = 0; i < 8U; ++i) {
        result->hash[i] = miner_read_reg(MINER_REG_RESULT_HASH0 + (i * 4U));
    }

    miner_write_reg(MINER_REG_RESULT_STATUS, MINER_STATUS_RESULT);
    return true;
}
