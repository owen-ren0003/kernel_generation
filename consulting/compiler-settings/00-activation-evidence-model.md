# Compiler-Feature Activation Evidence Model

## Four claims, four evidence levels

Use these labels in task logs and verdicts:

| Level | Claim | Typical evidence | What it does **not** prove |
|---|---|---|---|
| E1 — requested | frontend/backend requested an option | generated command contains the expected flag; metadata/env captured | pass ran or accepted the kernel |
| E2 — invoked/eligible | relevant pass or analysis executed | `--mlir-print-ir-after-all`, feature `--debug-only`, pass log | IR was materially transformed |
| E3 — transformed | generated program contains the feature's structural marker | off/on IR diff, attribute/op/buffer/schedule marker | target executed that path correctly or faster |
| E4 — runtime-observed | compiled kernel ran with the intended behavior | correctness, device print/profile/timeline/performance evidence | universality across shapes/builds |

Write the strongest level actually supported. Never promote E1 to “enabled.”

## Minimal non-invasive procedure

1. Record the effective wheel and compiler binary:

   ```bash
   python -c 'import triton, triton.language; print(triton.__file__)'
   command -v bishengir-compile
   bishengir-compile --version
   ```

2. Isolate the experiment from stale compilation artifacts. Prefer a fresh,
   task-specific cache/dump directory over deleting unrelated caches.
3. Set `TRITON_DEBUG=1`; for pytest, use `-sv` so the generated command and
   diagnostics are visible.
4. Capture the effective metadata/environment and generated
   `bishengir-compile` command (E1).
5. Preserve `kernel.ttadapter.mlir` and re-run the exact command with
   `--mlir-print-ir-after-all` plus the feature-specific `--debug-only` option
   when one is documented (E2).
6. Compare controlled off/on IR for a feature-specific structural difference
   (E3).
7. Run correctness first, then collect device/profile evidence on the same
   machine and shape (E4).

## Why command echo alone is weak

A flag can be present while:

- the pass rejects an unsafe operation;
- module metadata overrides the user default;
- a fallback return code disables the feature;
- no eligible operation exists;
- cached output predates the changed setting;
- later passes erase or reroute the transform;
- the transformed path is not executed for the tested shape.

## Negative evidence

| Observation | Proper conclusion |
|---|---|
| expected flag absent | feature was not requested through that command path |
| explicit disable/fallback warning | feature did not remain active for that kernel |
| pass ran, no eligible op | E2 only; no transformed feature instance |
| expected IR marker absent | feature not proven at E3; investigate pass/fallback/version |
| IR marker present, runtime unchanged | E3 proven; runtime effect may be negligible or masked |
| output incorrect or deadlocks | feature path is unsafe for the case, regardless of speed |

Absence of a warning is not positive proof unless the path is independently
shown to have been attempted.

## Source instrumentation is last resort

The saved wiki begins with edits that print subprocess stderr or command lists
inside installed `compiler.py`. Prefer normal debug/dump mechanisms first. If
instrumentation is necessary:

- copy or hash the original file;
- make the smallest print-only change;
- mark the environment as instrumented;
- restore it after capture;
- do not use an instrumented build as an unqualified performance baseline.

## Reporting template

```text
Feature:
Build/wheel/compiler:
Machine/SKU:
Shape and launch metadata:
Control value and environment:
E1 requested evidence:
E2 pass/analysis evidence:
E3 transformed-IR evidence:
E4 correctness/runtime evidence:
Fallback/warnings:
Off/on comparison:
Conclusion and evidence level:
```
