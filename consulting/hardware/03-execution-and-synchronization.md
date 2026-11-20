# A5 Execution and Synchronization Reference

## Independent pipelines

A kernel is not one globally serial instruction list. Scalar, movement,
compute, and output pipelines can progress asynchronously:

```text
time →
MTE2:    load 0     load 1     load 2
MTE1:               stage 0    stage 1
Cube:                           compute 0   compute 1
Fixpipe:                                    drain 0
AIV:                                          post-op 0
MTE3:                                                   store 0
```

This is a dependency model, not a cycle-accurate schedule.

## Two invariants for every reused buffer

For a producer `P`, consumer `C`, and reusable buffer `B`:

```text
P finishes writing B before C reads B
C finishes reading B before the next P overwrites B
```

Most deadlocks, stale reads, and unsafe buffer rotation can be framed as a
missing, unmatched, or cyclic edge around one of those invariants.

## Synchronization mechanisms

| Mechanism | Role |
|---|---|
| Event / flag | orders asynchronous producer and consumer pipelines |
| BufferID / queue ownership | acquires and releases local buffers at a higher abstraction |
| Cross-core flag | counter-like readiness/ordering across AIC/AIV or same-type cores |
| SSBuffer | AIC–AIV communication/storage facility, not itself proof of readiness |

Events have finite IDs. Set/wait pairs must match and IDs must be safely
released or reused. A cross-core data handoff generally needs both a payload
path and an ordering signal.

## Cross-core scopes

The public 3510 model includes synchronization for:

- all AICs or all AIVs across logical groups;
- the two AIVs inside one logical group;
- one AIC with two AIVs (1:2);
- one AIC with one selected AIV (1:1).

Do not confuse the hardware's available 1:2 ratio with proof that a particular
kernel was auto-bound in 1:2 mode. The compiler-setting evidence is covered in
[`../compiler-settings/06-cv-1-to-2.md`](../compiler-settings/06-cv-1-to-2.md).

## SSBuffer is not three different things

Keep these concepts separate:

```text
bulk payload:       L1↔UB or L0C→Fixpipe→UB
communication:      SSBuffer / SSBuf
readiness/ordering: events and cross-core flags
```

The public source does not specify SSBuffer capacity, exact endpoints, payload
format, banking, arbitration, or whether a given use carries control words,
tensor fragments, or both.

## Double and multibuffering

Double buffering overlaps work by giving producer and consumer different
slots:

```text
slot 0: consumer computes current tile
slot 1: producer loads next tile
```

More slots can extend overlap, but consume local capacity and multiply the
number of ownership transitions. A requested multibuffer option is not proof
that the pass created extra slots; see
[`../compiler-settings/07-multibuffer.md`](../compiler-settings/07-multibuffer.md).

## Deadlock audit

For each event/flag and buffer slot, record:

1. producer pipeline and iteration;
2. consumer pipeline and iteration;
3. set count and wait count;
4. first use and reuse boundary;
5. whether the edge is intra-core or cross-core;
6. fallback behavior when slots or events are insufficient;
7. tail behavior when the final phase has fewer active participants.

Draw a wait-for graph. A cycle with no initially satisfiable edge is a
deadlock; a missing edge is a race; an over-constrained edge can erase overlap.

## Public uncertainty

Block diagrams justify potential concurrency, not unlimited overlap. Queue
depths, scoreboard details, event propagation latency, and every resource
arbitration rule are not public. Confirm achieved overlap with generated IR,
compiler diagnostics, and target-device profiling.

Source: local A5 guide Sections 4, 6, 10, 11.10–11.12, 15, and 16.
