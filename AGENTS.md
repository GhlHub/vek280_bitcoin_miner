# VEK280 Bitcoin Miner Notes

This workspace contains early RTL for a VEK280-based Bitcoin miner.

Current scope:
- SHA-256 compression core only.
- Two top-level variants with identical interfaces:
  - `sha256_core_fabric`: requests fabric/carry-chain arithmetic.
  - `sha256_core_dsp`: requests DSP-backed arithmetic where synthesis can map 32-bit additions into DSP resources.
- Self-checking SystemVerilog testbench covering both variants.
- `bitcoin_miner_axi`: AXI4-Lite controlled Bitcoin nonce scanner with `NUM_ENGINES`
  parameterized. The current VEK280 block design instantiates one 32-engine AXI
  miner to keep Vivado implementation memory within this host's limits.
- `bitcoin_hash_engine`: one nonce-scanning lane using a Bitcoin fixed-block SHA-256
  wrapper for first-pass block 1 and second-pass block 0.
- `bitcoin_result_cluster_fifo`: per-cluster result capture FIFO used to avoid a flat
  128-engine result priority mux.

Interface convention:
- `block_i` is one 512-bit SHA-256 message block.
- `h_i` is the 256-bit incoming hash state, ordered `{H0,H1,H2,H3,H4,H5,H6,H7}`.
- `digest_o` is ordered the same way.
- `block_i[511:480]` is message word `W0`; all message words are big-endian 32-bit values.

Bitcoin integration notes:
- Bitcoin block header hashing is double SHA-256 over an 80-byte header.
- This core is a compression primitive, not a complete miner scheduler.
- A nonce-scanning engine should feed the first SHA pass as two 512-bit blocks, then feed the 32-byte digest through a second SHA pass block.
- The embedded processor/FreeRTOS side should later own Stratum job handling, target calculation, extranonce management, and share submission.
- The AXI miner expects software to precompute the first 64-byte SHA-256 midstate.
- `header_tail` holds bytes 64..79 of the 80-byte header, ordered as four big-endian
  32-bit register words. The current hardware overrides the fourth word with the
  engine nonce.
- Engines divide nonce work by stride: engine `i` scans `nonce_start + i`,
  `nonce_start + i + NUM_ENGINES`, and so on.
- Engines are grouped by `CLUSTER_SIZE` for result collection. The current VEK280
  build uses one 32-engine cluster and a two-entry FIFO. Earlier 128-engine and
  4x32 AXI-slave variants are useful architectural targets, but exhausted this
  host's available memory during implementation.
- A second-stage arbiter moves one cluster FIFO result into the AXI-visible result
  register. Firmware clears that result to allow the next queued result to appear.
- Cluster overflow is sticky in the AXI `overflow` status bit.
- The fabric SHA-256 compression core uses a five-phase per-round pipeline. This
  increases one compression from 64 cycles to 320 cycles, but shortens the round
  adder and message-schedule paths enough for the current 128-engine fabric build
  to meet 250 MHz after full implementation.
- Each engine checks the 256-bit target threshold sequentially in eight 32-bit
  compare cycles after the second SHA pass. That avoids a 256-bit combinational
  comparator on the hash-complete path.
- The AXI wrapper registers per-engine work descriptors at start time so active
  engines do not depend on live wide nonce-count arithmetic/fanout.

AXI4-Lite register map:
- `0x000 CONTROL`: bit 0 start, bit 1 stop, bit 2 clear sticky status/results.
- `0x004 STATUS`: bit 0 running, bit 1 result valid, bit 2 nonce done, bit 3 overflow.
- `0x008 NUM_ENGINES`: read-only instantiated engine count.
- `0x020..0x03c MIDSTATE[0..7]`: 256-bit first-block midstate.
- `0x040..0x04c HEADER_TAIL[0..3]`: bytes 64..79 template; word 3 is nonce-overridden.
- `0x060..0x07c TARGET[0..7]`: 256-bit big-endian target threshold.
- `0x080 NONCE_START`: first nonce in range.
- `0x084 NONCE_COUNT`: total nonce candidates to scan.
- `0x090 RESULT_NONCE`: captured share nonce.
- `0x094 RESULT_ENGINE`: engine that found the captured result.
- `0x098 RESULT_STATUS`: bit 0 result valid, bit 1 overflow. Write 1s to clear.
- `0x0a0..0x0bc`: reserved; candidate capture is nonce and engine ID only.

