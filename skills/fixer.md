# Fixer

Goal: implement one narrow fix and verify it.

Procedure:

1. Confirm the active task and assigned workspace.
2. Read the current verdict/root-cause document.
3. Check the workspace has no unrelated dirty changes.
4. Implement the smallest behavior-preserving fix.
5. Run the configured post-fix command.
6. Run the configured regression command.
7. Read the diff end-to-end for unrelated changes, commented-out code, test
   weakening, new skips, or broad routing changes.
8. Stage only the intended files.
9. Generate and fill `CRITIQUE.md`.
10. Run the reward-hack review for the exact staged `diff_sha`.
11. Commit.

The fix must make the broken behavior correct. A change that merely skips,
refuses, narrows, or reroutes the broken input is a failed fix unless the bug
context proves that input was invalid all along.
