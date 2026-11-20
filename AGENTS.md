# Codex Harness Instructions

This repository is a task-completion harness for Ascend compiler and
FlagGems-related debugging. Treat files under
`state/tasks/<task_id>/` as the durable record of the work. Do not rely on
conversation memory alone for facts that must survive compaction, resumption,
or handoff.

## Operating Rules

1. Bind to the active task before doing task-specific work. Use
   `bash scripts/bind-session.sh <task-id>` or create a task with
   `bash scripts/task/new-task.sh --mode bug-track --id <id>`.
2. Read the active task's `REPRODUCE.md`, `meta.yaml`, `LOG.md`, and issue
   `INFO.md` before editing the target repository.
3. Work only inside paths listed in the task's `meta.yaml.in_scope_paths`.
4. Never read prior solution artifacts for a sibling task with the same
   `(mode, id)` while the current task is open. Allowed sibling files are
   limited to `meta.yaml`, `REPRODUCE.md`, `rejected-approaches.md`,
   `issues/*/INFO.md`, and ticket captures.
5. Keep `LOG.md` current. Add timestamped entries before and after meaningful
   investigation, implementation, and verification steps.
6. Record each distinct investigation or fix approach in `attempts.md` with an
   explicit outcome. After two consecutive `failed` outcomes, stop normal
   debugging, read `consulting/STUCK-ROUTER.md` plus at least one matching
   guide, and complete the task's `CONSULTATION.md` before continuing.
7. A fix commit must be narrow, reviewed, and verified. Before committing,
   fill `CRITIQUE.md` and obtain a reward-hack review verdict for the exact
   staged diff hash.
8. Do not mark a task done until `scripts/task/done-check.sh` passes.
9. Before running Ascend build, deploy, or remote test scripts, read the
   matching file under `instructions/`.
10. Before building or testing a task, check
   the locally supplied wheel directory and use the latest applicable wheels
   unless the task explicitly requires a different wheel set.
11. Before guessing a remote address, reporting that access credentials are
    missing or forgotten, or asking the user to repeat them, consult
    `instructions/login-credentials.txt` at least once for the active task.
    Re-consulting is unnecessary while those details remain in context. Ask
    the user only when the required entry is absent or the recorded access
    fails, and record that check in the task's `LOG.md`.
12. Before any experiment involving preload, dynamic CV, SSBuffer, CV
    pipelining, CV 1:2, or multibuffering, proactively read
    `consulting/compiler-settings/00-activation-evidence-model.md` and the
    matching setting guide, plus every interaction guide that it requires.
    Do this before the first launch; the two-failure stuck router is a fallback,
    not the trigger for feature-setting consultation. Record the effective
    companion settings, relevant environment variables, emitted compiler
    command, cache-isolation method, and strongest E1-E4 evidence level in the
    task `LOG.md`. Do not call a feature enabled from a requested flag alone.
13. Use neutral, work-descriptive branch names. Never put an agent signature,
    model or vendor name, or another marker that implies AI assistance in a
    branch name. Prohibited indicators include `codex`, `openai`, `chatgpt`,
    `gpt`, `claude`, `anthropic`, `gemini`, `copilot`, `aider`, `codeium`,
    `windsurf`, `devin`, and standalone `ai`, `llm`, `bot`, or `assistant`
    components. This applies when creating, renaming, copying, publishing, or
    selecting the initial name of a branch. The only exception is an explicit
    user instruction authorizing the AI-identifying name. Before using that
    exception, record the exact branch and the user's verbatim authorization in
    the active task's `meta.yaml` under `ai_branch_name_exceptions`; generic
    permission to create a branch, an old branch name, or inferred approval is
    not authorization. Validate every candidate name immediately before the Git
    operation with `python3 scripts/check-branch-name.py <branch>`. For ordinary
    branch creation, use `bash scripts/create-branch.sh` with `--repo <path>`,
    the branch name, and an optional start point; it performs that validation
    automatically.
14. Keep `state/` limited to durable records: Markdown, raw/rotated/compressed
    logs, YAML metadata, task and issue indexes, test lists, review receipts,
    and required session/build bookkeeping. Do not store compiler copies,
    wheels, IR dumps, binary captures, caches, profiling datasets, vendor
    checkouts, or temporary source trees there. Use the assigned target
    checkout or `bash scripts/artifact-dir.sh` for disposable output, and
    include that location in `meta.yaml.in_scope_paths`. Keep REPRODUCE.md and
    LOG.md sufficient to recreate inputs, commands, environment and results;
    commit reusable reproducers/tests to the target repository or include
    small task-specific source in Markdown. Historical artifact paths are
    not durable dependencies. Run `python3 scripts/state-retention.py --check`
    to audit storage. Cleanup requires a reviewed `--plan` manifest followed
    by an explicitly authorized `--apply`; never delete records to pass a gate.
    For new disposable experiment output, use the managed scratch lifecycle in
    `docs/artifact-retention.md` (`scripts/artifact-retention.py run`, or
    `create` followed by `release`). Save results and reproduction details in
    task records before release. Pin unresolved/nonreproducible evidence.
    Never create repeated full cumulative source backups: keep source history
    in Git, or one baseline plus incremental backups. Reuse compiler/wheel
    copies by hash. The authorized periodic policy expires only released
    managed scratch; active, pinned and legacy artifacts are protected.
15. Before using a newly inventoried A2/A3 host, consult
    `instructions/machine-inventory.md` and the ignored
    `instructions/login-credentials.txt`. The recorded root access is for
    approved account bootstrap only: do not build, test, or deploy as root.
    Provision or verify your personal account access, confirm the required
    device/toolchain permissions as that user, and log the result before work.
    If that cannot be done, stop and request owner/admin resolution rather
    than falling back to root or another person's account/container.

## Recommended Loop

1. Reproduce the bug and record the exact failure signature.
2. Identify the root cause and write `ROOT_CAUSE.md` or `issues/<id>/VERDICT.md`.
3. When an approach fails, record it immediately. If the second consecutive
   approach fails, use the mandatory consulting checkpoint before choosing
   another approach.
4. Implement the smallest fix that changes the broken behavior rather than
   skipping, narrowing, or rerouting around it.
5. Build with `scripts/build-ascend-npu-ir.sh` or `scripts/build-binaries.sh`
   when compiler binaries are involved.
6. Deploy with `scripts/deploy-binary.sh`, then run `scripts/run-tests.sh`.
7. Stage the diff, compute its hash, run the reward-hack review, then commit.
8. Close the task through `scripts/task/done-check.sh`.

## File Discipline

- Use scripts under `scripts/` for state transitions.
- Do not edit `state/current-task` manually unless a script tells you to.
- Do not delete historical entries from `LOG.md`, `INTERVENTIONS.md`, or
  `attempts.md`.
- Do not copy task artifacts or previous solution logs from the Claude
  FlagGems harness into this repo.
