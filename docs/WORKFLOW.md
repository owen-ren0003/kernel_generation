# Workflow

## 1. Create Or Resume A Task

```bash
bash scripts/task/new-task.sh --mode bug-track --id <bug-id> --focus "<focus>"
bash scripts/bind-session.sh "$(cat state/current-task)"
```

Modes:

| Mode | Use |
|---|---|
| `bug-track` | A normal single bug report or issue. |
| `suite-run` | A test-suite triage that may produce many issues. |
| `direct-ticket` | A ticket with a known reproducer. |

By default, `new-task.sh` resumes the most recent task with the same mode/id.
Pass `--start-fresh` only when you intentionally want another attempt on the
same bug.

## 2. Fill The Reproducer

Edit `state/tasks/<task>/REPRODUCE.md` and `meta.yaml`.

Minimum useful fields:

- Target repository path.
- Branch or commit under test.
- Pre-fix command that currently fails.
- Expected failure signature.
- Post-fix command that should pass.
- Regression command.
- Semantic success criterion.
- In-scope workspace paths.

## 3. Assign A Workspace

```bash
bash scripts/file-issue.sh --id <bug-id> --from templates/issue.example.yaml
bash scripts/assign-issue.sh --issue <bug-id> --ws ws1
```

Codex should edit only the assigned workspace unless the user expands
`meta.yaml.in_scope_paths`.

## 4. Investigate

Use `skills/failure-investigator.md` as the procedure. The output should be
one of:

- `ROOT_CAUSE.md` for single-bug tasks.
- `issues/<id>/VERDICT.md` for issue-based tasks.
- `NEEDS-MORE-DATA.md` if the root cause is still not supported by evidence.

Record each distinct hypothesis/experiment in `attempts.md` with an explicit
`Outcome`. A single approach may contain several commands; command exit codes
do not define the attempt boundary.

### Stuck checkpoint

After two consecutive `failed` outcomes, the pre-tool hook stops ordinary
investigation. To resume:

1. Open `consulting/STUCK-ROUTER.md` and classify the obstacle.
2. Read at least one matching consulting guide.
3. Complete the next section of `CONSULTATION.md`, including the attempt it
   covers and a materially different next experiment.
4. Run `python3 scripts/task/check-stuck-consultation.py --mode checkpoint`.

A valid checkpoint resets the consecutive-failure streak. Another checkpoint
is required if two more approaches fail. Writing `NEEDS-MORE-DATA.md` or using
an abandonment path additionally requires
`python3 scripts/task/check-stuck-consultation.py --mode abandon` to pass; this
enforces `min_attempts_before_give_up` as well as the checkpoint.

## 5. Fix

Use `skills/fixer.md`. The key rules are:

- Change the broken path, not the test or the routing around it.
- Keep the diff scoped to the bug.
- Run the pre-fix command first when practical, then post-fix and regression.
- Update `LOG.md` with command outcomes.

## 6. Commit Gates

Before a workspace commit:

```bash
bash scripts/check-critique.sh --template
# Fill CRITIQUE.md.

diff_sha=$(git -C <repo> diff --cached | sha256sum | awk '{print $1}')
# Use skills/reward-hack-review.md to write reward-hack-reviews.log.
bash scripts/check-reward-hack-review.sh "$(cat state/current-task)" <repo>

git -C <repo> commit
```

The Codex pre-tool hook blocks `git commit` if either gate fails.

## 7. Done

```bash
bash scripts/task/done-check.sh
```

The done check requires the task layout to be valid, the post-fix command to
pass, the regression command to pass, and the task reflection to contain at
least one non-template note.
