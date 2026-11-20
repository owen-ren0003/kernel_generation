#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

from _common import (
    ROOT,
    block,
    command_from_event,
    current_task,
    event_text,
    git_commit_target,
    is_under,
    load_yaml,
    read_event,
    run,
    task_dir,
    tool_input,
    tool_name,
)


EXEMPT_SIBLING_RE = re.compile(
    r"state/tasks/[^/\s]+/(?:meta\.yaml|REPRODUCE\.md|rejected-approaches\.md|ticket-page\.(?:txt|png)|issues/[^/\s]+/INFO\.md)(?:\s|$)"
)


def workspace_guard(text: str, tdir: Path) -> None:
    meta = load_yaml(tdir / "meta.yaml")
    scope = "\n".join(str(x) for x in meta.get("in_scope_paths") or [])
    allowed = set(re.findall(r"\bws[0-9]+\b", scope))
    if not allowed:
        return
    allowed.add("master")
    seen = set(re.findall(r"\bws[0-9]+\b", text))
    bad = sorted(seen - allowed)
    if bad:
        block(
            "[workspace-guard] BLOCKED: tool input references workspaces outside "
            f"the active task allowlist.\n  task: {tdir.name}\n"
            f"  allowed: {', '.join(sorted(allowed))}\n"
            f"  violations: {', '.join(bad)}"
        )


def prior_task_firewall(text: str, tdir: Path) -> None:
    meta = load_yaml(tdir / "meta.yaml")
    if (tdir / "DONE").exists() or (tdir / "GAVE-UP").exists():
        return
    if meta.get("status") in {"done", "abandoned"}:
        return
    mode = str(meta.get("mode", ""))
    bug_id = str(meta.get("id", ""))
    if not mode or not bug_id:
        return

    refs = set(re.findall(r"state/tasks/([^/\s]+)/?", text))
    refs |= set(re.findall(r"(/[^'\"]*?/state/tasks/([^/\s]+)/?)", text))
    normalized: set[str] = set()
    for ref in refs:
        if isinstance(ref, tuple):
            normalized.add(ref[1])
        else:
            normalized.add(ref)

    violations = []
    for sibling in sorted(normalized):
        if sibling == tdir.name:
            continue
        sibling_dir = ROOT / "state" / "tasks" / sibling
        sibling_meta = load_yaml(sibling_dir / "meta.yaml")
        if sibling_meta.get("mode") != mode or str(sibling_meta.get("id", "")) != bug_id:
            continue
        grant = ROOT / "state" / "grants" / tdir.name / sibling
        if grant.exists():
            continue
        # If every textual mention of this sibling is an exempt path, allow.
        mentions = [m.group(0) for m in re.finditer(rf"state/tasks/{re.escape(sibling)}/[^\s'\"]*", text)]
        if mentions and all(EXEMPT_SIBLING_RE.search(m + " ") for m in mentions):
            continue
        violations.append(sibling)

    if violations:
        block(
            "[prior-task-firewall] BLOCKED: input references prior task(s) with "
            "the same bug key while this task is open.\n"
            f"  current task: {tdir.name}\n"
            f"  bug key: {mode} / {bug_id}\n"
            f"  sibling(s): {', '.join(violations)}\n\n"
            "Allowed sibling files: meta.yaml, REPRODUCE.md, rejected-approaches.md, "
            "issues/*/INFO.md, ticket-page.txt, ticket-page.png.\n"
            "To allow retrospective access, finish the current task or create a grant "
            "under state/grants/<current>/<sibling>."
        )


def commit_gates(command: str, tdir: Path) -> None:
    target = git_commit_target(command)
    if target is None:
        return
    if target == ROOT or is_under(target, ROOT):
        return

    critique = run(["bash", str(ROOT / "scripts" / "check-critique.sh"), tdir.name])
    if critique.returncode != 0:
        block(
            "[commit-gate] BLOCKED: critique check failed before git commit.\n\n"
            + critique.stdout
            + critique.stderr
        )

    reward = run(["bash", str(ROOT / "scripts" / "check-reward-hack-review.sh"), tdir.name, str(target)])
    if reward.returncode != 0:
        block(
            "[commit-gate] BLOCKED: reward-hack review check failed before git commit.\n\n"
            + reward.stdout
            + reward.stderr
        )


def task_is_closed(tdir: Path) -> bool:
    meta = load_yaml(tdir / "meta.yaml")
    return (tdir / "DONE").exists() or (tdir / "GAVE-UP").exists() or meta.get("status") in {"done", "abandoned"}


def consultation_check(tdir: Path, mode: str) -> object:
    return run(
        [
            "python3",
            str(ROOT / "scripts" / "task" / "check-stuck-consultation.py"),
            str(tdir),
            "--mode",
            mode,
        ]
    )


def is_consultation_recovery_action(text: str, tdir: Path) -> bool:
    markers = (
        "consulting/",
        "CONSULTATION.md",
        "attempts.md",
        "LOG.md",
        "meta.yaml",
        "check-stuck-consultation.py",
    )
    return any(marker in text for marker in markers)


def abandonment_requested(event: dict, text: str, command: str) -> bool:
    ti = tool_input(event)
    paths: list[str] = []
    if isinstance(ti, dict):
        for key in ("file_path", "path", "target"):
            if isinstance(ti.get(key), str):
                paths.append(str(ti[key]))
    paths.extend(re.findall(r"^\*\*\* (?:Add|Update) File:\s*(.*?)\s*$", text, re.MULTILINE))

    if any(Path(path).name in {"NEEDS-MORE-DATA.md", "GAVE-UP"} for path in paths):
        return True
    if any(Path(path).name == "meta.yaml" for path in paths) and re.search(
        r"^\+?\s*status\s*:\s*['\"]?abandoned\b", text, re.MULTILINE | re.IGNORECASE
    ):
        return True
    if re.search(r"\brelease-workspace\.sh\b[^\n]*\s--abandon\b", command):
        return True
    if re.search(
        r"(?:\b(?:touch|tee|cp|mv|install)\b[^\n]*|>{1,2}\s*[^\n]*)\b(?:NEEDS-MORE-DATA\.md|GAVE-UP)\b",
        command,
    ):
        return True
    return False


def main() -> None:
    event = read_event()
    tdir = task_dir(current_task())
    if not tdir or not tdir.exists():
        return

    text = event_text(tool_input(event))
    name = tool_name(event)
    cmd = command_from_event(event)

    workspace_guard(text, tdir)
    prior_task_firewall(text, tdir)

    if not task_is_closed(tdir):
        checkpoint = consultation_check(tdir, "checkpoint")
        if checkpoint.returncode != 0 and not is_consultation_recovery_action(text, tdir):
            block(
                "[stuck-checkpoint] BLOCKED: complete the mandatory consulting checkpoint "
                "before normal debugging continues.\n\n"
                + checkpoint.stdout
                + checkpoint.stderr
            )
        if abandonment_requested(event, text, cmd):
            abandon = consultation_check(tdir, "abandon")
            if abandon.returncode != 0:
                block(
                    "[give-up-gate] BLOCKED: the task has not earned NEEDS-MORE-DATA or abandonment.\n\n"
                    + abandon.stdout
                    + abandon.stderr
                )

    if name in {"Bash", "shell", ""} or cmd:
        commit_gates(cmd, tdir)


if __name__ == "__main__":
    main()
