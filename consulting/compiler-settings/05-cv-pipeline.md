# CV Pipeline Setting

## Control shown in the wiki

The compiler propagates:

```text
set_workspace_multibuffer = metadata["set_workspace_multibuffer"]
    → --set-workspace-multibuffer=<N>
```

The wiki uses this interpretation:

| Value | Wiki interpretation |
|---:|---|
| `2` | CV pipeline enabled |
| `0` or `1` | CV pipeline disabled |

It calls the feature default-on, but an inspected compiler dataclass defaults
the field to `None`; other metadata can supply the effective value. Therefore,
the generated command is authoritative for the tested build.

## Verification

### E1 — request

With `TRITON_DEBUG=1`, capture the full command and confirm the exact
`--set-workspace-multibuffer=<N>` value. Absence is not equivalent to `0`
unless the effective compiler source defines it that way.

### E2 — pass execution

Recompile the saved TTAdapter input with:

```text
--mlir-print-ir-after-all
```

Identify and preserve the CV-pipeline pass output in that build. The saved
wiki does not provide a stable universal pass-name token, so record the exact
name rather than guessing.

### E3 — transformation

Compare `N=2` with the controlled-off value and identify the changed workspace
buffers, producer/consumer stages, or synchronization structure. Option
presence alone is only E1.

### E4 — runtime

Check correctness, then confirm improved overlap or reduced idle time in a
timeline. A larger buffer count can consume capacity or add synchronization
without benefiting a short kernel.

## Interaction warnings

- The inspected dynamic-CV path sets `set_workspace_multibuffer=0`; record the
  final value after metadata adjustment.
- `--set-workspace-multibuffer` is distinct from
  `--enable-auto-multi-buffer`; verify them independently.
- A command generated from a stale cache does not prove the tested binary was
  rebuilt with the setting.

## Controlled comparison record

Preserve final metadata, command, after-pass IR, buffer counts, event edges,
correctness, and same-machine timing for both enabled and disabled runs.
