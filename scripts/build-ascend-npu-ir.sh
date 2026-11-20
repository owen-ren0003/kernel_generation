#!/usr/bin/env bash
# scripts/build-ascend-npu-ir.sh — canonical wrapper around
# AscendNPU-IR-Dev's build-tools/build.sh.
#
# Why a wrapper:
#   - Bakes in the canonical flag set documented in
#     instructions/build-ascend-npu-ir.txt, removing the easy-to-forget
#     flags (--apply-patches, --enable-assertion, -DLLVM_ENABLE_LLD=ON,
#     --build-triton, --build-bishengir-template + --bisheng-compiler when
#     needed).
#   - Builds into the naming-convention folder
#     build-<rel|debug>-<descriptor>/ (per deploy-and-test.txt).
#   - Writes BUILD_INFO.txt next to the produced binaries documenting
#     the exact flags used, git SHA, branch, build_type, timestamp. So
#     when a binary is deployed and later mis-behaves, we can verify
#     which configuration produced it.
#   - Records the build in state/build-tracker/<workspace>.yaml.
#
# Usage:
#   bash scripts/build-ascend-npu-ir.sh \
#       --workspace ws1 \
#       --build-type rel \
#       --descriptor my-fix \
#       [--repo AscendNPU-IR-Dev|hivmc]   # default AscendNPU-IR-Dev
#       [--incremental]                   # ninja -j16 in existing build dir
#       [--no-template]                   # skip --build-bishengir-template
#                                         # (faster, only
#                                         # needed when the build doesn't need
#                                         # custom meta_op.*.bc files)
#       [--bisheng-compiler <path>]       # override default path
#
# Exit codes:
#   0  build succeeded; BUILD_INFO.txt written; tracker updated
#   1  build failed; tracker NOT updated
#   2  bad args
set -euo pipefail

HARNESS_ROOT="${HARNESS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$HARNESS_ROOT/scripts/_lib.sh"
source "$HARNESS_ROOT/scripts/_build-tracker.sh"

ws=""
build_type=""
descriptor=""
repo="AscendNPU-IR-Dev"
incremental=0
no_template=0
bisheng_compiler=""
force_rebuild=0

usage() { sed -n '2,40p' "$0"; exit 2; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace)        ws="$2"; shift 2 ;;
    --build-type)       build_type="$2"; shift 2 ;;
    --descriptor)       descriptor="$2"; shift 2 ;;
    --repo)             repo="$2"; shift 2 ;;
    --incremental)      incremental=1; shift ;;
    --no-template)      no_template=1; shift ;;
    --bisheng-compiler) bisheng_compiler="$2"; shift 2 ;;
    --force-rebuild)    force_rebuild=1; shift ;;
    -h|--help) usage ;;
    *) echo "Unknown arg: $1" >&2; usage ;;
  esac
done

[[ -z "$ws" || -z "$build_type" || -z "$descriptor" ]] && {
  echo "ERROR: --workspace, --build-type, --descriptor required" >&2
  usage
}
[[ "$build_type" =~ ^(rel|debug)$ ]] || {
  echo "ERROR: --build-type must be 'rel' or 'debug'" >&2
  exit 2
}
[[ "$repo" =~ ^(AscendNPU-IR-Dev|AscendNPU-IR|hivmc)$ ]] || {
  echo "ERROR: --repo must be AscendNPU-IR-Dev, AscendNPU-IR, or hivmc" >&2
  exit 2
}

# Translate "rel"/"debug" → build.sh --build-type Release/Debug
case "$build_type" in
  rel)   cmake_btype="Release" ;;
  debug) cmake_btype="Debug" ;;
esac

build_folder="build-${build_type}-${descriptor}"
work_path="$(work_dir)/$ws"
repo_path="$work_path/$repo"
build_path="$repo_path/$build_folder"

[[ -d "$repo_path/.git" ]] || {
  echo "ERROR: $repo_path is not a git repo (run setup-workspaces.sh first?)" >&2
  exit 2
}

