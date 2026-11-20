# Ascend Instructions

These instructions cover the Ascend build, deploy, test, and profiling
workflows used by the harness.

Tracked operational files:

- `build-ascend-npu-ir.txt`
- `build-hivmc.txt`
- `clone-repositories.txt`
- `create-pr-gitcode.txt`
- `debug-ir-files.txt`
- `deploy-and-test.txt`
- `docker-setup.txt`
- `extract-bisheng-compiler.txt`
- `permanent-test-env.txt`
- `SIMULATOR_PROFILING.md`
- `machine-inventory.md` (A2/A3 inventory template and non-root access policy)

Local-only file:

- `login-credentials.txt` and any backups of it

Do not copy passwords or tokens into tracked operational notes. Put each
machine's actual access details in the ignored credentials file, and use
`login-credentials.example.txt` as the shareable template.

For newly inventoried A2/A3 machines, read `machine-inventory.md` before
selecting a host. The recorded root access is for account bootstrap only;
perform normal work through your verified personal account.
