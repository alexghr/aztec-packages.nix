#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
app_dir=${1:-}
channel=${2:-v5-stable}
task_limit=

fail() {
  echo "private-voting e2e failed: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "required command not found: $1"
  fi
}

assert_executable() {
  local label=$1
  local path=${2:-}

  if [ -z "$path" ] || [ ! -x "$path" ]; then
    fail "$label is not executable: ${path:-<unset>}"
  fi
}

init_task_guard() {
  local uid
  local current_tasks
  local task_headroom=${AZTEC_PRIVATE_VOTING_TASK_HEADROOM:-512}
  local hard_limit

  case "$task_headroom" in
    "" | *[!0-9]*) fail "AZTEC_PRIVATE_VOTING_TASK_HEADROOM must be a positive integer" ;;
  esac

  if [ "$task_headroom" -eq 0 ]; then
    fail "AZTEC_PRIVATE_VOTING_TASK_HEADROOM must be greater than zero"
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
}

run_bounded() {
  local duration=$1
  shift

  if [ -z "$task_limit" ]; then
    fail "task guard was not initialized"
  fi

  (
    ulimit -u "$task_limit"
    timeout --kill-after=30s "$duration" "$@"
  )
}

if [ -z "${IN_NIX_SHELL:-}" ]; then
  fail "run this test through nix develop"
fi

if [ -z "$app_dir" ] || [ ! -f "$app_dir/package.json" ] || [ ! -f "$app_dir/scripts/update.ts" ]; then
  fail "usage: $0 <aztec-private-voting checkout> [channel]"
fi

app_dir=$(cd -- "$app_dir" && pwd)

for command_name in awk aztec aztec-bb git id jq nc node npm ps readlink timeout tr; do
  require_command "$command_name"
done

expected_app_ref=$(tr -d '\r\n' < "$repo_root/e2e/private-voting.ref")
if [[ ! "$expected_app_ref" =~ ^[0-9a-f]{40}$ ]]; then
  fail "invalid private voting canary ref: $expected_app_ref"
fi

if ! actual_app_ref=$(git -C "$app_dir" rev-parse HEAD); then
  fail "private-voting path is not a git checkout: $app_dir"
fi

if [ "$actual_app_ref" != "$expected_app_ref" ]; then
  fail "private-voting checkout mismatch: expected $expected_app_ref, got $actual_app_ref"
fi

expected_tag=$(jq -r --arg channel "$channel" '.channels[$channel].tag // empty' "$repo_root/versions.json")
if [ -z "$expected_tag" ]; then
  fail "channel has no release tag in versions.json: $channel"
fi

expected_version=${expected_tag#v}
actual_version=$(aztec --version | head -1)
if [ "$actual_version" != "$expected_version" ]; then
  fail "aztec version mismatch for $channel: expected $expected_version, got $actual_version"
fi

assert_executable ANVIL_BIN "${ANVIL_BIN:-}"
assert_executable FORGE_BIN "${FORGE_BIN:-}"
assert_executable BB_BINARY_PATH "${BB_BINARY_PATH:-}"

bb_binary_path=$(readlink -f -- "$BB_BINARY_PATH")
bb_wrapper=$(readlink -f -- "$(command -v aztec-bb)")
if [ "$bb_binary_path" = "$bb_wrapper" ]; then
  fail "BB_BINARY_PATH resolves to the aztec-bb launcher and would recurse"
fi

export HARDWARE_CONCURRENCY="${HARDWARE_CONCURRENCY:-4}"
export RAYON_NUM_THREADS="${RAYON_NUM_THREADS:-4}"
init_task_guard

echo "channel: $channel ($actual_version)"
echo "private-voting checkout: $app_dir ($actual_app_ref)"
echo "retargeting app dependencies to $expected_tag"

(
  ulimit -u "$task_limit"
  cd "$app_dir"

  node scripts/update.ts --version "$expected_tag"
  run_bounded 5m npm install --package-lock-only --ignore-scripts --no-audit --no-fund
  run_bounded 10m npm ci --no-audit --no-fund
  run_bounded 2m npm run clean -w @app/contracts
  run_bounded 15m npm run build
  run_bounded 5m npm run typecheck -w @app/frontend
  run_bounded 15m npm test
)

echo "$channel private-voting e2e passed."