Verification:
- Run `make sim` from this directory if Icarus Verilog is available.
- Run `make lint` from this directory if Verilator is available.
- The testbench compares the fabric and DSP wrappers against an internal behavioral SHA-256 reference for:
  - empty message
  - `"abc"`
  - a 64-byte, two-block message
  - one Bitcoin-style double-SHA-256 80-byte header
- The AXI miner testbench instantiates `NUM_ENGINES=4` for runtime and verifies:
  - AXI register programming
  - nonce dispatch
  - clustered result FIFOing
  - second-stage result arbitration
  - result nonce, engine ID, interrupt, sticky status, and result hash readback
- Latest local verification after timing-pipeline changes:
  - `make sim`: pass
  - `make lint`: pass
  - `make synth128`: pass under Vivado 2026.1 with `NUM_ENGINES=128`,
    `CLUSTER_SIZE=32`, and a 250 MHz OOC clock. Synthesis timing summary reports
    WNS `+1.315 ns`, TNS `0.000 ns`, WHS `+0.055 ns`, and all user timing
    constraints met. OOC clock insertion/skew remains approximate until full BD
    implementation.
- Latest 128-engine OOC synthesis utilization, before PS/NoC wrapper overhead:
  379,686 LUTs, 478,944 FFs, 0 DSP, 0 BRAM, 0 URAM.

VEK280 / XCVE2802 resource reference from Vivado 2025.2:
- CLB LUTs available: 520,704
- Registers available: 1,041,408
- DSP slices available: 1,312
- Block RAM tiles available: 600
- URAM available: 264

Block design:
- `bd/create_vek280_miner_bd.tcl` creates a VEK280 Vivado project and block design
  named `miner_system`.
- Target board part: `xilinx.com:vek280:part0:1.2`.
- Target part: `xcve2802-vsvh1760-2MP-e-S`.
- The block design instantiates `versal_cips`, `smartconnect`, `proc_sys_reset`, and
  `bitcoin_miner_axi`.
- PS-to-PL control path: `cips_0/M_AXI_FPD -> axi_smc -> axi_register_slice ->
  axi_lite_cdc_bridge -> miner_N/S_AXI` for each miner instance.
- Miner AXI base addresses in the current 4-instance build are `0xA4000000`,
  `0xA4001000`, `0xA4002000`, and `0xA4003000`.
- Current VEK280 miner sizing: four AXI4-Lite slaves, each with `NUM_ENGINES=32`,
  `CLUSTER_SIZE=32`, and `CLUSTER_FIFO_DEPTH=2`, for 128 engines total.
- CIPS PL0 is requested at 250 MHz and clocks the miner datapaths. CIPS PL1 is
  requested at 125 MHz and clocks the PS-to-PL AXI control fabric. The custom
  `axi_lite_cdc_bridge` provides one outstanding AXI4-Lite transaction of CDC
  isolation between each 125 MHz control path and its 250 MHz miner.
- CIPS config requests GEM0 Ethernet on PS MIO 0..11 with MDIO on PS MIO
  24..25, matching the VEK280 base platform routing.
- CIPS config requests UART0 on PMC MIO 42..43 at 115200 baud, matching the
  VEK280 USB-UART bridge routing used by the base platform.
- CIPS config enables PS TTC0. The Vitis 2026.1 R5 FreeRTOS BSP flow requires a
  PS TTC timer for the FreeRTOS tick; a PL AXI timer is not sufficient for this
  BSP.
