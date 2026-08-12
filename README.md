# VEK280 Bitcoin Miner

An AMD Versal Premium VEK280 Bitcoin-mining demonstrator. The project combines a
250 MHz programmable-logic nonce scanner with a 125 MHz AXI control plane and
an R5 FreeRTOS control plane that uses Stratum v1 to receive work and submit
candidate shares.

The current implemented design has four AXI4-Lite miner instances with 32 hash
engines each: **128 engines total**. Its estimated raw double-SHA-256 rate is
approximately **49 MH/s**.

## Current implementation status

The active target is `xcve2802-vsvh1760-2MP-e-S` on the VEK280. The fabric
4×32 design meets its 250 MHz miner-clock and 125 MHz AXI-control-clock
constraints after route and physical optimization:

| Metric | Result |
| --- | ---: |
| Setup slack (WNS) | +0.101 ns |
| Setup violations (TNS) | 0.000 ns |
| Hold slack (WHS) | +0.009 ns |
| Hold violations (THS) | 0.000 ns |
| LUTs | 309,774 (59.5%) |
| Registers | 356,240 (34.2%) |
| Slices | 58,255 (89.5%) |
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
| `reports/` | Notes about locally generated, untracked implementation reports. |
| `doc/` | Project documentation. |

## Build

The project uses Vivado and Vitis 2026.1. The major targets are:

```bash
make sim                 # RTL simulation; requires Icarus Verilog/vvp
make lint                # RTL lint; requires Verilator
make impl4x32-ooc        # Implement the four-instance, 128-engine PL design
make impl4x32-dsp-ooc    # Implement the isolated explicit-DSP58 alternate
make vitis-r5            # Rebuild the matching R5 BSP and application ELF
```

`impl4x32-dsp-ooc` is an alternate hardware experiment.
It keeps the same register map and nonce-only result path, but explicitly maps
the three SHA message-schedule additions in each engine to DSP58 resources.
Its 32-engine OOC checkpoint uses 96 DSP58s and 78,491 LUTs, versus 0 DSP58s
and 81,595 LUTs for the fabric checkpoint. Both meet the 250 MHz OOC clock
constraint with +1.566 ns WNS.

Generated PDIs, XSAs, checkpoints, and raw implementation reports are local
build outputs and are deliberately not tracked. Use the corresponding build
target to regenerate them.

## Runtime control

After DHCP, the R5 app provides these console commands:

```text
help
status
stats
health
stratum
regs
start <nonce_start_hex> <nonce_count_hex>
stop
clear
pool <host> <port> <wallet-or-worker> [password]
connect
disconnect
```

- `stats` reports nominal hash rate and job, result, queue, and share-path
  counters.
- `health` reports PS SysMon device temperature and alarm state.

## Load and operate

Vitis 2026.1 uses XSDB Python APIs; legacy XSCT is disabled. With the hardware
server reachable at the address configured in the local scripts:

```bash
# Program the PDI, then reset, download, and start the R5 app.
/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/load_target.py

# Reload only the R5 app without modifying PL configuration.
/tools/Xilinx/2026.1/Vitis/bin/vitis -s software/vitis/reload_r5_app.py
```

Security warning: the telnet console is unauthenticated and unencrypted. It is
for **isolated, trusted lab-network use only**. Do not expose, route, or
port-forward TCP port 23 to an untrusted network.

Do not commit wallet identifiers, passwords, pool credentials, or UART/pool
logs to the repository.

## License

Project-owned source and documentation are licensed under
[Apache-2.0](LICENSE). The bundled FreeRTOS LTS content retains its upstream
licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
