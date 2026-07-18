#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/list-channel-build-attrs.sh <system>

Prints flake package refs for every release channel configured in channels.json
and resolved in versions.json. Channels without a resolved tag are skipped.
Resolved channels must have a matching release manifest and complete artifacts
for the requested system.
EOF
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

system=$1
channels_json="channels.json"
versions_json="versions.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "required tool not found: jq" >&2
  exit 1
fi

if [ ! -f "$versions_json" ]; then
  echo "versions manifest not found: $versions_json" >&2
  exit 1
fi

if [ ! -f "$channels_json" ]; then
  echo "channel definitions not found: $channels_json" >&2
  exit 1
fi

scripts/check-channels.sh "$channels_json" "$versions_json" >/dev/null

build_count=0
invalid=0

while IFS= read -r channel_json; do
  channel=$(printf "%s" "$channel_json" | jq -r '.key')
  tag=$(jq -r --arg channel "$channel" '.channels[$channel].tag // ""' "$versions_json")

  if [ -z "$tag" ] || [ "$tag" = "null" ]; then
    continue
  fi

  if ! jq -e --arg tag "$tag" '.releases[$tag] != null' "$versions_json" >/dev/null; then
    echo "channel $channel points to missing release: $tag" >&2
    invalid=1
    continue
  fi

  if ! jq -e --arg tag "$tag" --arg system "$system" '
    .releases[$tag].systems[$system].foundry?
    and .releases[$tag].systems[$system].noir?
  ' "$versions_json" >/dev/null; then
    echo "channel $channel release $tag is incomplete for $system" >&2
    invalid=1
    continue
  fi

  printf ".#%s\n" "$channel"
  build_count=$((build_count + 1))
done < <(jq -c 'to_entries[]' "$channels_json")

if [ "$invalid" -ne 0 ]; then
  exit 1
fi

if [ "$build_count" -eq 0 ]; then
  echo "no mirrored channels have complete artifacts for $system" >&2
  exit 1
fi