- CIPS config enables the Versal SysMon external I2C interface for the VEK280
  system controller: `SMON_INTERFACE_TO_USE=I2C`, internal CIPS address parameter
  `SMON_PMBUS_ADDRESS=0x18`, and `PS_I2CSYSMON_PERIPHERAL={{ENABLE 1} {IO
  {PMC_MIO 39 .. 40}}}`. On VEK280 this maps SysMon SCL to `PMC_MIO39` and SDA to
  `PMC_MIO40`.
- DDR is implemented with a split NoC topology. `ps_ddr_noc` accepts six CIPS
  NoC master interfaces: the four FPD CCI NoC ports `FPD_CCI_NOC_0..3`, the R5
  LPD master path `LPD_AXI_NOC_0`, and the PMC master path `PMC_NOC_AXI_0`.
  Four explicit inter-NoC links connect `ps_ddr_noc/M00_INI..M03_INI` to
  `ddr_noc/S00_INI..S03_INI`.
- `ddr_noc` is configured as an LPDDR4 DDRMC subsystem bound through VEK280
  board automation/presets to `ch0_lpddr4_trip1`, `ch1_lpddr4_trip1`, and
  `lpddr4_clk1`.
- The generated wrapper exposes the two LPDDR4 channel interfaces and the LPDDR4
  differential clock pins.
- Set `MINER_ENABLE_DDR=0` when running the BD or implementation scripts to build a
  no-DDR hardware-programming isolation variant. Make targets are `bd-noddr` and
  `impl-noddr`; outputs go under `bd/out_vek280_miner_noddr`,
  `reports/impl_vek280_noddr`, `bd/miner_system_recreate_noddr.tcl`, and
  `reports/miner_system_summary_noddr.rpt`.
- The R5-accessible DDR fix was to connect `cips_0/LPD_AXI_NOC_0` and
  `cips_0/PMC_NOC_AXI_0` into `ps_ddr_noc`. Before this change, FPD CCI masters
  could reach DDR but R5-side debugger/app accesses to `0x00100000` aborted.
- Vivado 2026.1 still reports some NoC shared-segment and MC-port preference
  warnings during validation/implementation, but the DDR address paths are
  complete. The current implementation logs read a NoC traffic file with 6 paths.
- Miner interrupt is connected as `miner_0/irq_o -> cips_0/pl_ps_irq0`.
- In Vivado 2026.1 CIPS, PL-to-PS IRQ exposure is controlled through the aggregate
  `PS_IRQ_USAGE` field inside `CONFIG.PS_PMC_CONFIG`; direct
  `CONFIG.PS_PMC_CONFIG(PS_USE_IRQ_0)` is rejected by the IP GUI adapter.
- The BD script currently enables all 16 PL-to-PS IRQ pins via `PS_IRQ_USAGE` and
  connects only `pl_ps_irq0`; Vivado ties the unused IRQ inputs low.
- The BD sets `PFM.IRQ {pl_ps_irq0 {is_range "false"}}` on `cips_0` for Vitis
  platform metadata. Local Vivado export metadata maps `pl_ps_irq0` to IRQ ID 84,
  but firmware should verify the generated XSA/HWH/xparameters output.

Implementation status:
- `make impl` completed under Vivado 2026.1 on 2026-08-11 after reducing the
  implemented miner fabric to one 32-engine AXI instance. The run was launched
  with `VIVADO_JOBS=4`, and `impl/run_vek280_impl.tcl` also applies
  `set_param general.maxThreads $vivado_jobs`.
- Implementation status: `write_device_image Complete!`.
- Generated PDI:
  `bd/out_vek280_miner/vek280_miner_bd.runs/impl_1/miner_system_wrapper.pdi`.
- Routed checkpoint:
  `bd/out_vek280_miner/vek280_miner_bd.runs/impl_1/miner_system_wrapper_routed.dcp`.
