# A5 Performance-Debugging Checklist

## Six-question mental model

Ask these in order for every hot tensor or tile:

1. **Where does the large tensor live?** Usually GM, with shared L2 in the
   physical access path.
2. **Which engine computes it?** Cube for dense matrix work; SIMD for regular
   vector work; SIMT for irregular/thread-style work; Scalar for control.
3. **Which local storage must hold it?** L1/L0A/L0B/L0C, UB, RegTensor, SIMT
   registers, BT, or FP.
4. **Which engine moves it?** MTE2, MTE1, MTE3, NDDMA, Fixpipe, or SDMA.
5. **Which dependency protects it?** Event, BufferID ownership, or cross-core
   synchronization.
6. **Can an external-memory round trip be removed?** Check `L0C→UB`, `L1↔UB`,
   register reuse, Fixpipe transforms, NDDMA, and L2 retention.

## Symptom-to-evidence map

| Symptom | First hypotheses | Evidence to collect |
|---|---|---|
| Cube underutilized | insufficient tasks, tail waste, MTE1 starvation, small/non-fractal tiles | task grid, Cube issue count, MTE1/Cube timeline, tile shapes |
| Vector underutilized | UB traffic, bank conflicts, short vectors, SIMT divergence, register pressure | SIMD/SIMT mode, lane utilization, UB access pattern, register/thread count |
| High GM traffic | lost L1/L2 reuse, indirect GM intermediate, cache non-allocation | requested bytes, L2 hit behavior, generated payload path, tile reuse count |
| Pipeline does not overlap | missing preload/multibuffer transform, conservative dependency, slot exhaustion | requested option, pass log, transformed IR, event timeline |
| Correctness changes with tuning | reduction regrouping, changed accumulation type/order, unsafe overwrite | arithmetic trace, K partition/tree, buffer ownership, datatype conversion |
| Deadlock or hang | unmatched set/wait, cyclic slot reuse, participant-count mismatch | wait-for graph, per-flag counts, tail/phase trace, fallback diagnostics |

## Tile hierarchy to keep distinct

```text
logical M,N,K
    ↓ source program tile: BLOCK_M/BLOCK_N/BLOCK_K
    ↓ compiler lowering
AIC task tile: T_M/T_N
    ↓ local schedule
base/L0 tile: b_M/b_N/b_K
    ↓ ISA decomposition
Cube microtile: i_M/i_N/i_K
    ↔ datatype-specific fractal layout atom
```

Numerical equality between two levels is a property of a particular lowering,
not a definition. `BLOCK_K` and `b_K`, for example, can match but need not.

## Common architecture-reading errors

- Calling L1/L0/UB hardware-managed caches.
- Treating MTE1/MTE2/MTE3 as storage levels.
- Assuming a GM arrow bypasses shared L2.
- Reading an arrow as a mandatory route instead of a supported path.
- Treating FP Buffer as “floating-point buffer” rather than Fixpipe Buffer.
- Treating a fractal block as a free scheduler tile.
- Inferring every latency, queue depth, or overlap rule from a block diagram.
- Equating a generated option with a successful compiler transformation.

## Minimum performance experiment record

Record together:

- hardware SKU, firmware/driver/CANN, wheel, and compiler build;
- shape, datatype, layout, launch metadata, and cache state;
- source program tile and observed physical task/base tile;
- generated compiler command and setting evidence level;
- correctness result before timing;
- warm-up policy, repetitions, distribution, and device occupancy;
- relevant IR, profiler trace, and interpretation boundary.

Without that record, a faster number may be an environment or routing change
rather than the intended optimization.

Source: local A5 guide Sections 4, 8–13, 15–17, plus the guide's documented
versus unknown boundary.
