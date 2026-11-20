# kernel_generation

A Codex-oriented harness for repeatedly debugging and fixing Ascend compiler
and FlagGems-related bugs without losing task state, contaminating repeated
attempts, or accepting "test passes" as proof of a real fix.

This harness was adapted from an Ascend/FlagGems debugging harness for use with
Codex. The source harness is specialized for FlagGems, AscendNPU-IR-Dev,
remote NPU test machines, and Claude Code subagents/hooks. This version keeps
that Ascend operational scope while replacing Claude-specific wiring with
Codex project instructions and hooks.

## What This Is For

Use this harness when you want Codex to solve Ascend-related bug-fix tasks
with an auditable process:

1. Create or resume a task folder under `state/tasks/<task_id>/`.
2. Capture the bug report, reproducer, expected failure, semantic success
   criterion, and regression command.
3. Assign the task to a named workspace such as `ws1`.
4. Investigate until the root cause is explicit.
5. If two consecutive approaches fail, complete the mandatory consulting
   checkpoint before trying another approach.
6. Implement a narrow fix in the assigned workspace.
7. Build/deploy Ascend binaries when needed and run pre-fix/post-fix
   verification commands plus a regression sample.
8. Pass critique and reward-hack gates before committing.
9. Mark the task done only when the objective evidence is present.

The harness does not replace judgment. It forces the evidence and state to be
kept in predictable files so the next Codex turn, a fresh Codex session, or a
human reviewer can continue from the same record.

## Consulting Library

The [`consulting/`](consulting/) directory adds reusable technical context to
the operational harness:

- `hardware/` distills the public Ascend A5 / Ascend 950 (`dav-3510`)
  programmer-visible architecture into compute, memory/data-movement,
  synchronization, and performance-debugging references;
- `compiler-settings/` provides one playbook per captured AscendNPU-IR setting:
  costmodel/VF fusion, AutoBlockify, SIMT template selection, SSBuffer,
  CV pipeline, CV 1:2, multibuffer, and preload;
- `harness/` explains where consultation fits into the task/evidence loop;
- [`materials/`](consulting/materials/README.md) indexes user-provided kernel
  source and test repositories;
- `presentation/` contains the template-matched harness overview slide.

The library is also part of the stuck-recovery gate. Two consecutive failed
approaches stop normal tool use until Codex reads `consulting/STUCK-ROUTER.md`,
reads at least one matching guide, and records a new experiment in the task's
`CONSULTATION.md`.

The setting guides distinguish option request, pass execution, transformed IR,
and runtime evidence. A generated compiler flag alone is never treated as
proof that a feature took effect.

## Key Concepts

| Term | Meaning |
|---|---|
| Task | One bug-fix attempt. State lives at `state/tasks/<task_id>/`. |
| Issue | The bug being investigated. Generic tasks usually have one issue whose id matches the task id. Suite-style tasks may have many issues. |
| Workspace | A checkout or worktree that Codex may edit. Workspaces are named `ws1`, `ws2`, etc. |
| Reproducer | The command that demonstrates the bug before the fix. Stored in `REPRODUCE.md` and optionally `meta.yaml`. |
| Semantic success criterion | The behavior that must be true for the bug to be fixed, independent of whether a specific test exits 0. |
| Critique gate | A pre-commit check requiring Codex to answer fix-quality questions before committing. |
| Reward-hack gate | A pre-commit check requiring an independent review verdict for the exact staged diff hash. |
| Prior-task firewall | A hook that blocks reading previous solutions for the same `(mode, id)` while the current attempt is still open. |
| Consulting library | Source-traceable A5 architecture and compiler-setting references under `consulting/`; advisory, while task artifacts remain authoritative. |
| Consulting checkpoint | A required recovery record after two consecutive failed approaches; it selects relevant consulting material and a different next experiment. |

## Quickstart

Requires Linux/WSL, Bash, Git and Python 3.11 or newer. The local harness tests
do not require Ascend hardware; compiler builds and remote tests additionally
need the matching toolchains and access described in `instructions/`.

```bash
cd kernel_generation
python3 -m venv .venv
source .venv/bin/activate
python -m pip install -r requirements.txt

# 1. On a new clone, create and edit your local configuration.
#    Do not overwrite existing local files when updating an installation.
cp -n config.yaml config.local.yaml
cp -n instructions/login-credentials.example.txt instructions/login-credentials.txt
$EDITOR config.local.yaml instructions/login-credentials.txt
bash tests/run-all.sh

# 2. Create a task.
bash scripts/task/new-task.sh --mode bug-track --id my-bug --focus "one-line bug focus"

# 3. Fill in the task's REPRODUCE.md and meta.yaml fields.
$EDITOR state/tasks/$(cat state/current-task)/REPRODUCE.md
$EDITOR state/tasks/$(cat state/current-task)/meta.yaml

# 4. Optionally file a more structured issue.
bash scripts/file-issue.sh --id my-bug --from templates/issue.example.yaml

# 5. Assign to a workspace.
bash scripts/assign-issue.sh --issue my-bug --ws ws1

# 6. Work the loop with Codex:
#    "Investigate the current task and write ROOT_CAUSE.md."
#    "Implement the fix in ws1, verify it, then prepare the commit gates."

# 7. Before committing a fix, generate and fill critique questions.
bash scripts/check-critique.sh --template

# 8. Run the reward-hack review prompt in skills/reward-hack-review.md,
#    append the verdict to reward-hack-reviews.log, then commit.

# 9. Close only when verification and regression pass.
bash scripts/task/done-check.sh
```

