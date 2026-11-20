# Collecting Ascend Op-Simulator Profiling Data for One Kernel

This is an English runbook translated from `creating simulator.mp4`. The
recording demonstrates an SWA backward `dkdv` Triton kernel on
`simulator-npu.example.org`; the method applies to other kernels as well.

The important idea is to profile a standalone program that launches exactly
one kernel. Do not put the complete workload under the simulator: it launches
unrelated kernels, makes the simulator much slower, and produces unnecessarily
large output.

## Workflow at a glance

1. At the target kernel's real call site, save every runtime input with
   `torch.save`.
2. Run the normal workload once to produce the `.pt` input file.
3. Write a small Python runner that loads that file and launches only the target
   kernel with the same grid, arguments, constexpr values, and required compile
   options.
4. Check that the standalone runner works without the profiler.
5. Run it through `msprof op simulator`.
6. For a long-running simulation, export one core from the live
   `device0/tmp_dump` before interrupting the producer.
7. Preserve both `simulator/trace.json` and `simulator/visualize_data.bin`.
   Open `trace.json` in Perfetto/Chrome, or `visualize_data.bin` in MindStudio
   Insight.

## Prerequisites

- Use the same repository revision, Python environment, Triton/Ascend compiler,
  and kernel options that produced the behavior you want to inspect.
- `msprof` must be available in the shell environment.
- Determine the correct SoC string for the installed toolchain. The recording
  uses `Ascend950PR_9599`; do not assume that value is correct for another
  environment.
- Use a writable output directory with ample free disk space. The recording
  shows simulator directories growing to tens of gigabytes.
- Use Perfetto or Chrome for the JSON timeline. Install MindStudio Insight only
  when the full `visualize_data.bin` views are required.

Before starting a long run, make these checks:

```bash
command -v msprof
msprof op simulator --help
df -h .
```

On `simulator host`, `msprof` is initialized by the login-shell environment. The
validated setup was:

```bash
source /home/npu-user/preload_fwa/env.sh
command -v python3
command -v msprof
```

If `msprof` is missing from a non-login SSH command, execute the command with
`bash -lc '...'` and source that environment file inside the quoted command.

## 1. Capture the kernel's exact runtime inputs

Find the point immediately before the target kernel is launched. Build a
dictionary containing everything needed to reproduce that launch:

- all tensor arguments;
- scalar and boolean arguments;
- explicit strides passed to the kernel;
- shape-derived values;
- the launch grid;
- constexpr/meta parameters such as block sizes; and
- any compiler options that must be reproduced by the isolated launch.

The pattern used in the recording is:

```python
grid = (...,)

kernel_data = {
    "input": input_tensor,
    "output": output_tensor,
    "input_s0": input_tensor.stride(0),
    "input_s1": input_tensor.stride(1),
    "problem_size": problem_size,
    "BLOCK_SIZE": BLOCK_SIZE,
    "grid": grid,
}

torch.save(kernel_data, "/absolute/path/target_kernel_data.pt")

target_kernel[grid](
    input_tensor,
    output_tensor,
    input_tensor.stride(0),
    input_tensor.stride(1),
    problem_size,
    BLOCK_SIZE,
    # The real launch's compiler options, if any.
)
```

The names in the dictionary are arbitrary, but the saved values must match the
values used by the launch directly below it. Prefer an absolute output path so
there is no ambiguity about where the `.pt` file is written.

The recording's SWA example saved the tensors, all input strides, mask sizes,
window sizes, head counts, `BLOCK_D`, and `grid` to
`swa_bwd_dkdv_data.pt` immediately before `_swa_bwd_dkdv_kernel[grid](...)`.

![Input capture at the real kernel call site](screenshots/01-dump-kernel-inputs.png)

## 2. Run the normal workload once

Run the workload or test that reaches the instrumented call site. The recording
used this command while also requesting Triton compiler dumps:

```bash
TRITON_KERNEL_DUMP=1 \
TRITON_DUMP_DIR=./cache_output_split \
TRITON_DEBUG=1 \
TRITON_ALWAYS_COMPILE=1 \
pytest -sv mojo_opset/tests/accuracy/functions/test_attention.py::test_swa_function_perf
```

The `TRITON_*` variables are useful when compiler artifacts are also wanted;
the `.pt` input capture itself comes from the inserted `torch.save` call.

Confirm that the captured file exists and is non-empty:

```bash
ls -lh /absolute/path/target_kernel_data.pt
```

Avoid repeatedly overwriting the capture if the call site executes multiple
times. Select the invocation whose shapes and options correspond to the case
you want to profile.

