# VEK280 Bitcoin Miner Notes

This workspace contains early RTL for a VEK280-based Bitcoin miner.

Current scope:
- SHA-256 compression core only.
- Two top-level variants with identical interfaces:
  - `sha256_core_fabric`: requests fabric/carry-chain arithmetic.
  - `sha256_core_dsp`: requests DSP-backed arithmetic where synthesis can map 32-bit additions into DSP resources.
- Self-checking SystemVerilog testbench covering both variants.
- `bitcoin_miner_axi`: AXI4-Lite controlled Bitcoin nonce scanner with `NUM_ENGINES`
  defaulting to 128.
- `bitcoin_hash_engine`: one nonce-scanning lane using the fabric SHA-256 compression
  core for first-pass block 1 and second-pass block 0.
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
- Engines are grouped by `CLUSTER_SIZE` for result collection. The default 128-engine
  build uses 16 engines per cluster and a two-entry FIFO per cluster.
- A second-stage arbiter moves one cluster FIFO result into the AXI-visible result
  register. Firmware clears that result to allow the next queued result to appear.
- Cluster overflow is sticky in the AXI `overflow` status bit.

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
- `0x0a0..0x0bc RESULT_HASH[0..7]`: captured 256-bit double-SHA result.

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
- PS-to-PL control path: `cips_0/M_AXI_FPD -> axi_smc -> miner_0/S_AXI`.
- Miner AXI address is auto-assigned by Vivado at `0xA4000000` in the current build.
- CIPS PL0 clock is requested at 250 MHz. Vivado realizes this as 249.997498 MHz, so
  the miner AXI metadata uses that exact `FREQ_HZ` value for BD validation.
- CIPS config requests GEM0 Ethernet on PMC MIO 26..37 with MDIO on PMC MIO 50..51.
- CIPS config requests UART0 on PMC MIO 0..1 and UART1 on PMC MIO 4..5 at 115200 baud.
- DDR is implemented with `axi_noc_0` configured as an LPDDR4 DDRMC subsystem.
- `axi_noc_0` connects all six CIPS NoC master interfaces:
  `FPD_CCI_NOC_0..3`, `LPD_AXI_NOC_0`, and `PMC_NOC_AXI_0`.
- `axi_noc_0` is bound to VEK280 board interfaces `ch0_lpddr4_trip1`,
  `ch1_lpddr4_trip1`, and `lpddr4_clk1`.
- The generated wrapper exposes the two LPDDR4 channel interfaces and the LPDDR4
  differential clock pins.
- Vivado 2026.1 still reports incomplete NoC address-path warnings during
  `validate_bd_design`, but the BD validates sufficiently to save and generate the
  wrapper. This should be revisited before producing the final XSA/PDI.
- Miner interrupt is connected as `miner_0/irq_o -> cips_0/pl_ps_irq0`.
- In Vivado 2026.1 CIPS, PL-to-PS IRQ exposure is controlled through the aggregate
  `PS_IRQ_USAGE` field inside `CONFIG.PS_PMC_CONFIG`; direct
  `CONFIG.PS_PMC_CONFIG(PS_USE_IRQ_0)` is rejected by the IP GUI adapter.
- The BD script currently enables all 16 PL-to-PS IRQ pins via `PS_IRQ_USAGE` and
  connects only `pl_ps_irq0`; Vivado ties the unused IRQ inputs low.
- The BD sets `PFM.IRQ {pl_ps_irq0 {is_range "false"}}` on `cips_0` for Vitis
  platform metadata. Local Vivado export metadata maps `pl_ps_irq0` to IRQ ID 84,
  but firmware should verify the generated XSA/HWH/xparameters output.
