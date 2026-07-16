#!/usr/bin/env bash
set -euo pipefail

channel=${1:-v5-stable}
repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

fail() {
  echo "dev-shell smoke test failed: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command not found: $1"
  fi
}

assert_executable() {
  local label=$1
  local path=$2

  if [ ! -x "$path" ]; then
    fail "$label is not executable: $path"
  fi
}

run_bounded() {
  local duration=$1
  shift

  local uid
  local current_tasks
  local task_headroom=${AZTEC_DEV_SHELL_TASK_HEADROOM:-256}
  local task_limit
  local hard_limit

  case "$task_headroom" in
    "" | *[!0-9]*) fail "AZTEC_DEV_SHELL_TASK_HEADROOM must be a positive integer" ;;
  esac

  if [ "$task_headroom" -eq 0 ]; then
    fail "AZTEC_DEV_SHELL_TASK_HEADROOM must be greater than zero"
  fi

  uid=$(id -u)
  current_tasks=$(ps -eLo ruid= | awk -v uid="$uid" '$1 == uid { count++ } END { print count + 0 }')
  task_limit=$((current_tasks + task_headroom))
  hard_limit=$(ulimit -Hu)

  if [ "$hard_limit" != "unlimited" ] && [ "$task_limit" -gt "$hard_limit" ]; then
    task_limit=$hard_limit
  fi

  if [ "$task_limit" -le "$current_tasks" ]; then
    fail "cannot reserve task headroom: $current_tasks tasks already running, hard limit is $hard_limit"
  fi

  echo "task guard: current=$current_tasks limit=$task_limit"
  (
    ulimit -u "$task_limit"
    timeout --kill-after=15s "$duration" "$@"
  )
}

if [ -z "${IN_NIX_SHELL:-}" ]; then
  fail "run this test through nix develop"
fi

for command_name in awk aztec aztec-bb id jq nargo node npm ps python3 readlink timeout; do
  require_command "$command_name"
done

expected_tag=$(jq -r --arg channel "$channel" '.channels[$channel].tag // empty' "$repo_root/versions.json")
if [ -z "$expected_tag" ]; then
  fail "channel has no release tag in versions.json: $channel"
fi

expected_version=${expected_tag#v}
actual_version=$(aztec --version | head -1)
if [ "$actual_version" != "$expected_version" ]; then
  fail "aztec version mismatch for $channel: expected $expected_version, got $actual_version"
fi

: "${BB:?dev shell did not set BB}"
: "${BB_BINARY_PATH:?dev shell did not set BB_BINARY_PATH}"
: "${NARGO:?dev shell did not set NARGO}"

bb=$(readlink -f -- "$BB")
bb_binary_path=$(readlink -f -- "$BB_BINARY_PATH")
bb_wrapper=$(readlink -f -- "$(command -v aztec-bb)")
nargo=$(readlink -f -- "$NARGO")
path_nargo=$(readlink -f -- "$(command -v nargo)")

if [ "$bb_binary_path" = "$bb_wrapper" ]; then
  fail "BB_BINARY_PATH resolves to the aztec-bb launcher and would recurse"
fi

assert_executable BB "$bb"
assert_executable BB_BINARY_PATH "$bb_binary_path"

if [ ! -x "$NARGO" ]; then
  fail "NARGO is not executable: $NARGO"
fi

if [ "$nargo" != "$path_nargo" ]; then
  fail "NARGO does not match the nargo on PATH"
fi

if [ ! -d "${AZTEC_CONTRACTS_DIR:-}" ]; then
  fail "AZTEC_CONTRACTS_DIR is missing or is not a directory"
fi

echo "channel: $channel ($actual_version)"
echo "aztec: $(command -v aztec)"
echo "nargo: $nargo"
echo "bb: $bb"
echo "bb binary path: $bb_binary_path"
nargo --version
python3 --version

# Reject the known BB_BINARY_PATH self-reference before invoking the launcher,
# then contain any other process-spawning regression with a temporary per-user
# task limit.
run_bounded 30s aztec-bb --version

workdir=$(mktemp -d)
cleanup() {
  chmod -R u+w "$workdir" 2>/dev/null || true
  rm -rf "$workdir"
}
trap cleanup EXIT

cp -R "$repo_root/e2e/counter_contract/fixture/." "$workdir/"
chmod -R u+w "$workdir"
sed -i "s/__AZTEC_VERSION__/$actual_version/g" "$workdir/counter_contract/Nargo.toml"

export HARDWARE_CONCURRENCY="${HARDWARE_CONCURRENCY:-4}"
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}"

(
  cd "$workdir"
  run_bounded "${AZTEC_DEV_SHELL_COMPILE_TIMEOUT:-300s}" aztec compile
)

artifact="$workdir/target/counter_contract-Counter.json"
if [ ! -s "$artifact" ]; then
  fail "aztec compile did not create the expected counter artifact"
fi

echo "$channel dev-shell smoke test passed."
