#include "miner_regs.h"

#include "app_config.h"

#ifdef __has_include
#if __has_include("xil_io.h")
#include "xil_io.h"
#define MINER_HAVE_XIL_IO 1
#endif
#endif

static uintptr_t g_miner_base;

static uintptr_t miner_instance_base(uint32_t instance)
{
    return g_miner_base + ((uintptr_t)instance * (uintptr_t)MINER_AXI_INSTANCE_STRIDE);
}

static uint32_t miner_read_at(uintptr_t addr)
{
#ifdef MINER_HAVE_XIL_IO
    return Xil_In32(addr);
#else
    volatile uint32_t *reg = (volatile uint32_t *)addr;
    return *reg;
#endif
}

static void miner_write_at(uintptr_t addr, uint32_t value)
{
#ifdef MINER_HAVE_XIL_IO
    Xil_Out32(addr, value);
#else
    volatile uint32_t *reg = (volatile uint32_t *)addr;
    *reg = value;
#endif
}

void miner_init(uintptr_t base_addr)
{
    g_miner_base = base_addr;
    miner_stop();
    miner_clear();
}

uint32_t miner_read_reg(uint32_t offset)
{
    return miner_read_reg_instance(0, offset);
}

uint32_t miner_read_reg_instance(uint32_t instance, uint32_t offset)
{
    if (instance >= MINER_AXI_INSTANCES) {
        return 0U;
    }

    return miner_read_at(miner_instance_base(instance) + offset);
}

void miner_write_reg(uint32_t offset, uint32_t value)
{
    miner_write_reg_instance(0, offset, value);
}

void miner_write_reg_instance(uint32_t instance, uint32_t offset, uint32_t value)
{
    if (instance >= MINER_AXI_INSTANCES) {
        return;
    }

    miner_write_at(miner_instance_base(instance) + offset, value);
}

uint32_t miner_num_engines(void)
{
    uint32_t total = 0;

    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        total += miner_read_reg_instance(inst, MINER_REG_NUM_ENGINES);
    }

    return total;
}

uint32_t miner_status(void)
{
    uint32_t aggregate = 0;
    bool all_done = true;

    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        uint32_t status = miner_read_reg_instance(inst, MINER_REG_STATUS);

        if ((status & MINER_STATUS_RUNNING) != 0U) {
            aggregate |= MINER_STATUS_RUNNING;
        }
        if ((status & MINER_STATUS_RESULT) != 0U) {
            aggregate |= MINER_STATUS_RESULT;
        }
        if ((status & MINER_STATUS_OVERFLOW) != 0U) {
            aggregate |= MINER_STATUS_OVERFLOW;
        }
        if ((status & MINER_STATUS_DONE) == 0U) {
            all_done = false;
        }
    }

    if (all_done) {
        aggregate |= MINER_STATUS_DONE;
    }

    return aggregate;
}

void miner_clear(void)
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        miner_write_reg_instance(inst, MINER_REG_CONTROL, MINER_CONTROL_CLEAR);
        miner_write_reg_instance(inst, MINER_REG_RESULT_STATUS,
                                 MINER_RESULT_STATUS_RESULT |
                                 MINER_RESULT_STATUS_OVERFLOW);
    }
}

void miner_stop(void)
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        miner_write_reg_instance(inst, MINER_REG_CONTROL, MINER_CONTROL_STOP);
    }
}

void miner_irq_mask_all(void)
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        uint32_t control = miner_read_reg_instance(inst, MINER_REG_IRQ_CONTROL);

        miner_write_reg_instance(inst, MINER_REG_IRQ_CONTROL,
                                 control | MINER_IRQ_CONTROL_MASK);
    }
}

void miner_irq_unmask_all(void)
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        uint32_t control = miner_read_reg_instance(inst, MINER_REG_IRQ_CONTROL);

        miner_write_reg_instance(inst, MINER_REG_IRQ_CONTROL,
                                 control & ~MINER_IRQ_CONTROL_MASK);
    }
}

void miner_program_job(const uint32_t midstate[8],
                       const uint32_t header_tail[4],
                       const uint32_t target[8])
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        for (uint32_t i = 0; i < 8U; ++i) {
            miner_write_reg_instance(inst, MINER_REG_MIDSTATE0 + (i * 4U), midstate[i]);
            miner_write_reg_instance(inst, MINER_REG_TARGET0 + (i * 4U), target[i]);
        }

        for (uint32_t i = 0; i < 4U; ++i) {
            miner_write_reg_instance(inst, MINER_REG_HEADER_TAIL0 + (i * 4U), header_tail[i]);
        }
    }
}

void miner_start_range(uint32_t nonce_start, uint32_t nonce_count)
{
    uint32_t base_count = nonce_count / MINER_AXI_INSTANCES;
    uint32_t remainder = nonce_count % MINER_AXI_INSTANCES;
    uint32_t range_start = nonce_start;

    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        uint32_t range_count = base_count + ((inst < remainder) ? 1U : 0U);

        miner_write_reg_instance(inst, MINER_REG_NONCE_START, range_start);
        miner_write_reg_instance(inst, MINER_REG_NONCE_COUNT, range_count);
        miner_write_reg_instance(inst, MINER_REG_CONTROL, MINER_CONTROL_START);
        range_start += range_count;
    }
}

bool miner_read_result(miner_result_t *result)
{
    for (uint32_t inst = 0; inst < MINER_AXI_INSTANCES; ++inst) {
        uint32_t result_status = miner_read_reg_instance(inst, MINER_REG_RESULT_STATUS);

        if ((result_status & MINER_RESULT_STATUS_RESULT) == 0U) {
            continue;
        }

        result->nonce = miner_read_reg_instance(inst, MINER_REG_RESULT_NONCE);
        result->engine = miner_read_reg_instance(inst, MINER_REG_RESULT_ENGINE) +
                         (inst * MINER_ENGINES_PER_INSTANCE);
        result->status = result_status;

        miner_write_reg_instance(inst, MINER_REG_RESULT_STATUS, MINER_RESULT_STATUS_RESULT);
        return true;
    }

    return false;
}
