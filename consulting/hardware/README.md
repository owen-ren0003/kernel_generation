# Ascend A5 Hardware Consulting

These documents distill the local `ascend_a5_architecture_guide.md` into four
operational references for compiler and kernel investigations.

| Document | Use it when |
|---|---|
| [`01-system-and-compute.md`](01-system-and-compute.md) | identifying AIC/AIV ownership, compute mode, local resource, capacity, or datatype constraints |
| [`02-memory-and-data-movement.md`](02-memory-and-data-movement.md) | tracing GM/L2/local-memory traffic, format conversion, alignment, Fixpipe, or Cube–Vector fusion |
| [`03-execution-and-synchronization.md`](03-execution-and-synchronization.md) | reasoning about asynchronous pipelines, events, cross-core flags, SSBuffer, or buffer reuse |
| [`04-performance-debugging-checklist.md`](04-performance-debugging-checklist.md) | planning an evidence-driven performance or utilization investigation |

## Scope shorthand

In this library, **A5** means the public programmer-visible architecture for
Ascend 950PR/950DT and CANN target `dav-3510`. It is not a claim that every SKU
has identical counts or that public block diagrams expose a cycle-accurate
microarchitecture.

For provenance and uncertainty rules, see [`../SOURCE-NOTES.md`](../SOURCE-NOTES.md).
