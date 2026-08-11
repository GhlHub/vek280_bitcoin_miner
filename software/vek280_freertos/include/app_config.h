#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stdint.h>

#ifndef MINER_AXI_BASEADDR
#define MINER_AXI_BASEADDR 0xA4000000UL
#endif

#ifndef MINER_AXI_INSTANCE_STRIDE
#define MINER_AXI_INSTANCE_STRIDE 0x00001000UL
#endif

#define MINER_AXI_INSTANCES          1U
#define MINER_ENGINES_PER_INSTANCE  32U

#ifndef MINER_IRQ_ID
#define MINER_IRQ_ID 84U
#endif

#define MINER_NUM_ENGINES_EXPECTED 32U
#define MINER_HASHRATE_HS          12250000UL

#ifndef APP_USE_DDR_HEAP
#define APP_USE_DDR_HEAP           0
#endif

#ifndef APP_DDR_SMOKE_AT_BOOT
#define APP_DDR_SMOKE_AT_BOOT      1
#endif

#ifndef APP_DDR_TEST_BASE
#define APP_DDR_TEST_BASE          0x00100000UL
#endif

#ifndef APP_DDR_MPU_BASE
#define APP_DDR_MPU_BASE           0x00100000UL
#endif

#ifndef APP_DDR_MPU_SIZE
#define APP_DDR_MPU_SIZE           0x00100000UL
#endif

#define TELNET_LISTEN_PORT         23U
#define TELNET_RX_BUFFER_BYTES     256U
#define TELNET_TX_BUFFER_BYTES     512U

#define STRATUM_DEFAULT_HOST       "solo.ckpool.org"
#define STRATUM_DEFAULT_PORT       3333U
#define STRATUM_DEFAULT_USER       "replace-with-btc-address"
#define STRATUM_DEFAULT_PASSWORD   "x"
#define STRATUM_LINE_BUFFER_BYTES  2048U
#define STRATUM_JOB_ID_BYTES       64U
#define STRATUM_EXTRANONCE1_BYTES  32U
#define STRATUM_EXTRANONCE2_BYTES  16U
#define STRATUM_COINBASE_BYTES     512U
#define STRATUM_MERKLE_BRANCHES    16U
#define STRATUM_SCAN_NONCE_COUNT   0xffffffffUL

#define NET_USE_DHCP               1
#define NET_HOSTNAME               "vek280-miner"

static const uint8_t kDefaultMacAddress[6] = {
    0x02, 0x00, 0x00, 0x28, 0x02, 0x80
};

static const uint8_t kStaticIpAddress[4] = { 192, 168, 1, 80 };
static const uint8_t kStaticNetmask[4]   = { 255, 255, 255, 0 };
static const uint8_t kStaticGateway[4]   = { 192, 168, 1, 1 };
static const uint8_t kStaticDns[4]       = { 1, 1, 1, 1 };

#endif
