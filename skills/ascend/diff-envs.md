# Skill: Diff envs when one reproduces and another doesn't

When the same binaries produce a different result in two environments,
the binaries are probably running through different code paths. Diff
the envs BEFORE concluding what's "buggy".

## Why this matters

Failure mode of past investigations: claim "binary X is buggy" based on
"binary X fails here, binary Y passes there." This skips the question
of whether X and Y were even invoked the same way. Two runs with
identical binaries can route through different compiler paths if:

- A different `.ttadapter` reaches `bishengir-compile`
- A different cmd_list is constructed by triton-ascend
- A different chip target is selected (`--target=Ascend950PR_957c` vs
  `_9579`)
- BISHENG_INSTALL_PATH points to a different `hivmc-a5`

Until those are matched, "X is the trigger" is speculation.

## NPU device state is a variable too

A failing test on a single device after many prior failed runs is NOT
evidence about the binary. Failed kernels can leave the NPU in a
corrupted state (`dcmi module initialize failed. ret is -8005`,
`507035 vector core exception`, etc.). All subsequent kernels on that
device — including the known-good baseline — will fail until the device
is reset.

**Symptom checklist**:
- Test that previously passed now fails on the same device.
- The known-good 0428 baseline binary fails too on the same device.
- A different NPU device (`ASCEND_RT_VISIBLE_DEVICES=0` instead of `=4`)
  with the same binary passes.

**Action when corruption suspected**:
1. Switch `ASCEND_RT_VISIBLE_DEVICES` to an unused device.
2. Re-run the known-good baseline — confirm it passes.
3. Then re-run your fix on the new device.
4. Document which device(s) are corrupted; flag for restart.

Do NOT attribute device-state failures to the binary you're testing.
Past sessions have wasted hours diagnosing a "fix regression" that was
in fact NPU corruption from earlier binary tests.

## Variables to capture from each env

```bash
# Inside the container or shell where the test runs:

# Wheel versions (the silent triggers — older/newer often emit
# different cmd_list and different .ttadapter for the same kernel)
python3 -c "import importlib.metadata as m; print('triton-ascend:', m.version('triton-ascend'))"
python3 -c "import torch; print('torch', torch.__version__)"
python3 -c "import torch_npu; print('torch_npu', torch_npu.__version__)"

# CANN + driver
echo "ASCEND_TOOLKIT_HOME=$ASCEND_TOOLKIT_HOME"
ls -l /data/pri/Ascend/latest 2>&1
cat /usr/local/Ascend/driver/version.info | head -3

# Python
which python3 && python3 --version

# Compile cmd_list (run with TRITON_PRINT_AUTOTUNING=1 and grep)
TRITON_PRINT_AUTOTUNING=1 python3 run_test.py 2>&1 | grep -F "DEBUG] cmd_list:"

# .ttadapter that Triton actually emits (the input to bishengir-compile)
for f in ~/.triton/cache/*/*.ttadapter; do cp "$f" /tmp/cap_$(basename $(dirname $f)).mlir; done

# Effective NPUOptions / metadata
cat ~/.triton/cache/*/*kernel_persistent.json | python3 -m json.tool | \
  grep -E 'parallel_mode|compile_mode|mix_mode|force_simt_template|enable_mixed_cv|target|arch'

# Library / search paths
echo "$LD_LIBRARY_PATH" | tr : '\n'
echo "BISHENG_INSTALL_PATH=$BISHENG_INSTALL_PATH"
```

Run that on BOTH the failing env and the passing env. `diff` the
captured files.

## Reading the diff

If the **`.ttadapter` differs (after stripping `loc(...)` lines)**:
the frontend is producing different IR. The bug isn't in the binary
— at least not as a "binary X is broken" claim. It's in the
interaction between the frontend's IR generation and that binary.

If the **cmd_list differs**: triton-ascend is calling
`bishengir-compile` with different flags. Even with identical
binaries, different flags route through different compile paths.

If those are identical and the **binary output (npubin md5) still
differs**: the binary is non-deterministic w.r.t. some input we
haven't captured (env vars, working dir, parent PID). Strip more
variables until you find the one that flips the result.

## How to phrase conclusions

| Evidence | Use |
|---|---|
| Two envs differ in many ways; one fails | "the failure correlates with X" |
| One variable changes, pass/fail flips | "X is the trigger" |
| You haven't done the diff yet | don't claim a cause |

`is the trigger` requires demonstrating that flipping a single
variable (with all else held constant) flips the test result. Until
then, use `correlates with` or `consistent with` and keep digging.

## When to apply this skill

- You have one env where the test fails and another where it passes.
- You're about to write `VERDICT.md` saying "binary X is buggy".
- A user asks "what's different between these envs?".
- You're tempted to say `is the cause` based on one observation.
