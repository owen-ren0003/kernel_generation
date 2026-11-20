#!/usr/bin/env bash
# build-binaries.sh — Build bishengir-compile + hivmc-a5 + Template .bc
# files for a workspace, then stage them for deploy.
#
# Reads work_dir, docker.container and docker.bind_container_path from
# config.yaml so it works for any task. Default build dir is build-dev;
# auto-switches to build-fix if it already exists (i.e. a fix has been
# applied to that workspace).
#
# Usage:
#   bash scripts/build-binaries.sh --ws ws1
#   bash scripts/build-binaries.sh --ws ws1 --clean        # full rebuild
#   bash scripts/build-binaries.sh --ws ws1 --skip-ascend  # only hivmc
#   bash scripts/build-binaries.sh --ws ws1 --skip-hivmc   # only ascend
#   bash scripts/build-binaries.sh --ws ws1 --build-dir build-fix
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

WS=""
CLEAN=0
SKIP_ASCEND=0
SKIP_HIVMC=0
SKIP_PATCHES=0
BUILD_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws)            WS="$2";       shift 2 ;;
    --build-dir)     BUILD_DIR="$2"; shift 2 ;;
    --clean)         CLEAN=1;       shift ;;
    --skip-ascend)   SKIP_ASCEND=1; shift ;;
    --skip-hivmc)    SKIP_HIVMC=1;  shift ;;
    --skip-patches)  SKIP_PATCHES=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$WS" ]] && { echo "ERROR: --ws required" >&2; exit 2; }

WORK_DIR=$(work_dir)
WS_HOST="$WORK_DIR/$WS"
[[ -d "$WS_HOST/AscendNPU-IR-Dev" && -d "$WS_HOST/hivmc" ]] || {
  echo "ERROR: $WS_HOST does not look like a workspace (missing AscendNPU-IR-Dev or hivmc)" >&2
  exit 2
}

CONTAINER=$(read_yaml docker.container)
BIND_CTR=$(read_yaml docker.bind_container_path)
BIND_HOST=$(read_yaml docker.bind_host_path)
WS_CTR="$BIND_CTR/$WS"

# Default build dir: build-fix if it already exists, else build-dev.
if [[ -z "$BUILD_DIR" ]]; then
  if [[ -d "$WS_HOST/AscendNPU-IR-Dev/build-fix" ]]; then
    BUILD_DIR=build-fix
  else
    BUILD_DIR=build-dev
  fi
fi

echo "Build pipeline:"
echo "  workspace:  $WS_HOST  (in-container: $WS_CTR)"
echo "  build dir:  $BUILD_DIR"
echo "  container:  $CONTAINER"

docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || {
  echo "ERROR: container $CONTAINER not running. Start it with:" >&2
  echo "  docker start $CONTAINER" >&2
  exit 2
}

build_ascend_npu_ir() {
  echo
  echo "===== Building AscendNPU-IR-Dev/$BUILD_DIR ====="
  if [[ $CLEAN -eq 1 ]]; then
    docker exec "$CONTAINER" rm -rf "$WS_CTR/AscendNPU-IR-Dev/$BUILD_DIR"
  fi
  docker exec "$CONTAINER" mkdir -p "$WS_CTR/AscendNPU-IR-Dev/$BUILD_DIR"
  if [[ ! -e "$WS_HOST/AscendNPU-IR-Dev/$BUILD_DIR/build.ninja" || $CLEAN -eq 1 ]]; then
    # Full configure+build. -t enables BISHENGIR_BUILD_TEMPLATE so meta_op*.bc
    # get generated alongside bishengir-compile.
    APPLY_PATCHES_FLAG="--apply-patches"
    [[ $SKIP_PATCHES -eq 1 ]] && APPLY_PATCHES_FLAG=""
    docker exec -w "$WS_CTR/AscendNPU-IR-Dev/$BUILD_DIR" "$CONTAINER" bash -c "
      export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH
      ../build-tools/build.sh --c-compiler clang-17 --cxx-compiler clang++-17 \
        '--add-cmake-options=-DLLVM_ENABLE_LLD=ON' --build-type Release -j 16 \
        --enable-assertion --disable-werror --disable-mlir-werror \
        --disable-bishengir-werror --build-triton --build . $APPLY_PATCHES_FLAG \
        --build-template \
        --bisheng-compiler $BIND_CTR/bisheng_compiler/bisheng_compiler/bin"
  else
    # Incremental: just rebuild the binaries + Template targets.
    # Re-run apply_patches.sh first — incremental builds don't, so a
    # cherry-pick that adds a patch under build-tools/patches/triton/
    # would be silently un-applied (the integration of ws3's
    # PadTensorShapesToPow2 fix tripped over this on 2026-05-02).
    if [[ $SKIP_PATCHES -eq 0 ]]; then
      docker exec -w "$WS_CTR/AscendNPU-IR-Dev" "$CONTAINER" bash -c "
        ./build-tools/apply_patches.sh" || true
    fi
    docker exec -w "$WS_CTR/AscendNPU-IR-Dev/$BUILD_DIR" "$CONTAINER" bash -c "
      export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH
      touch build.ninja
      ninja -j16 bin/bishengir-compile bishengir_template_bitcode || ninja -j16 bin/bishengir-compile"
  fi
}

