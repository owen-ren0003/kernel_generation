# Skill: Classify FlagGems Test Failures

How the harness turns a raw pytest log into the canonical Excel workbook.

The classifier is **discovery-driven** — it does NOT assume any specific
failure categories. Categories are derived from the actual log via
signature clustering, then named by the investigator agent (or the user)
in a side-car YAML file.

## Why Discovery, Not a Fixed Taxonomy

The failure landscape changes over time. As compiler fixes land upstream,
old categories shrink to zero and new ones appear. A hardcoded category
list (e.g. `SEGV`, `KWARG`, `ACCURACY`) gets stale fast and forces the
classifier to bucket new failures into the wrong bin. Discovery-based
clustering picks up new failure modes automatically.

## How Signatures Work

For each pytest failure block, `classify-failures.py` computes a stable
signature:

1. **Normalise** the error text — strip absolute paths, line numbers, hex
   addresses, large integers, test parameter blocks, Triton cache hashes,
   PIDs, tensor element values, and floating-point numbers.
2. **Hash** the first 800 chars of the normalised result with SHA1.
3. **Truncate** to 8 hex chars → the signature.

Two failures with identical signatures share a root cause. Re-running on
the same log produces identical signatures (deterministic).

## Naming Categories — `state/categories.yaml`

The classifier writes/reads `state/categories.yaml`:

```yaml
signatures:
  a1b2c3d4:
    code: SEGV-cmpf
    description: Segfault in arith.cmpf lowering
    fixable_in_compiler: yes
    notes: See state/tasks/<task>/issues/SEGV-cmpf/VERDICT.md
    sample_test: tests/test_x.py::test_y[...]
  e5f6a7b8:
    code: ""           # not yet named -> classifier uses SIG-e5f6a7b8
    description: ""
    fixable_in_compiler: ""
    notes: ""
    sample_test: tests/test_z.py::test_w[...]
```

When the classifier runs:

- New signatures get a stub entry with empty `code` and `description`.
  They appear in the Excel as `SIG-<sig>`.
- Existing signatures keep their assigned `code`. The Excel shows that
  code instead of `SIG-<sig>`.
- The `sample_test` field is refreshed every run so it points to a test
  that's currently failing (not one that was fixed in the meantime).

To **name** a new category, edit `state/categories.yaml` and fill in the
`code`, `description`, and `fixable_in_compiler` fields. Re-running
`classify-failures.py` picks up the change.

## Merging Two Signatures Into One Category

Sometimes two superficially different errors share a root cause (e.g. a
trailing newline difference makes them hash differently). To merge:

```yaml
signatures:
  a1b2c3d4:
    code: SEGV-cmpf      # same
    ...
  fffeeedd:
    code: SEGV-cmpf      # same
    ...
```

Both signatures will roll up under `SEGV-cmpf` in the Excel.

## Output Excel Schema

### Sheet 1: Failure Summary

One row per category code (after merging signatures).

| Column | Source |
|---|---|
| `Code` | from `categories.yaml::code`, fallback `SIG-<sig>` |
| `Count` | number of FAILED tests with this code |
| `Description` | from `categories.yaml::description` |
| `Fixable In AscendNPU-IR` | `yes`, `no - <reason>`, or empty (not yet triaged) |
| `Notes` | from `categories.yaml::notes` (link to VERDICT.md, etc.) |
| `Signatures` | comma-separated list of signatures rolled up into this code |
| `Sample Test` | one test name to reproduce with |

### Sheet 2: ACCURACY Breakdown

Per-operator detail. Only meaningful once at least one signature has been
named with a code containing `ACCURACY`.

| Column | Meaning |
|---|---|
| `Operator` | from the test name (e.g. `upsample_nearest2d`) |
| `Total Fail` | how many failures of this op (any code) |
| `Codes` | comma-separated codes hit by this op |
| `Sample Test` | one test name to reproduce with |

### Sheet 3: All Test Results

Every test the runner reported.

| Column | Meaning |
|---|---|
| `Test Name` | full pytest path |
| `Status` | `PASSED`, `FAILED`, `SKIPPED`, `ERROR` |
| `Failure Code` | code from Sheet 1; blank for non-failures |
| `Signature` | the raw 8-char signature |

## Recommended Workflow for the Investigator Agent

When the agent picks up a category to investigate:

1. Read the Excel `Failure Summary` row. Note the code (e.g. `SIG-a1b2c3d4`)
   and sample test.
2. Look up the entry in `state/categories.yaml`. If `code` is empty, this
   is a fresh signature — give it a meaningful name based on the error
   pattern (`SEGV-cmpf`, `ACCURACY-quantile`, `COMPILE-i1-ub`, etc.).
3. Investigate per `skills/extract-ir.md`.
4. After writing `VERDICT.md`, update the YAML entry's `description`,
   `fixable_in_compiler`, and `notes`.
5. Re-run `classify-failures.py` to refresh the Excel with the new name.

## When the Heuristic Misclusters

The signature normaliser is generic. It may collapse two distinct bugs
into one signature, or split one bug across two signatures. Symptoms:

- **One category should be two**: edit `categories.yaml` and give the two
  signatures different `code` values.
- **Two categories should be one**: edit `categories.yaml` and give the
  two signatures the same `code` value.
- **A signature seems too generic**: add a more specific normaliser to
  `NORMALIZERS` in `classify-failures.py` and re-run.

## Verification

After classification, the script prints a summary. The runner agent
checks:

- `Total tests` matches pytest's reported count.
- `Failed == Classified` (every failure was bucketed).
- `Signatures seen` equals the number of distinct error patterns.
- `Top codes` shows the largest categories — the agent investigates these
  first.

If `Failed != Classified`, some pytest failure block didn't match the
parser regex. Add a sample to `state/tasks/<task>/issues/UNPARSED/` and update
the regex in `parse_log()`.