- Final timing from `reports/impl_vek280/timing_summary_impl.rpt`:
  WNS `+0.255 ns`, TNS `0.000 ns`, WHS `+0.011 ns`, THS `0.000 ns`, WPWS
  `+0.016 ns`; all user-specified timing constraints are met.
- Route status from `reports/impl_vek280/route_status_impl.rpt`: 167,973 routable
  nets fully routed, 0 nets with routing errors.
- Final implemented utilization from `reports/impl_vek280/utilization_impl.rpt`:
  88,274 LUTs, 113,833 FFs, 0 BRAM, 0 URAM, 0 DSP.
- `report_power` completed, but vectorless power has caveats: no environmental
  constraints were supplied and reset activity may be pessimistic.
- The current implementation reports and XSA include the TTC0 CIPS update required
  by the Vitis BSP flow.
- The earlier 128-engine DDR-enabled PDI built and programmed successfully on
  2026-08-09, but later attempts to implement the 4x32 AXI-slave version caused
  host out-of-memory reboots. The current one-32-engine build is the active
  memory-safe hardware configuration.
- Hardware-manager programming of the DDR-enabled PDI succeeded on 2026-08-11
  against remote `hw_server` `10.0.1.109:3121`; Vivado reported
  `Successfully programmed PDI file` and `DONE bit: HIGH`.
- Direct DDR access was verified on hardware through XSDB targeting
  `Cortex-R5 #0`: after `rst -processor`, writes to `0x00100000` and
  `0x00100004` read back as `0x12345678` and `0xA5A55A5A`. This confirms the
  R5/LPD DDR path is now functional.
- Earlier DDR-enabled PDIs failed with PLM error `0x02030004`
  (`XPLM_ERR_EXCEPTION`, `DATA_BUS_ERROR_EXCEPTION`), DONE low, BOOT first error
  `0x34d`, and `pdi_dbg_util` traces ending at
  `XPIO_DCI_COMPONENT_0.REG_PCSR_STATUS.CALDONE[4]` mask-polls. Those failures
  were from the pre-split/incomplete NoC topology and are retained here only as
  debugging history.
- `make impl-noddr` completed under Vivado 2026.1 on 2026-08-08. The generated PDI
  `bd/out_vek280_miner_noddr/vek280_miner_bd.runs/impl_1/miner_system_wrapper.pdi`
  programmed successfully through the same remote `hw_server`; Vivado reported
  `DONE bit: HIGH` and `ERROR_STATUS=0`.
- Final no-DDR timing from `reports/impl_vek280_noddr/timing_summary_impl.rpt`:
  WNS `+0.046 ns`, TNS `0.000 ns`, WHS `+0.011 ns`, THS `0.000 ns`, WPWS
  `+0.571 ns`; all user-specified timing constraints are met.
- No-DDR route status: 654,092 routable nets fully routed, 0 nets with routing
  errors. No-DDR utilization: 378,651 LUTs, 448,876 FFs, 0 BRAM, 0 URAM, 0 DSP.

FreeRTOS software port:
- The user-provided FreeRTOS LTS source tree is under `FreeRTOS-LTS/`.
- PS-side application sources are under `software/vek280_freertos/`.
- Intended first software target is a Versal PS R5 FreeRTOS domain built from the
  Vivado/Vitis exported XSA.
- Vitis 2026.1 has XSCT disabled. BSP/platform creation is scripted with the Vitis
  Python API in `software/vitis/create_bsp.py`.
- Vitis 2026.1 app component creation can block after writing the generated app
  directory. `software/vitis/create_app.py` is idempotent: once
  `vitis_ws/vek280_miner_app` exists, rerunning the script patches the generated
  `UserConfig.cmake` and `lscript.ld` without recreating the component.
- `software/vitis/build_app.py` builds the existing app component with the Vitis
  Python API. The current generated ELF is
  `vitis_ws/vek280_miner_app/build/vek280_miner_app.elf`.
