#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/smoke-test.sh [package-output]

If package-output is provided, its bin directory is prepended to PATH.
Override the checked commands with SMOKE_COMMANDS, for example:

  SMOKE_COMMANDS="aztec bb-avm nargo" scripts/smoke-test.sh ./result
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

package_output=${1:-}

if [ -n "$package_output" ]; then
  if [ ! -d "$package_output" ]; then
    echo "package output does not exist or is not a directory: $package_output" >&2
    exit 1
  fi

  if [ -d "$package_output/bin" ]; then
    export PATH="$package_output/bin:$PATH"
  fi

  if [ -d "$package_output/share/aztec/contracts" ] && [ -z "${AZTEC_CONTRACTS_DIR:-}" ]; then
    export AZTEC_CONTRACTS_DIR="$package_output/share/aztec/contracts"
  fi
fi

commands=${SMOKE_COMMANDS:-"aztec bb-avm nargo"}

run_help() {
  local command_name=$1

  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "missing command: $command_name" >&2
    return 1
  fi

  echo "==> $command_name --help"
  "$command_name" --help >/dev/null
}

for command_name in $commands; do
  run_help "$command_name"
done

if [ -n "${AZTEC_CONTRACTS_DIR:-}" ]; then
  if [ ! -d "$AZTEC_CONTRACTS_DIR" ]; then
    echo "AZTEC_CONTRACTS_DIR is set but does not exist: $AZTEC_CONTRACTS_DIR" >&2
    exit 1
  fi
  echo "==> AZTEC_CONTRACTS_DIR exists"
fi

if [ "${SMOKE_LOCAL_NETWORK:-0}" = "1" ]; then
  if ! command -v timeout >/dev/null 2>&1; then
    echo "SMOKE_LOCAL_NETWORK=1 requires timeout" >&2
    exit 1
  fi
  if ! command -v anvil >/dev/null 2>&1; then
    echo "SMOKE_LOCAL_NETWORK=1 requires anvil" >&2
    exit 1
  fi

  echo "==> aztec start --local-network smoke"
  status=0
  timeout "${SMOKE_LOCAL_NETWORK_TIMEOUT:-30s}" aztec start --local-network >/dev/null 2>&1 || status=$?

  case "$status" in
    0|124)
      ;;
    *)
      echo "aztec local-network smoke failed with status $status" >&2
      exit "$status"
      ;;
  esac
fi

echo "Smoke tests passed."
