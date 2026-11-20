# Ascend Consulting Library

This folder is the harness's reusable consulting layer. It turns two local
reference sources into short, task-oriented documents that can be consulted
before reproduction, root-cause analysis, compiler-option experiments, and
remote verification.

The library is intentionally separate from `instructions/`:

- `instructions/` says **how to operate the harness and its environments**;
- `consulting/` says **how to reason about A5 hardware and how to prove that
  AscendNPU-IR features actually took effect**.

## Contents

```text
consulting/
├── README.md
├── SOURCE-NOTES.md
├── STUCK-ROUTER.md
├── hardware/
│   ├── README.md
│   ├── 01-system-and-compute.md
│   ├── 02-memory-and-data-movement.md
│   ├── 03-execution-and-synchronization.md
│   └── 04-performance-debugging-checklist.md
├── compiler-settings/
│   ├── README.md
│   ├── 00-activation-evidence-model.md
│   ├── 01-costmodel-and-vf-fusion.md
│   ├── 02-autoblockify.md
│   ├── 03-simt-template.md
│   ├── 04-ssbuffer.md
│   ├── 05-cv-pipeline.md
│   ├── 06-cv-1-to-2.md
│   ├── 07-multibuffer.md
│   └── 08-preload.md
├── harness/
│   └── structure-and-consulting-flow.md
├── materials/
│   └── README.md
└── presentation/
    ├── README.md
    ├── build_slide.py
    └── harness-overview-half-slide.png
```

The editable PPTX was delivered to
`/path/to/presentation/harness-overview-half-slide.pptx`.
The harness retains its rendered preview and deterministic generator.

## Fast routing

After two consecutive approaches fail, stop normal investigation and use
[`STUCK-ROUTER.md`](STUCK-ROUTER.md). Record the selected route, matching
guides, useful guidance, and a genuinely different next experiment in the
active task's `CONSULTATION.md`.

| Question | Consult |
|---|---|
| Which engine or local memory owns this operation? | [`hardware/01-system-and-compute.md`](hardware/01-system-and-compute.md) |
| Is this a cache, scratchpad, transfer engine, or data path? | [`hardware/02-memory-and-data-movement.md`](hardware/02-memory-and-data-movement.md) |
| Which event, flag, or buffer-ownership edge is required? | [`hardware/03-execution-and-synchronization.md`](hardware/03-execution-and-synchronization.md) |
| What should I profile first? | [`hardware/04-performance-debugging-checklist.md`](hardware/04-performance-debugging-checklist.md) |
| How strong is my evidence that a feature is active? | [`compiler-settings/00-activation-evidence-model.md`](compiler-settings/00-activation-evidence-model.md) |
| Which setting controls a particular feature? | [`compiler-settings/README.md`](compiler-settings/README.md) |
| Where does consulting fit into the task state machine? | [`harness/structure-and-consulting-flow.md`](harness/structure-and-consulting-flow.md) |
| Where are the user-provided kernel source/test repositories? | [`materials/README.md`](materials/README.md) |

## The non-negotiable evidence rule

For compiler settings, do not equate these claims:

```text
option requested  ≠  pass ran  ≠  IR changed  ≠  runtime effect observed
```

Every setting guide identifies the strongest positive evidence available in
the source snapshot and calls out weaker indicators and missing evidence.

## Source status

These documents are consulting summaries, not new primary specifications.
Defaults and implementation details can drift between Triton Ascend and CANN
builds. Record the exact wheel/compiler build, generated command, metadata,
and IR artifact used for each investigation. See [`SOURCE-NOTES.md`](SOURCE-NOTES.md).
