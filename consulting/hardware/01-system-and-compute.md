# A5 System and Compute Quick Reference

## Core organization

The safest programmer-visible model for architecture 3510 (`dav-3510`) is one
logical compute group containing one independently executing matrix core and
two independently executing vector cores:

```text
logical AI Core group
├── AIC  — Scalar 0 + Cube + L1/L0A/L0B/L0C + MTE/Fixpipe
├── AIV0 — Scalar 1 + UB0 + SIMD/SIMT + vector/SIMT registers
└── AIV1 — Scalar 2 + UB1 + SIMD/SIMT + vector/SIMT registers
```

The physical product provision is 1 AIC : 2 AIV, but a kernel can launch AIC
only, AIV only, 1:1 mixed, or 1:2 mixed work. Do not infer a 1:2 launch merely
from the physical ratio.

Above this group, STARS 2.0 schedules chip resources, and a shared coherent L2
connects compute resources to global memory. STARS is not the same as a
core-local Scalar scheduler.

## Division of labor

| Resource | Programmer-visible role |
|---|---|
| Cube / AIC | dense tiled matrix multiply-accumulate |
| Vector SIMD / AIV | regular elementwise, activation, reduction, conversion, and vector work |
| Vector SIMT / AIV | irregular addressing, divergent control, gather/scatter-style work |
| Scalar | loops, branches, address arithmetic, issue, and synchronization |
| MTE / DMA / NDDMA | asynchronous tensor movement and supported rearrangement |
| Fixpipe | L0C result drain plus selected conversion, layout, quantization, and activation functions |

SIMD and SIMT are modes of the AIV/vector subsystem, not evidence for two
unrestricted full-width ALU arrays. Public material describes SIMD as primary
and SIMT as auxiliary.

## Published local capacities

| Storage/resource | Public capacity | Scope |
|---|---:|---|
| Shared L2 | up to 128 MB | chip-shared |
| L1 Buffer | 512 KB | AIC / logical group |
| L0A | 64 KB | AIC left operand |
| L0B | 64 KB | AIC right operand |
| L0C | 256 KB | AIC accumulator/result |
| Unified Buffer | 256 KB per AIV; 512 KB per group | AIV scratchpad |
| SIMT Register File | 128 KB per AIV | AIV thread state |
| SIMT DCache | up to 128 KB per AIV | UB-backed cache lines |
| RegTensor | 256-byte vector length | SIMD register object |

No universal public capacity should be asserted for BT Buffer, Fixpipe Buffer,
or SSBuffer from this source set.

## Compute shapes and datatype implications

The architecture guide records these programmer-visible Cube primitives,
written below as `(M × K × N)`:

- FP16: `16 × 16 × 16`, a `16 × 16` by `16 × 16` matrix step;
- INT8: `16 × 32 × 16`, a `16 × 32` by `32 × 16` matrix step.

The shape describes an architectural compute primitive, not complete GEMM
latency. Staging, issue, accumulation, tails, pipeline fill/drain, and output
handling still matter.

The guide lists Cube support including FP32, FP16, BF16, HiF8, FP8 E4M3,
FP8 E5M2, U8, and S8, with product-level material also discussing MXFP8 and
MXFP4. Always distinguish input encoding, multiply behavior, accumulator
precision, and Fixpipe output type.

For a 256-byte SIMD vector:

| Element width | Elements |
|---:|---:|
| 4 bytes | 64 |
| 2 bytes | 128 |
| 1 byte | 256 |

This is a width calculation, not an end-to-end throughput claim.

## SIMT occupancy constraint

The public register-allocation relationship is:

| Active SIMT threads | Maximum registers per thread |
|---:|---:|
| 1–256 | 127 |
| 257–512 | 64 |
| 513–1024 | 32 |
| 1025–2048 | 16 |

Do not assume an NVIDIA warp width. The source material documents four warp
schedulers per AIV but does not disclose every parameter needed for a
cycle-accurate occupancy or divergence model.

## Confidence boundary

Treat the capacities, 1:2 organization, documented paths, alignments, and
register width as high-confidence public facts. Do not fabricate exact queue
depths, bus widths, instruction latencies, scoreboard behavior, event latency,
or all legal overlap combinations.

Source: local A5 guide Sections 0–6, 8, 12, and 15; provenance in
[`../SOURCE-NOTES.md`](../SOURCE-NOTES.md).
