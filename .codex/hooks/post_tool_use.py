#!/usr/bin/env python3
from __future__ import annotations

import re

from _common import ROOT, current_task, event_text, load_yaml, read_event, run, task_dir, tool_input, warn


def main() -> None:
    event = read_event()
    tdir = task_dir(current_task())
    if not tdir or not tdir.exists():
        return

    meta = load_yaml(tdir / "meta.yaml")
    if not (tdir / "DONE").exists() and not (tdir / "GAVE-UP").exists() and meta.get("status") not in {
        "done",
        "abandoned",
    }:
        consultation = run(
            [
                "python3",
                str(ROOT / "scripts" / "task" / "check-stuck-consultation.py"),
                str(tdir),
                "--mode",
                "checkpoint",
            ]
        )
        if consultation.returncode != 0:
            warn("[stuck-checkpoint] " + consultation.stdout + consultation.stderr)

    text = event_text(tool_input(event))
    counter = tdir / ".log-gap-counter"

    if re.search(r"(?:^|/)LOG\.md\b|(?:^|/)INVESTIGATION-LOG\.md\b|(?:^|/)VERDICT\.md\b", text):
        counter.write_text("0\n")
        return

    try:
        n = int(counter.read_text().strip() or "0") if counter.exists() else 0
    except Exception:
        n = 0
    n += 1
    counter.write_text(f"{n}\n")

    meta = load_yaml(tdir / "meta.yaml")
    limit = int(meta.get("max_tool_calls_per_log_entry") or 20)
    if n > limit:
        warn(
            f"[log-gap] Reminder: {n} tool calls since the last apparent task log update. "
            f"Append a timestamped entry to {tdir / 'LOG.md'} when you reach a stable checkpoint."
        )


if __name__ == "__main__":
    main()
