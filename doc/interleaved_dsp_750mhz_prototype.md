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
