#!/usr/bin/env bash
# deploy-binary.sh — Deploy a workspace's freshly-built binary to its slot.
#
# Validates the workspace ↔ slot mapping before scp. Works for both
# test_env.mode = docker and conda. In conda mode, bitcode files (.bc)
# get deployed to <pipeline_root>/lib/ (per the post-Apr-2026 layout where
# bishengir-compile resolves them via $bin/../lib/), while binaries
# stay in <pipeline_root>/<slot>/.
#
# Usage:
#   bash scripts/deploy-binary.sh --ws ws1                  # deploy bishengir-compile only
#   bash scripts/deploy-binary.sh --ws ws1 --include-hivmc  # also deploy hivmc-a5
#   bash scripts/deploy-binary.sh --ws ws1 --include-bc     # also deploy meta_op*.bc + host-a5.bc
#                                                            # (implies --include-hivmc)
#   bash scripts/deploy-binary.sh --ws ws1 --slot fix_bin_alt
#                                                            # override deploy slot name
set -euo pipefail

HARNESS_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$HARNESS_ROOT"
source "$HARNESS_ROOT/scripts/_lib.sh"

WS=""
SLOT=""
INCLUDE_HIVMC=0
INCLUDE_BC=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ws)              WS="$2";               shift 2 ;;
    --slot)            SLOT="$2";             shift 2 ;;
    --include-hivmc)   INCLUDE_HIVMC=1;       shift ;;
    --include-bc)      INCLUDE_BC=1;          INCLUDE_HIVMC=1; shift ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done
[[ -z "$WS" ]] && { echo "ERROR: --ws required" >&2; exit 2; }

MODE=$(read_yaml test_env.mode)
HOST=$(read_yaml test_env.host)
LOCAL_DIR=$(ws_path "$WS")
[[ -d "$LOCAL_DIR" ]] || { echo "ERROR: local workspace missing: $LOCAL_DIR" >&2; exit 2; }

# Pick deploy slot:
#   --slot wins if given; else mode-specific default.
if [[ -n "$SLOT" ]]; then
  REMOTE_BIN=$(remote_bin_dir "$SLOT")
else
  if [[ "$MODE" == "docker" ]]; then
    REMOTE_BIN=$(remote_bin_dir "$WS")           # dt_debug_<ws>/fix_bin
  else
    REMOTE_BIN=$(remote_bin_dir fix_bin)
  fi
fi
REMOTE_LIB=$(remote_lib_dir)   # empty in mode=docker

# Build dir: build-fix if it exists, otherwise build-dev.
BUILD=build-dev
[[ -e "$LOCAL_DIR/AscendNPU-IR-Dev/build-fix/bin/bishengir-compile" ]] && BUILD=build-fix
[[ "$WS" == "master" ]] && BUILD=build-master

ASCEND_BIN="$LOCAL_DIR/AscendNPU-IR-Dev/$BUILD/bin/bishengir-compile"
[[ -f "$ASCEND_BIN" ]] || { echo "ERROR: $ASCEND_BIN not found" >&2; exit 2; }

echo "Deploying $WS"
echo "  local:   $LOCAL_DIR  (build dir: $BUILD)"
echo "  remote:  $REMOTE_BIN  (mode: $MODE)"
[[ -n "$REMOTE_LIB" ]] && echo "  bitcode: $REMOTE_LIB"

ssh "$HOST" "mkdir -p $REMOTE_BIN ${REMOTE_LIB:+$REMOTE_LIB}"

# 1) bishengir-compile.
scp "$ASCEND_BIN" "$HOST:$REMOTE_BIN/"

# Master in conda-mode also deploys to builds/master/ (the canonical
# stable slot used by the .206 task). The fix_bin is the active path
# but builds/master/ is where master-fixes.json records the canonical
# binary for forensics + side-by-side comparison. Without this, prior
# master integrations had to scp manually after invoking this script.
if [[ "$WS" == "master" && "$MODE" != "docker" ]]; then
  PIPELINE=$(read_yaml test_env.pipeline_root)
  MASTER_SLOT="$PIPELINE/builds/master/bin"
  ssh "$HOST" "mkdir -p $MASTER_SLOT"
  scp "$ASCEND_BIN" "$HOST:$MASTER_SLOT/"
  echo "  also deployed to: $MASTER_SLOT"
