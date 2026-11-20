# Codex Debug-Fix Skill

Use this when working an active harness task.

1. Resolve the active task with `bash scripts/bind-session.sh --show`.
2. Read `state/tasks/<task>/REPRODUCE.md`, `meta.yaml`, `LOG.md`, and
   `attempts.md`, `CONSULTATION.md`, and `issues/*/INFO.md` if present.
3. Read the relevant Ascend instruction file before build, deploy, remote
   test, or IR extraction work.
4. Run the pre-fix reproducer when it is configured and safe.
5. Investigate to a specific root cause. Record each distinct approach and its
   outcome in `attempts.md`. After two consecutive failures, complete the
   consulting checkpoint before continuing. Write evidence to `ROOT_CAUSE.md`
   or `issues/<id>/VERDICT.md`.
6. Implement a scoped fix only in paths listed by `meta.yaml.in_scope_paths`.
7. Build/deploy with Ascend scripts when compiler binaries are involved.
8. Run the post-fix command and regression command.
9. Update `LOG.md`.
10. Stage the diff, fill `CRITIQUE.md`, run the reward-hack review, and commit.
11. Run `bash scripts/task/done-check.sh`.

Avoid reading sibling task solution artifacts while the task is open.
