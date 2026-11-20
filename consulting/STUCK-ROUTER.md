# Stuck-Investigation Router

Use this page when two consecutive debugging approaches have failed. A failed
command is not automatically a failed approach: record an approach as
`failed` only after its hypothesis or proposed fix has been tested and ruled
out.

## Required checkpoint

1. Stop the current line of investigation.
2. Choose the obstacle class below.
3. Read the listed starting guide and any setting-specific guide it points to.
4. Record the paths and useful guidance in the task's `CONSULTATION.md`.
5. Define one new experiment that differs from both failed approaches.

The completed checkpoint resets the failure streak. If the next two revised
approaches also fail, repeat the checkpoint with a new section.

## Route by obstacle

| Obstacle class | Start here | Use it to decide |
|---|---|---|
| Synchronization, hang, or deadlock | [`hardware/03-execution-and-synchronization.md`](hardware/03-execution-and-synchronization.md) | producer, consumer, event/flag, buffer owner, and the exact wait edge to prove |
| Memory, transfer, address space, or stale data | [`hardware/02-memory-and-data-movement.md`](hardware/02-memory-and-data-movement.md) | source/destination memory, transfer engine, lifetime, reuse, and alignment evidence |
| Compiler setting or pass appears inactive | [`compiler-settings/00-activation-evidence-model.md`](compiler-settings/00-activation-evidence-model.md), then [`compiler-settings/README.md`](compiler-settings/README.md) | whether the option was requested, accepted, run, visible in IR, and observed at runtime |
| Performance regression or unexplained timing | [`hardware/04-performance-debugging-checklist.md`](hardware/04-performance-debugging-checklist.md) | correctness controls, warmup/cache controls, timing layer, bottleneck, and comparison evidence |
| Wrong answer, type/layout, or numerical behavior | [`hardware/01-system-and-compute.md`](hardware/01-system-and-compute.md) and [`hardware/02-memory-and-data-movement.md`](hardware/02-memory-and-data-movement.md) | executing engine, supported representation, conversion point, data path, and overwrite/reuse risks |
| Build, runtime, wheel, or remote-environment mismatch | [`SOURCE-NOTES.md`](SOURCE-NOTES.md) | exact source snapshot, version drift, deployed artifact identity, and which claim needs fresh verification |
| Unknown or mixed | [`README.md`](README.md) and [`SOURCE-NOTES.md`](SOURCE-NOTES.md) | split the symptom into hardware, compiler-setting, environment, and evidence questions before choosing a narrower guide |

For preload, multibuffering, and CUBE/VECTOR pipeline problems, begin with the
synchronization guide and then consult the matching pages under
`compiler-settings/`.

## What must be different afterward

The next experiment cannot merely rerun the same command or apply the same
idea with a cosmetic change. It should change at least one of:

- the hypothesis being tested;
- the boundary being isolated;
- the evidence being collected;
- the compiler setting or pass stage being compared;
- the controlled input, build, or runtime configuration.

Generated IR, logs, and measurements remain the deciding evidence. Consulting
material helps choose the next experiment; it does not prove the result.
