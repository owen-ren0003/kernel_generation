#!/usr/bin/env python3
"""Reject branch names that disclose or imply AI assistance by default."""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[1]
AI_COMPONENTS = {
    "ai",
    "aider",
    "anthropic",
    "assistant",
    "bot",
    "chatgpt",
    "claude",
    "codeium",
    "codex",
    "copilot",
    "devin",
    "gemini",
    "gpt",
    "llm",
    "openai",
    "windsurf",
}
DISTINCTIVE_SUBSTRINGS = (
    "anthropic",
    "chatgpt",
    "codeium",
    "codex",
    "copilot",
    "openai",
)


def normalize(name: str) -> str:
    name = name.strip().lstrip("+")
    if name.startswith("refs/heads/"):
        return name.removeprefix("refs/heads/")
    return name


def ai_indicator(name: str) -> str | None:
    branch = normalize(name).lower()
    for marker in DISTINCTIVE_SUBSTRINGS:
        if marker in branch:
            return marker

    components = [part for part in re.split(r"[/._+~=\-]+", branch) if part]
    for component in components:
        if component in AI_COMPONENTS:
            return component
        if re.fullmatch(
            r"(?:codex|chatgpt|gpt|claude|gemini|copilot)[0-9][a-z0-9]*",
            component,
        ):
            return component
    return None


def current_task_dir() -> Path | None:
    task = os.environ.get("CODEX_TASK_ID", "").strip()
    if not task:
        current = ROOT / "state" / "current-task"
        if current.exists():
            task = current.read_text().strip()
    if not task:
        return None
    path = Path(task)
    return path if path.is_absolute() else ROOT / "state" / "tasks" / task


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        data = yaml.safe_load(path.read_text()) or {}
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}


def explicitly_authorized(branch: str) -> bool:
    task_dir = current_task_dir()
    if not task_dir or not task_dir.exists():
        return False
    entries = load_yaml(task_dir / "meta.yaml").get("ai_branch_name_exceptions") or []
    if not isinstance(entries, list):
        return False
    for entry in entries:
        if not isinstance(entry, dict):
            continue
        allowed = entry.get("branch")
        authorization = entry.get("user_authorization")
        if (
            isinstance(allowed, str)
            and normalize(allowed) == branch
            and isinstance(authorization, str)
            and authorization.strip()
        ):
            return True
    return False


def valid_git_branch(branch: str) -> bool:
    result = subprocess.run(
        ["git", "check-ref-format", "--branch", branch],
        text=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] in {"-h", "--help"}:
        print(f"Usage: {Path(sys.argv[0]).name} <branch>", file=sys.stderr)
        return 0 if len(sys.argv) == 2 else 2

    branch = normalize(sys.argv[1])
    if not valid_git_branch(branch):
        print(f"[branch-name] BLOCKED: invalid Git branch name: {branch}", file=sys.stderr)
        return 2

    marker = ai_indicator(branch)
    if not marker:
        return 0
    if explicitly_authorized(branch):
        print(f"[branch-name] allowed by explicit user authorization: {branch}", file=sys.stderr)
        return 0

    print(
        "[branch-name] BLOCKED: branch names must be neutral and must not imply AI assistance.\n"
        f"  branch: {branch}\n"
        f"  indicator: {marker}\n"
        "Choose a work-descriptive name. The only exception is explicit user authorization "
        "for this exact name, recorded in the active task's meta.yaml under "
        "ai_branch_name_exceptions with branch and user_authorization fields.",
        file=sys.stderr,
    )
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
