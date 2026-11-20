#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

import yaml


ROOT = Path(__file__).resolve().parents[2]


def read_event() -> dict[str, Any]:
    raw = sys.stdin.read()
    if not raw.strip():
        return {}
    try:
        return json.loads(raw)
    except Exception:
        return {"_raw": raw}


def current_task() -> str:
    env = os.environ.get("CODEX_TASK_ID", "").strip()
    if env:
        return env
    cur = ROOT / "state" / "current-task"
    if cur.exists():
        return cur.read_text().strip()
    cfg = ROOT / "config.local.yaml"
    if not cfg.exists():
        cfg = ROOT / "config.yaml"
    if cfg.exists():
        try:
            return str((yaml.safe_load(cfg.read_text()) or {}).get("task_id", "")).strip()
        except Exception:
            return ""
    return ""


def task_dir(task: str | None = None) -> Path | None:
    task = task or current_task()
    if not task:
        return None
    path = Path(task)
    if path.is_absolute():
        return path
    return ROOT / "state" / "tasks" / task


def load_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        return {}
    try:
        return yaml.safe_load(path.read_text()) or {}
    except Exception:
        return {}


def event_text(value: Any) -> str:
    chunks: list[str] = []

    def walk(v: Any) -> None:
        if isinstance(v, str):
            chunks.append(v)
        elif isinstance(v, dict):
            for x in v.values():
                walk(x)
        elif isinstance(v, list):
            for x in v:
                walk(x)

    walk(value)
    return "\n".join(chunks)


def tool_name(event: dict[str, Any]) -> str:
    return str(event.get("tool_name") or event.get("tool") or "")


def tool_input(event: dict[str, Any]) -> Any:
    return event.get("tool_input") or event.get("input") or event


def command_from_event(event: dict[str, Any]) -> str:
    ti = tool_input(event)
    if isinstance(ti, dict):
        return str(ti.get("command") or ti.get("cmd") or "")
    return ""


def block(message: str, code: int = 2) -> None:
    print(message.rstrip(), file=sys.stderr)
    raise SystemExit(code)


def warn(message: str) -> None:
    print(message.rstrip(), file=sys.stderr)


def run(args: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=str(cwd or ROOT), text=True, capture_output=True)


def git_commit_target(command: str) -> Path | None:
    if not re.search(r"\bgit\s+(-c\s+\S+\s+|-C\s+\S+\s+)*commit(\s|$)", command):
        return None
    if re.search(r"\bgit\s+(-c\s+\S+\s+|-C\s+\S+\s+)*commit\b[^\n;|&]*(--help|--dry-run)\b", command):
        return None

    m = re.search(r"\bgit\s+-C\s+([^\s;|&]+).*?\bcommit\b", command)
    if m:
        raw = m.group(1).strip("'\"")
        path = Path(raw)
        if not path.is_absolute():
            path = ROOT / path
        return path.resolve()

    m = re.search(r"\bcd\s+([^\s;|&]+).*?\bgit\s+commit\b", command)
    if m:
        raw = m.group(1).strip("'\"")
        path = Path(raw)
        if not path.is_absolute():
            path = ROOT / path
        return path.resolve()

    return ROOT


def is_under(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except Exception:
        return False
