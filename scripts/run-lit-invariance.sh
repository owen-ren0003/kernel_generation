#!/usr/bin/env bash
# scripts/run-lit-invariance.sh
#
# Master-integration gate 4 for the dcache-stack-overflow fix (and any
# future fix that adds a TritonGPU-dialect rewriting pass).
#
# Iterates a corpus of cached TTIRs through `bishengir-compile` and
# verifies:
#   (a) zero crashes / zero verifier errors over the whole corpus;
#   (b) for kernels NOT in the dcache-target families (var_mean,
#       upsample, addmm), no `ttgext.thread_local_alloc` op gets emitted
#       — i.e. the matchLoop predicate did not fire.
#
# This is the gate that would have caught the SDPA fix's order-dependent
# regression (commit 6d3342d, rolled back 2026-05-04). Run it with
# `--ws master` after a master-stack cherry-pick + build, or with
# `--ws ws1` to validate before the cherry-pick.
#
# Three exit-code-non-zero classes from bishengir-compile, distinguished
# in this runner:
#   - STACK    — controlled "SIMT warp stack size ... exceeds limit"
#                diagnostic. Expected on master baseline for the three
#                dcache-target kernels (var_mean, upsample, addmm).
#                Counted as PASS for gate purposes — the IR pipeline
#                ran cleanly; it's the device-codegen step that
#                bailed because the stack budget was already exceeded
#                before the fix.
#   - CRASH    — segfault / assertion / verifier error / malformed-IR.
#                Hard fail, exits 2.
#   - OTHER    — any other non-zero exit. Treated as fail (exit 2)
#                until proven benign.
#
# Usage:
#   scripts/run-lit-invariance.sh --ws <name> [--corpus DIR] [--keep-logs]
#
# Exit codes:
#   0 — all corpus entries compiled cleanly (or hit only the expected
#       STACK diagnostic on the three target kernels); no unexpected
#       rewrites.
#   1 — usage / setup error (binary missing, corpus empty, ...).
#   2 — at least one TTIR crashed bishengir-compile (CRASH or OTHER),
#       or the STACK diagnostic surfaced on a non-target kernel.
#   3 — at least one TTIR was rewritten by the new pass when it
#       shouldn't have been (i.e. emitted ttgext ops outside the
#       known target families).

set -uo pipefail

HARNESS_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$HARNESS_ROOT/scripts/_lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/run-lit-invariance.sh --ws <name> [--corpus DIR] [--keep-logs]

  --ws NAME       Workspace whose binary to test. Resolved as:
                    $work_dir/<ws>/AscendNPU-IR-Dev/build-{master,dev}/bin/bishengir-compile
                  (build-master if ws=="master", build-dev otherwise).
  --corpus DIR    Override the corpus location. Default:
                    .local-artifacts/<task_id>/lit-invariance-corpus/
                  (or the task's configured artifact_dir).
  --keep-logs     Don't delete the per-TTIR stderr logs after the run.
                  Default: keep only failing logs.
EOF
}

WS=""
CORPUS_OVERRIDE=""
KEEP_LOGS=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --ws)        WS=$2; shift 2 ;;
    --corpus)    CORPUS_OVERRIDE=$2; shift 2 ;;
    --keep-logs) KEEP_LOGS=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           echo "Unknown arg: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z $WS ]]; then
  echo "ERROR: --ws is required" >&2
  usage
  exit 1
fi

# Resolve the binary. master uses build-master/, every other ws uses
# build-dev/. Mirrors the convention in build-binaries.sh.
WS_DIR=$(ws_path "$WS")
if [[ $WS == master ]]; then
  BUILD_DIR="$WS_DIR/AscendNPU-IR-Dev/build-master"
else
  BUILD_DIR="$WS_DIR/AscendNPU-IR-Dev/build-dev"
fi
BIN="$BUILD_DIR/bin/bishengir-compile"

if [[ ! -x $BIN ]]; then
  echo "ERROR: bishengir-compile not found or not executable: $BIN" >&2
  exit 1
fi

