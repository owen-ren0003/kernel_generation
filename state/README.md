# Local task state

Task Markdown, logs and required metadata are the durable record. All runtime
state except this README is ignored by Git because it can include internal
ticket details, host information, credentials in historical output, and large
logs. A new clone creates task directories as needed.

Keep Markdown, plain-text records/test lists, raw and compressed logs, YAML,
task/issue JSON metadata, fix indexes, review records and lifecycle markers.
Session bindings, grants and build-tracker bookkeeping are also retained.

Do not accumulate compiler executables, wheels, vendor repositories, cached
objects, generated IR, profiling databases, archives or captured tensors here.
Use the assigned checkout or `.local-artifacts/<task-id>/` instead. The path
can be obtained with `bash scripts/artifact-dir.sh` and must be in task scope.

REPRODUCE.md and LOG.md must record enough source, environment, input-generation
and build/run detail to regenerate disposable files. Where a historical
cleanup retained task-owned code in SOURCE-SNAPSHOTS.md, restore that code
outside state and adapt the historical paths before rerunning it. A snapshot
is not proof that every historical environment or input remains recoverable.

Storage checks never delete anything:

```bash
python3 scripts/state-retention.py --check
python3 scripts/state-retention.py --check --task TASK_ID
```

After reviewing scope and obtaining authorization to delete the listed files:

```bash
python3 scripts/state-retention.py --plan --manifest .local-artifacts/cleanup.json
python3 scripts/state-retention.py --apply --manifest .local-artifacts/cleanup.json
python3 scripts/state-retention.py --verify --manifest .local-artifacts/cleanup.json
```

The manifest records exact paths and file identities. Apply revalidates the
keep-list, refuses unsafe parent paths, skips files that changed or were open
when cleanup started, retains small task-owned sources in Markdown, and
removes only inventoried files and empty subdirectories. Symlink targets are
never traversed. Its result report records skipped paths and any missing
protected records. Removal is permanent; the manifest is an audit record,
not a backup. Other active sessions can create new files during an audit, so
recheck afterward and review a new manifest for any subsequent cleanup.
`--verify` checks the original deletion manifest and reports any later
recreations separately. It does not replace `--check`, which still reports
all currently present disposable files, including new output from other work.

For automatic retention of new experiment scratch outside state, see
[artifact retention](../docs/artifact-retention.md). Its monthly audit logs
under `state/artifact-retention/` are durable records. Automatic cleanup never
applies this state-only cleanup tool or removes task records.
