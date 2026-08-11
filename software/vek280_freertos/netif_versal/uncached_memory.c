/*
 * Local VEK280 descriptor-memory provider for the FreeRTOS+TCP Xilinx GEM port.
 *
 * The imported upstream helper depends on legacy DDR address macros that are not
 * emitted by the 2026.1 SDT BSP for this R5 domain. Keep the app build self
 * contained and provide an aligned pool for the small GEM descriptor allocations.
 */

#include <stdint.h>
#include <string.h>

#include "FreeRTOS.h"
#include "FreeRTOS_IP.h"
#include "uncached_memory.h"
#include "xil_mpu.h"
#include "xil_printf.h"
#include "xreg_cortexr5.h"

#ifndef uncMEMORY_SIZE
    #define uncMEMORY_SIZE       0x800U
#endif

#define uncALIGNMENT_SIZE        64U

static uint8_t ucDmaDescriptorPool[ uncMEMORY_SIZE ] __attribute__( ( section( ".ddr_bss" ), aligned( uncMEMORY_SIZE ) ) );
static uint32_t ulDmaDescriptorOffset;
static uint8_t ucPoolInitialised;

uint8_t ucIsCachedMemory( const uint8_t * pucBuffer )
{
    const uint8_t * pucPoolStart = ucDmaDescriptorPool;
    const uint8_t * pucPoolEnd = ucDmaDescriptorPool + uncMEMORY_SIZE;

    return ( ( pucBuffer >= pucPoolStart ) && ( pucBuffer < pucPoolEnd ) ) ? pdFALSE : pdTRUE;
}

uint8_t * pucGetUncachedMemory( uint32_t ulSize )
{
    uint32_t ulAlignedSize = ( ulSize + uncALIGNMENT_SIZE - 1U ) & ~( uncALIGNMENT_SIZE - 1U );
    uint8_t * pucReturn = NULL;

    if( ucPoolInitialised == 0U )
    {
        u32 status;

        status = Xil_SetMPURegion( ( INTPTR ) ucDmaDescriptorPool,
                                   uncMEMORY_SIZE,
                                   STRONG_ORDERD_SHARED | PRIV_RW_USER_RW );
        xil_printf( "dma pool: base=0x%08lx size=%lu mpu=%lu\r\n",
                    ( unsigned long ) ucDmaDescriptorPool,
                    ( unsigned long ) uncMEMORY_SIZE,
                    ( unsigned long ) status );
        ucPoolInitialised = 1U;
    }

    if( ( ulDmaDescriptorOffset + ulAlignedSize ) <= uncMEMORY_SIZE )
    {
        pucReturn = &( ucDmaDescriptorPool[ ulDmaDescriptorOffset ] );
        memset( pucReturn, 0, ulAlignedSize );
        ulDmaDescriptorOffset += ulAlignedSize;
    }

    return pucReturn;
}
