# Preload Setting

## Control in the wiki snapshot

The compiler appends:

```text
--enable-preload=<value>
```

when `enable_preload` is not `None`. The captured default is `None` (off unless
supplied).

The wiki gives two enablement routes:

1. global compiler metadata/default: set `enable_preload=True` and
   `enable_dynamic_cv_pipeline=False`;
2. per-operator launch metadata: pass the same two values for that kernel.

Use build-supported booleans/casing and preserve the final command. Do not
silently edit an installed compiler for a baseline run.

## Verification

### E1 — request

With `TRITON_DEBUG=1`, confirm:

```text
--enable-preload=true
```

and record that dynamic CV is disabled as required by the wiki recipe.

### E2 — feature diagnostic

Add the documented debug category to the captured command:

```text
--debug-only=hivm-create-preload
```

The wiki's expected diagnostic contains:

```text
[hivm-create-preload]: After processing preload
```

This proves the preload processing path ran, not yet that it changed an
eligible operation.

### E3 — transformed IR

Preserve before/after IR and identify the moved/created preload operation,
its producer/consumer stage, buffer slot, and new dependency edges. A debug
banner with identical IR is E2 only.

### E4 — runtime

Run correctness, then compare same-machine timelines and robust timing. Show
that a future load overlaps useful work and that added waits or buffer pressure
do not offset the gain.

## Safety and interaction checks

- Verify dynamic CV is actually off in final metadata, not merely requested
  off before module adjustment.
- Audit multibuffer slot rotation and all set/wait pairs.
- Test short loops, tails, and insufficient-slot cases; preload distance can
  exceed available future work.
- Confirm the pass did not preload across an unsafe control-flow, alias, or
  lifetime boundary.
- Use a fresh task-specific compile cache so an old binary cannot masquerade
  as the new setting.

## Conclusion vocabulary

Use one of:

- “preload requested” (E1);
- “preload pass ran” (E2);
- “preload transformed these operations” (E3);
- “preload executed correctly and changed this measured overlap” (E4).

Avoid the unqualified statement “preload is on.”