build_hivmc() {
  echo
  echo "===== Building hivmc/$BUILD_DIR ====="
  if [[ $CLEAN -eq 1 ]]; then
    docker exec "$CONTAINER" rm -rf "$WS_CTR/hivmc/$BUILD_DIR"
  fi
  docker exec "$CONTAINER" mkdir -p "$WS_CTR/hivmc/$BUILD_DIR"
  if [[ ! -e "$WS_HOST/hivmc/$BUILD_DIR/build.ninja" || $CLEAN -eq 1 ]]; then
    # NOTE: we deliberately do NOT pass `-t` to hivmc's build.sh — that
    # flag silently terminates option parsing and discards the `-o` value
    # (causing the build to write into build-tools/ instead of
    # $BUILD_DIR/, which then skips the Template subdir).
    docker exec -w "$WS_CTR/hivmc" "$CONTAINER" bash -c "
      export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH
      export BISHENG_INSTALL_PATH=$BIND_CTR/bisheng_compiler/bisheng_compiler/bin
      ./build-tools/build.sh --c-compiler clang-17 --cxx-compiler clang++-17 \
        '--add-cmake-options=-DLLVM_ENABLE_LLD=ON' --build-type Release \
        --enable-assertion --disable-werror --build-triton \
        --bisheng-compiler \${BISHENG_INSTALL_PATH} -o ./$BUILD_DIR"
  else
    docker exec -w "$WS_CTR/hivmc/$BUILD_DIR" "$CONTAINER" bash -c "
      export PATH=/usr/local/bin:/usr/lib/llvm-17/bin:\$PATH
      touch build.ninja
      ninja -j16 bin/hivmc-a5"
  fi
}

[[ $SKIP_ASCEND -eq 0 ]] && build_ascend_npu_ir
[[ $SKIP_HIVMC  -eq 0 ]] && build_hivmc

# Stage: collect everything deploy-binary.sh expects to find under
# $WS_HOST/AscendNPU-IR-Dev/$BUILD_DIR/{bin,lib} and $WS_HOST/hivmc/$BUILD_DIR/bin.
# Nothing to copy for the staging step itself — deploy-binary.sh reads
# directly from these paths. We just confirm the artifacts exist.

echo
echo "===== Build artifacts ====="
ls -la "$WS_HOST/AscendNPU-IR-Dev/$BUILD_DIR/bin/bishengir-compile" 2>&1 || echo "MISSING bishengir-compile"
ls -la "$WS_HOST/hivmc/$BUILD_DIR/bin/hivmc-a5"                     2>&1 || echo "MISSING hivmc-a5"
ls "$WS_HOST/AscendNPU-IR-Dev/$BUILD_DIR/lib/"meta_op*.bc 2>/dev/null | head -3 || echo "(no meta_op .bc — pass --build-template + --bisheng-compiler in cmake)"
echo
echo "BUILD OK. Run: bash scripts/deploy-binary.sh --ws $WS --include-bc"
