# SIMT Template Selection

## Modes in the wiki snapshot

| `compile_mode` | Derived behavior shown in the captured code |
|---|---|
| `simd` | `parallel_mode = "simd"` |
| `unstructured_in_simt` | `force_simt_template = True`; mixed SIMD/SIMT template |
| `simt_only` | `force_simt_only = True`; `parallel_mode = "simt"` |

The wiki says `unstructured_in_simt` was the current default on 2026-06-08.
An inspected July compiler snapshot has the same dataclass default, but future
wheels must be checked.

The captured code also assigns default dynamic shared-memory sizes based on
the mode. Treat those numbers as build-specific implementation defaults, not
portable architectural capacities.

## Verification

### E1 — frontend metadata

Capture `compile_mode`, `parallel_mode`, `force_simt_template`,
`force_simt_only`, `num_warps`, `warp_size`, and shared-memory metadata from
the effective compilation.

### E3 — TTAdapter marker

For the mixed SIMT template, the wiki's positive marker is:

```text
parallel_mode = "mix_simd_simt"
```

Search the generated `*.ttadapter.mlir`, not only Python defaults.

For `simt_only`, the inspected compiler snapshot also emits a pure-SIMT
command path with options such as `--pure-simt`, warp count, and threads per
warp. Capture the actual tokens for the wheel under test.

### E4 — runtime

Confirm correctness and collect evidence that the intended SIMT kernel/path
ran. Compare memory-access behavior, divergence, register pressure, and AIV
utilization rather than assuming SIMT is faster for regular work.

## Interpretation

- `compile_mode` selected in Python is E1.
- `parallel_mode = "mix_simd_simt"` in TTAdapter IR is E3 for that template.
- A function containing both regular and irregular work can legitimately use
  mixed mode.
- Hardware has SIMD and SIMT capabilities, but template selection is a
  compiler/program decision.

## Interaction with AutoBlockify

The inspected source appends SIMT AutoBlockify options inside the pure-SIMT
path when the all-blocks-parallel predicate is true. Verify both template and
AutoBlockify independently; one does not prove the other.
