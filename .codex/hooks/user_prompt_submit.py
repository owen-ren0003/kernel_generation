#!/usr/bin/env python3
from __future__ import annotations

import re

from _common import current_task, event_text, read_event, task_dir, warn


NEW_TASK_PATTERNS = [
    r"\bnew\s+(task|issue|bug)\b",
    r"\banother\s+(task|issue|bug|ticket)\b",
    r"\bDTS\s*\d{8,}\b",
    r"https?://\S+/issues/\d+",
]


def main() -> None:
    event = read_event()
    text = event_text(event)
    if not any(re.search(p, text, re.I) for p in NEW_TASK_PATTERNS):
        return
    cur = current_task()
    tdir = task_dir(cur)
    if cur and tdir and tdir.exists():
        return
    warn(
        "[task-bind] This prompt looks like a new bug/task, but no active task is bound. "
        "Create one with: bash scripts/task/new-task.sh --mode bug-track --id <id> --focus \"<focus>\""
    )


if __name__ == "__main__":
    main()
