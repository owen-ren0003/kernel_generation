# Skill: recognize and avoid reward-hacking fixes

Reward-hacking is fixing a bug by *making the symptom go away* instead
of fixing the root cause. The test passes, the CI is green, the user is
happy in the short term — and the underlying bug is still there,
waiting to surface in a different reproducer or in production.

For example, disabling CV pipelining for every loop with a tensor
`iter_arg` might pass one failing test while disabling the optimization
for a whole kernel family. Keep the reproducer on the affected path.

## What reward-hacking looks like in this codebase

**Pattern 1 — bailout at the head of the triggering pass.**
A new `if (...) return failure();` (or `return std::nullopt;`) at the
top of the function the bug is in. The condition matches the failing
case, so the pass skips it; everything else still runs. Symptom gone,
bug intact.

**Pattern 2 — skipping the failing test.**
`@pytest.mark.skip`, `@pytest.mark.xfail`, `try: ... except:
pytest.skip()`, or deleting the test file outright.

**Pattern 3 — weakening a CHECK.**
Adding `// CHECK-NOT:` for a previously-`CHECK:`'d line, or removing a
positive `CHECK:` from a lit test. The test now tolerates the wrong
behavior.

**Pattern 4 — disable-flag.**
`--no-verify`, `--skip-checks`, `--disable-...`, `--no-gpg-sign` added
to a script that previously didn't have it.

**Pattern 5 — weakening the reproducer.**
Editing the task's REPRODUCE.md to remove or soften the expected
failure signature, so verify-repro.sh stops detecting the bug.

## How the harness defends against this

Three layers:

1. **This skill.** You read it; you internalize the patterns; you
   recognize them when you're tempted to ship one.
2. **`scripts/commit-guards/check-spirit.sh` at commit time.** Forces you to answer
   "does this fix the root cause, or dodge the symptom?" in one
   paragraph. The answer becomes a `Spirit-check:` trailer.
3. **PreToolUse + pre-commit hooks** (`.claude/hooks/pre-edit-bailout-detect.sh`,
   `scripts/commit-guards/check-bailout.sh`). They match the patterns above and
   refuse the Edit/commit until you fill in BAILOUT-CANDIDATE.md and
   touch `.bailout-approved`.

If the hook flags your edit and you genuinely believe it's not a
bailout, fill in BAILOUT-CANDIDATE.md honestly. The three questions:

1. **What is the root cause this patch bypasses?**
   If you can name it precisely, your patch should fix *that*, not the
   symptom. If you can't, you don't understand the bug yet — stop and
   investigate further.
2. **Is there a downstream consumer whose behavior depends on the
   bypassed path?**
   If yes, you've created a partial regression: that consumer is now
   wrong for the cases that previously worked.
3. **Would this fix still be correct under a different reproducer of
   the same bug?**
   Name a hypothetical reproducer that should fail after your patch.
   If you can, you've fixed the *one* reproducer, not the bug.

## What's not reward-hacking

- Adding a guard for a genuinely-impossible case (e.g.
  `if (rank <= 1) return UNKNOWN;` in a function whose input is
  *expected* to have rank ≥ 2). Distinguishing factor: the guard
  doesn't bypass the failing path; it documents a precondition that
  was implicit before.
- Removing a redundant CHECK that was only present because of a
  prior workaround. Distinguishing factor: the test still verifies the
  same observable behavior, just with one fewer redundant line.
- Marking a test as `xfail` *and* opening a tracking ticket whose
  acceptance criteria include re-enabling the test. Distinguishing
  factor: the failure is not hidden, it's tracked.

If you're unsure: write down the bug's root cause first. If you can't,
do not commit the patch.