# Default bisheng compiler path (used when --build-bishengir-template is
# enabled).
if [[ -z "$bisheng_compiler" ]]; then
  bisheng_compiler="$work_path/bisheng_compiler/bisheng_compiler/bin"
fi

# Read docker container name from config.
container=$(read_yaml docker.container)
host_bind=$(read_yaml docker.bind_host_path)
container_bind=$(read_yaml docker.bind_container_path)
[[ -z "$container" ]] && { echo "ERROR: docker.container not set in config.yaml" >&2; exit 2; }

# Translate host paths to container paths for the docker exec.
#   $work_path is under $host_bind. The same path under the bind mount
#   is $container_bind/<relative-from-host-bind>.
rel_path="${work_path#$host_bind/}"
[[ "$rel_path" == "$work_path" ]] && {
  echo "ERROR: workspace $work_path is not under docker.bind_host_path=$host_bind" >&2
  exit 2
}
in_container_repo="$container_bind/$rel_path/$repo"
in_container_build="$in_container_repo/$build_folder"
in_container_bisheng=""
if [[ -n "$bisheng_compiler" ]]; then
  bisheng_rel="${bisheng_compiler#$host_bind/}"
  in_container_bisheng="$container_bind/$bisheng_rel"
fi

# Resolve git state BEFORE building so BUILD_INFO has the pre-build snapshot.
git_sha=$(git -C "$repo_path" rev-parse HEAD)
git_branch=$(git -C "$repo_path" rev-parse --abbrev-ref HEAD)
git_clean=$(git -C "$repo_path" status --porcelain | wc -l)

echo "[build-ascend-npu-ir] workspace=$ws repo=$repo build_folder=$build_folder"
echo "[build-ascend-npu-ir] branch=$git_branch sha=$git_sha clean=$( ((git_clean==0)) && echo yes || echo "no ($git_clean dirty paths)" )"
echo "[build-ascend-npu-ir] build_type=$build_type (cmake: $cmake_btype)"
echo "[build-ascend-npu-ir] incremental=$incremental no_template=$no_template force_rebuild=$force_rebuild"

# ============================================================================
# MANDATORY TRACKER CONSULTATION (the core "don't redo what's already done,
# but always verify" mechanism — see upgrades/2026-05-19.md and CLAUDE.md
# "build-folder convention" section).
#
# 1. If THIS folder already exists with a BUILD_INFO matching the requested
#    commit + build_type → switch to INCREMENTAL mode automatically.
#    Incremental is cheap (ninja checks timestamps, near-no-op if everything
#    is current) but it catches any drift: source edits since last build,
#    partial builds from a killed invocation, corrupted artifacts. We do NOT
#    short-circuit on BUILD_INFO alone because BUILD_INFO is metadata, not
#    proof the binary is actually correct.
# 2. Otherwise, print a table of all OTHER existing builds for this
#    workspace/repo so Claude can see whether an incremental rebuild in a
#    close-commit folder would be cheaper than starting fresh here.
# ============================================================================

primary_binary="$build_path/bin/bishengir-compile"
[[ "$repo" == "hivmc" ]] && primary_binary="$build_path/bin/hivmc-a5"
existing_build_info="$build_path/bin/BUILD_INFO.txt"

skip_table=0
if [[ -f "$existing_build_info" && -x "$primary_binary" && $incremental -eq 0 && $force_rebuild -eq 0 ]]; then
  existing_sha=$(grep -E '^git_sha:' "$existing_build_info" | awk '{print $2}')
  existing_btype=$(grep -E '^build_type:' "$existing_build_info" | awk '{print $2}')
  if [[ "$existing_sha" == "$git_sha" && "$existing_btype" == "$build_type" ]]; then
    # Incremental-unsafe check: new .patch files in build-tools/patches/
    # since the last build. This is the #1 documented footgun in
    # instructions/build-ascend-npu-ir.txt (real example: the
    # 0008-add-hivm.patch incident on 2026-04-29). Ninja doesn't re-apply
    # patches, so a "successful" incremental build silently produces a
    # binary built against the OLD patched state.
    cmake_cache="$build_path/CMakeCache.txt"
    new_patches=""
    if [[ -f "$cmake_cache" && -d "$repo_path/build-tools/patches" ]]; then
      new_patches=$(find "$repo_path/build-tools/patches" -name "*.patch" -newer "$cmake_cache" 2>/dev/null | head -5)
    fi
    if [[ -n "$new_patches" ]]; then
      cat >&2 <<EOF
