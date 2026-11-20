# Harness Structure and Consulting Flow

The harness now has six cooperating layers:

| Layer | Paths | Responsibility |
|---|---|---|
| Governance | `AGENTS.md`, `skills/` | investigation, fixing, review, and safety rules |
| Durable state | `state/tasks/<task_id>/` | reproducer, metadata, log, attempts, verdicts, critique, evidence |
| Automation | `scripts/` | state transitions, build, deploy, test, and checks |
| Enforcement | `.codex/hooks/` | scope guard, prior-task firewall, commit gates, log reminders |
| Ascend operations | `instructions/` | environment-specific build/deploy/test and IR procedures |
| Consulting | `consulting/` | reusable A5 architecture and compiler-setting interpretation |

## Control and evidence flow

```text
user request
    ↓
bind/create task ───────────────→ state/tasks/<task_id>/
    ↓                                  │
consulting/                            │ durable facts, logs, evidence
├── hardware/                          │
└── compiler-settings/                 │
    ↓                                  ▼
choose reproducer and evidence ─→ scripts/ + instructions/
    ↓                                  │
workspace fix ← scope guard/hooks ─────┘
    ↓
build → deploy → correctness → performance/regression
    ↓
critique + exact-diff reward-hack review
    ↓
done-check
```

The consulting documents' technical claims are advisory; using them at a
triggered stuck checkpoint is mandatory. Scripts own state transitions, task
artifacts own facts, and generated IR and test results decide whether a claim
is true.

## Recovery after two failed approaches

```text
attempt N: failed
       ↓
attempt N+1: failed
       ↓
ordinary tool use pauses
       ↓
STUCK-ROUTER → matching guide → CONSULTATION.md → different experiment
       ↓
failure streak resets; investigation resumes
```

The hook counts explicit approach outcomes in `attempts.md`, not individual
command exit codes. This keeps expected failures during reproduction or a
multi-command experiment from triggering the checkpoint accidentally. A
checkpoint records what was consulted and what will change next; it does not
replace runtime or IR evidence.

## Where the new references enter the workflow

### Before reproduction

- use the hardware docs to name the expected engine, local memory, transfer
  path, and synchronization boundary;
- use the setting index to identify the actual control and interactions;
- choose a fresh cache/dump location and capture build identity.

### During investigation

- classify setting evidence as requested, pass-invoked, IR-transformed, or
  runtime-observed;
- use the memory/data-path guide to distinguish cache effects from explicit
  movement;
- use the synchronization guide to build producer/consumer and wait-for
  graphs.

### During verification

- prove correctness before performance;
- preserve the exact generated command, transformed IR marker, and runtime
  observation in the task record;
- run the configured regression and commit gates.

## Representative work handled by the harness

The durable task inventory shows repeated use for:

- AscendNPU-IR compilation, verification, pointer/layout, and pass-pipeline
  failures;
- preload, CV pipeline, AIC/AIV synchronization, event-slot, and deadlock
  investigations;
- FlagGems correctness and high-priority performance work;
- batch-invariance, MXFP8/low-precision, tiling, and A5 architecture analysis;
- remote build/deploy/test and PR validation across controlled environments.

The recurring accomplishment is the closed loop—not merely producing a patch:

```text
reproduce → root-cause → narrow fix → remote evidence → regression → review
```

## Boundary

The consulting library does not make every wiki default current, and the
harness does not treat a passing test as proof of semantic success. Each task
must still identify its exact build, failure signature, success criterion, and
strongest available evidence.