# bishengir-compile shells out to several siblings via $PATH for the
# final device-codegen step:
#   - hivmc-a5         (BiShengIR -> HIVM lowering)
#   - bisheng / lld    (LLVM -> NPU object code)
# Per the Stage-5 reproduction recipe in
# state/tasks/2026-04-30-flaggems-206-run/issues/dcache-stack-overflow/STAGE-5-CAPTURES-VERIFIED.md,
# these live in three different places:
#   $work_dir/bisheng_compiler/bisheng_compiler/bin            (bisheng + lld)
#   $work_dir/<ws>/hivmc/build-{master,dev}/install/bin        (hivmc-a5)
#   $work_dir/<ws>/AscendNPU-IR-Dev/build-{master,dev}/bin     (bishengir-compile)
# Falls back to $work_dir/<ws>/stage/bin/ if the install dir isn't built
# (build-binaries.sh stages every binary under stage/bin/).
WORK_DIR=$(work_dir)
BISHENG_BIN="$WORK_DIR/bisheng_compiler/bisheng_compiler/bin"
if [[ $WS == master ]]; then
  HIVMC_INSTALL_BIN="$WS_DIR/hivmc/build-master/install/bin"
else
  HIVMC_INSTALL_BIN="$WS_DIR/hivmc/build-dev/install/bin"
fi
STAGE_BIN="$WS_DIR/stage/bin"

if [[ -x "$HIVMC_INSTALL_BIN/hivmc-a5" ]]; then
  HIVMC_SRC="$HIVMC_INSTALL_BIN/hivmc-a5"
  HIVMC_DIR="$HIVMC_INSTALL_BIN"
elif [[ -x "$STAGE_BIN/hivmc-a5" ]]; then
  HIVMC_SRC="$STAGE_BIN/hivmc-a5"
  HIVMC_DIR="$STAGE_BIN"
else
  echo "ERROR: hivmc-a5 not found under $HIVMC_INSTALL_BIN or $STAGE_BIN" >&2
  exit 1
fi

if [[ ! -x "$BISHENG_BIN/bisheng" ]]; then
  echo "ERROR: bisheng compiler not found under $BISHENG_BIN" >&2
  exit 1
fi

export BISHENG_INSTALL_PATH="$WORK_DIR/bisheng_compiler/bisheng_compiler"
export PATH="$BISHENG_BIN:$HIVMC_DIR:$PATH"

# Resolve the corpus.
if [[ -n $CORPUS_OVERRIDE ]]; then
  CORPUS="$CORPUS_OVERRIDE"
else
  CORPUS="$(task_artifact_dir)/lit-invariance-corpus"
fi

if [[ ! -d $CORPUS ]]; then
  echo "ERROR: corpus directory not found: $CORPUS" >&2
  exit 1
fi

# Sorted list of *.ttir.mlir files (alphabetical = numeric prefix order).
mapfile -t TTIRS < <(find "$CORPUS" -maxdepth 1 -name '*.ttir.mlir' | sort)

