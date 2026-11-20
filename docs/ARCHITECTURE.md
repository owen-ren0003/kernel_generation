# Architecture

The harness has six layers:

1. **Instructions**: `AGENTS.md` and `skills/*.md` define how Codex should
   approach investigation, fixing, verification, and review.
2. **State**: `state/tasks/<task_id>/` holds task metadata, reproducer,
   logs, attempts, critique, review verdicts, and done sentinels.
3. **Scripts**: `scripts/` owns state transitions and checks. Codex should
   call scripts rather than hand-editing JSON/YAML when possible.
4. **Hooks**: `.codex/hooks/` enforce the rules that are easy to forget:
   workspace scope, prior-task contamination, commit gates, and log nudges.
5. **Ascend instructions**: `instructions/` contains build, deploy, test,
   IR-debugging, clone, and permanent environment procedures copied from the
   original Ascend harness. `instructions/login-credentials.txt` is local-only
   and ignored by git.
6. **Consulting**: `consulting/` contains source-traceable Ascend A5 hardware
   references and setting-specific AscendNPU-IR feature-observation playbooks.
   These explain how to reason about a task and how to distinguish a requested
   option from pass execution, transformed IR, and runtime evidence.

The layers have different authority. Consulting is advisory; scripts own state
transitions, task artifacts hold durable facts, hooks enforce policy, and
generated IR/tests determine whether a technical claim is true.

## State Machine

```text
created
  -> assigned
  -> investigating
  -> root-caused
  -> fixing
  -> verified
  -> committed
  -> done
```

For suite-style tasks, `active-fixes.json` tracks multiple workspaces:

```json
{
  "ws1": {
    "available": false,
    "issue_id": "bug-123",
    "status": "assigned",
    "assigned_at": "2026-06-04T10:00:00"
  }
}
```

For single-bug tasks, this same file is still useful because it names the
workspace Codex is allowed to modify.

## Codex Hook Behavior

The pre-tool hook receives Codex lifecycle JSON on stdin. It recursively scans
the tool input text and applies these checks:

- **Workspace guard**: if `meta.yaml.in_scope_paths` mentions `ws1`, `ws2`,
  etc., references to other `wsN` paths are blocked.
- **Prior-task firewall**: while the task is open, reads of sibling tasks with
  the same `(mode, id)` are blocked unless the path is explicitly exempt or
  a grant exists under `state/grants/<current>/<sibling>`.
- **Commit gate**: shell commands that perform `git commit` outside the
  harness repo must pass `check-critique.sh` and
  `check-reward-hack-review.sh`.
- **Stuck checkpoint**: two consecutive failed outcomes in `attempts.md`
  block ordinary tool use. Consulting reads and task-record updates remain
  available until a valid `CONSULTATION.md` checkpoint resets the streak.
- **Give-up gate**: `NEEDS-MORE-DATA.md` and abandonment operations are
  blocked until no consulting checkpoint is pending and the task has the
  configured minimum number of failed approaches.

The post-tool hook increments a per-task log-gap counter. It warns after too
many tool calls without a `LOG.md` write. It also reports a required consulting
checkpoint immediately after the second failed approach is recorded.

## Differences From The Claude Harness

- Claude subagents are translated to Codex skills. Codex does not need a
  `.claude/agents` directory for this harness.
- Claude hook settings are translated to `.codex/config.toml`.
- Remote NPU build/deploy scripts are installed under `scripts/` and use the
  original `test_env`/`docker` config keys.
- The FlagGems classifier script is copied, while issue filing remains usable
  for direct DTS/manual bug reports.
- The reward-hack reviewer is not a separate built-in subagent here; it is a
  skill prompt plus a machine-checked verdict log keyed by diff hash.
