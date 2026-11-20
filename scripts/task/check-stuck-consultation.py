#!/usr/bin/env python3
"""Validate the two-failure consulting checkpoint for an active task."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]
ATTEMPT_HEADER = re.compile(r"^##\s+Attempt\s+(\d+)\s*-\s*(.*?)\s*$", re.MULTILINE)
CHECKPOINT_HEADER = re.compile(r"^##\s+Checkpoint\s+(\d+)\s*$", re.MULTILINE)
GUIDE_RE = re.compile(r"consulting/[A-Za-z0-9_.\-/]+\.md")
VALID_OUTCOMES = {"in-progress", "failed", "succeeded"}
VALID_OBSTACLES = {
    "synchronization",
    "memory/data movement",
    "compiler setting/pass",
    "performance",
    "correctness/numerics",
    "build/runtime/environment",
    "unknown",
}


@dataclass(frozen=True)
class Attempt:
    number: int
    name: str
    outcome: str


@dataclass(frozen=True)
class Checkpoint:
    number: int
    covers: int
    obstacle: str
    guides: tuple[str, ...]


def task_dir(raw: str | None) -> Path:
    if raw:
        path = Path(raw)
        return path if path.is_absolute() else ROOT / "state" / "tasks" / path
    current = ROOT / "state" / "current-task"
    if not current.exists() or not current.read_text().strip():
        raise ValueError("no task supplied and state/current-task is empty")
    return ROOT / "state" / "tasks" / current.read_text().strip()


def sections(text: str, header: re.Pattern[str]) -> list[tuple[re.Match[str], str]]:
    matches = list(header.finditer(text))
    return [
        (match, text[match.end() : matches[index + 1].start() if index + 1 < len(matches) else len(text)])
        for index, match in enumerate(matches)
    ]


def field(body: str, name: str) -> str:
    match = re.search(rf"^\*\*{re.escape(name)}:\*\*\s*(.*?)\s*$", body, re.MULTILINE | re.IGNORECASE)
    return match.group(1).strip() if match else ""


def placeholder(value: str) -> bool:
    lowered = value.strip().lower()
    return not lowered or (lowered.startswith("<") and lowered.endswith(">")) or lowered in {"tbd", "todo", "fill in"}


def load_attempts(path: Path) -> tuple[list[Attempt], list[str]]:
    if not path.exists():
        return [], [f"missing {path.name}"]
    attempts: list[Attempt] = []
    errors: list[str] = []
    for match, body in sections(path.read_text(), ATTEMPT_HEADER):
        number = int(match.group(1))
        name = match.group(2).strip()
        outcome_raw = field(body, "Outcome")

        # Tasks created before this feature have no Outcome field. Preserve
        # compatibility: only explicitly outcome-tagged attempts participate.
        if not outcome_raw:
            continue
        if placeholder(outcome_raw):
            other_values = [field(body, label) for label in ("What was tried", "Why it did not work", "What was learned", "Next implication")]
            if any(not placeholder(value) for value in other_values):
                errors.append(f"attempt {number} has content but no explicit Outcome")
            continue

        outcome = outcome_raw.lower()
        if outcome not in VALID_OUTCOMES:
            errors.append(
                f"attempt {number} has invalid Outcome {outcome_raw!r}; expected in-progress, failed, or succeeded"
            )
            continue
        if placeholder(name):
            errors.append(f"attempt {number} needs an approach name")
            continue
        attempts.append(Attempt(number, name, outcome))

    numbers = [attempt.number for attempt in attempts]
    if len(numbers) != len(set(numbers)):
        errors.append("attempt numbers must be unique")
    if numbers != sorted(numbers):
        errors.append("attempt numbers must increase in file order")
    return attempts, errors


def load_checkpoints(path: Path, attempts: list[Attempt], threshold: int) -> tuple[list[Checkpoint], list[str]]:
    if not path.exists():
        return [], []
    checkpoints: list[Checkpoint] = []
    errors: list[str] = []
    attempts_by_number = {attempt.number: attempt for attempt in attempts}

    for match, body in sections(path.read_text(), CHECKPOINT_HEADER):
        number = int(match.group(1))
        covers_raw = field(body, "Covers through attempt")
        obstacle = field(body, "Obstacle class").lower()
        guides_raw = field(body, "Consulted guides")
        guidance = field(body, "Relevant guidance")
        experiment = field(body, "Next experiment")
        values = (covers_raw, obstacle, guides_raw, guidance, experiment)

        if all(placeholder(value) for value in values):
            continue
        missing = [
            label
            for label, value in zip(
                ("Covers through attempt", "Obstacle class", "Consulted guides", "Relevant guidance", "Next experiment"),
                values,
            )
            if placeholder(value)
        ]
        if missing:
            errors.append(f"checkpoint {number} has incomplete fields: {', '.join(missing)}")
            continue
        try:
            covers = int(covers_raw)
        except ValueError:
            errors.append(f"checkpoint {number} has a non-numeric Covers through attempt")
            continue
        if obstacle not in VALID_OBSTACLES:
            errors.append(f"checkpoint {number} has unknown Obstacle class {obstacle!r}")
            continue

        guides = tuple(dict.fromkeys(GUIDE_RE.findall(guides_raw)))
        if "consulting/STUCK-ROUTER.md" not in guides:
            errors.append(f"checkpoint {number} must record consulting/STUCK-ROUTER.md")
            continue
        matching_guides = [guide for guide in guides if guide != "consulting/STUCK-ROUTER.md"]
        if not matching_guides:
            errors.append(f"checkpoint {number} must record at least one matching guide after the router")
            continue
        missing_guides = [guide for guide in guides if not (ROOT / guide).is_file()]
        if missing_guides:
            errors.append(f"checkpoint {number} names missing guide(s): {', '.join(missing_guides)}")
            continue
        if covers not in attempts_by_number:
            errors.append(f"checkpoint {number} covers unknown attempt {covers}")
            continue
        if attempts_by_number[covers].outcome != "failed":
            errors.append(f"checkpoint {number} must cover an attempt whose Outcome is failed")
            continue
        checkpoints.append(Checkpoint(number, covers, obstacle, guides))

    checkpoint_numbers = [checkpoint.number for checkpoint in checkpoints]
    covered_numbers = [checkpoint.covers for checkpoint in checkpoints]
    if len(checkpoint_numbers) != len(set(checkpoint_numbers)):
        errors.append("checkpoint numbers must be unique")
    if checkpoint_numbers != sorted(checkpoint_numbers):
        errors.append("checkpoint numbers must increase in file order")
    if covered_numbers != sorted(set(covered_numbers)):
        errors.append("each checkpoint must cover a later attempt than the previous checkpoint")

    previous_cover = -1
    for checkpoint in checkpoints:
        streak = failure_streak(attempts, previous_cover, checkpoint.covers)
        if streak < threshold:
            errors.append(
                f"checkpoint {checkpoint.number} covers only {streak} consecutive failure(s); threshold is {threshold}"
            )
        previous_cover = checkpoint.covers
    return checkpoints, errors


def failure_streak(attempts: list[Attempt], after: int, through: int | None = None) -> int:
    streak = 0
    for attempt in attempts:
        if attempt.number <= after or (through is not None and attempt.number > through):
            continue
        if attempt.outcome == "failed":
            streak += 1
        elif attempt.outcome == "succeeded":
            streak = 0
        # An in-progress approach neither adds a failure nor erases the last
        # completed result.
    return streak


def positive_int(meta: dict, name: str, default: int) -> int:
    try:
        value = int(meta.get(name, default))
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{name} must be a positive integer") from exc
    if value < 1:
        raise ValueError(f"{name} must be a positive integer")
    return value


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("task", nargs="?", help="task id or absolute task directory")
    parser.add_argument("--mode", choices=("checkpoint", "abandon", "status"), default="checkpoint")
    args = parser.parse_args()

    try:
        tdir = task_dir(args.task)
        if not tdir.is_dir():
            raise ValueError(f"task directory does not exist: {tdir}")
        meta = yaml.safe_load((tdir / "meta.yaml").read_text()) or {}
        threshold = positive_int(meta, "consultation_failure_threshold", 2)
        minimum = positive_int(meta, "min_attempts_before_give_up", 3)
    except (OSError, ValueError, yaml.YAMLError) as exc:
        print(f"[consultation] ERROR: {exc}", file=sys.stderr)
        return 2

    attempts, errors = load_attempts(tdir / "attempts.md")
    checkpoints, checkpoint_errors = load_checkpoints(tdir / "CONSULTATION.md", attempts, threshold)
    errors.extend(checkpoint_errors)
    if errors:
        for error in errors:
            print(f"[consultation] ERROR: {error}", file=sys.stderr)
        return 2

    last_cover = checkpoints[-1].covers if checkpoints else -1
    streak = failure_streak(attempts, last_cover)
    failures = sum(attempt.outcome == "failed" for attempt in attempts)
    due = streak >= threshold

    if args.mode == "status":
        print(
            f"[consultation] task={tdir.name} consecutive_failures={streak} "
            f"threshold={threshold} failed_attempts={failures} checkpoints={len(checkpoints)}"
        )

    if due:
        print(
            f"[consultation] REQUIRED: {streak} consecutive approaches failed since the last checkpoint "
            f"(threshold {threshold}).\n"
            "Open consulting/STUCK-ROUTER.md, read at least one matching guide, then complete "
            f"{tdir / 'CONSULTATION.md'} before normal debugging continues.",
            file=sys.stderr,
        )
        return 2

    if args.mode == "abandon" and failures < minimum:
        print(
            f"[consultation] BLOCKED: abandonment/NEEDS-MORE-DATA requires at least {minimum} "
            f"failed approaches; only {failures} are recorded.",
            file=sys.stderr,
        )
        return 2

    if args.mode != "status":
        label = "abandonment gate" if args.mode == "abandon" else "checkpoint"
        print(f"[consultation] OK: {label}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
