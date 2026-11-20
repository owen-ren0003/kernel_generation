#!/usr/bin/env python3
"""classify-failures.py — Convert a pytest log into the harness Excel format.

Discovery-driven classification. Failures are grouped by a stable signature
derived from the normalized error block (paths, line numbers, addresses,
hex values, test params, and run-specific numbers stripped). Two failures
with the same signature share a category.

Categories are not hardcoded. They are LEARNED from the log. A
human-readable name for each signature is read from (and written to) the
side-car file `state/categories.yaml`. The first time a signature is seen,
it is given the auto code `SIG-<hash>`. The investigator agent renames it
later by editing categories.yaml.

This way:
  * Re-running on the same log produces identical signatures (deterministic).
  * Adding new failures introduces new SIG-<hash> entries that the agent
    can review and name.
  * Two signatures that are actually the same root cause can be merged by
    editing categories.yaml (give them the same `code` field).

Usage:
  python3 scripts/classify-failures.py \
    --log state/full-run-2026-04-28-1015.log \
    --xlsx .local-artifacts/<task-id>/failures-latest.xlsx \
    [--categories state/categories.yaml]

Output:
  Sheet 1: Failure Summary       (one row per category code)
  Sheet 2: ACCURACY Breakdown    (per-operator detail; only populated for
                                  failures whose code is named "ACCURACY")
  Sheet 3: All Test Results      (one row per test)
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import re
import sys
from pathlib import Path

try:
    import openpyxl
except ImportError:
    sys.exit("ERROR: openpyxl not installed. Run: pip install --user openpyxl")

try:
    import yaml
except ImportError:
    sys.exit("ERROR: PyYAML not installed. Run: pip install --user pyyaml")


# Normalisation pipeline. Each function takes a string and returns a string.
# Order matters — earlier substitutions are seen by later ones.
NORMALIZERS: list[tuple[re.Pattern, str]] = [
    # Strip absolute paths down to the filename.
    (re.compile(r"/[^\s:]+/([^\s:/]+\.(py|cpp|h|hpp|mlir|ll|o))"), r"\1"),
    # Hex addresses.
    (re.compile(r"0x[0-9a-fA-F]+"), "<ADDR>"),
    # Long integers (e.g. test params, sizes).
    (re.compile(r"\b\d{3,}\b"), "<N>"),
    # Line:col like "foo.cpp:123:45".
    (re.compile(r":\d+:\d+"), ":<LOC>"),
    # Test parameter blocks like "[dtype1-shape0-True]".
    (re.compile(r"\[[^\[\]\n]+\]"), "[<PARAMS>]"),
    # Triton cache hashes.
    (re.compile(r"\.triton/cache/[a-zA-Z0-9_-]+/"), ".triton/cache/<HASH>/"),
    # Process / pid / job ids.
    (re.compile(r"PID:\d+|pid \d+"), "PID:<N>"),
    # Specific tensor element values in error messages.
    (re.compile(r"tensor\([^)]+\)", re.DOTALL), "tensor(<VALUES>)"),
    # Float values.
    (re.compile(r"-?\d+\.\d+(e[+-]?\d+)?"), "<F>"),
]

# How many leading characters of the normalised error block to hash. Beyond
# this point the trace usually diverges into call-site noise.
SIGNATURE_PREFIX_LEN = 800


def normalize_error(text: str) -> str:
    """Reduce a pytest error block to a stable, comparable form."""
    out = text
    for pattern, replacement in NORMALIZERS:
        out = pattern.sub(replacement, out)
    return out


def signature(text: str) -> str:
    """Stable 8-char SHA hash of the first SIGNATURE_PREFIX_LEN normalised chars."""
    norm = normalize_error(text)
    return hashlib.sha1(norm[:SIGNATURE_PREFIX_LEN].encode(errors="replace")).hexdigest()[:8]


def parse_log(log_path: Path) -> tuple[list[tuple[str, str]], list[tuple[str, str]]]:
    """Return (all_results, failed_blocks).

    all_results = [(test_name, status), ...] — every test the runner reported.
    failed_blocks = [(test_name, error_block_text), ...] — pytest "____ test ____" blocks.
    """
    text = log_path.read_text(errors="replace")

    # Pytest verbose format: "tests/x.py::test_y[params] PASSED" etc.
    line_re = re.compile(
        r"^(?P<test>tests/[^\s]+::[^\s]+) (?P<status>PASSED|FAILED|SKIPPED|ERROR)",
        re.MULTILINE,
    )
    all_results: list[tuple[str, str]] = []
    seen: set[str] = set()
    for m in line_re.finditer(text):
        if m.group("test") in seen:
            continue
        seen.add(m.group("test"))
        all_results.append((m.group("test"), m.group("status")))

    # Pytest failure blocks. Two formats:
    #   --tb=long: "_______ tests/x.py::test_name[params] _______"
    #   --tb=short: "_______ test_name[params] _______"
    # Use the short form as the canonical match, then resolve back to full
    # tests/<file>::test_name via all_results.
    short_to_full: dict[str, str] = {}
    for test, _status in all_results:
        # tests/x.py::test_name[params] -> test_name[params]
        short = test.split("::", 1)[1] if "::" in test else test
        short_to_full[short] = test
    block_re = re.compile(
        r"^_+ (?P<test>(?:tests/[^\s]+::)?[^\s_][^\s]*) _+\n"
        r"(?P<body>.*?)(?=^_+ (?:tests/[^\s]+::)?[^\s_][^\s]* _+\n|^=+ )",
        re.MULTILINE | re.DOTALL,
    )
    failed_blocks: list[tuple[str, str]] = []
    for m in block_re.finditer(text):
        name = m.group("test")
        full = name if "::" in name else short_to_full.get(name, name)
        failed_blocks.append((full, m.group("body")))
    return all_results, failed_blocks


def load_categories(path: Path) -> dict:
    """Read state/categories.yaml. Schema:

        signatures:
          a1b2c3d4:
            code: SEGV-cmpf
            description: Segfault in arith.cmpf lowering
            fixable_in_compiler: yes
            notes: ...
            sample_test: tests/foo.py::test_bar[params]

    Returns the parsed dict (with `signatures` always present).
    """
    if not path.exists():
        return {"signatures": {}}
    data = yaml.safe_load(path.read_text()) or {}
    data.setdefault("signatures", {})
    return data


def save_categories(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(yaml.safe_dump(data, sort_keys=True, default_flow_style=False))


def code_for(sig: str, cats: dict) -> str:
    """Return the canonical code for this signature.

    Falls back to SIG-<sig> when no human-assigned code exists.
    """
    entry = cats["signatures"].get(sig)
    if entry and entry.get("code"):
        return entry["code"]
    return f"SIG-{sig}"


def description_for(sig: str, cats: dict) -> str:
    entry = cats["signatures"].get(sig, {})
    return entry.get("description", "(unnamed; investigator should classify)")


def fixable_for(sig: str, cats: dict) -> str:
    entry = cats["signatures"].get(sig, {})
    return entry.get("fixable_in_compiler", "")


def notes_for(sig: str, cats: dict) -> str:
    entry = cats["signatures"].get(sig, {})
    return entry.get("notes", "")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--log", required=True, help="pytest log to parse")
    ap.add_argument("--xlsx", required=True, help="output Excel path")
    ap.add_argument(
        "--categories",
        default="state/categories.yaml",
        help="side-car file mapping signature -> code/description (default: state/categories.yaml)",
    )
    args = ap.parse_args()

    log_path = Path(args.log)
    if not log_path.exists():
        sys.exit(f"log not found: {log_path}")

    cats_path = Path(args.categories)
    cats = load_categories(cats_path)

    all_results, failed_blocks = parse_log(log_path)

    # Compute per-test signatures.
    test_to_sig: dict[str, str] = {}
    sig_to_sample: dict[str, str] = {}     # sig -> one example test name
    sig_to_block: dict[str, str] = {}      # sig -> normalised error block
    for test, body in failed_blocks:
        sig = signature(body)
        test_to_sig[test] = sig
        sig_to_sample.setdefault(sig, test)
        sig_to_block.setdefault(sig, normalize_error(body))

    # Update the side-car for any new signatures we just discovered.
    new_sigs = []
    for sig in sig_to_sample:
        if sig not in cats["signatures"]:
            cats["signatures"][sig] = {
                "code": "",   # blank -> auto code SIG-<sig>
                "description": "",
                "fixable_in_compiler": "",
                "notes": "",
                "sample_test": sig_to_sample[sig],
            }
            new_sigs.append(sig)
        else:
            # Refresh the sample test in case the previous one stopped failing.
            cats["signatures"][sig]["sample_test"] = sig_to_sample[sig]
    save_categories(cats_path, cats)

    # Aggregate by canonical code (multiple signatures can map to one code).
    counts: collections.Counter[str] = collections.Counter()
    code_to_sigs: dict[str, list[str]] = collections.defaultdict(list)
    for test, sig in test_to_sig.items():
        code = code_for(sig, cats)
        counts[code] += 1
        if sig not in code_to_sigs[code]:
            code_to_sigs[code].append(sig)

    # ---------- Build the workbook. ----------
    wb = openpyxl.Workbook()

    s1 = wb.active
    s1.title = "Failure Summary"
    s1.append(["Code", "Count", "Description", "Fixable In AscendNPU-IR",
               "Notes", "Signatures", "Sample Test"])
    for code in sorted(counts, key=lambda c: -counts[c]):
        sigs = code_to_sigs[code]
        # Pick description / fixable / notes from any signature in this code; if
        # multiple disagree, prefer non-empty values.
        desc = next((description_for(s, cats) for s in sigs if description_for(s, cats)), "")
        fixable = next((fixable_for(s, cats) for s in sigs if fixable_for(s, cats)), "")
        notes = next((notes_for(s, cats) for s in sigs if notes_for(s, cats)), "")
        s1.append([
            code,
            counts[code],
            desc,
            fixable,
            notes,
            ", ".join(sigs),
            sig_to_sample[sigs[0]],
        ])

    s2 = wb.create_sheet("ACCURACY Breakdown")
    s2.append([
        "Operator", "Total Fail", "Codes", "Sample Test",
    ])
    op_re = re.compile(r"::test_accuracy_(?P<op>[a-zA-Z0-9_]+)")
    op_data: dict[str, dict] = {}
    for test, sig in test_to_sig.items():
        m = op_re.search(test)
        if not m:
            continue
        op = m.group("op")
        op_data.setdefault(op, {"total": 0, "codes": set(), "sample": test})
        op_data[op]["total"] += 1
        op_data[op]["codes"].add(code_for(sig, cats))
    for op, d in sorted(op_data.items(), key=lambda kv: -kv[1]["total"]):
        s2.append([
            op,
            d["total"],
            ", ".join(sorted(d["codes"])),
            d["sample"],
        ])

    s3 = wb.create_sheet("All Test Results")
    s3.append(["Test Name", "Status", "Failure Code", "Signature"])
    for test, status in all_results:
        sig = test_to_sig.get(test, "")
        s3.append([
            test,
            status,
            code_for(sig, cats) if sig else "",
            sig,
        ])

    out_path = Path(args.xlsx)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    wb.save(out_path)

    # ---------- Sanity report. ----------
    n_total = len(all_results)
    n_failed = sum(1 for _, s in all_results if s in ("FAILED", "ERROR"))
    n_classified = len(test_to_sig)

    print(f"Wrote: {out_path}")
    print(f"Categories file: {cats_path}")
    print(f"Total tests:     {n_total}")
    print(f"Failed:          {n_failed}")
    print(f"Classified:      {n_classified}")
    print(f"Signatures seen: {len(sig_to_sample)} ({len(new_sigs)} new this run)")
    print(f"Codes:           {len(counts)}")
    print(f"Top codes:")
    for code, count in counts.most_common(10):
        sigs = code_to_sigs[code]
        sample = sig_to_sample[sigs[0]]
        print(f"  {count:5d}  {code:14s}  e.g. {sample}")

    if new_sigs:
        print()
        print(f"New signatures discovered this run ({len(new_sigs)}):")
        for sig in new_sigs:
            print(f"  {sig}  sample: {sig_to_sample[sig]}")
        print()
        print(f"Edit {cats_path} to assign each a 'code' and 'description'.")

    if n_failed != n_classified:
        print(
            f"WARNING: {n_failed - n_classified} failed test(s) had no parseable error block.",
            file=sys.stderr,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