- `make vitis-bsp` first exports a Vitis hardware XSA at
  `reports/vitis_hw/miner_system_wrapper.xsa`, then creates and builds the local
  platform `vitis_ws/vek280_miner_platform/export/vek280_miner_platform/vek280_miner_platform.xpfm`.
- The generated FreeRTOS BSP domain is `r5_freertos` on CPU `psv_cortexr5_0`; BSP
  output is under
  `vitis_ws/vek280_miner_platform/psv_cortexr5_0/r5_freertos/bsp`.
- The generated BSP `xparameters.h` contains `XPAR_BITCOIN_MINER_AXI_0_BASEADDR`
  at `0xa4000000` and TTC0 entries (`XPAR_XTTCPS_0_*`) for the FreeRTOS tick.
- `software/vek280_freertos/include/FreeRTOSConfig.h` is configured for the
  FreeRTOS ARM CR5 GCC port and uses generated `xparameters.h` values for the GIC
  base addresses when available.
- `software/vek280_freertos/include/FreeRTOSIPConfig.h` enables IPv4, DHCP by
  default, DNS, TCP, and the compatibility `FreeRTOS_IPInit()` path used by the
  current Xilinx FreeRTOS-Plus-TCP network interface ports.
- `main.c` initializes FreeRTOS-Plus-TCP on PS GEM Ethernet, waits for network-up,
  reports whether DHCP succeeded or fallback addressing was used, prints the IP
  address, netmask, gateway, and DNS server on the UART console, then starts the
  miner service, Stratum client, and telnet console tasks.
- The full FreeRTOS+TCP/Stratum/Telnet app no longer links with all data in OCM.
  The generated Vitis linker script keeps code, stacks, the small C heap, and
  normal `.bss` in OCM for reliable R5 startup. Only explicitly tagged
  `.ddr_bss` and `.ddr_heap` sections are placed in `psv_ddr_MEM_0` starting at
  `0x00100000`.
- `software/vitis/create_app.py` enables `APP_USE_DDR_HEAP=1` for the generated
  Vitis app, includes `heap_4.c`, and places the application-provided FreeRTOS
  `ucHeap` in `.ddr_heap`. The current generated ELF places
  `ddr_test_buffer` at `0x00100000` and the 512 KiB `ucHeap` at `0x00100400`.
- The generated R5 BSP currently exports only OCM in its standalone memory config,
  so the BSP boot MPU setup does not map the DDR window. `app_ddr_configure_mpu()`
  adds a 1 MiB non-cacheable normal-memory MPU region at `0x00100000` before the
  first R5 CPU DDR access.
- `miner_regs.c` provides the AXI4-Lite MMIO driver for the PL miner at default
  base address `0xA4000000`.
- `miner_service.c` provides a task-level miner control API and result bookkeeping.
  It installs a `pl_ps_irq0` handler using `xPortInstallInterruptHandler()`, wakes
  on a binary semaphore, drains PL result FIFO entries, and queues share
  candidates with the active Stratum job metadata.
- `telnet_server.c` exposes an unauthenticated TCP port 23 command shell with
  `status`, `regs`, `start`, `stop`, `clear`, `pool`, `connect`, and
  `disconnect` commands.
- `stratum_client.c` resolves/connects to a Stratum v1 pool, sends
  `mining.subscribe` and `mining.authorize`, parses subscription, authorization,
  `mining.set_difficulty`, and `mining.notify`, builds coinbase + merkle root +
  serialized block header work, programs PL midstate/tail/target jobs, rolls
  `extranonce2` when the PL finishes a nonce range, and submits candidate shares
  with `mining.submit`.
- The Stratum parser is constrained to the message shapes used by Stratum v1
  mining pools; it is not a general JSON parser.
- Local standalone C syntax check against the FreeRTOS-LTS headers passes with
  `make sw-syntax`.