## Codex Wiring

The project-level Codex files are:

| File | Purpose |
|---|---|
| `AGENTS.md` | Durable instructions Codex reads for this harness. |
| `.codex/config.toml` | Project hook registration for Codex. |
| `.codex/hooks/pre_tool_use.py` | Workspace guard, prior-task firewall, and commit gates. |
| `.codex/hooks/post_tool_use.py` | Log-gap counter and reminders. |
| `.codex/hooks/user_prompt_submit.py` | New-task binding reminders. |

Codex may ask you to trust project hooks when starting in this directory.
That is expected: hooks run local scripts before/after tool calls. Inspect
the scripts before trusting them.

## Repository Layout

```text
kernel_generation/
├── AGENTS.md
├── README.md
├── config.yaml
├── .codex/
│   ├── config.toml
│   └── hooks/
├── docs/
│   ├── ANALYSIS-CLAUDE-HARNESS.md
│   ├── ARCHITECTURE.md
│   └── WORKFLOW.md
├── consulting/
│   ├── hardware/
│   ├── compiler-settings/
│   ├── harness/
│   ├── materials/
│   └── presentation/
├── instructions/                    Ascend build/deploy/test/env instructions
├── scripts/
│   ├── _lib.sh
│   ├── assign-issue.sh
│   ├── bind-session.sh
│   ├── check-critique.sh
│   ├── check-reward-hack-review.sh
│   ├── file-issue.sh
│   ├── release-workspace.sh
│   └── task/
├── skills/
│   ├── codex-debug-fix.md
│   ├── failure-investigator.md
│   ├── fixer.md
│   └── reward-hack-review.md
├── state/
│   ├── current-task
│   ├── grants/
│   ├── sessions/
│   └── tasks/
└── templates/
```

## What Was Deliberately Not Copied

- Existing task artifacts and previous solution logs.
- Claude-specific `.claude/agents` and Claude hook JSON.

## Local-Only Material

Keep credentials and host access notes in the ignored
`instructions/login-credentials.txt`.
Machine paths and hosts belong in the ignored `config.local.yaml`.
A shareable placeholder lives at
`instructions/login-credentials.example.txt`.

## State Retention

Keep task Markdown, logs, YAML and required bookkeeping in `state/`. Compiler
copies, caches, IR, binary inputs, profiling data and other temporary artifacts
belong in the assigned checkout or the ignored `.local-artifacts/<task>/`.
`bash scripts/artifact-dir.sh` prints the task's configured artifact location.

Keep source revisions, environment, exact input-generation and build/run
commands, failure signatures and solution instructions in REPRODUCE.md and
LOG.md. Commit reusable reproducers to the target repository or embed small
source snippets in Markdown so deleting generated files does not erase the
recipe. The task done gate checks storage policy before closing a task.

Run `python3 scripts/state-retention.py --check` for a read-only inventory.
The explicit plan/apply cleanup procedure and retention details are documented
in [state/README.md](state/README.md).

New disposable experiment output uses a managed scratch lifecycle with
seven-day retention, 5 GiB per-task and 20 GiB total soft budgets. A per-user
cron schedule and session-start catch-up clean only completed, explicitly
released scratch under a locally authorized policy. Active/pinned evidence,
source history and legacy artifacts are protected. See
[artifact retention](docs/artifact-retention.md) for setup, release/pinning,
audit records and the limits of what logs preserve.

## Maintain This Repository On GitHub

Version the harness code, instructions, templates and tests. Runtime task
history, local credentials/configuration, build products and cleanup manifests
stay outside Git; check `git status --short` before staging changes. Operational instructions use example host names and paths. Configure them
for your own Ascend environment.

After creating an empty repository on GitHub, connect and push this checkout:

```bash
git remote add origin git@github.com:YOUR_ACCOUNT/YOUR_REPOSITORY.git
git push -u origin main
```

For subsequent maintenance, run `bash tests/run-all.sh`, review `git diff`,
then commit and push the scoped changes. Review the applicable task's critique
and reward-hack gates before a fix commit. No license is selected by this
setup; choose one explicitly if you intend to grant redistribution rights.
