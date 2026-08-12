# Interleaved DSP SHA-256 Throughput Investigation

## Objective

Investigate a higher-throughput SHA-256 round architecture that runs the
message-schedule arithmetic in a faster DSP58 clock domain.  The goal is hash
throughput, not DSP58 conservation.

The current explicit-DSP core keeps the complete five-phase SHA-256 round at
250 MHz.  DSP58 instances replace the three additions that form each expanded
message word, but they are combinational (`PREG=0`) and run at the same clock as
the fabric.  A compression therefore still takes 320 clocks (64 rounds x 5
phases).

## Candidate architecture

Keep a per-engine SHA context in the 250 MHz miner domain.  During the first
phase of a round, send the four message-schedule operands, plus an
`engine_id`/`round_id` tag, to a registered DSP pipeline in a faster related
clock domain.  Return the completed `W[t]` to the context before the `T1` phase.

```text
250 MHz SHA context                         Fast DSP58 schedule pipeline
---------------------                        ----------------------------
read W ring, form sigma terms -- request --> add A: sigma1(W[t-2]) + W[t-7]
                                             add B: sigma0(W[t-15]) + W[t-16]
                                         --> add C: A + B
consume tagged W[t]        <-- response ---- registered result
form T1, update SHA state
```

The request and response channels must preserve the context tag and have
explicit back-pressure.  A synchronous integer-ratio clocking scheme is
preferred for the first prototype; an asynchronous FIFO CDC is required if the
clocks are unrelated.

## Throughput opportunity

If schedule generation is completed within one 250 MHz period, the five
current phases may be recast as approximately:

1. Form schedule operands and launch the DSP request.
2. Consume `W[t]` and form `T1`.
3. Update the SHA state and message ring.

That reduces a compression from approximately 320 to 192 miner-clock cycles.
At an unchanged 250 MHz miner clock, the ideal improvement is `320 / 192 =
1.67x`: roughly 50 MH/s to 83 MH/s for 128 engines.  This is an upper bound;
placement, FIFO/CDC latency, and the remaining fabric paths can reduce it.

## DSP clocking implications

`W[t]` is the sum of four terms and requires three modular additions.  A single
serial DSP58 path needs three fast cycles after its inputs are available.

- At 500 MHz, only two DSP clocks fit within one 250 MHz period, so one serial
  path cannot return `W[t]` in time.
- At about 750 MHz to 1 GHz, a registered three-add path may fit inside one
  250 MHz period, subject to real implementation timing and CDC overhead.
- At 500 MHz, parallel DSP stages can still meet the latency target, but would
  use multiple DSPs per engine.  This is acceptable when throughput is the
  priority.

The DSP58's published SIMD timing reaches 1.07 GHz for the applicable -2
speed-grade operating condition, but that is a fully pipelined DSP figure and
does not guarantee system-level timing.  The prototype must use DSP input and
output registers rather than the current combinational (`PREG=0`) mapping.

## Expected bottlenecks and risks

- The present DSP implementation closes the 250 MHz design with only +0.003 ns
  WNS.  The fabric `T1` and state-update logic must be repartitioned and
  registered, not simply retained unchanged.
- A faster DSP domain adds placement, clocking, and request/response alignment
  constraints.  A missing or delayed `W[t]` must stall only its tagged context.
- The SHA round has true state dependencies.  Interleaving hides DSP-pipeline
  latency across independent contexts, but cannot permit a single context to
  skip its round dependency.
- Any added fabric stages that negate the saved schedule phases erase the
  throughput gain.

## Recommended prototype sequence

1. Build a one-32-engine experimental variant with a 500 MHz, registered DSP58
   schedule pipeline and tagged request/response FIFOs.
2. Measure achievable DSP clock rate, FIFO latency, placement, and whether the
   schedule service can sustain one result per engine-round demand.
3. Implement the three-phase 250 MHz round only after the service can return
   `W[t]` at the required boundary.
4. Compare post-route WNS, slice/LUT/DSP use, and hashes per second against the
   current 250 MHz explicit-DSP variant.
5. If 500 MHz cannot meet the one-miner-cycle return latency, evaluate a
   750 MHz+ DSP clock or a parallel-DSP schedule datapath before scaling to the
   128-engine build.

## Success criteria

The approach is worthwhile only if post-route timing closes and the measured
hash rate rises materially above the current 250 MHz, five-phase design.  A
resource reduction without a corresponding round-cycle reduction is not a
throughput win.