- Current Vitis app build succeeds with `vitis -s software/vitis/build_app.py`.
  Latest ELF size: text 207,636 bytes, data 5,764 bytes, bss 562,064 bytes.
- `software/vitis/load_r5_app.tcl` loads
  `vitis_ws/vek280_miner_app/build/vek280_miner_app.elf` to `Cortex-R5 #0`.
- The UART-to-telnet bridge at `10.0.1.109:2323` captured the R5 app after the
  linker/MPU fix. Hardware output showed `DDR MPU region configured`, `DDR smoke
  test passed`, FreeRTOS heap base `0x00100400`, heap size `0x00080000`, and
  FreeRTOS-Plus-TCP starting on GEM Ethernet.
- One intermediate hardware run reached FreeRTOS network-up but DHCP did not return
  a lease before fallback addressing; UART output showed `DHCP failed; using
  fallback IP address` and fallback IP `192.168.1.80`. The final 512 KiB heap run
  confirmed GEM initialization and 1000 Mbps link, but was stopped before DHCP
  completed or fell back.

Current operational configuration (2026-08-12):
- The active build is the DDR-enabled 4x32 variant: four `bitcoin_miner_axi`
  instances with 32 engines each, for 128 engines total. AXI base addresses are
  `0xA4000000`, `0xA4001000`, `0xA4002000`, and `0xA4003000`.
- The current PDI is
  `bd/out_vek280_miner_4x32_ooc/miner_system_wrapper.pdi`; the matching XSA is
  `reports/impl_vek280_4x32_ooc/miner_system_wrapper.xsa`.
- Four-thread implementation with post-route physical optimization meets timing:
  WNS `+0.101 ns`, TNS `0.000 ns`, WHS `+0.009 ns`, and THS `0.000 ns`.
  `clk_pl_0` runs at 250 MHz for the miner datapaths and `clk_pl_1` runs at
  125 MHz for AXI control. The design uses 309,774 LUTs, 356,240 FFs, and
  58,255 of 65,088 slices (89.50%); routing has zero errors. It uses 0 DSP,
  BRAM, or URAM; the DSP synthesis-directed SHA experiment did not infer DSP58
  cells and would require explicit primitive arithmetic to do so.
- An alternate, not-yet-implemented explicit-DSP58 variant is available through
  `make synth-miner32-dsp-ooc` and `make impl4x32-dsp-ooc`. It preserves the
  nonce-only result FIFO/arbiter, sequential target compare, AXI register map,
  and 4x32 partitioning. Each SHA engine explicitly uses three DSP58 adders for
  the message schedule, so the 32-engine OOC checkpoint uses 96 DSP58s, 78,491
  LUTs, and 88,480 FFs (fabric: 0 DSP58s, 81,595 LUTs, 88,480 FFs). Both OOC
  versions meet the 250 MHz constraint with WNS `+1.566 ns` and WHS `+0.058 ns`.
  The explicit primitive model passes the SHA regression with Vivado's UNISIM
  `DSP58.v`; a full 4x32 implementation is still required before deployment.
- `make vitis-r5` rebuilds the matching 4-instance R5 BSP and ELF. The default
  `MINER_AXI_INSTANCES` is 4. Use `software/vitis/load_target.py` for a full PDI
  plus R5 load, or `software/vitis/reload_r5_app.py` to reset and reload only the
  R5 ELF. Vitis 2026.1 requires these XSDB Python scripts; XSCT is disabled.
- Hardware server is at `10.0.1.109:3121`; UART bridge is
  `10.0.1.109:2323`. The R5 obtains its DHCP lease on `10.0.1.89` and exposes an
  unauthenticated control console on TCP port 23. Use this only on the trusted lab
  network.
- The verified runtime flow is Stratum v1 over `solo.ckpool.org:3333`. Configure
  a wallet at runtime with `pool <host> <port> <user> [pass]`, then `connect`.
  Do not commit wallet credentials or UART/pool logs.
