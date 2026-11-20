# Auto-Multibuffer Setting

## Control logic in the wiki

The captured compiler logic is:

```text
multibuffer = metadata.get("multibuffer")
num_stages = metadata.get("num_stages")

if either is not None:
    value = True
    if multibuffer is explicitly False:
        value = False
    elif num_stages == 1:
        value = False
    append --enable-auto-multi-buffer=<value>
```

The snapshot dataclass shows `multibuffer=True`; an inspected snapshot also
uses `num_stages=2`. The wiki itself questions whether `num_stages` must be
greater than one. Preserve that uncertainty: the shown logic determines the
emitted boolean, but does not prove a pass will create multiple buffers.

## Verification gap in the source page

Unlike several other rows, the wiki provides no positive activation marker.
Do not invent one. Use a controlled structural comparison.

### E1 — request

Capture `multibuffer`, `num_stages`, and the generated
`--enable-auto-multi-buffer=<value>` token.

### E2 — pass

Use after-all IR to identify the actual auto-multibuffer pass for the compiler
build. Preserve its diagnostic output and eligibility decision.

### E3 — required positive proof

Compare off/on IR and show at least one concrete change:

- multiple allocations or indexed slots for the same logical buffer;
- a modulo/rotation index;
- duplicated producer/consumer stage state;
- changed buffer count metadata;
- new synchronization edges protecting slot reuse.

The exact marker is build-dependent and must be quoted from the artifact.

### E4 — runtime

Confirm correctness, then show overlap in a timeline or reduced stall time.
More buffering can increase local-memory pressure and can reduce occupancy or
trigger a different fallback.

## Distinguish from CV workspace multibuffer

```text
ordinary:  --enable-auto-multi-buffer=<bool>
CV path:   --set-workspace-multibuffer=<integer>
```

They can interact but are not interchangeable evidence.

## Buffer-rotation audit

Record slot count, producer and consumer phase, first write/read, reuse edge,
tail behavior, and event/flag count for every transformed buffer.
