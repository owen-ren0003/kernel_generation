#!/usr/bin/env python3
"""Bound explicitly released scratch; never infer that legacy files are disposable.

Only .local-artifacts/TASK/scratch/RUN directories created here are managed.
All mutations use one lock. A run lease plus /proc checks protect active users.
Automatic application requires a local authorization for the exact policy hash.
"""
import argparse
import contextlib
import datetime as dt
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import time
import uuid

ROOT = Path(__file__).resolve().parents[1]
GIB = 1024 ** 3
SAFE = re.compile(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*\Z")


def encoded(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value):
    return hashlib.sha256(encoded(value)).hexdigest()


def read(path):
    if path.is_symlink():
        raise ValueError(f"symlink metadata: {path}")
    return json.loads(path.read_text())


def safe_dir(path, create=False):
    """Walk lexical descendants without resolving away a symlink."""
    parts = path.relative_to(ROOT).parts
    if ".." in parts:
        raise ValueError("parent traversal is forbidden")
    current = ROOT
    for part in parts:
        current /= part
        if create:
            current.mkdir(exist_ok=True)
        info = current.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
            raise ValueError(f"not an owned, real directory: {current}")
    return path


def save(path, value):
    safe_dir(path.parent, create=True)
    if path.is_symlink():
        raise ValueError(f"symlink destination: {path}")
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    try:
        with temporary.open("x") as stream:
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def control():
    return ROOT / ".local-artifacts/.retention"


def audit(event, **details):
    directory = safe_dir(ROOT / "state/artifact-retention", create=True)
    path = directory / (dt.datetime.now(dt.timezone.utc).strftime("%Y-%m") + ".log")
    fd = os.open(path, os.O_APPEND | os.O_CREAT | os.O_WRONLY | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "a") as stream:
        stream.write(json.dumps({"time": time.time(), "event": event, **details}, sort_keys=True) + "\n")


@contextlib.contextmanager
def lock(path, blocking=True, create=True):
    safe_dir(path.parent, create=create)
    fd = os.open(path, (os.O_CREAT if create else 0) | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | (0 if blocking else fcntl.LOCK_NB))
        except BlockingIOError:
            yield None
        else:
            yield fd
    finally:
        os.close(fd)


def policy():
    value = read(ROOT / "artifact-retention.json")
    keys = {"version", "keep_days", "minimum_hours", "task_budget_gib", "total_budget_gib", "sweep_hours"}
    if set(value) != keys or value["version"] != 1:
        raise ValueError("unsupported retention policy")
    for key in keys - {"version"}:
        if isinstance(value[key], bool) or not isinstance(value[key], (int, float)) or not math.isfinite(value[key]) or value[key] <= 0:
            raise ValueError(f"invalid positive policy limit: {key}")
    if value["minimum_hours"] > value["keep_days"] * 24:
        raise ValueError("minimum age exceeds maximum age")
    return value


def task_dir(task):
    if not SAFE.fullmatch(task):
        raise ValueError("invalid task id")
    directory = safe_dir(ROOT / "state/tasks" / task)
    if not (directory / "meta.yaml").is_file():
        raise ValueError("task metadata is missing")
    return directory


def run_path(value):
    path = Path(value)
    if not path.is_absolute():
        path = ROOT / path
    parts = path.relative_to(ROOT).parts
    if len(parts) != 4 or parts[0] != ".local-artifacts" or parts[2] != "scratch":
        raise ValueError("only a managed task scratch run may be modified")
    if not SAFE.fullmatch(parts[1]) or not SAFE.fullmatch(parts[3]):
        raise ValueError("invalid scratch path")
    safe_dir(path)
    return path


def metadata(path):
    value = read(path / ".artifact.json")
    if value.get("version") != 1 or value.get("path") != str(path.relative_to(ROOT)):
        raise ValueError("scratch registration does not match its path")
    if value.get("status") not in {"active", "released", "pinned"}:
        raise ValueError("invalid scratch lifecycle")
    task_dir(path.parts[-3])
    return value


def record_path(path, record):
    item = Path(record)
    if not item.is_absolute():
        item = ROOT / item
    expected = task_dir(path.parts[-3])
    if not item.is_relative_to(expected) or item.suffix not in {".md", ".log", ".yaml"}:
        raise ValueError("record must be a durable Markdown, log or YAML file in this task")
    safe_dir(item.parent)
    info = item.lstat()
    if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or not info.st_size:
        raise ValueError("record must be a nonempty owned regular file")
    return item


def create(task, name):
    task_dir(task)
    if not SAFE.fullmatch(name):
        raise ValueError("invalid scratch name")
    identifier = dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + name + "-" + uuid.uuid4().hex[:12]
    parent = safe_dir(ROOT / ".local-artifacts" / task / "scratch", create=True)
    path = parent / identifier
    path.mkdir(mode=0o700)
    save(path / ".artifact.json", {"version": 1, "path": str(path.relative_to(ROOT)), "created": time.time(), "status": "active"})
    (path / ".lease").touch()
    audit("create", path=str(path.relative_to(ROOT)))
    return path


def change(path, action, record=None):
    path = run_path(path)
    with lock(path / ".lease", blocking=False, create=False) as lease:
        if lease is None:
            raise ValueError("run is leased by an active command")
        value = metadata(path)
        if action == "release":
            item = record_path(path, record)
            value.update(status="released", finished=time.time(), record=str(item.relative_to(ROOT)))
        elif action == "pin":
            value["status"] = "pinned"
        else:
            value["status"] = "released" if "finished" in value else "active"
        save(path / ".artifact.json", value)
        audit(action, path=str(path.relative_to(ROOT)))


def snapshot(path):
    """Hash file identities/metadata, not multi-GB tensor contents; follow no links."""
    path = run_path(path)
    device = path.stat().st_dev
    hasher = hashlib.sha256()
    allocated = count = 0
    pending = [path]
    while pending:
        item = pending.pop()
        info = item.lstat()
        if info.st_dev != device or info.st_uid != os.getuid():
            raise ValueError(f"foreign owner or mounted filesystem: {item}")
        if item != path and item.name == ".git":
            raise ValueError(f"source repository inside scratch: {item}")
        if not (stat.S_ISREG(info.st_mode) or stat.S_ISDIR(info.st_mode) or stat.S_ISLNK(info.st_mode)):
            raise ValueError(f"special file inside scratch: {item}")
        hasher.update(encoded([str(item.relative_to(path)), info.st_dev, info.st_ino, info.st_mode, info.st_size, info.st_mtime_ns, info.st_ctime_ns]))
        allocated += info.st_blocks * 512
        count += 1
        if stat.S_ISDIR(info.st_mode):
            if item != path and os.path.ismount(item):
                raise ValueError(f"nested mount: {item}")
            pending.extend(sorted(item.iterdir(), reverse=True))
    return {"tree": hasher.hexdigest(), "bytes": allocated, "entries": count}


def in_use(path):
    """Additional protection for manually released scratch; wrappers use leases."""
    prefix = str(path) + "/"
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != os.getuid():
                continue
            links = [proc / "cwd", proc / "exe", *list((proc / "fd").iterdir())]
            for link in links:
                try:
                    target = os.readlink(link).removesuffix(" (deleted)")
                except FileNotFoundError:
                    continue
                # Ignore this cleaner's own lease fd, which it deliberately holds.
                if proc.name == str(os.getpid()) and target == str(path / ".lease"):
                    continue
                if target == str(path) or target.startswith(prefix):
                    return True
            if prefix in (proc / "maps").read_text():
                return True
        except (FileNotFoundError, ProcessLookupError):
            continue
        except PermissionError:
            # An uninspectable same-user process could still own the files.
            return True
    return False


def make_plan(settings, now=None):
    now = time.time() if now is None else now
    runs, skipped = [], []
    base = ROOT / ".local-artifacts"
    if base.exists():
        safe_dir(base)
        for task in sorted(base.iterdir()):
            scratch = task / "scratch"
            if task.is_symlink() or not scratch.exists():
                continue
            try:
                safe_dir(scratch)
                for path in sorted(scratch.iterdir()):
                    try:
                        path = run_path(path)
                        value = metadata(path)
                        if value["status"] != "released":
                            skipped.append({"path": str(path.relative_to(ROOT)), "reason": value["status"]})
                            continue
                        record_path(path, value["record"])
                        with lock(path / ".lease", blocking=False, create=False) as lease:
                            if lease is None or in_use(path):
                                skipped.append({"path": value["path"], "reason": "in use"})
                                continue
                            runs.append({"path": value["path"], "task": task.name, "finished": float(value["finished"]), **snapshot(path)})
                    except (OSError, ValueError, KeyError, TypeError) as error:
                        skipped.append({"path": str(path.relative_to(ROOT)), "reason": str(error)})
            except (OSError, ValueError) as error:
                skipped.append({"path": str(scratch.relative_to(ROOT)), "reason": str(error)})
    runs.sort(key=lambda run: (run["finished"], run["path"]))
    selected = {}
    eligible = [run for run in runs if now - run["finished"] >= settings["minimum_hours"] * 3600]
    for run in eligible:
        if now - run["finished"] >= settings["keep_days"] * 86400:
            selected[run["path"]] = "age"
    for task in sorted({run["task"] for run in runs}):
        size = sum(run["bytes"] for run in runs if run["task"] == task and run["path"] not in selected)
        for run in eligible:
            if size <= settings["task_budget_gib"] * GIB:
                break
            if run["task"] == task and run["path"] not in selected:
                selected[run["path"]] = "task budget"
                size -= run["bytes"]
    size = sum(run["bytes"] for run in runs if run["path"] not in selected)
    for run in eligible:
        if size <= settings["total_budget_gib"] * GIB:
            break
        if run["path"] not in selected:
            selected[run["path"]] = "total budget"
            size -= run["bytes"]
    return {"version": 1, "root": str(ROOT), "created": now, "policy_sha256": digest(settings),
            "remove": [{**run, "reason": selected[run["path"]]} for run in runs if run["path"] in selected],
            "retained_released_bytes": size, "protected": skipped,
            "note": "Legacy/unregistered artifacts are excluded; budgets are soft when work is active, pinned or under 24 hours old."}


def apply_plan(plan, settings, reviewed_hash):
    if plan.get("version") != 1 or plan.get("root") != str(ROOT) or plan.get("policy_sha256") != digest(settings) or digest(plan) != reviewed_hash:
        raise ValueError("plan/root/policy/review hash mismatch")
    # Re-evaluate eligibility, including newly added pins/leases and changed files.
    current = {item["path"]: item for item in make_plan(settings)["remove"]}
    if len({item["path"] for item in plan["remove"]}) != len(plan["remove"]):
        raise ValueError("duplicate removal in manifest")
    for item in plan["remove"]:
        run_path(item["path"])
    result = {"removed": [], "skipped": [], "freed_bytes": 0, "plan_sha256": reviewed_hash}
    for item in plan["remove"]:
        path = run_path(item["path"])
        fresh = current.get(item["path"])
        if fresh is None or fresh["tree"] != item["tree"]:
            result["skipped"].append({"path": item["path"], "reason": "changed or no longer eligible"})
            continue
        with lock(path / ".lease", blocking=False, create=False) as lease:
            if lease is None or in_use(path) or snapshot(path)["tree"] != item["tree"]:
                result["skipped"].append({"path": item["path"], "reason": "changed or in use"})
                continue
            if not shutil.rmtree.avoids_symlink_attacks:
                raise RuntimeError("safe fd-based tree deletion unavailable")
            audit("remove-start", path=item["path"], plan_sha256=reviewed_hash)
            shutil.rmtree(path)
            result["removed"].append(item["path"])
            result["freed_bytes"] += item["bytes"]
            audit("remove-complete", path=item["path"], bytes=item["bytes"])
    audit("apply", result=result)
    return result


def sweep(settings, if_due=False):
    authorization = control() / "authorization.json"
    if not authorization.exists():
        return {"status": "disabled: no local authorization"}
    auth = read(authorization)
    if auth.get("policy_sha256") != digest(settings) or not auth.get("user_request"):
        raise ValueError("policy changed; review and authorize it before automatic cleanup")
    last = control() / "last-sweep.json"
    if if_due and last.exists() and time.time() - read(last)["time"] < settings["sweep_hours"] * 3600:
        return {"status": "not due"}
    plan = make_plan(settings)
    save(control() / "latest-plan.json", plan)
    review_hash = digest(plan)
    audit("policy-review", authorization=auth, plan=plan, plan_sha256=review_hash)
    result = apply_plan(plan, settings, review_hash)
    save(control() / "latest-result.json", result)
    save(last, {"time": time.time()})
    return result


def run_command(args):
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        raise ValueError("a foreground command is required")
    with lock(control() / "lock"):
        path = create(args.task, args.name)
        record_path(path, args.record)
        lease = os.open(path / ".lease", os.O_RDWR | os.O_NOFOLLOW)
        fcntl.flock(lease, fcntl.LOCK_EX)
    try:
        print(f"Scratch: {path}", file=sys.stderr)
        env = {**os.environ, "HARNESS_SCRATCH_DIR": str(path)}
        code = subprocess.call(command, env=env, pass_fds=(lease,))
        # Release only after the foreground command has exited. Interrupted runs
        # stay active and need an explicit release after their records are saved.
        with lock(control() / "lock"):
            value = metadata(path)
            value.update(finished=time.time(), record=str(record_path(path, args.record).relative_to(ROOT)),
                         status="released" if code == 0 else "pinned", exit_code=code)
            save(path / ".artifact.json", value)
            audit("command-complete", path=value["path"], command=command, exit_code=code, record=value["record"])
        return code
    finally:
        os.close(lease)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="action", required=True)
    for action in ("check", "sweep", "policy-hash"):
        item = sub.add_parser(action)
        if action == "sweep":
            item.add_argument("--if-due", action="store_true")
    item = sub.add_parser("authorize")
    item.add_argument("--policy-sha256", required=True)
    item.add_argument("--user-request", required=True)
    for action in ("plan", "apply"):
        item = sub.add_parser(action)
        item.add_argument("--manifest", type=Path, required=True)
        if action == "apply":
            item.add_argument("--reviewed-sha256", required=True)
    for action in ("create", "run"):
        item = sub.add_parser(action)
        item.add_argument("--task", required=True)
        item.add_argument("--name", required=True)
        if action == "run":
            item.add_argument("--record", required=True)
            item.add_argument("command", nargs=argparse.REMAINDER)
    for action in ("release", "pin", "unpin"):
        item = sub.add_parser(action)
        item.add_argument("path")
        if action == "release":
            item.add_argument("--record", required=True)
    args = parser.parse_args()
    settings = policy()
    if args.action == "policy-hash":
        print(digest(settings))
        return 0
    if args.action == "check":
        print(json.dumps(make_plan(settings), indent=2))
        return 0
    if args.action == "run":
        return run_command(args)
    with lock(control() / "lock", blocking=args.action != "sweep") as guard:
        if guard is None:
            return 0
        if args.action == "authorize":
            if args.policy_sha256 != digest(settings) or not args.user_request.strip():
                raise ValueError("review the policy and provide its exact hash and user authorization")
            value = {"policy_sha256": digest(settings), "user_request": args.user_request, "time": time.time()}
            save(control() / "authorization.json", value)
            audit("authorize", **value)
            print("Authorized the reviewed scratch policy on this machine.")
        elif args.action == "create":
            print(create(args.task, args.name))
        elif args.action in {"release", "pin", "unpin"}:
            change(args.path, args.action, getattr(args, "record", None))
        elif args.action == "plan":
            plan = make_plan(settings)
            manifest = args.manifest.absolute()
            if manifest.exists() or manifest.is_symlink():
                raise ValueError("manifest already exists")
            if not manifest.is_relative_to(control()):
                raise ValueError("keep manual plans under .local-artifacts/.retention/")
            save(manifest, plan)
            print(digest(plan))
        elif args.action == "apply":
            plan = read(args.manifest)
            audit("manual-review", plan=plan, plan_sha256=args.reviewed_sha256)
            print(json.dumps(apply_plan(plan, settings, args.reviewed_sha256), indent=2))
        else:
            print(json.dumps(sweep(settings, args.if_due), indent=2))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, TypeError, RuntimeError) as error:
        print(f"artifact retention: {error}", file=sys.stderr)
        # Cron need not accumulate a second unbounded stdout/stderr log.
        with contextlib.suppress(OSError, ValueError):
            audit("error", message=str(error))
        sys.exit(1)