if [[ ${#TTIRS[@]} -eq 0 ]]; then
  echo "ERROR: no *.ttir.mlir files in $CORPUS" >&2
  exit 1
fi

# Per-run log directory. Kept under /tmp so multiple ws runs in the
# same session don't stomp each other.
RUN_TS=$(date -u +%Y%m%dT%H%M%SZ)
RUN_DIR="/tmp/lit-invariance-${WS}-${RUN_TS}"
mkdir -p "$RUN_DIR"

# Kernels for which the dcache pass IS expected to fire. Anything outside
# this list that emits ttgext.* ops trips exit 3 (false-positive
# matcher). Match by substring of the corpus filename — robust to
# numeric prefixes and the .ttir.mlir suffix.
EXPECTED_REWRITE_PATTERNS=(
  var_mean_welford_kernel
  upsample_bicubic2d_aa_kernel
  addmm_kernel
)

# Common bishengir-compile flags (per the gate-4 recipe in
# MASTER-INTEGRATION-PLAN.md §2 gate 4).
COMMON_FLAGS=(
  --enable-triton-ir-compile
  --pure-simt
  --num-warps=4
  --threads-per-warp=32
  --target=Ascend910_9589
  --simt-stack-limit=4096
  --mlir-print-ir-after-all
)

echo "lit-invariance run"
echo "  ws         : $WS"
echo "  binary     : $BIN"
echo "  bin md5    : $(md5sum "$BIN" | awk '{print $1}')"
echo "  hivmc-a5   : $HIVMC_SRC"
echo "  corpus     : $CORPUS"
echo "  num TTIRs  : ${#TTIRS[@]}"
echo "  log dir    : $RUN_DIR"
echo "  flags      : ${COMMON_FLAGS[*]}"
echo

PASS_COUNT=0
STACK_COUNT=0
FAIL_COUNT=0
REWRITE_COUNT=0
UNEXPECTED_REWRITE_COUNT=0
UNEXPECTED_STACK_COUNT=0

# Print a fixed-width header for the summary table.
printf '%-46s %-6s %-9s %-9s %s\n' "TTIR" "STATUS" "REWRITE?" "EXPECTED" "NOTE"
printf '%s\n' "$(printf '%.0s-' {1..100})"

for ttir in "${TTIRS[@]}"; do
  name=$(basename "$ttir")
  # Strip leading "NN-" prefix and trailing ".ttir.mlir" for matching
  # against EXPECTED_REWRITE_PATTERNS.
  stripped=${name#[0-9][0-9]-}
  stripped=${stripped%.ttir.mlir}

  expected="no"
  for pat in "${EXPECTED_REWRITE_PATTERNS[@]}"; do
    if [[ $stripped == *"$pat"* ]]; then
      expected="yes"
      break
    fi
  done

  ir_log="$RUN_DIR/${name%.ttir.mlir}.ir.log"
  out_bin="$RUN_DIR/${name%.ttir.mlir}.bin"

  # Run in a subshell with job control disabled so that bash's own
  # "Aborted (core dumped)" diagnostic on a SIGABRT doesn't leak past
  # the 2>ir_log redirect into our terminal. --mlir-print-ir-after-all
  # goes to stderr along with diagnostics; we redirect 2>ir_log. No
  # `set -e` — every failing command below would otherwise abort
  # mid-corpus and lose the summary table.
  ( set +m; "$BIN" "$ttir" "${COMMON_FLAGS[@]}" -o "$out_bin" ) >/dev/null 2>"$ir_log"
  rc=$?

  # Detect rewrite: ttgext.* ops only show up in the IR after the new
  # pass (Stage 2/3 in the dcache fix's design). On master baseline this
  # token never appears. `grep -q` returns 1 when no match, which is fine.
  if grep -q "ttgext\." "$ir_log" 2>/dev/null; then
    rewrite="yes"
    REWRITE_COUNT=$((REWRITE_COUNT + 1))
  else
    rewrite="no"
  fi

  # Classify the failure kind. The "SIMT warp stack size ... exceeds
  # limit" line is the controlled diagnostic the gate-4 recipe asks for
  # via --simt-stack-limit=4096; it indicates the IR pipeline ran fine
  # and the device-codegen step bailed because the kernel's stack
  # frame was already over budget BEFORE any new pass would have run.
  # That's expected on the dcache target kernels on master baseline.
  is_stack_diag=0
  if grep -qE "SIMT warp stack size .* exceeds limit" "$ir_log" 2>/dev/null; then
    is_stack_diag=1
  fi

  # CRASH means a hard process abort or verifier failure. Note we
  # deliberately do NOT match "assert" alone — `tt.assert %true ...`
  # appears in many IR dumps and is benign dead-code.
  is_crash=0
  if grep -qE "Aborted \(core dumped\)|Segmentation fault|UNREACHABLE executed|LLVM ERROR|fatal error: error in backend|verifier '.+' op" "$ir_log" 2>/dev/null; then
    is_crash=1
  fi

  # int32-overflow assert that the compiler statically proves and bails
  # on. Indicates the cached TTIR was captured from a context whose
  # index dtype doesn't fit; the kernel is unbuildable on master baseline
  # regardless of any new pass. Treated like STACK — a known controlled
  # bail-out. Detected by the bisheng frontend-error footer that follows
  # the assert.
  is_int32_assert=0
  if grep -q "tt.assert %true" "$ir_log" 2>/dev/null \
      && grep -qE "exit code 70|Failed to compile BiShengLIR for device" "$ir_log" 2>/dev/null \
      && [[ $is_stack_diag -eq 0 ]]; then
    is_int32_assert=1
  fi

  note=""
  status="PASS"
  if [[ $rc -eq 0 ]]; then
    PASS_COUNT=$((PASS_COUNT + 1))
    if [[ $rewrite == "yes" && $expected == "no" ]]; then
      UNEXPECTED_REWRITE_COUNT=$((UNEXPECTED_REWRITE_COUNT + 1))
      note="UNEXPECTED rewrite"
    fi
  elif [[ $is_crash -eq 1 ]]; then
    status="CRASH"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    note=$(grep -E "Aborted \(core dumped\)|Segmentation fault|UNREACHABLE executed|LLVM ERROR|fatal error: error in backend|verifier '.+' op" "$ir_log" | head -n 1 | cut -c1-60)
  elif [[ $is_stack_diag -eq 1 ]]; then
    status="STACK"
    if [[ $expected == "yes" ]]; then
      # Expected on master baseline for the three dcache target kernels.
      # Counts as PASS for the gate (the IR pipeline ran cleanly).
      PASS_COUNT=$((PASS_COUNT + 1))
      STACK_COUNT=$((STACK_COUNT + 1))
      note=$(grep -oE "SIMT warp stack size [^[:space:]]+ \* [^[:space:]]+ = [0-9]+" "$ir_log" | head -n 1)
    else
      # Stack diagnostic on a kernel we DIDN'T expect to trip the
      # budget is a real regression — the new pass changed the
      # codegen for an unrelated kernel. Report as a failure.
      UNEXPECTED_STACK_COUNT=$((UNEXPECTED_STACK_COUNT + 1))
      FAIL_COUNT=$((FAIL_COUNT + 1))
      note="UNEXPECTED stack-overflow"
    fi
  elif [[ $is_int32_assert -eq 1 ]]; then
    # Static int32-overflow assert. Proven dead at compile-time;
    # bisheng bails because the assert taint pollutes the LLVM IR.
    # Same disposition as STACK — accept on the targets, reject
    # elsewhere as a corpus-quality issue.
    status="INT32"
    if [[ $expected == "yes" ]]; then
      PASS_COUNT=$((PASS_COUNT + 1))
      STACK_COUNT=$((STACK_COUNT + 1))
      note="static int32-overflow assert (expected on master baseline)"
    else
      FAIL_COUNT=$((FAIL_COUNT + 1))
      note="static int32-overflow assert — corpus entry not viable"
    fi
  else
    status="FAIL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    note=$(tail -n 50 "$ir_log" 2>/dev/null | grep -E "error:|ERROR" | tail -n 1 | cut -c1-60 || true)
    [[ -z $note ]] && note="exit=$rc"
  fi

  printf '%-46s %-6s %-9s %-9s %s\n' \
    "${name%.ttir.mlir}" "$status" "$rewrite" "$expected" "$note"

  # Cleanup: keep IR logs for any non-PASS row; drop bin always once
  # we've grepped its associated log. --keep-logs preserves everything.
  if [[ $KEEP_LOGS -eq 0 ]]; then
    rm -f "$out_bin"
    if [[ $status == PASS ]]; then
      rm -f "$ir_log"
    fi
  fi
done

echo
echo "Summary: $PASS_COUNT pass (incl $STACK_COUNT expected STACK), $FAIL_COUNT fail, $REWRITE_COUNT rewritten ($UNEXPECTED_REWRITE_COUNT unexpected, $UNEXPECTED_STACK_COUNT unexpected-stack)"

exit_code=0
if [[ $FAIL_COUNT -gt 0 ]]; then
  exit_code=2
elif [[ $UNEXPECTED_REWRITE_COUNT -gt 0 ]]; then
  exit_code=3
fi

if [[ $exit_code -ne 0 ]]; then
  echo "Failing logs retained under: $RUN_DIR"
elif [[ $KEEP_LOGS -eq 0 ]]; then
  rmdir "$RUN_DIR" 2>/dev/null || true
fi

exit $exit_code
