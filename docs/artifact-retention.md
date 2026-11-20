# Disposable artifact retention

Task records preserve the recipe and conclusions; Git preserves source versions.
Neither preserves arbitrary binary inputs or a compiler build by itself. Keep
seeds/shapes, exact source and wheel revisions, commands, settings, summaries,
failure signatures and source hashes in `state/tasks/TASK/`. Pin the few raw
inputs, IR dumps or builds that cannot yet be reproduced or are needed for an
unresolved failure. Save reusable test code in the target repository.

Do not make a complete cumulative source archive after each experiment. Use Git
history, or one baseline plus small incremental backups when commits are not
appropriate. Do not copy a compiler or wheel into every run directory; reference
one versioned copy by its hash. Avoid dumping every tensor/IR/profile unless the
current investigation needs it. Keep scalar results and correctness summaries
even when raw arrays are deleted.

## What expires

Only directories created by `scripts/artifact-retention.py` under
`.local-artifacts/TASK/scratch/RUN/` are eligible. Existing artifacts are **not**
adopted automatically. Records under `state/`, source checkouts, kernel history,
and ordinary `artifact-dir.sh` output are outside the automatic deletion scope.

The reviewed defaults in `artifact-retention.json` are:

| Setting | Default |
| --- | --- |
| Finished scratch lifetime | 7 days |
| Budget for finished scratch per task | 5 GiB |
| Budget for finished scratch across tasks | 20 GiB |
| Minimum time to inspect a finished run | 24 hours |
| Scheduled sweep | Every 6 hours |

The oldest eligible runs go first. These are **soft scratch budgets**, not a
20 GiB cap on the whole artifact tree. Active runs, pinned evidence, the 24-hour
inspection period and legacy files can keep actual usage above the budgets.
`check` lists protected managed runs and planned removals. Review active/pinned
runs when they are no longer needed; a crashed run stays active until released.

## Use for new experiments

Put the reproduction recipe and source revisions in the task record first.
The foreground wrapper holds a lease and provides `HARNESS_SCRATCH_DIR`:

```bash
python3 scripts/artifact-retention.py run \
  --task TASK --name quant-bench \
  --record state/tasks/TASK/REPRODUCE.md -- \
  bash -c 'python /path/to/committed/benchmark.py --output "$HARNESS_SCRATCH_DIR"'
```

Successful commands release their scratch. Failed commands pin it; interrupted
wrappers leave it active. The wrapper records command/exit status but **does not
capture stdout or save experiment results for you**. The command must write its
logs and result summary to the task records before returning. Do not launch
detached/background work inside the wrapper. For multi-step experiments:

```bash
scratch=$(python3 scripts/artifact-retention.py create --task TASK --name quant-bench)
# Write disposable output into "$scratch". Finish ALL producers/consumers.
# Save result summaries, exact inputs/seeds and source/reproduction details.
python3 scripts/artifact-retention.py release "$scratch" \
  --record state/tasks/TASK/REPRODUCE.md
python3 scripts/artifact-retention.py pin "$scratch"    # preserve needed evidence
python3 scripts/artifact-retention.py unpin "$scratch"  # allow expiry again
```

Release is an explicit assertion that the output is disposable and its useful
records are saved. A nonempty task record is required. No script can infer
whether the written recipe actually captures every experiment parameter.
Never place the only copy of source code, a raw result needed as proof, or an
irreplaceable input in released scratch. Use pins until evidence is durable.

## Review, authorization and scheduling

Automatic cleanup is disabled on a fresh clone. Review the policy, then record
the user's authorization for recurring cleanup of this scope:

```bash
cat artifact-retention.json
python3 scripts/artifact-retention.py policy-hash
python3 scripts/artifact-retention.py authorize \
  --policy-sha256 REVIEWED_HASH --user-request 'Exact user authorization'
bash scripts/install-artifact-cleanup.sh
python3 scripts/artifact-retention.py sweep
```

The installer preserves other cron entries and does not start a private daemon.
The OS cron service must run. On WSL without systemd, start it using
`sudo service cron start`; to start it after WSL restarts, add
`command=service cron start` to `/etc/wsl.conf`'s `[boot]` section, preserving
any existing boot command. Do not restart WSL just to apply that setting during
ongoing work. Session binding and artifact-directory requests also perform a
sweep when due, covering sleep/restart gaps. Changing the policy invalidates
authorization until the new limits have been reviewed. Disable automatic
deletion by removing `.local-artifacts/.retention/authorization.json`; remove
the crontab line bearing this checkout's `harness-artifact-retention` marker
to remove the schedule.

Every automatic sweep writes a plan, reviews it against the authorized policy,
then applies it under the global cleanup lock. It checks leases, same-user
process file descriptors/cwd/mappings, changed file identities, path boundaries,
ownership and symlinks. It skips uninspectable or changed runs, active runs,
pins, source repositories, special files and nested filesystems. No process is
stopped. A cleanup crash may leave a partially deleted disposable directory;
remove-start/completion records identify what happened.

Durable monthly audit logs are in `state/artifact-retention/`. They contain the
authorization, reviewed plans, removals and errors. Only the latest plan/result
and sweep time are kept in `.local-artifacts/.retention/`; no backup of deleted
data is made. The audit log is metadata, not a second tensor/archive collection.

For a manual review:

```bash
python3 scripts/artifact-retention.py check
python3 scripts/artifact-retention.py plan \
  --manifest .local-artifacts/.retention/review-001.json
# Read that manifest. The plan command prints its review hash.
python3 scripts/artifact-retention.py apply \
  --manifest .local-artifacts/.retention/review-001.json \
  --reviewed-sha256 REVIEWED_PLAN_HASH
```

Legacy archives require a separate reviewed cleanup. Do not auto-register or
delete them by filename or age: some contain the only surviving sources or
correctness results. The existing `state-retention.py` remains an independent,
manual tool for misplaced outputs under `state/`; it is not scheduled.