[build-ascend-npu-ir] REFUSING auto-incremental: new patches found
since the last build's CMakeCache.txt. Incremental ninja will NOT
re-apply these, so the rebuilt binary would silently use the OLD
patched source. This is the #1 documented incremental footgun for
AscendNPU-IR-Dev (see instructions/build-ascend-npu-ir.txt §"Important
Rules" #5).

New patches:
$(printf '  %s\n' $new_patches)

Choose one:
  --force-rebuild     clean build (re-applies patches; takes 1-2 hours)
  --incremental       override and incremental anyway (at your risk)
EOF
      exit 4
    fi
    cat <<EOF
[build-ascend-npu-ir] $build_folder exists with BUILD_INFO matching the
requested commit + build_type. Auto-switching to incremental mode —
ninja will be near-no-op if the binary is current and will rebuild any
stale objects otherwise. BUILD_INFO alone is not proof of correctness.

  prior build_at: $(grep -E '^built_at:' "$existing_build_info" | awk '{print $2}')
  commit:         $git_sha

EOF
    incremental=1
    skip_table=1
  fi
fi

# Show what the tracker knows about OTHER builds in this workspace/repo,
# so Claude can decide whether an incremental rebuild in a close-commit
# folder would be cheaper than starting fresh here. Skipped when we
# already decided to incremental THIS folder.
if [[ $skip_table -eq 0 ]]; then
  echo "[build-ascend-npu-ir] Tracker shows existing $repo builds in $ws:"
  shown=0
  while IFS=$'\t' read -r ex_folder ex_commit ex_branch ex_btype; do
    [[ -z "$ex_folder" ]] && continue
    [[ "$ex_folder" == "$build_folder" ]] && continue
    if git -C "$repo_path" cat-file -e "$ex_commit" 2>/dev/null; then
      dist=$(git -C "$repo_path" rev-list --count "$ex_commit...$git_sha" 2>/dev/null || echo "?")
    else
      dist="(commit not in this repo)"
    fi
    printf "  %-40s  commit=%-12s  branch=%-15s  type=%-5s  distance=%s\n" \
      "$ex_folder" "${ex_commit:0:12}" "$ex_branch" "$ex_btype" "$dist"
    shown=$((shown + 1))
  done < <(tracker_list_builds "$ws" "$repo")
  if [[ $shown -eq 0 ]]; then
    echo "  (no prior $repo builds recorded in tracker for $ws)"
  else
    echo ""
    echo "If a close-distance folder above is the right starting point for"
    echo "an INCREMENTAL build, cancel this invocation and run instead:"
    echo "  cd $repo_path/<that-folder>"
    echo "  git checkout $git_sha   # if not already there"
    echo "  bash scripts/build-ascend-npu-ir.sh --workspace $ws --build-type $build_type \\"
    echo "       --descriptor <that-folder's descriptor> --incremental"
    echo ""
    echo "Proceeding with a fresh build in $build_folder/ in 5 seconds; ^C to cancel."
    echo "(For non-interactive use, pass --force-rebuild to skip this prompt.)"
    [[ $force_rebuild -eq 0 ]] && sleep 5
  fi
fi

if (( incremental )); then
  [[ -d "$build_path" ]] || { echo "ERROR: incremental requested but $build_path does not exist" >&2; exit 2; }
  cmd="export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH && touch build.ninja && ninja -j16 bin/bishengir-compile"
  echo "[build-ascend-npu-ir] running: $cmd  (in $in_container_build)"
  docker exec -w "$in_container_build" "$container" bash -c "$cmd"
  build_command_record="ninja -j16 bin/bishengir-compile (incremental)"
else
  mkdir -p "$build_path"
  template_flags=""
  if (( no_template == 0 )); then
    template_flags="--build-bishengir-template --bisheng-compiler $in_container_bisheng"
  fi
  cmd="export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH && \
    ../build-tools/build.sh --c-compiler clang-17 --cxx-compiler clang++-17 \
      '--add-cmake-options=-DLLVM_ENABLE_LLD=ON' --build-type $cmake_btype -j 16 \
      --enable-assertion --disable-werror --disable-mlir-werror \
      --disable-bishengir-werror --build-triton --build . --apply-patches \
      $template_flags"
  echo "[build-ascend-npu-ir] running canonical build (in $in_container_build)"
  docker exec -w "$in_container_build" "$container" bash -c "$cmd"
  build_command_record="../build-tools/build.sh ... --build-type $cmake_btype --enable-assertion --apply-patches --build-triton ${template_flags}"
fi

# Verify binary exists.
binary="$build_path/bin/bishengir-compile"
if [[ ! -x "$binary" ]] && [[ "$repo" == AscendNPU-IR* ]]; then
  echo "ERROR: expected binary $binary not found or not executable" >&2
  exit 1
fi
# hivmc produces hivmc-a5 at a different path.
if [[ "$repo" == "hivmc" ]]; then
  binary="$build_path/bin/hivmc-a5"
  [[ -x "$binary" ]] || { echo "ERROR: expected $binary not found" >&2; exit 1; }
fi

# Post-build smoke test. Catches "build said success but binary is
# dead-on-arrival" — partial objects, ABI mismatch, linker producing
# a broken executable, etc. Runs the binary with --help inside the
# docker container (same env as the build); cheap (~100 ms). If the
# smoke fails, we do NOT write BUILD_INFO and do NOT update the tracker
# so a downstream deploy sees no record of this folder being current.
in_container_binary="$in_container_build/bin/$(basename "$binary")"
echo "[build-ascend-npu-ir] smoke-test: $in_container_binary --help"
if ! docker exec "$container" "$in_container_binary" --help >/dev/null 2>&1; then
  cat >&2 <<EOF
ERROR: post-build smoke test failed — $(basename "$binary") --help
returned non-zero or did not produce output. The binary at $binary
is likely dead-on-arrival (partial objects, ABI mismatch, broken link,
or a stale incremental build).

NOT writing BUILD_INFO.txt or updating the tracker, so the next
deploy / build attempt won't see this folder as "current".

Suggested next steps:
  - re-run with --force-rebuild for a clean rebuild (incremental is
    likely the source if you didn't pass --force-rebuild this run);
  - inspect the docker build log for the actual failure;
  - check disk space (a full disk can produce truncated objects).
EOF
  exit 3
fi
echo "[build-ascend-npu-ir] smoke-test: passed"

# Write BUILD_INFO.txt next to the binary so deploys can verify
# provenance. This file is the "attestation" the user requested per A#3.
build_info="$build_path/bin/BUILD_INFO.txt"
cat > "$build_info" <<EOF
# Attestation of how this binary was built.
# Written by scripts/build-ascend-npu-ir.sh.
workspace:      $ws
repo:           $repo
build_folder:   $build_folder
build_type:     $build_type
cmake_type:     $cmake_btype
git_branch:     $git_branch
git_sha:        $git_sha
git_clean:      $( ((git_clean==0)) && echo yes || echo "no ($git_clean dirty paths)" )
built_at:       $(date -Iseconds)
built_by:       $(whoami)@$(hostname)
build_command:  $build_command_record
binary:         $binary
binary_size:    $(stat -c %s "$binary") bytes
EOF
echo "[build-ascend-npu-ir] wrote attestation: $build_info"

# Record in tracker.
tracker_record_build "$ws" "$repo" "$build_folder" "$git_sha" "$git_branch" "$build_type"
echo "[build-ascend-npu-ir] tracker updated: state/build-tracker/$ws.yaml"

echo "[build-ascend-npu-ir] SUCCESS — binary at $binary"
exit 0