## 3. Create a one-kernel runner

Write a small Python program that imports the kernel, loads the captured data,
unpacks it, and performs the same launch. It must not invoke the complete model
or test.

```python
import torch

from your_package import target_kernel


if __name__ == "__main__":
    data = torch.load("/absolute/path/target_kernel_data.pt")

    input_tensor = data["input"]
    output_tensor = data["output"]
    grid = data["grid"]

    target_kernel[grid](
        input_tensor,
        output_tensor,
        data["input_s0"],
        data["input_s1"],
        data["problem_size"],
        data["BLOCK_SIZE"],
        # Reproduce required compiler options here.
    )
```

The SWA example loads `swa_bwd_dkdv_data.pt`, restores all saved variables, and
launches only `_swa_bwd_dkdv_kernel`.

![Standalone runner loading and launching one kernel](screenshots/02-standalone-kernel-runner.png)

Run this script once without `msprof` and fix import, device, argument-order,
grid, or compiler errors before starting the much slower simulation:

```bash
python3 /path/to/target_kernel_runner.py
```

## 4. Start op-simulator profiling

Generic form:

```bash
msprof op simulator \
  --soc-version="${SOC_VERSION}" \
  --kernel-name="${KERNEL_NAME}" \
  --output="${PROFILE_DIR}" \
  python3 "${RUNNER}"
```

The exact example shown in the recording is:

```bash
msprof op simulator \
  --soc-version=Ascend950PR_9599 \
  --kernel-name=_swa_bwd_dkdv_kernel \
  --output=./perf_swa_bwd_dkdv_preload_0714/ \
  python3 mojo_opset/tests/accuracy/functions/perf_swa_bwd_dkdv_kernel.py
```

Use the compiled kernel name, including a leading underscore when present.

![The exact msprof command from the recording](screenshots/03-msprof-simulator-command.png)

## 5. Export a usable snapshot from a long simulation

Simulation is extremely slow. The presenter notes that roughly two hours may
produce only 30–50 microseconds of timeline data. Let it run long enough to
capture a useful region, while watching both free space and output growth from
a second shell:

```bash
df -h "${PROFILE_DIR}"
du -h --max-depth=1 "${PROFILE_DIR}"
find "${PROFILE_DIR}" -type d -path '*/device0/tmp_dump' -print
```

The growing raw trace is under a path like:

```text
${PROFILE_DIR}/OPPROF_<timestamp>_<suffix>/device0/tmp_dump
```

Do not interrupt the live simulator before exporting the data you want to
keep. In another shell, export a selected core from the current `tmp_dump`:

```bash
msprof op simulator \
  --soc-version="${SOC_VERSION}" \
  --core-id=0 \
  --export="${PROFILE_DIR}/OPPROF_<timestamp>_<suffix>/device0/tmp_dump"
```

The recording used `--core-id=0` so the export did not process every core. Once
the export has completed and a non-empty visualization file exists, the live
producer can be stopped if enough timeline has been captured.

## 6. Locate and validate the result

Successful output includes core timing rows and a message similar to:

```text
[INFO] Core operator results run in simulator as follows:
core_name        duration_time(us)  running_time(us)
core0.cubecore0  ...                ...
core0.veccore0   ...                ...
core0.veccore1   ...                ...
[INFO] Profiling results saved in .../OPPROF_<timestamp>_<suffix>
[INFO] Profiling data parse finished.
```

Find both visualization payloads with:

```bash
find "${PROFILE_DIR}" -type f \( \
  -path '*/simulator/trace.json' -o \
  -path '*/simulator/visualize_data.bin' \) \
  -printf '%s bytes  %p\n'
```

Preserve these top-level files together:

```text
OPPROF_<timestamp>_<suffix>/simulator/trace.json
OPPROF_<timestamp>_<suffix>/simulator/visualize_data.bin
```

Per-core `trace.json`, `core*_instr_exe.csv`, and `core*_code_exe.csv` files
should also be retained when present. Use the top-level `simulator/trace.json`
for the combined pipeline view.

The recording also shows warnings about a missing `pc_start_addr.txt`, missing
`debug_line` information, an empty code call stack, and missing code-info files.
Those warnings did not prevent core timings or `visualize_data.bin` from being
created. If source/call-stack correlation is required, follow the warning and
recompile the kernel with debug information (the message specifically suggests
the `-g` option).

![Successful export and saved profiling result](screenshots/05-exported-profile-results.png)

## 7. Inspect the timeline

### Perfetto

Open <https://ui.perfetto.dev>, choose **Open trace file**, and select the
top-level `simulator/trace.json`. Use W/S to zoom and A/D to pan.

