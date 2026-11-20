#!/usr/bin/env bash
set -uo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/_test-lib.sh"

PYTHONDONTWRITEBYTECODE=1 python3 - "$HARNESS_ROOT" "$SCRATCH" <<'PY'
import argparse
import contextlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time
from unittest import mock

source, scratch = map(Path, sys.argv[1:])
spec = importlib.util.spec_from_file_location('artifacts', source / 'scripts/artifact-retention.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
# Unit fixtures must not depend on unrelated, non-dumpable workstation jobs.
# Keep real /proc FD/map checks for this test process; separately assert the
# production fail-closed behavior for an uninspectable same-user process below.
real_iterdir = Path.iterdir
def fixture_iterdir(path):
    if path == Path('/proc'):
        return iter([path / str(os.getpid())])
    return real_iterdir(path)
process_view = mock.patch.object(Path, 'iterdir', fixture_iterdir)
process_view.start()
root = scratch / 'harness'
root.mkdir()
m.ROOT = root
settings = json.loads((source / 'artifact-retention.json').read_text())
m.save(root / 'artifact-retention.json', settings)
for task in ['task-a', 'task-b']:
    p = root / 'state/tasks' / task
    p.mkdir(parents=True)
    (p / 'meta.yaml').write_text('status: open\n')
    (p / 'REPRODUCE.md').write_text('Source in Git, seed=37, input shapes, command and result summary.\n')

def make(name, days=8, task='task-a', size=8192):
    p = m.create(task, name)
    (p / 'raw.bin').write_bytes(b'x' * size)
    m.change(str(p), 'release', str(root / 'state/tasks' / task / 'REPRODUCE.md'))
    data = m.metadata(p)
    data['finished'] = time.time() - days * 86400
    m.save(p / '.artifact.json', data)
    return p

def paths(plan):
    return {root / item['path'] for item in plan['remove']}

def apply(plan, policy=settings):
    return m.apply_plan(plan, policy, m.digest(plan))

def rejects(call):
    try:
        call()
    except (ValueError, OSError):
        return
    raise AssertionError('unsafe operation was accepted')

# Age cleanup preserves records, ordinary legacy output, recent, active and pinned runs.
old = make('old')
recent = make('recent', days=.1)
active = m.create('task-a', 'active')
pinned = make('pinned')
m.change(str(pinned), 'pin')
legacy = root / '.local-artifacts/task-a/source-backup.tar.gz'
legacy.write_bytes(b'unique source backup')
record = root / 'state/tasks/task-a/REPRODUCE.md'
before_record = record.read_bytes()
plan = m.make_plan(settings)
assert paths(plan) == {old}, plan
result = apply(plan)
assert not old.exists() and result['freed_bytes'] > 0
assert all(p.exists() for p in (recent, active, pinned, legacy))
assert record.read_bytes() == before_record
print('age, lifecycle, records and legacy preservation: PASS')

# A live same-process file descriptor or lease prevents cleanup.
opened = make('opened')
with (opened / 'raw.bin').open('rb'):
    assert opened not in paths(m.make_plan(settings))
with m.lock(opened / '.lease', create=False):
    assert opened not in paths(m.make_plan(settings))
    rejects(lambda: m.change(str(opened), 'release', str(record)))
assert opened in paths(m.make_plan(settings))
def unreadable_fd(path):
    if path == Path('/proc') / str(os.getpid()) / 'fd':
        raise PermissionError('simulated same-user process restriction')
    return fixture_iterdir(path)
with mock.patch.object(Path, 'iterdir', unreadable_fd):
    assert m.in_use(opened)
    assert opened not in paths(m.make_plan(settings))
apply(m.make_plan(settings))
print('open-file, lease and uninspectable-process protection: PASS')

# Changes or a new pin after planning invalidate that run, not the records.
changed = make('changed')
new_pin = make('new-pin')
plan = m.make_plan(settings)
(changed / 'raw.bin').write_bytes(b'new important data')
m.change(str(new_pin), 'pin')
result = apply(plan)
assert changed.exists() and new_pin.exists() and len(result['skipped']) == 2
apply(m.make_plan(settings))
assert not changed.exists()
print('changes between plan and apply: PASS')

# A missing record, malformed registration, source repository and root symlink
# must never be interpreted as permission to delete.
bad = make('bad-record')
data = m.metadata(bad); data['record'] = 'state/tasks/task-b/REPRODUCE.md'
m.save(bad / '.artifact.json', data)
repo = make('git-source'); (repo / '.git').mkdir()
outside = root / 'outside'; outside.mkdir(); (outside / 'keep').write_text('keep')
link = active.parent / 'linked-root'; link.symlink_to(outside, target_is_directory=True)
malformed = active.parent / 'unregistered'; malformed.mkdir(); (malformed / 'raw.bin').write_text('keep')
plan = m.make_plan(settings)
assert not ({bad, repo, link, malformed} & paths(plan))
rejects(lambda: m.run_path(str(root / 'state/tasks/task-a')))
rejects(lambda: m.run_path(str(link)))
rejects(lambda: m.record_path(active, str(record.parent / '../task-b/REPRODUCE.md')))
rejects(lambda: m.safe_dir(root / '..'))
rejects(lambda: m.change(str(active), 'release', str(legacy)))
assert (outside / 'keep').read_text() == 'keep'
print('scope, record, repository and symlink safeguards: PASS')

# Symlinks inside an eligible payload are unlinked without touching targets.
syms = make('internal-links')
(syms / 'link').symlink_to(outside, target_is_directory=True)
apply(m.make_plan(settings))
assert not syms.exists() and (outside / 'keep').exists()

# Plan replay with modified hash, root or traversal is rejected in full.
victim = make('victim'); plan = m.make_plan(settings)
rejects(lambda: m.apply_plan(plan, settings, 'incorrect-hash'))
wrong = {**plan, 'root': '/'}
rejects(lambda: apply(wrong))
wrong = json.loads(json.dumps(plan)); wrong['remove'][0]['path'] = 'state/tasks/task-a'
rejects(lambda: apply(wrong))
assert victim.exists()
apply(m.make_plan(settings))
print('plan review and tamper rejection: PASS')

# Budget eviction is oldest-first, respects minimum lifetime, and works across tasks.
first = make('first', days=3, size=32768)
second = make('second', days=2, size=32768)
small = {**settings, 'task_budget_gib': 60000 / m.GIB}
plan = m.make_plan(small)
assert first in paths(plan) and second not in paths(plan) and recent not in paths(plan), plan
apply(plan, small)
cross = make('cross', days=1.5, task='task-b', size=32768)
small = {**settings, 'total_budget_gib': 70000 / m.GIB}
plan = m.make_plan(small)
assert second in paths(plan) and cross not in paths(plan), plan
apply(plan, small)
print('task/global budgets and minimum lifetime: PASS')

# Sweeps are inert without authorization, reject a changed policy, and catch up only when due.
expired = make('expired')
assert 'disabled' in m.sweep(settings)['status'] and expired.exists()
m.save(m.control() / 'authorization.json', {'policy_sha256': m.digest(settings), 'user_request': 'Set regular cleanup'})
rejects(lambda: m.sweep({**settings, 'keep_days': 8}))
m.sweep(settings)
assert not expired.exists()
assert m.sweep(settings, if_due=True)['status'] == 'not due'
logs = list((root / 'state/artifact-retention').glob('*.log'))
assert logs and 'policy-review' in logs[0].read_text() and 'remove-complete' in logs[0].read_text()
print('standing authorization, due time and durable audit: PASS')

# Foreground wrapper releases success, pins failure, and supplies a real output directory.
args = argparse.Namespace(task='task-b', name='wrapper-success', record='state/tasks/task-b/REPRODUCE.md',
    command=['--', sys.executable, '-c', 'import os,pathlib; pathlib.Path(os.environ["HARNESS_SCRATCH_DIR"],"output").write_text("result")'])
assert m.run_command(args) == 0
args.name = 'wrapper-failure'; args.command = [sys.executable, '-c', 'raise SystemExit(7)']
assert m.run_command(args) == 7
entries = [m.metadata(p) for p in (root / '.local-artifacts/task-b/scratch').iterdir()]
assert any('wrapper-success' in x['path'] and x['status'] == 'released' for x in entries)
assert any('wrapper-failure' in x['path'] and x['status'] == 'pinned' for x in entries)
print('foreground command lifecycle: PASS')

# Scheduler installation is idempotent and preserves unrelated entries. Stub
# crontab/pgrep so tests never modify the workstation's scheduler.
scripts = root / 'scripts'; scripts.mkdir()
for name in ['artifact-retention.py', 'install-artifact-cleanup.sh']:
    shutil.copy2(source / 'scripts' / name, scripts / name)
bin_dir = scratch / 'bin'; bin_dir.mkdir()
cron_file = scratch / 'crontab'; cron_file.write_text('5 2 * * * echo unrelated\n')
(bin_dir / 'crontab').write_text('#!/bin/sh\nif [ "$1" = "-l" ]; then cat "$TEST_CRONTAB"; else cat > "$TEST_CRONTAB"; fi\n')
(bin_dir / 'pgrep').write_text('#!/bin/sh\nexit 0\n')
for p in bin_dir.iterdir(): p.chmod(0o755)
env = {**os.environ, 'PATH': str(bin_dir) + ':' + os.environ['PATH'], 'TEST_CRONTAB': str(cron_file)}
for _ in range(2): subprocess.run(['bash', str(scripts / 'install-artifact-cleanup.sh')], check=True, env=env, capture_output=True)
text = cron_file.read_text()
assert text.count('harness-artifact-retention-') == 1 and 'echo unrelated' in text and '17 */6' in text
cli = subprocess.run([sys.executable, str(scripts / 'artifact-retention.py'), 'check'], check=True, text=True, capture_output=True)
assert json.loads(cli.stdout)['root'] == str(root)
print('scheduler preservation/idempotence and CLI: PASS')
PY
assert_zero "$?" "automatic artifact retention must preserve active work and durable evidence"
exit 0
