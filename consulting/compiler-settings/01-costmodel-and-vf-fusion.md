# Costmodel and VF-Fusion Setting

## Naming warning

The wiki row is labeled **costmodel**, but every control and diagnostic shown
in that row concerns **VF fusion**:

```text
metadata enable_vf_fusion
    → --enable-vf-fusion=<value>
    → vf-fusion-max-parallel-analyzer diagnostics
```

An inspected local `compiler.py` also contains a separate
`enable_costmodel_backend` option. Do not treat that option and
`enable_vf_fusion` as synonyms. This guide verifies only the wiki's VF-fusion
path unless the task supplies build-specific costmodel evidence.

## Control chain in the wiki snapshot

The captured logic appends:

```text
--enable-vf-fusion=<True|False>
```

when `enable_vf_fusion` is not `None`. The wiki also shows a temporary
`TRITON_ENABLE_VF_FUSION` environment override accepting true-like values,
then metadata, then `None`. That override was not present in the older local
compiler snapshot used for cross-checking, which demonstrates version drift.

Controlled disable in the wiki is `enable_vf_fusion=False`. For enablement,
capture the exact accepted metadata/environment path in the wheel under test.

## Verification

### E1 — request

With `TRITON_DEBUG=1`, confirm the generated command contains the exact
`--enable-vf-fusion=<value>` token.

### E2 — analyzer/pass execution

Re-run the captured TTAdapter input with the original options plus:

```text
--mlir-print-ir-after-all
--debug-only="vf-fusion-max-parallel-analyzer"
```

Preserve combined stdout/stderr and search for the documented `VFFusion`
diagnostics.

### E3 — transformation

Diff controlled off/on after-pass IR. Identify the exact fused regions,
operation count, or scheduling attributes changed by the pass. Analyzer text
without a structural IR change is E2, not E3.

### E4 — runtime

Run correctness first. Then compare the same kernel/shape/build with identical
warm-up and cache policy. Record whether fusion removed operations/transfers or
changed vector utilization; timing alone does not identify the mechanism.

## Failure interpretation

| Observation | Conclusion |
|---|---|
| flag missing | VF fusion not requested on that command path |
| flag present, no analyzer output | diagnostic/pass path not proven; check build and debug category |
| analyzer output, unchanged IR | analysis ran but no material fusion proved |
| IR fused, runtime unchanged | transform active; workload may not benefit |

## Drift check

Inspect the effective `compiler.py` for all of:

```text
enable_vf_fusion
TRITON_ENABLE_VF_FUSION
enable_costmodel_backend
vf_fusion_mode
```

Document which controls exist before making a “costmodel enabled” claim.
