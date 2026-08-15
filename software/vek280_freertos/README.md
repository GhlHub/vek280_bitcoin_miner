# VEK280 FreeRTOS Miner Control App

This directory contains the PS-side FreeRTOS application scaffold for the VEK280
Bitcoin miner design.

Target architecture:
- Processor: Versal PS R5 FreeRTOS domain is the intended first target.
- Network: PS GEM0 Ethernet through FreeRTOS-Plus-TCP, with DHCP enabled by
  default.
- Miner control: AXI4-Lite MMIO at `0xA4000000` by default.
- PL interrupt: `pl_ps_irq0`; CIPS assigns legacy IRQ 84 (`0x54`), which the
  FreeRTOS SDT wrapper maps to R5 GIC SPI 116. The generic
  `XPAR_FPGA0_INTERRUPT_ID` header default is unrelated to this CIPS input.
- Remote control: unauthenticated telnet server on TCP port 23.
- Pool protocol: Stratum v1 client. Stratum v2 can be added later behind the same
  miner-control API.

Security note: telnet has no authentication and sends all data in clear text. Use it
only on a trusted lab network.

## Integration Steps

1. Generate the Vitis hardware export and FreeRTOS BSP:
   `make vitis-bsp`.
2. The generated Vitis platform is
   `vitis_ws/vek280_miner_platform/export/vek280_miner_platform/vek280_miner_platform.xpfm`.
3. The generated R5 FreeRTOS BSP is under
   `vitis_ws/vek280_miner_platform/psv_cortexr5_0/r5_freertos/bsp`.
4. Add these sources and include paths to the application:
   - `software/vek280_freertos/src`
   - `software/vek280_freertos/include`
   - `FreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/include`
   - the selected FreeRTOS portable compiler/CPU port
   - `FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/include`
   - `FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/Compiler/GCC`
   - `FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/NetworkInterface/xilinx_ultrascale`
5. Confirm the generated `xparameters.h` values for:
   - miner AXI base address
   - GIC device/interrupt IDs
   - GEM device ID
6. Update `include/app_config.h` if the generated addresses differ.

The Vitis 2026.1 BSP flow uses the Vitis Python API in
`software/vitis/create_bsp.py`; XSCT is disabled in this release. The hardware
export used by `make vitis-bsp` enables CIPS TTC0 because the Versal R5 FreeRTOS
BSP requires a PS TTC tick timer.

Run `make impl` again before producing final programming files from the current
source tree, because the BSP hardware export includes the TTC0 update.

Before importing into Vitis, `make sw-syntax` can be run from the repository root
to check the application sources against the local FreeRTOS-LTS headers.

## Runtime

The app starts the FreeRTOS scheduler, brings up the IP stack, waits for network
configuration, prints whether DHCP succeeded or fallback addressing was used, then
prints the IP address, netmask, gateway, and DNS server on the UART console before
starting:
- `miner_task`: handles PL miner control, installs the `pl_ps_irq0` handler using
  the Xilinx FreeRTOS interrupt hook, source-masks the level-sensitive miner IRQ
  in the ISR, and drains result FIFO entries into a share result queue before
  clearing and unmasking the source. Result handling is interrupt-driven; do not
  add routine result-register polling.
- `stratum_task`: connects to the configured mining pool, parses Stratum v1
  subscription, authorization, difficulty, and notify messages, materializes
  coinbase/merkle/header work for the PL miner, rolls `extranonce2` when a nonce
  range finishes, and submits found shares.
- `telnet_task`: exposes a minimal command shell.

Useful telnet commands:
- `help`
- `status`
- `regs`
- `start <nonce_start_hex> <nonce_count_hex>`
- `stop`
- `clear`
- `pool <host> <port> <user> [pass]`
- `connect`
- `disconnect`

`regs` reports each cluster's `IRQ_CONTROL` register. Its bit 0 masks that
cluster's `irq_o`; bit 1 forces `irq_o` high for controlled interrupt-path
debug. Both bits reset to zero.

The Stratum parser is intentionally constrained to the Stratum v1 message shapes
needed for mining. It is not a general JSON parser. The first Vitis board bring-up
should verify the generated `MINER_IRQ_ID`, GEM PHY settings, and pool acceptance
of submitted nonce byte order on the wire.
