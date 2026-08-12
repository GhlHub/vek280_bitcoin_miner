# Developer Guide

This repository contains a VEK280-based Bitcoin-mining demonstrator. The
programmable logic scans nonces and the PS R5 FreeRTOS application receives
Stratum v1 work, programs the miner, and submits candidate shares.

## Design overview

- Target board: AMD Versal Premium VEK280 (xcve2802-vsvh1760-2MP-e-S).
- Active fabric architecture: four AXI4-Lite miner instances, 32 engines each,
  for 128 nonce-scanning engines.
- Miner clock: 250 MHz. AXI control clock: 125 MHz.
- Each engine double-hashes an 80-byte Bitcoin header using a five-phase,
  64-round SHA-256 compression pipeline.
- Candidate results capture only the nonce and engine ID; the R5 reconstructs
  Stratum submission metadata from the active job.
- The alternate explicit-DSP58 architecture maps the three message-schedule
  additions in each SHA round to DSP58 primitives. It preserves the interface
  and nonce-only result path.

See the theory-of-operation document and the SHA architecture diagrams under
doc/. The high-throughput interleaved-DSP concept is documented separately in
doc/interleaved_dsp_throughput_investigation.md.

## RTL conventions

- block_i is one 512-bit SHA-256 block. block_i[511:480] is big-endian message
  word W0.
- Hash states and digests use {H0,H1,H2,H3,H4,H5,H6,H7} ordering.
- The AXI miner expects a software-precomputed first-block midstate.
- header_tail contains bytes 64-79 of the Bitcoin header; the fourth word is
  replaced by each engine's nonce.
- Engines split nonce work by stride. Results are collected in per-cluster
  FIFOs before AXI-visible arbitration.

## AXI4-Lite register map

- 0x000 CONTROL: bit 0 start, bit 1 stop, bit 2 clear sticky state/results.
- 0x004 STATUS: running, result valid, nonce done, overflow.
- 0x008 NUM_ENGINES: read-only engine count.
- 0x020..0x03c MIDSTATE[0..7]
- 0x040..0x04c HEADER_TAIL[0..3]
- 0x060..0x07c TARGET[0..7]
- 0x080 NONCE_START; 0x084 NONCE_COUNT
- 0x090 RESULT_NONCE; 0x094 RESULT_ENGINE; 0x098 RESULT_STATUS

## Build and verify

The supported toolchain is Vivado and Vitis 2026.1.

~~~bash
make sim
make lint
make synth128
make impl4x32-ooc
make impl4x32-dsp-ooc
make vitis-r5
~~~

Keep Vivado-generated PDIs, checkpoints, XSA files, raw timing/utilization
reports, Vitis workspaces, UART captures, and pool logs out of Git. Raw build
reports are intentionally ignored; record concise, reproducible results in
project documentation instead.

## R5 application

software/vek280_freertos/ contains the FreeRTOS application. It configures GEM
networking, Stratum v1, miner MMIO, result interrupts, and PS SysMon telemetry.
The telnet console supports help, status, stats, health, stratum, regs, start,
stop, clear, pool, connect, and disconnect.

stats reports nominal hash rate and job/result/share-path counters. health
reports PS SysMon device temperature and alarms.

Security requirement: the unauthenticated telnet console is for an isolated,
trusted lab network only. Do not route, port-forward, or expose TCP port 23 to
an untrusted network. Configure pool wallet/worker credentials only at runtime;
never commit them or runtime logs.

## Hardware bring-up

The local lab scripts currently use the configured remote hardware-server and
UART-bridge endpoints. Keep those values in lab-only scripts and do not place
wallet credentials in source control. The target-load script performs a full
PDI and R5 ELF load; the R5 reload script reloads only the ELF.

The block design enables PS TTC0 for the FreeRTOS tick, GEM0 networking, DDR
through the NoC, and the PS SysMon I2C interface. The R5 application's DDR
heap requires the configured non-cacheable MPU region before first access.
