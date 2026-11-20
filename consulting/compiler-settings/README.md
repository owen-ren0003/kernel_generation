# AscendNPU-IR Compiler-Setting Consulting

This directory converts the saved “feature took effect” wiki page into one
document per setting. Read
[`00-activation-evidence-model.md`](00-activation-evidence-model.md) before any
individual playbook.

## Snapshot matrix

| Wiki label | Primary control shown in the capture | Snapshot/default note | Strongest positive evidence in the capture | Guide |
|---|---|---|---|---|
| costmodel | `enable_vf_fusion` → `--enable-vf-fusion` | no timeless default; naming is ambiguous | VF-fusion analyzer output plus changed IR | [`01`](01-costmodel-and-vf-fusion.md) |
| autoblockify | `TRITON_ALL_BLOCKS_PARALLEL` → `--enable-auto-blockify-loop` | wiki says normally enabled; safety checks can disable it | pass/IR evidence such as `autoblockify.subloop`; no disable warning | [`02`](02-autoblockify.md) |
| SIMT template | `compile_mode` | capture says `unstructured_in_simt` was current default | `parallel_mode = "mix_simd_simt"` in TTAdapter IR | [`03`](03-simt-template.md) |
| ssbuf | `enable_dynamic_cv_pipeline` and module return code | build-dependent; inspected snapshot defaults dynamic CV off | no fallback return code only after proving the path was attempted; positive instrumentation/IR preferred | [`04`](04-ssbuffer.md) |
| cvpipeline | `set_workspace_multibuffer` → `--set-workspace-multibuffer=N` | wiki says default on; actual metadata must be captured | CV-pipeline pass and transformed after-all IR | [`05`](05-cv-pipeline.md) |
| cv 1:2 | `enable_auto_bind_sub_block` / module-derived `auto_tile_and_bind_subblock` | wiki says default on; explicit user value has priority | `tiled_op` on a listed HIR store/copy operation | [`06`](06-cv-1-to-2.md) |
| multibuffer | `multibuffer`, `num_stages` → `--enable-auto-multi-buffer` | `multibuffer=True` in capture; `num_stages==1` forces false | wiki gives no positive marker; require structural IR/buffer evidence | [`07`](07-multibuffer.md) |
| preload | `enable_preload` → `--enable-preload` | `None`/off by default in capture | `hivm-create-preload` diagnostic plus transformed IR | [`08`](08-preload.md) |

“Default” in this table means a dated observation, not a contract for a future
wheel.

## Interaction map

```text
compile_mode ───────────────→ SIMD / mixed-SIMT / pure-SIMT lowering
TRITON_ALL_BLOCKS_PARALLEL ─→ AutoBlockify request ─→ may be rejected as unsafe

enable_dynamic_cv_pipeline ─┬→ SSBuffer eligibility/result code
                            ├→ enable_mixed_cv = True
                            ├→ disable_auto_inject_block_sync = True
                            └→ set_workspace_multibuffer = 0 in inspected code

set_workspace_multibuffer ──→ CV workspace pipeline setting
multibuffer / num_stages ───→ ordinary auto-multibuffer setting

enable_auto_bind_sub_block ─→ CV 1:2 binding override
enable_preload ─────────────→ preload transform; wiki recipes disable dynamic CV
```

`set_workspace_multibuffer` and ordinary `multibuffer` are separate controls.
Do not use one as proof that the other is active.

## Required task record

For any setting experiment, preserve:

- machine/SKU, CANN, wheel, and compiler identity;
- launch metadata and relevant environment variables;
- generated TTAdapter/IR and `bishengir-compile` command;
- feature-specific diagnostic output;
- off/on structural comparison;
- correctness and runtime result;
- cache/dump isolation method.

Source and drift notes: [`../SOURCE-NOTES.md`](../SOURCE-NOTES.md).
