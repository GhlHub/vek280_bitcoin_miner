#ifndef FREERTOS_IP_CONFIG_H
#define FREERTOS_IP_CONFIG_H

#include <stdint.h>

#include "app_config.h"

#define ipconfigBYTE_ORDER                         pdFREERTOS_LITTLE_ENDIAN
#define ipconfigIPv4_BACKWARD_COMPATIBLE           1
#define ipconfigDRIVER_INCLUDED_RX_IP_CHECKSUM     1
#define ipconfigDRIVER_INCLUDED_TX_IP_CHECKSUM     1
#define ipconfigNIC_LINKSPEED_AUTODETECT           1
#define ipconfigHAS_PRINTF                         1
#define ipconfigHAS_DEBUG_PRINTF                   1
#define ipconfigUSE_DHCP                           NET_USE_DHCP
#define ipconfigUSE_DHCP_HOOK                      0
#define ipconfigUSE_DNS                            1
#define ipconfigUSE_DNS_CACHE                      1
#define ipconfigUSE_NETWORK_EVENT_HOOK             1
#define ipconfigUSE_TCP                            1
#define ipconfigUSE_TCP_WIN                        1
#define ipconfigUSE_IPv4                           1
#define ipconfigUSE_IPv6                           0
#define ipconfigNETWORK_MTU                        1500
#define ipconfigNUM_NETWORK_BUFFER_DESCRIPTORS     12
#define ipconfigEVENT_QUEUE_LENGTH                 20
#define ipconfigIP_TASK_PRIORITY                   6
#define ipconfigIP_TASK_STACK_SIZE_WORDS           1024
#define ipconfigTCP_TX_BUFFER_LENGTH               (4 * 1460)
#define ipconfigTCP_RX_BUFFER_LENGTH               (4 * 1460)
#define ipconfigTCP_WIN_SEG_COUNT                  4
#define ipconfigTCP_HANG_PROTECTION                1
#define ipconfigTCP_KEEP_ALIVE                     1
#define ipconfigSOCK_DEFAULT_RECEIVE_BLOCK_TIME    5000
#define ipconfigSOCK_DEFAULT_SEND_BLOCK_TIME       5000
#define ipconfigDNS_CACHE_NAME_LENGTH              96
#define ipconfigDNS_REQUEST_ATTEMPTS               4

uint32_t miner_platform_rand32(void);
void miner_platform_dhcp_succeeded(uint32_t ip_addr);
void miner_platform_dhcp_failed(uint32_t ip_addr);

#define iptraceDHCP_SUCCEEDED(ip_addr) \
    miner_platform_dhcp_succeeded((ip_addr))

#define iptraceDHCP_REQUESTS_FAILED_USING_DEFAULT_IP_ADDRESS(ip_addr) \
    miner_platform_dhcp_failed((ip_addr))

#endif
