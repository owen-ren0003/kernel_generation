#!/usr/bin/env python3
"""Inventory or explicitly remove disposable task files; never follow symlinks.

The default operation is read-only. Deletion requires a previously generated
manifest and --apply. Runtime bookkeeping outside state/tasks is untouched.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import stat
import sys

ROOT = Path(__file__).resolve().parents[1]
RECORD_SUFFIXES = {".md", ".markdown", ".mdx", ".yaml", ".yml", ".txt", ".csv", ".tsv", ".sha256", ".md5"}
MARKERS = {"DONE", "GAVE-UP", ".log-gap-counter", "reward-hack-review-overridden", "active-fixes.json", "master-fixes.json"}
LOG_NAME = re.compile(r"(?:\.log(?:[._-].*)?$|(?:^|[._-])(?:stdout|stderr)(?:[._-].*)?$|\.out$)", re.I)
SOURCE_SUFFIXES = {".py", ".sh", ".ps1", ".c", ".cc", ".cpp", ".h", ".hpp", ".inc", ".patch", ".diff", ".js", ".ts", ".makefile"}
SOURCE_DIRS = {"src", "scripts", "repro", "reproducer", "reproducers", "tools", "tests"}


def kept_reason(path: PurePosixPath) -> str | None:
    parts = path.parts
    if parts[:2] != ("state", "tasks") or len(parts) < 4:
        return "harness bookkeeping"
    if path.name in MARKERS or path.suffix.lower() in {".pid", ".lock"}:
        return "task bookkeeping"
    plain = path
    if plain.suffix.lower() in {".gz", ".bz2", ".xz", ".zst"}:
        plain = plain.with_suffix("")
    if plain.suffix.lower() in RECORD_SUFFIXES:
        return "records and metadata"
    if LOG_NAME.search(plain.name):
        return "raw/compressed logs"
    if not path.suffix and any(part.lower() in {"log", "logs"} for part in parts[3:-1]):
        return "raw logs"
    if path.suffix.lower() == ".json" and (len(parts) == 4 or (len(parts) == 6 and parts[3] == "issues")):
        return "task/issue metadata"
    return None


def signature(info: os.stat_result) -> list[int]:
    return [info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns]


def validate_tasks() -> Path:
    tasks = ROOT / "state" / "tasks"
    if ROOT == Path(ROOT.anchor) or ROOT == Path.home():
        raise ValueError("Refusing a filesystem/home root as the harness")
    if not (ROOT / "AGENTS.md").is_file() or not (ROOT / "scripts" / "task" / "new-task.sh").is_file():
        raise ValueError("Not a recognized harness root")
    if (ROOT / "state").is_symlink() or tasks.is_symlink():
        raise ValueError("state and state/tasks must be real directories")
    return tasks


def task_path(raw: str) -> Path:
    if not raw or raw in {".", ".."} or Path(raw).name != raw:
        raise ValueError("--task must be one task directory name")
    path = validate_tasks() / raw
    if path.is_symlink() or not path.is_dir():
        raise ValueError("Task must be an existing, non-symlink directory")
    return path


def inventory(task: str | None) -> dict:
    tasks = validate_tasks()
    start = task_path(task) if task else tasks
    result = {"version": 1, "root": str(ROOT), "created_at": dt.datetime.now().astimezone().isoformat(), "task": task,
              "remove": [], "keep": [], "allocated_file_bytes": 0, "special_paths": []}
    if not start.exists():
        return result
    device = start.stat().st_dev
    for folder, directories, names in os.walk(start, followlinks=False):
        for dirname in list(directories):
            path = Path(folder, dirname)
            info = path.lstat()
            if info.st_dev != device:
                raise ValueError(f"Nested mount requires a separate assessment: {path.relative_to(ROOT)}")
            if stat.S_ISLNK(info.st_mode):
                directories.remove(dirname)
                names.append(dirname)
        for name in names:
            path = Path(folder, name)
            info = path.lstat()
            relative = path.relative_to(ROOT).as_posix()
            if not (stat.S_ISREG(info.st_mode) or stat.S_ISLNK(info.st_mode)):
                result["special_paths"].append(relative)
                continue
            entry = {"path": relative, "signature": signature(info), "allocated_bytes": info.st_blocks * 512}
            result["allocated_file_bytes"] += entry["allocated_bytes"]
            reason = kept_reason(PurePosixPath(relative))
            if reason:
                entry["reason"] = reason
                result["keep"].append(entry)
            else:
                result["remove"].append(entry)
    return result


def summary(plan: dict) -> dict:
    return {"kept_files": len(plan["keep"]), "disposable_files": len(plan["remove"]),
            "kept_allocated_bytes": sum(e["allocated_bytes"] for e in plan["keep"]),
            "disposable_allocated_bytes": sum(e["allocated_bytes"] for e in plan["remove"]),
            "special_paths": plan["special_paths"],
            "largest_disposable": [{"path": e["path"], "bytes": e["allocated_bytes"]}
                                   for e in sorted(plan["remove"], key=lambda e: e["allocated_bytes"], reverse=True)[:8]]}


def open_directory(parts: tuple[str, ...]) -> int:
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    descriptor = os.open(ROOT, flags)
    try:
        for component in parts:
            child = os.open(component, flags, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        return descriptor
    except BaseException:
        os.close(descriptor)
        raise


def open_parent(relative: str) -> tuple[int, str]:
    """Open every path component without following symlinks, including parents."""
    path = PurePosixPath(relative)
    if path.is_absolute() or ".." in path.parts or path.parts[:2] != ("state", "tasks") or len(path.parts) < 4:
        raise ValueError(f"Invalid deletion target: {relative}")
    if kept_reason(path):
        raise ValueError(f"Protected record in deletion manifest: {relative}")
    return open_directory(path.parts[:-1]), path.name


def in_use_inodes() -> set[tuple[int, int]]:
    """Protect open files and executables held by accessible local processes."""
    found = set()
    for process in Path("/proc").glob("[0-9]*"):
        try:
            targets = list((process / "fd").iterdir()) + [process / "exe"]
        except (FileNotFoundError, PermissionError):
            continue
        for target in targets:
            try:
                info = target.stat()
                found.add((info.st_dev, info.st_ino))
            except (FileNotFoundError, PermissionError, ProcessLookupError):
                pass
        try:
            with (process / "maps").open() as stream:
                for line in stream:
                    fields = line.split(None, 5)
                    if len(fields) >= 5 and fields[4] != "0":
                        major, minor = fields[3].split(":")
                        found.add((os.makedev(int(major, 16), int(minor, 16)), int(fields[4])))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return found


def snapshot_source(relative: str, parent: int, name: str, expected: list[int]) -> bool:
    """Keep small task-authored repro scripts/patches as text before removing them."""
    path = PurePosixPath(relative)
    inner = path.parts[3:]
    authored = len(inner) == 1 or inner[0] in SOURCE_DIRS
    source = path.suffix.lower() in SOURCE_SUFFIXES or name.lower() == "makefile"
    if not (authored and source and stat.S_ISREG(expected[2])):
        return False
    if expected[3] > 2 * 1024 * 1024:
        raise ValueError("Task source exceeds snapshot limit; needs manual preservation")
    fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW, dir_fd=parent)
    with os.fdopen(fd, "rb") as stream:
        if signature(os.fstat(stream.fileno())) != expected:
            raise ValueError("Source changed before snapshot")
        data = stream.read()
    text = data.decode("utf-8")
    task_path(path.parts[2])
    fence = "`" * max(3, 1 + max((len(m.group()) for m in re.finditer(r"`+", text)), default=0))
    task_fd = open_directory(path.parts[:3])
    try:
        descriptor = os.open("SOURCE-SNAPSHOTS.md", os.O_WRONLY | os.O_APPEND | os.O_CREAT | os.O_NOFOLLOW,
                             0o600, dir_fd=task_fd)
    finally:
        os.close(task_fd)
    with os.fdopen(descriptor, "a", encoding="utf-8") as out:
        if out.tell() == 0:
            out.write("# Source snapshots retained during state cleanup\n\n"
                      "Restore any needed source into the assigned checkout or `.local-artifacts/<task>/`, "
                      "then adjust historical commands to that location. Generated binaries, captures and "
                      "vendor source trees are not included; use the recorded revisions and build/input recipes.\n")
        out.write(f"\n## {PurePosixPath(*inner)}\n\nOriginal path: `{relative}`\n\n"
                  f"SHA-256: `{hashlib.sha256(data).hexdigest()}`\n\n"
                  f"{fence}\n{text}" + ("" if text.endswith("\n") else "\n") + f"{fence}\n")
        out.flush()
        os.fsync(out.fileno())
    return True


def apply_plan(plan: dict) -> dict:
    validate_tasks()
    if plan.get("version") != 1 or plan.get("root") != str(ROOT):
        raise ValueError("Manifest belongs to another harness or version")
    seen = set()
    # Validate the whole target list before making any changes.
    for entry in plan["remove"]:
        relative = entry["path"]
        if relative in seen:
            raise ValueError("Duplicate target in manifest")
        seen.add(relative)
        parent, _ = open_parent(relative)
        os.close(parent)
    busy = in_use_inodes()
    removed = collections.Counter()
    removed_bytes = 0
    snapshots = 0
    skipped = []
    for entry in plan["remove"]:
        relative = entry["path"]
        parent = None
        try:
            parent, name = open_parent(relative)
            info = os.stat(name, dir_fd=parent, follow_symlinks=False)
            if signature(info) != entry["signature"]:
                raise ValueError("Changed since inventory")
            if (info.st_dev, info.st_ino) in busy:
                raise ValueError("Open in a running process")
            snapshots += snapshot_source(relative, parent, name, entry["signature"])
            if signature(os.stat(name, dir_fd=parent, follow_symlinks=False)) != entry["signature"]:
                raise ValueError("Changed immediately before removal")
            os.unlink(name, dir_fd=parent)
            removed[PurePosixPath(relative).parts[2]] += 1
            removed_bytes += entry["allocated_bytes"]
        except (OSError, ValueError) as exc:
            skipped.append({"path": relative, "reason": str(exc)})
        finally:
            if parent is not None:
                os.close(parent)
    # Only remove empty directories below task roots, retaining issues/.
    tasks = ROOT / "state" / "tasks"
    prune_root = task_path(plan["task"]) if plan.get("task") else tasks
    for folder, dirs, files, descriptor in os.fwalk(prune_root, topdown=False, follow_symlinks=False):
        for name in dirs:
            path = Path(folder, name)
            relative = path.relative_to(tasks)
            if len(relative.parts) == 1 or (len(relative.parts) == 2 and name == "issues"):
                continue
            try:
                os.rmdir(name, dir_fd=descriptor)
            except OSError:
                pass  # Not empty, a symlink, or concurrently changed.
    missing_kept = [e["path"] for e in plan["keep"] if not os.path.lexists(ROOT / e["path"])]
    return {"removed_files": sum(removed.values()), "removed_allocated_bytes": removed_bytes,
            "affected_tasks": dict(sorted(removed.items())), "source_snapshots": snapshots,
            "skipped": skipped, "missing_protected_records": missing_kept}


def write_manifest(path: Path, value: dict) -> None:
    destination = path.absolute()
    if destination.resolve().is_relative_to((ROOT / "state").resolve()):
        raise ValueError("Store inventory manifests outside state (for example .local-artifacts/)")
    destination.parent.mkdir(parents=True, exist_ok=True)
    # Never overwrite an earlier audit record.
    with destination.open("x", encoding="utf-8") as out:
        os.chmod(destination, 0o600)
        json.dump(value, out, separators=(",", ":"))
        out.write("\n")


def verify_plan(plan: dict, result: dict) -> dict:
    """Verify the recorded cleanup without confusing later work with old files."""
    validate_tasks()
    if plan.get("version") != 1 or plan.get("root") != str(ROOT):
        raise ValueError("Manifest belongs to another harness or version")
    still_original = []
    recreated = []
    missing_records = []
    for kind in ("remove", "keep"):
        for entry in plan[kind]:
            relative = PurePosixPath(entry["path"])
            if relative.is_absolute() or ".." in relative.parts or relative.parts[:2] != ("state", "tasks"):
                raise ValueError("Invalid path in manifest")
            try:
                info = (ROOT / relative).lstat()
            except FileNotFoundError:
                if kind == "keep":
                    missing_records.append(str(relative))
                continue
            if kind == "remove":
                if signature(info) == entry["signature"]:
                    still_original.append(str(relative))
                else:
                    recreated.append(str(relative))
    return {"original_artifacts_remaining": still_original, "missing_protected_records": missing_records,
            "recreated_paths": recreated, "skipped_at_cleanup": result["skipped"],
            "removed_count_matches_manifest": result["removed_files"] == len(plan["remove"])}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check", action="store_true", help="report disposable files; exit 1 if any remain")
    mode.add_argument("--plan", action="store_true", help="write a metadata-only deletion manifest")
    mode.add_argument("--apply", action="store_true", help="delete unchanged, unused files from an existing manifest")
    mode.add_argument("--verify", action="store_true", help="verify an applied manifest; report later recreations separately")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--task", help="limit an inventory/check to one task id")
    args = parser.parse_args()
    if (args.plan or args.apply or args.verify) and args.manifest is None:
        parser.error("--plan/--apply/--verify requires --manifest")
    if args.verify:
        if args.task:
            parser.error("--verify uses the task scope recorded in its manifest")
        with args.manifest.open(encoding="utf-8") as stream:
            plan = json.load(stream)
        with args.manifest.with_name(args.manifest.name + ".result.json").open(encoding="utf-8") as stream:
            result = json.load(stream)
        verified = verify_plan(plan, result)
        print(json.dumps(verified, indent=2))
        return int(bool(verified["original_artifacts_remaining"] or verified["missing_protected_records"]
                        or verified["skipped_at_cleanup"] or not verified["removed_count_matches_manifest"]))
    if args.apply:
        if args.task:
            parser.error("--apply uses the task scope recorded in its manifest")
        if args.manifest.resolve().is_relative_to((ROOT / "state").resolve()):
            raise ValueError("The cleanup manifest must be outside state")
        with args.manifest.open(encoding="utf-8") as stream:
            plan = json.load(stream)
        report_path = args.manifest.with_name(args.manifest.name + ".result.json")
        if report_path.exists():
            raise ValueError("This manifest was already applied; generate a fresh inventory")
        result = apply_plan(plan)
        write_manifest(report_path, result)
        print(json.dumps(result, indent=2))
        return 1 if result["skipped"] or result["missing_protected_records"] else 0
    plan = inventory(args.task)
    if args.plan:
        write_manifest(args.manifest, plan)
    print(json.dumps(summary(plan), indent=2))
    return 1 if not args.plan and (plan["remove"] or plan["special_paths"]) else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"[state-retention] {error}", file=sys.stderr)
        sys.exit(2)
