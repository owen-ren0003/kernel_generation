# AutoBlockify Setting

## Purpose

AutoBlockify maps or packs logical parallel blocks into a physical execution
schedule. The wiki focuses on the SIMT path and ties compile-time lowering and
the runtime block-count cap to the same environment switch.

## Control

The captured control chain is:

```text
TRITON_ALL_BLOCKS_PARALLEL
    → _is_auto_map_parallel_blocks_enabled()
    → --enable-auto-blockify-loop
```

The wiki calls the feature normally enabled and gives this controlled-off
recipe:

```bash
export TRITON_ALL_BLOCKS_PARALLEL=0
```

For a controlled-on run, use only values accepted by the effective source and
record whether the variable was unset or explicitly set. Do not infer truthy
parsing from another wheel.

## Verification

### E1 — request

Run with `TRITON_DEBUG=1` and confirm the generated command includes:

```text
--enable-auto-blockify-loop
```

### Explicit negative evidence

Search for a warning equivalent to:

```text
AutoBlockify disabled for kernel '<name>'; unsafe operation: ...
```

The option can be requested while a safety blacklist prevents transformation.

### E2/E3 — pass and IR

Use after-all IR to confirm the `AutoBlockifyParallelLoop` pass ran and look
for a structural marker such as:

```text
autoblockify.subloop
```

Capture the before/after loop and physical-block mapping. A pass banner alone
is E2; a rewritten loop/attribute is E3.

### E4 — runtime heuristic

The wiki suggests `TRITON_DEVICE_PRINT=1` and comparing printed AIC count with
physical core count. Treat this as corroborating runtime evidence, not a unique
proof: other scheduling choices can produce the same count.

## Common false conclusions

- Flag present ⇒ transformed: false; safety rejection can follow.
- AIC count equals hardware count ⇒ AutoBlockify caused it: only a heuristic.
- More physical blocks ⇒ faster: tails, sequential work per core, and memory
  pressure can reverse the result.
- AutoBlockify is always safe with cross-block locks: the inspected snapshot
  specifically blacklists some `sync_block_lock` cases.

## Minimum comparison

Record off/on command lines, warnings, loop IR, logical and physical block
counts, correctness, and runtime on the same shape and machine.
