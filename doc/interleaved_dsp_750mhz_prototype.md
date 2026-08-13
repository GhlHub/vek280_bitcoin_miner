# 750 MHz DSP schedule-service prototype

This branch contains the first isolated prototype for the interleaved DSP
throughput architecture described in `interleaved_dsp_throughput_investigation.md`.

## Datapath

`rtl/dsp58_schedule_pipeline.sv` implements an elastic two-stage service:

1. Two registered DSP58 adders calculate
   `A = sigma1(W[t-2]) + W[t-7]` and
   `B = sigma0(W[t-15]) + W[t-16]` in parallel.
2. A third registered DSP58 adder calculates `W[t] = A + B`.

The service has two fast-clock pipeline stages, carries engine and round tags,
and supports request and response backpressure. `dsp58_add32_registered.sv`
uses DSP58 output registers in synthesis and a clocked arithmetic fallback in
simulation.

## Current boundary

This is deliberately not connected to the 250 MHz SHA core yet. The eventual
integration must provide:

- a 750 MHz clock derived from the miner clock source;
- reset synchronization for the fast domain;
- a CDC-safe request/response boundary (an asynchronous FIFO is the default
  safe choice even though the clocks can be frequency-related). The current
  prototype uses AMD `xpm_fifo_async` in `rtl/dsp58_schedule_xpm_cdc.sv`;
- a service-lane count sufficient for the request burst from each engine
  cluster;
- generated-clock and fast-domain timing constraints.

For a synchronized 32-engine cluster, one lane produces at most three results
per 250 MHz period at 750 MHz. Full-rate service therefore requires at least
11 equivalent lanes, unless engine round launches are deliberately staggered.

## Verification

Run:

```text
make sim-schedule
make sim
make lint
```

The dedicated testbench checks modular-add results, tag preservation, and
response backpressure. It does not claim implementation timing closure; that
requires Vivado synthesis and post-route analysis with the new clocking
constraints.

The XPM CDC wrapper is exercised with Vivado XSim using:

```text
make sim-xsim-cdc
```

That test uses independent 250 MHz and 750 MHz clocks, reset sequencing, a
16-request burst, and an eight-cycle response stall. It currently passes all
16 tagged responses. Generated XSim data is kept under `sim/xsim_cdc/` and is
not part of the source-controlled design.

The single-context SHA proof core is exercised by the same XSim target. It
routes expanded schedule requests through the XPM CDC wrapper and compares the
complete SHA-256 digest for `abc` against the standard result. The current
prototype passes this test at 816 slow-clock cycles; this latency includes the
per-round request/response CDC overhead and is not yet the optimized
three-phase miner schedule.

## Four-phase DSP resource experiment

The isolated four-phase variant is `rtl/sha256_core_4phase.sv`. It retains the
three DSP58 schedule adders and adds two DSP58 adders for the round's T1 path:

```text
T1 = (Σ1(e) + ch(e,f,g) + K[t]) + W[t]
```

The two T1 additions are evaluated during the same phase as the final schedule
addition. The following phase performs the state update, removing the separate
fifth phase. This is a throughput experiment only; the active miner remains on
the existing architecture.

Simulation results for the `abc` digest are:

| Variant | DSP58/core | Cycles/core invocation | Relative throughput |
| --- | ---: | ---: | ---: |
| Explicit-DSP five-phase | 3 | 320 | 1.00x |
| Explicit-DSP four-phase | 5 | 256 | 1.25x |

The four-phase test passes the complete digest. Vivado 2026.1 out-of-context
synthesis at a 4.000 ns clock reports 1,552 LUTs, 1,652 FFs, 5 DSP58s, and
0.447 ns setup slack. The five-phase reference reports 1,589 LUTs, 1,656 FFs,
3 DSP58s, and 1.982 ns setup slack. These are synthesis estimates, not
post-route timing results. The four-phase critical path contains the schedule
DSP followed by both T1 DSP additions, so implementation timing, placement,
routing congestion, and power must be checked before considering integration.

At 128 engines, the DSP count would increase from approximately 384 to 640
DSP58s, or about 48.8% of the VEK280's 1,312 DSP blocks. The next meaningful
step is a placed-and-routed 128-engine or representative multi-engine build
with the 250 MHz miner clock and the intended 750 MHz service clock constraints.
