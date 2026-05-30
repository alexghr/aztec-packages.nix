#!/usr/bin/env bash
# mirrors https://github.com/AztecProtocol/aztec-packages/blob/next/aztec-up/test/counter_contract.sh.

set -euo pipefail

echo
echo "nargo version: $(nargo --version | head -1 | cut -d' ' -f4)"
echo "bb version: $(bb --version)"
echo "aztec version: $(aztec --version)"
echo "aztec-wallet version: $(aztec-wallet --version)"
echo

export LOG_LEVEL="${LOG_LEVEL:-silent}"
export PXE_PROVER="${PXE_PROVER:-none}"
export SEQ_ENABLE_PROPOSER_PIPELINING="${SEQ_ENABLE_PROPOSER_PIPELINING:-true}"

AZTEC_COUNTER_FIXTURE="${AZTEC_COUNTER_FIXTURE:-$(dirname "$0")/fixture}"
AZTEC_PORT="${AZTEC_PORT:-8080}"
AZTEC_READY_TIMEOUT="${AZTEC_READY_TIMEOUT:-120}"

AZTEC_WORKING_DIR=$(mktemp -d)
AZTEC_LOCALNET_LOG="$AZTEC_WORKING_DIR/localnet.txt"
AZTEC_LOCALNET_DATA="$AZTEC_WORKING_DIR/localnet"
AZTEC_WALLET_DATA="$AZTEC_WORKING_DIR/wallet"
AZTEC_NODE_URL="http://127.0.0.1:$AZTEC_PORT"

mkdir -p "$AZTEC_LOCALNET_DATA" "$AZTEC_WALLET_DATA"

cleanup() {
  if [ -n "${AZTEC_LOCALNET_PID:-}" ]; then
    kill -- "-$AZTEC_LOCALNET_PID" 2>/dev/null || true
  fi
  chmod -R u+w "$AZTEC_WORKING_DIR" 2>/dev/null || true
  rm -rf "$AZTEC_WORKING_DIR"
}

trap cleanup EXIT

cd "$AZTEC_WORKING_DIR"

# Execute the project creation flow as per:
# https://docs.aztec.network/tutorials/codealong/contract_tutorials/counter_contract
aztec new counter
chmod -R u+w counter

aztec_version=$(aztec --version | head -1)

cp -R "$AZTEC_COUNTER_FIXTURE"/. counter/
sed -i "s/__AZTEC_VERSION__/$aztec_version/g" counter/counter_contract/Nargo.toml

cd counter

aztec compile
counter_artifact="$PWD/target/counter_contract-Counter.json"

setsid aztec start --local-network --data-directory "$AZTEC_LOCALNET_DATA" --port "$AZTEC_PORT" >"$AZTEC_LOCALNET_LOG" 2>&1 &
AZTEC_LOCALNET_PID=$!

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

aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" deploy "$counter_artifact" \
  --init initialize \
  --from accounts:test0 \
  --args 5 accounts:test0 \
  -a counter

aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" send increment \
  --from accounts:test0 \
  --contract-address counter \
  --contract-artifact "$counter_artifact" \
  --args accounts:test0

aztec-wallet -d "$AZTEC_WALLET_DATA" -n "$AZTEC_NODE_URL" simulate get_counter \
  --from test0 \
  --contract-address counter \
  --contract-artifact "$counter_artifact" \
  --args accounts:test0
