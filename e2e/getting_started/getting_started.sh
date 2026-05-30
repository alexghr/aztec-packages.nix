#!/usr/bin/env bash
# runs through the "Getting started" guide
# https://docs.aztec.network/developers/getting_started_on_local_network
# mirror of https://github.com/AztecProtocol/aztec-packages/blob/next/aztec-up/test/basic_install.sh

set -euo pipefail

echo
echo "nargo version: $(nargo --version | head -1 | cut -d' ' -f4)"
echo "bb version: $(bb --version)"
echo "aztec version: $(aztec --version)"
echo "aztec-wallet version: $(aztec-wallet --version)"
echo

AZTEC_PORT="${AZTEC_PORT:-8080}"
AZTEC_READY_TIMEOUT="${AZTEC_READY_TIMEOUT:-120}"

AZTEC_WORKING_DIR=$(mktemp -d)
AZTEC_LOCALNET_LOG="$AZTEC_WORKING_DIR/localnet.txt"
AZTEC_LOCALNET_DATA="$AZTEC_WORKING_DIR/localnet"
AZTEC_WALLET_DATA="$AZTEC_WORKING_DIR/wallet"

mkdir -p "$AZTEC_LOCALNET_DATA" "$AZTEC_WALLET_DATA"

cleanup() {
  if [ -n "${AZTEC_LOCALNET_PID:-}" ]; then
    kill -- "-$AZTEC_LOCALNET_PID" 2>/dev/null || true
    wait "$AZTEC_LOCALNET_PID" 2>/dev/null || true
  fi
  rm -rf "$AZTEC_WORKING_DIR"
}

trap cleanup EXIT

export LOG_LEVEL=silent
export PXE_PROVER=none
export SEQ_ENABLE_PROPOSER_PIPELINING=true

setsid aztec start --local-network --data-directory "$AZTEC_LOCALNET_DATA" --port "$AZTEC_PORT" >"$AZTEC_LOCALNET_LOG" 2>&1 &
AZTEC_LOCALNET_PID=$!
AZTEC_NODE_URL="http://127.0.0.1:$AZTEC_PORT"

for _ in $(seq 1 "$AZTEC_READY_TIMEOUT"); do
  if curl --silent --fail "$AZTEC_NODE_URL/status" >/dev/null; then
    break
  fi

  echo "Waiting for localnet..."
  sleep 1
done

if ! curl --silent --fail "$AZTEC_NODE_URL/status" >/dev/null; then
  echo "localnet did not become ready within ${AZTEC_READY_TIMEOUT}s" >&2
  exit 1
fi

aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" import-test-accounts

aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" create-account -a my-wallet -f test0
aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" deploy TokenContractArtifact --from accounts:test0 --args accounts:test0 TestToken TST 18 -a testtoken
aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" send mint_to_public --from accounts:test0 --contract-address contracts:testtoken --args accounts:test0 100
aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" send transfer_to_private --from accounts:test0 --contract-address testtoken --args accounts:test0 25
aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" simulate balance_of_public --from test0 --contract-address testtoken --args accounts:test0
aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" simulate balance_of_private --from test0 --contract-address testtoken --args accounts:test0
