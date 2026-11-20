#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

fake=$(with_scratch_harness)
python3 - "$fake" <<'PY'
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1])
script = root / "scripts/state-retention.py"
spec = importlib.util.spec_from_file_location("retention", script)
retention = importlib.util.module_from_spec(spec)
spec.loader.exec_module(retention)
task = root / "state/tasks/synthetic"
(task / "issues").mkdir(parents=True)
kept = {
    "LOG.md": b"historical log\n", "REPRODUCE.md": b"exact commands\n",
    "meta.yaml": b"id: synthetic\n", "active-fixes.json": b"{}\n",
    "master-fixes.json": b"[]\n", "DONE": b"", ".log-gap-counter": b"7\n",
    "reward-hack-review-overridden": b"authorization\n",
    "evidence/run.log": b"raw log\n", "evidence/run.log.2.gz": b"compressed log\n",
    "evidence/run.out.gz": b"compressed output\n", "evidence/run.txt.gz": b"compressed text\n",
    "evidence/run.stderr": b"stderr\n", "evidence/stdout": b"stdout\n",
    "evidence/capture.yaml": b"metadata\n", "regression-sample.txt": b"test_case\n",
    "issues/one/metadata.json": b"{}\n", "evidence/check.sha256": b"checksum\n",
}
for name, data in kept.items():
    path = task / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
outside = root.parent / "outside"
outside.mkdir()
(outside / "keep.bin").write_bytes(b"external")
(task / "external").symlink_to(outside, target_is_directory=True)
sources = {"repro.py": "print('reproduce')\n", "scripts/fix.sh": "#!/bin/bash\nprintf '```example'\n"}
for name, content in sources.items():
    path = task / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
for name in ("cache/code.mlir", "cache/kernel.so", "results/trace.json", "backup.tgz"):
    path = task / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"artifact")
(root / "state/build-tracker").mkdir()
(root / "state/build-tracker/ws1.yaml").write_text("workspace: ws1\n")

def run(*args, expected=0):
    result = subprocess.run([sys.executable, str(script), *args], capture_output=True, text=True)
    assert result.returncode == expected, (args, result.returncode, result.stdout, result.stderr)
    return result

run('--check', expected=1)
assert (task / 'cache/code.mlir').exists(), 'Check must not mutate'
manifest = root / '.local-artifacts/cleanup.json'
run('--plan', '--manifest', str(manifest))
plan = json.loads(manifest.read_text())
assert len(plan['remove']) == 7, plan['remove']
result = json.loads(run('--apply', '--manifest', str(manifest)).stdout)
assert result['removed_files'] == 7 and result['source_snapshots'] == 2, result
assert result['missing_protected_records'] == []
run('--verify', '--manifest', str(manifest))
for name, data in kept.items():
    assert (task / name).read_bytes() == data, name
assert (outside / 'keep.bin').read_bytes() == b'external'
assert (task / 'issues').is_dir(), 'Required directory must remain'
assert not (task / 'cache').exists(), 'Empty artifact directories should be removed'
assert (root / 'state/build-tracker/ws1.yaml').exists()
snapshot = (task / 'SOURCE-SNAPSHOTS.md').read_text()
for source in sources.values():
    assert source in snapshot
    assert hashlib.sha256(source.encode()).hexdigest() in snapshot
run('--check')
# Verification must distinguish a new file from an original artifact that survived.
original = plan['remove'][0]
original_path = root / original['path']
original_path.parent.mkdir(parents=True, exist_ok=True)
original_path.write_bytes(b'new output after cleanup')
verified = json.loads(run('--verify', '--manifest', str(manifest)).stdout)
assert original['path'] in verified['recreated_paths']
info = original_path.lstat()
unchanged_plan = {'version': 1, 'root': str(root), 'keep': [], 'remove': [{'path': original['path'], 'signature': retention.signature(info)}]}
verified = retention.verify_plan(unchanged_plan, {'removed_files': 1, 'skipped': []})
assert verified['original_artifacts_remaining'] == [original['path']]
original_path.unlink()
run('--apply', '--manifest', str(manifest), expected=2)
run('--check', '--task', '../synthetic', expected=2)

# A changed candidate must not be deleted.
changing = task / 'changing.bin'
changing.write_bytes(b'before')
changed_manifest = root / '.local-artifacts/changed.json'
run('--plan', '--manifest', str(changed_manifest))
changing.write_bytes(b'changed after inventory')
result = json.loads(run('--apply', '--manifest', str(changed_manifest), expected=1).stdout)
assert len(result['skipped']) == 1 and changing.exists()
changing.unlink()

# Refuse protected names and traversal even if a manifest is edited.
for target in ('state/tasks/synthetic/LOG.md', '../outside/keep.bin'):
    unsafe = {'version': 1, 'root': str(root), 'remove': [{'path': target}], 'keep': []}
    try:
        retention.apply_plan(unsafe)
    except ValueError:
        pass
    else:
        raise AssertionError('Unsafe target accepted: ' + target)
assert (task / 'LOG.md').read_bytes() == kept['LOG.md']
assert (outside / 'keep.bin').exists()

# Replacing a candidate's parent with an external symlink must fail closed.
(task / 'swap').mkdir()
(task / 'swap/item.bin').write_bytes(b'local')
swap = retention.inventory(None)
(task / 'swap').rename(task / 'original-parent')
(task / 'swap').symlink_to(outside, target_is_directory=True)
try:
    retention.apply_plan(swap)
except OSError:
    pass
else:
    raise AssertionError('Followed a replaced parent directory')
assert (task / 'original-parent/item.bin').exists()
assert (outside / 'keep.bin').exists()

# Open artifacts are retained rather than interrupting local work.
(task / 'swap').unlink()
(task / 'original-parent/item.bin').unlink()
(task / 'original-parent').rmdir()
busy = task / 'busy.bin'
busy.write_bytes(b'in use')
with busy.open('rb'):
    result = retention.apply_plan(retention.inventory(None))
    assert busy.exists() and any('Open in' in s['reason'] for s in result['skipped'])
print('retention safety and record preservation verified')
PY
assert_zero "$?" "state retention must preserve records and reject unsafe deletion"

out=$(CODEX_TASK_ID=synthetic bash "$fake/scripts/artifact-dir.sh")
assert_eq "$out" "$fake/.local-artifacts/synthetic"
bad=$(CODEX_TASK_ID=../bad bash "$fake/scripts/artifact-dir.sh" 2>&1)
assert_nonzero "$?" "artifact directory must reject traversal"
exit 0