fi

# 2) hivmc-a5 if requested.
if [[ $INCLUDE_HIVMC -eq 1 ]]; then
  HIVMC="$LOCAL_DIR/hivmc/$BUILD/bin/hivmc-a5"
  [[ -f "$HIVMC" ]] || { echo "ERROR: $HIVMC not found" >&2; exit 2; }
  scp "$HIVMC" "$HOST:$REMOTE_BIN/"
  if [[ "$WS" == "master" && "$MODE" != "docker" ]]; then
    scp "$HIVMC" "$HOST:$MASTER_SLOT/"
  fi
fi

# 3) Bitcode files if requested.
if [[ $INCLUDE_BC -eq 1 ]]; then
  # Source: AscendNPU-IR-Dev/<build>/lib/{meta_op.*.bc,host-a5.bc}
  # (Template/.bc moved here from hivmc/lib/Template/ by commit 3fd9344.)
  BC_DIR="$LOCAL_DIR/AscendNPU-IR-Dev/$BUILD/lib"
  TMP=$(mktemp -d)
  trap "rm -rf $TMP" EXIT
  cp "$BC_DIR"/host-a5.bc       "$TMP/" 2>/dev/null || true
  cp "$BC_DIR"/meta_op.*.bc     "$TMP/" 2>/dev/null || true
  if [[ "$MODE" == "docker" ]]; then
    # Old layout: bc files live alongside binaries, with dav- prefix.
    for f in "$TMP"/meta_op.*.bc; do
      [[ -f "$f" ]] || continue
      base=$(basename "$f")
      new=$(echo "$base" | sed -E 's/\.(c[0-9]+)\./.dav-\1./')
      [[ "$new" != "$base" ]] && mv "$f" "$TMP/$new"
    done
    scp "$TMP"/*.bc "$HOST:$REMOTE_BIN/"
  else
    # New layout (mode=conda): bc files in <pipeline_root>/lib/, no dav- prefix.
    scp "$TMP"/*.bc "$HOST:$REMOTE_LIB/"
  fi
fi

# Re-establish ccec → bisheng symlink in the slot if it existed before.
ssh "$HOST" "
  cd $REMOTE_BIN
  [ -f bisheng ] && ln -sf bisheng ccec
  ls -la 2>&1 | head -15
"

# Record this deploy in the build tracker (state/build-tracker/<ws>.yaml).
# Atomic; if the tracker call fails, the deploy already succeeded — we
# don't roll back, just warn.
source "$HARNESS_ROOT/scripts/_build-tracker.sh"
MACHINE=".$(echo "$HOST" | grep -oE '[0-9]+$')"
BIN_FOLDER=$(basename "$REMOTE_BIN")
ASCEND_SHA=$(git -C "$LOCAL_DIR/AscendNPU-IR-Dev" rev-parse HEAD 2>/dev/null || echo "unknown")
NOTE=""
if [[ $INCLUDE_HIVMC -eq 1 ]]; then
  HIVMC_SHA=$(git -C "$LOCAL_DIR/hivmc" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  NOTE="hivmc@$HIVMC_SHA"
fi
[[ $INCLUDE_BC -eq 1 ]] && NOTE="${NOTE:+$NOTE +}bitcode"
if tracker_record_deploy "$WS" "$MACHINE" "$BIN_FOLDER" "AscendNPU-IR-Dev" "$ASCEND_SHA" "$NOTE"; then
  echo "Deploy recorded: state/build-tracker/$WS.yaml deployments.$MACHINE.$BIN_FOLDER ← $ASCEND_SHA${NOTE:+ ($NOTE)}"
else
  echo "WARNING: tracker update failed; deploy succeeded but state/build-tracker/$WS.yaml is stale" >&2
fi

echo "Deploy complete."
