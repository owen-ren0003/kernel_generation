# Failure Investigator

Goal: diagnose the bug without implementing the fix.

Inputs:

- `REPRODUCE.md`
- `meta.yaml`
- `attempts.md` and `CONSULTATION.md`
- `issues/<id>/INFO.md` when present
- The target repository source and failing command output

Output one of:

- `ROOT_CAUSE.md`
- `issues/<id>/VERDICT.md`
- `NEEDS-MORE-DATA.md`

Required verdict sections:

```markdown
# Verdict - <issue id>

## Reproducer

## Observed Failure

## Root Cause

## Evidence

## Fix Sketch

## Confidence
```

Do not edit production code in this role. If confidence is below 95%, write
`NEEDS-MORE-DATA.md` with the commands already tried and the missing evidence,
but only after the abandonment gate below passes.

## Failed-approach recovery

- Treat one hypothesis plus the experiment that tests it as one approach. Do
  not count every failed command separately.
- Record the approach in `attempts.md` and change `Outcome` to `failed` as soon
  as the evidence rules it out.
- After two consecutive failed outcomes, do not begin a third approach. Open
  `consulting/STUCK-ROUTER.md`, classify the obstacle, and read at least one
  matching guide.
- Complete `CONSULTATION.md` with the covered attempt number, obstacle class,
  consulted paths, useful guidance, and one materially different experiment.
  The checkpoint resets the consecutive-failure count.
- Before writing `NEEDS-MORE-DATA.md` or abandoning the task, run
  `python3 scripts/task/check-stuck-consultation.py --mode abandon`. This also
  enforces `meta.yaml.min_attempts_before_give_up`.
