# VEK280 Bitcoin Miner

An AMD Versal Premium VEK280 Bitcoin-mining demonstrator. The project combines a
250 MHz programmable-logic nonce scanner with a 125 MHz AXI control plane and
an R5 FreeRTOS control plane that uses Stratum v1 to receive work and submit
candidate shares.

The current implemented design has four AXI4-Lite miner instances with 32 hash
engines each: **128 engines total**. Its estimated raw double-SHA-256 rate is
approximately **49 MH/s**.

## Current implementation status

The active target is `xcve2802-vsvh1760-2MP-e-S` on the VEK280. The 4×32 design
meets its 250 MHz miner-clock and 125 MHz AXI-control-clock constraints after
route and physical optimization:

| Metric | Result |
| --- | ---: |
| Setup slack (WNS) | +0.117 ns |
| Setup violations (TNS) | 0.000 ns |
| Hold slack (WHS) | +0.005 ns |
| Hold violations (THS) | 0.000 ns |
| LUTs | 351,459 (67.5%) |
| Registers | 496,748 (47.7%) |
| Routing errors | 0 |

Detailed operation, register semantics, architecture, and runtime control are
documented in [doc/theory_of_operation.md](doc/theory_of_operation.md).

## Repository layout

| Path | Contents |
| --- | --- |
| `rtl/` | SHA-256 core, nonce engines, result FIFO, and AXI4-Lite miner RTL. |
| `bd/` | Vivado block-design creation and recreation scripts. |
| `impl/` | Vivado implementation flow. |
| `tb/` | SystemVerilog testbenches. |
| `software/vek280_freertos/` | R5 FreeRTOS, GEM networking, telnet, and Stratum client. |
| `software/vitis/` | Vitis 2026.1 platform, application, and XSDB load scripts. |
| `reports/` | Timing, utilization, routing, and implementation reports. |
| `doc/` | Project documentation. |

## Build

The project uses Vivado and Vitis 2026.1. The major targets are:

```bash
make sim                 # RTL simulation; requires Icarus Verilog/vvp
make lint                # RTL lint; requires Verilator
make impl4x32-ooc        # Implement the four-instance, 128-engine PL design
make vitis-r5            # Rebuild the matching R5 BSP and application ELF
```

The current PDI and XSA are:

```text
bd/out_vek280_miner_4x32_ooc/miner_system_wrapper.pdi
reports/impl_vek280_4x32_ooc/miner_system_wrapper.xsa
```

## Load and operate

Vitis 2026.1 uses XSDB Python APIs; legacy XSCT is disabled. With the hardware
server reachable at the address configured in the scripts:

```bash
# Program the PDI, then reset, download, and start the R5 app.
/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/load_target.py

# Reload only the R5 app without modifying PL configuration.
/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/reload_r5_app.py
```

After DHCP, the R5 app provides an unauthenticated telnet console on TCP port
23. It supports `status`, `regs`, `stratum`, `pool`, `connect`, `disconnect`,
`stop`, and `clear`. It is intended only for a trusted lab network.

```text
pool <host> <port> <wallet-or-worker> [password]
connect
status
stratum
```

Do not commit wallet identifiers, passwords, pool credentials, or UART/pool
logs to the repository.

## License

This repository includes third-party FreeRTOS LTS content under its respective
upstream license terms. Review the license information in that tree before
redistributing it.