### Chrome or Edge tracing

Open `chrome://tracing` or `edge://tracing` and load the same top-level
`trace.json`.

### MindStudio Insight

Copy `visualize_data.bin` to the workstation running MindStudio Insight, choose
**Import Data**, and open the timeline. The recording shows tracks for the
scalar, flow-control, MTE, cube, vector, and related pipelines.

![Simulator timeline in MindStudio Insight](screenshots/04-mindstudio-timeline.png)

### Why a `.bin` may also appear to work in Perfetto

Do not confuse `visualize_data.bin` with a compiled kernel `.bin`/`.npubin`
ELF. A compiled kernel executable is not a visualization trace.

The retained CANN 9.1.0.B060 validation `visualize_data.bin` uses a 12-byte
container header followed by an embedded Chrome JSON trace. Its first eight
bytes encode the trace length as a little-endian integer; the JSON begins at
offset 12. In that validated file, the embedded bytes are exactly identical to
the adjacent top-level `trace.json`. This explains why some Perfetto or legacy
trace-viewer versions may accept the `.bin` directly. That direct behavior is
not the portable interface, so preserve and prefer the generated `trace.json`.

If only a `visualize_data.bin` from this verified framing remains, extract and
validate its embedded trace as follows:

```bash
python3 - /path/to/visualize_data.bin /path/to/trace.json <<'PY'
import json
import sys
from pathlib import Path

source = Path(sys.argv[1]).read_bytes()
length = int.from_bytes(source[:8], "little")
trace = source[12:12 + length]
if len(trace) != length:
    raise SystemExit("truncated visualization container")
json.loads(trace)
Path(sys.argv[2]).write_bytes(trace)
PY
```

Treat the 12-byte layout as CANN-version-specific: validate the resulting JSON
instead of assuming every future `visualize_data.bin` has the same framing.

## Common failure modes

- **The profile contains many unrelated kernels:** the full workload was used
  instead of a one-kernel runner.
- **The requested kernel is never captured:** verify the exact compiled kernel
  name and confirm that the standalone script reaches that launch.
- **The runner fails before profiling:** compare every argument, stride,
  constexpr, grid dimension, and compiler option with the original call site.
- **The output consumes disk space rapidly:** monitor `du`/`df`, export only the
  required core, and stop only after preserving a valid snapshot.
- **There is no `visualize_data.bin` after stopping:** export the live
  `device0/tmp_dump` before terminating the producer.
- **Perfetto rejects `visualize_data.bin`:** load the accompanying top-level
  `trace.json`, or use the validated extraction procedure above when that JSON
  was not retained.
- **The timeline has no source mapping:** rebuild with debug information; the
  simulator trace can still be valid without source/call-stack metadata.

## Recording-specific notes that are not generic requirements

The Q&A after the demonstration discusses a particular SWA experiment: using
the requested PR stack and latest kernel version, making previously agreed
fixed-length/shape adjustments, and enabling preload in the compiler Python
layer. The presenter says the operator's other options were not changed and
that preload was already enabled in the then-current base. These details should
not be copied to an unrelated kernel without checking its intended revision and
configuration.

## Validation status

The procedure was translated from the recording and validated end to end on
`simulator host` on 2026-07-21 with the included
[`simple_add_kernel.py`](simple_add_kernel.py). The native launch first printed
`simple_add_kernel: PASS`. The simulator invocation was:

```bash
msprof op simulator \
  --soc-version=Ascend950PR_9599 \
  --kernel-name=simple_add_kernel \
  --launch-count=1 \
  --output=./profile \
  --timeout=15 \
  python3 simple_add_kernel.py
```

`msprof` selected only `simple_add_kernel`, profiled `core0.veccore0`, and
reported 1.54 microseconds duration and 1.27 microseconds running time. Parsing
completed and produced a 129,308-byte `visualize_data.bin` and a 67,752-byte
top-level `trace.json`. That JSON is embedded byte-for-byte at offset 12 of
this validation `.bin`. The copied profile, full log, exact commands, and
checksum are under
[`validation-129/`](validation-129/README.md).

After the script printed `PASS`, its child process emitted `double free or
corruption (out)` and was killed with signal 6. `msprof` warned about the child
failure but continued parsing successfully; the timing rows, trace files, and
non-empty visualization payload were all present. Treat this as a post-run
cleanup warning for this environment, but always verify the parsed output
rather than assuming a warning is harmless.

This short kernel completed automatic parsing, so the live `tmp_dump` export
path in section 5 was not needed during this smoke test. That path remains the
recording's procedure for a long-running simulation.
