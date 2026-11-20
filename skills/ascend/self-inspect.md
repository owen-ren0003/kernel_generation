# Skill: Self-inspect a fix before committing

Before declaring a compiler fix done, walk this checklist. Each item has a
PASS/FAIL outcome you must capture in `state/issues/<DTS_ID>/INSPECTION.md`.

A fix that fails any item below is **not ready to commit**. Either resolve
the failure or document why it is acceptable in `INSPECTION.md`.

## 0. Convention discovery (do FIRST, before any code change)

Before writing source or test changes, collect:

```bash
# Commit-message tag style on this repo
git log --format='%s' -20 <upstream-branch> | head

# Test-file layout for the pass being modified
ls bishengir/test/<closest-dialect-or-area>/
grep -rl '<pass-flag>' bishengir/test/

# Convention rule of thumb in this repo: one pass per test file. Search
# for an existing test file dedicated to the pass you're modifying. If
# none exists, create one whose path mirrors the source path.
```

Skipping this step costs 3-4 commit/reset cycles when reviewers point
out the wrong file location, missing tags, or wrong branch name. The
search above takes 30 seconds.

## 1. Behavior verified end-to-end (THREE-way check, not one-way)

A test passing with the fix is not a verification. The minimum is a
three-way comparison on the **same environment / same NPU device**:

| Binary | Expected outcome |
|---|---|
| Known-good baseline (e.g. 0428) | PASS — confirms environment is sane |
| Bug-reproducing reference (e.g. 0429 ticket binary) | FAIL with the documented bug signature |
| HEAD + your fix | PASS |

If the bug-reproducing reference *passes* in your env, the env doesn't
exercise the bug — your fix isn't being tested. If the known-good
baseline fails, the env is corrupted (e.g., NPU device state — see
`diff-envs.md`).

Save all three test outputs to `state/issues/<DTS_ID>/`.

If verification needs an ABI-compatible counterpart binary that we did not
build (e.g. `hivmc-a5` paired with our own `bishengir-compile`), document
the pairing. Don't assume "compiles → fixed".

## 2. Style consistency

Open the file you edited. Confirm new code matches the surrounding style:

- Indentation, brace style, naming convention.
- Same include conventions (alphabetized? per-block?).
- Use the same APIs as nearby code — e.g. if the file uses
  `markOp.getSrc()`, do not introduce `markOp.getOperand(0)`.
- Comment density: match the file's local norm.

If you copied from a sibling fix (e.g. ported a patch from another file),
verify the API surface is the same in both files — nearby utilities may
have diverged.

## 3. Time-complexity audit (CRITICAL)

### 3a. Optimization sniff test (do BEFORE coding the change)

Before implementing any change framed as a perf improvement, write the
cost equation in `INSPECTION.md`:

| Quantity | Old | New |
|---|---|---|
| Setup cost | | |
| Per-mark/per-iter cost | | |
| Total work | | |

Then identify the **crossover regime** — for what inputs does the new
version actually win? If the crossover is at sizes larger than the
typical workload, the "optimization" is a regression for the common case
and a marginal win for an edge case. Either drop it or guard it with a
heuristic.

Common false-optimization patterns observed:

- Pre-built `DenseSet<Value>` to avoid `getAnnotateOpWithAttr`: O(N)
  setup cost. For typical kernels with M·U ≪ N, this is a regression.
- Symmetric forward/backward walk to "eliminate" a cleanup loop: relocates
  the same use-edge traversal to a different pass, doesn't reduce total
  work.
- Counter-based pre-aggregation: same edge traversal cost, just amortized
  differently. Wins only when the inner-probe constant matters.

The honest reality for `AnalyzeArithVectorMask`-shaped passes (M·U·U′
typically ~hundreds of ops): the cleanup loop is not a hotspot.
Optimization changes that add setup cost are net-negative. Only bother
optimizing if profiling shows the function is hot.

### 3b. Loop complexity in the patch

If your patch added a loop, **work out the big-O cost** before committing:

- Outer-walk cost (once per op / per annotation / per region).
- Inner work per outer step.
- Multiply: is the result polynomially bigger than the unfixed version?

Common red flags:

| Pattern | Cost | Problem |
|---|---|---|
| Inner `getXxxWithAttr(v, ...)` walks `v.getUsers()` | O(U) | If called inside a per-user loop → O(U²) |
| Recursive walk into operands without memoization | unbounded | exponential on diamond DAGs |
| Repeated `DominanceInfo` construction | expensive | hoist out of the loop |

If you see O(U²) or worse, **first ask whether the optimization is
sound**. Some checks need to read state that changes during the walk —
caching the state pre-walk gives stale answers. Common pitfalls:

- An "is this value annotated?" probe that reads current annotation
  state, when the same walk erases annotations mid-iteration. Caching
  the answer pre-walk loses transitive cascading-erasure semantics.
- A dominance-style query that depends on IR position, in a walk that
  reorders or splits ops.

If the dynamic probe's answer can change because of the walk's own
side-effects, **the dynamic probe is doing real work** — caching it
breaks correctness. Document it in source (`// dynamic on purpose:
erasure during this walk must propagate`) and accept the cost.

If the dynamic probe is provably side-effect-free w.r.t. the walk,
caching is safe. Common cures:

- Pre-compute a `llvm::DenseSet<Value>` / `DenseMap` once, do O(1) lookups
  inside the loop.
- Hoist invariants (DominanceInfo, attribute lookup) out of inner loops.
- Walk in `PostOrder` once and accumulate state instead of nesting walks.

**Concrete example** (failure mode this rule catches): pre-caching a
`DenseSet<Value>` of marked values before a cleanup walk that erases
marks. The set goes stale relative to the IR → marks that should be
transitively erased keep their annotation → silent miscompile.
The dynamic probe is correct; the cache is faster but wrong.

Document in `INSPECTION.md`:
> "Patch adds an inner loop over `value.getUsers()`. Worst-case U per
>  marked value. We pre-build a `DenseSet<Value>` of marked values once, so
>  the user-loop check is O(1) per user → O(M·U) total. Overall pass cost
>  unchanged from O(M·U) baseline."

## 4. IR unittest

Add or extend an `mlir` lit-test to cover the fix. Keep the test minimal
and self-contained — one func.func per case, with `// CHECK` directives
that assert the expected post-pass IR.

For an erasure-style fix (annotation removed), use `// CHECK-NOT`. For an
insertion-style fix, use `// CHECK` with capture variables.

Cover:

- The bug pattern (without your fix, this case fails).
- The negative case (a similar pattern that should NOT trigger the fix).
- A regression guard (the existing healthy path).

Test file location: `bishengir/test/Dialect/<dialect>/<pass-name>.mlir`,
or under `Conversion/<source>To<dest>/` for conversion patterns. Mirror
how existing tests in the same area are organized.

Run the test locally:

```bash
docker exec ascend-build bash -c "
  cd /src/AscendNPU-IR-Dev/build-dev
  ninja check-bishengir-${dialect}    # if available
  # or run lit directly:
  ./bin/llvm-lit -v ../bishengir/test/Dialect/HIVM/TransformOps/analyze-arith-vector-mask.mlir
"
```

If lit is not available in the build, check the test by manually invoking
`bishengir-opt` with the same flags lit would use, and grep for the CHECK
patterns in the output.

## 5. Did the fix break anything else?

Run a small regression sample, not just the representative test.

```bash
bash scripts/run-tests.sh --tests state/regression-sample.txt
```

If `regression-sample.txt` doesn't yet cover the dialect / pass area you
touched, add 3-5 representative tests and commit them in the same PR.

Document any test that newly fails. If the fix causes regression, **do not
commit** — back out and re-investigate.

## 6. Duplicate-symbol / link-order check

If the file you edited also exists at another path in the repo (a
duplicated source tree), check whether **both** define the same symbol:

```bash
docker exec ascend-build bash -c "
  cd /src/AscendNPU-IR-Dev/build-dev
  for lib in $(ls lib/*.a); do
    if nm \$lib 2>/dev/null | grep -q '<your-symbol-mangled>'; then
      echo \"\$lib defines the symbol\"
    fi
  done
"
```

If multiple libraries define the same symbol, only the first one on the
link line is linked into the final binary. Your fix may be dead code if
applied to the wrong copy. Check the symbol address in the final binary
matches your fix:

```bash
nm ./bin/bishengir-compile | grep '<your-symbol-mangled>'
addr2line -e ./bin/bishengir-compile <addr>
```

If duplicates are found, also file a follow-up to deduplicate the source
tree. Note this in `INSPECTION.md`.

## 7. Commit hygiene

Before `git commit`:

- Branch name: `fix/<dts-id>` or `fix/<category>` (per WORKFLOW.md).
- Commit message format: a short subject (≤72 chars), blank line,
  body explaining **why** the fix is correct (the IR-level reason), and
  the **bug-introducing commit** hash if known.
- **Do NOT include `Co-Authored-By` lines, AI-tool signatures, or
  "Generated with X" footers.** Author the commit as the user.
- One commit per fix. If you also added a test, include it in the same
  commit unless the test is a substantial separate effort.

Example commit message body skeleton:

```
[<repo-tag>][<area-or-pass>] short imperative subject (≤72 chars)

WHAT goes wrong (the IR-level / runtime symptom).

WHY it goes wrong (the line of reasoning from cause to symptom).

WHAT the fix does (one paragraph; reference functions/passes by name).

(optional) Where the same logic lives elsewhere in the tree, prior-art
commits, follow-ups.
```

Match the project's tag style observed in Step 0 (`git log --format='%s'`).

## 8. Write `INSPECTION.md`

Final artifact. Save in `state/issues/<DTS_ID>/INSPECTION.md`:

```markdown
# Self-inspection — <DTS_ID>

## Behavior verification — PASS
<test invocation, output>

## Style — PASS
<sibling-file API surface checked: `markOp.getSrc()` matches; include
order matches>

## Time complexity — PASS
<big-O analysis>

## IR unittest — PASS  (or PARTIAL with reason)
<test file path, what it asserts, lit run result>

## Regression sample — PASS
<tests run, all pass>

## Duplicate-symbol check — <FOUND duplicates / NONE>
<lib paths with the symbol; link-order analysis>

## Commit — <branch name, commit SHA>
```

Only **after** writing INSPECTION.md should the fix be considered ready
for `master-maintainer` integration.
