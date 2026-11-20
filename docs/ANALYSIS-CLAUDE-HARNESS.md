# Analysis Of The Claude FlagGems Harness

Source analyzed:
`/path/to/source-harness`.

## High-Level Shape

The Claude harness is not merely a set of scripts. It is an operational
control system around a long-running bug-fix workflow. Its strongest design
choice is separating **agent behavior**, **imperative actions**, and
**durable state**:

- Agent behavior lives in `.claude/agents/*.md`, `CLAUDE.md`, and
  `skills/*.md`.
- Imperative actions live in `scripts/*.sh` and `scripts/*.py`.
- Durable state lives under `state/tasks/<task_id>/`.
- Hooks in `.claude/hooks/` enforce the highest-risk rules at tool-call time.

This means a fresh session can recover by reading the state directory and the
role instructions, without needing the prior conversation.

## Main Workflow

The harness supports two primary entry paths:

- **Discovery path**: run a large FlagGems suite, classify failures, create
  issues from clusters, then fix selected clusters.
- **Direct path**: file a specific DTS ticket or bug report, assign it to a
  workspace, investigate, fix, verify, and integrate.

Both paths converge on the same state machine:

```text
available -> assigned -> verdict-compiler -> verified-pending-master
          -> in-master -> available
```

`active-fixes.json` is the coordination point. It maps each workspace to the
issue it owns, whether it is available, and where it is in the loop.

## Roles

The Claude harness defines specialized agents:

| Agent | Responsibility |
|---|---|
| `flaggems-test-runner` | Run the mass suite and classify failures. |
| `failure-investigator` | Diagnose one issue and write a high-confidence verdict. |
| `compiler-fixer` | Implement exactly one compiler fix in one workspace. |
| `master-maintainer` | Cherry-pick verified fixes into the integration workspace and run regressions. |
| `reward-hack-reviewer` | Independently judge whether a staged diff fixes or sidesteps the bug. |
| `give-up-reviewer` | Judge whether abandonment is earned or premature. |

The important pattern is role separation, not the literal Claude subagent
mechanism. The Codex version implements the same separation as skills and
scripts because Codex can execute directly in the shared workspace.

## Guardrails

The best parts to preserve are the generic guardrails:

- **Task binding** prevents an unbound session from inheriting the wrong
  singleton task.
- **Workspace guard** prevents cross-workspace edits and deploys.
- **Prior-task firewall** prevents repeated bug attempts from reading prior
  solutions.
- **Log consistency** keeps `LOG.md` aligned with actual work.
- **Critique gate** blocks fix commits until structured self-review is filled.
- **Reward-hack gate** requires an independent verdict for the exact diff hash.
- **Give-up gate** prevents premature abandonment without attempts and review.
- **Done check** closes a task only after evidence is present.

The Codex harness ports these guardrails where they are generic and practical.
The give-up gate is enforced from explicit outcomes in `attempts.md`: two
consecutive failures first require a consulting checkpoint, and abandonment
also requires the configured minimum number of failed approaches.

## What Is Domain-Specific

The following are tightly coupled to the FlagGems/Ascend environment:

- `run-full-suite.sh`, `classify-failures.py`, and Excel summaries.
- Remote deployment slots like `dt_debug_ws1`.
- `build-ascend-npu-ir.sh`, `deploy-binary.sh`, and bitcode layout.
- DTS browser automation and Huawei credential instructions.
- Ascend-specific skills such as IR extraction and Hivmc build recipes.

Because this Codex harness is now explicitly Ascend-focused, the operational
instruction files and main build/deploy/test scripts are copied over. The
credential-bearing login file is local-only and ignored by git.

## Notable Implementation Details

- `config.local.yaml` overrides `config.yaml`, allowing one-off hot tasks
  without editing shared config.
- `state/current-task` is a legacy singleton, while `state/sessions/<pid>/`
  supports parallel sessions.
- Task folders include `REPRODUCE.md`, `LOG.md`, `INTERVENTIONS.md`,
  `REFLECTION.md`, `attempts.md`, and optional issue directories.
- Hooks communicate by reading lifecycle JSON from stdin and exiting nonzero
  to block risky calls.
- Review logs are append-only and keyed by a stable hash (`diff_sha`) so a
  verdict cannot silently apply to a changed diff.

## Codex Translation

The Codex harness maps:

| Claude harness | Codex harness |
|---|---|
| `CLAUDE.md` | `AGENTS.md` |
| `.claude/settings.json` | `.codex/config.toml` |
| `.claude/hooks/*.sh` | `.codex/hooks/*.py` |
| `.claude/agents/*.md` | `skills/*.md` |
| FlagGems build/deploy scripts | copied to `scripts/` and wired through Ascend config |
| DTS/remote state | generic issue/task state |

The result is intentionally smaller but preserves the core control loop.
