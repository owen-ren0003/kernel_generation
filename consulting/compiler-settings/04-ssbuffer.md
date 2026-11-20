# SSBuffer / Dynamic-CV Setting

## Scope and coupling

The wiki's `ssbuf` entry is controlled through the dynamic CV pipeline. In the
captured implementation, enabling that path also adjusts other metadata:

```text
enable_dynamic_cv_pipeline = True
set_workspace_multibuffer = 0
enable_mixed_cv = True
disable_auto_inject_block_sync = True
```

This is a coupled configuration, not an isolated “SSBuffer=true” switch.

An inspected local compiler snapshot defaults `enable_dynamic_cv_pipeline` to
`False`; the wiki describes changing it to `True` or `False` in
`compiler.py`. Always capture the effective per-kernel value.

## Module result and fallback

The compiler reads a module return code equivalent to:

```text
triton_ascend.dynamic_cv_pipeline.rc
```

The wiki defines:

| Return code observation | Meaning |
|---|---|
| `SSBUFFER return code=1` | unexpected fallback; SSBuffer path did not remain active |
| `SSBUFFER return code=2` | expected/specification fallback; path did not remain active |
| no fallback line | wiki treats this as success, but only after proving the path was attempted |

On fallback, the inspected code restores dynamic CV to false and restores
related metadata.

## Verification

### E1 — request

Capture `enable_dynamic_cv_pipeline` and every coupled metadata value before
the TTIR/TTAdapter pass runs.

### E2 — pass/result handling

With `TRITON_DEBUG=1`, preserve the dynamic-CV pass diagnostics and module
return code. A return code of 1 or 2 is explicit negative evidence.

### E3 — positive evidence

Absence of a fallback message is insufficient if the feature was never
requested. Prefer one of:

- a build-provided positive diagnostic;
- temporary, print-only instrumentation of the successful `else` branch,
  clearly labeled as instrumented (the wiki screenshot uses
  “SSBUFFER has been successfully enabled”);
- a documented SSBuffer/dynamic-CV structural marker in transformed IR.

Record the exact positive marker for the tested compiler build.

### E4 — runtime

Validate correctness and the intended AIC/AIV communication behavior. For
hangs, build a wait-for graph and compare fallback-off versus active-on IR.

## Do not claim

- No return-code print ⇒ active, unless request/attempt is separately proven.
- SSBuffer is necessarily the bulk tensor path; public hardware sources leave
  payload semantics open.
- Dynamic CV, CV workspace multibuffer, and ordinary multibuffer are the same
  feature.

Hardware context: [`../hardware/03-execution-and-synchronization.md`](../hardware/03-execution-and-synchronization.md).
