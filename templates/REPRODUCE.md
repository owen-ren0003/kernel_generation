# REPRODUCE - {{ID}}

Task dir: `{{TASK_DIR}}`
Mode: `{{MODE}}`

## A. Ticket Description

Fill in the bug report, user-visible symptom, and any links or issue ids.

## 1. Target Repository

Fill in the absolute path to the checkout Codex should edit.

## 2. Branch Or Commit

Fill in the base branch or commit under test.

## 3. Pre-Fix Command

```bash
# Command that currently demonstrates the bug.
```

## 4. Expected Failure Signature

Fill in the exact stderr/stdout/status pattern that proves the bug reproduced.

## 5. Post-Fix Command

```bash
# Command that should pass after the fix.
```

## 6. Expected Pass Signature

Fill in the exact output or exit-code evidence that proves the fix works.

## 7. Regression Command

```bash
# Command that checks nearby behavior did not regress.
```

## 8. Semantic Success Criterion

Describe the real behavior the code must have after the fix. This must be
stronger than "the test passes."

## 9. Recreate Disposable Artifacts

Keep the exact source revisions, dependency/wheel identifiers, input generation
recipe (including seeds and shapes), environment, build/run commands, and
expected results in this document or LOG.md. Include small uncommitted
reproducer source in a Markdown code block, or cite its committed source path.

Use `.local-artifacts/{{TASK_ID}}/` or the assigned checkout for compiler
copies, generated IR, caches and binary inputs/output. These files may be
deleted; the reproduction recipe must not rely on them remaining available.

For new disposable experiment output, use `scripts/artifact-retention.py run`
or `create`/`release` as described in `docs/artifact-retention.md`. Save result
summaries here or in LOG.md before releasing scratch. Pin unresolved evidence.
Keep source versions in Git; avoid repeated full cumulative source archives.
