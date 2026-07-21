#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/check-channels.sh [--allow-missing-releases] [--channels PATH] [--versions PATH]
       scripts/check-channels.sh [CHANNELS_JSON [VERSIONS_JSON]]

Validates channel policy and mirrored channel state. Paths default to
channels.json and versions.json. Supply paths either as options or as positional
arguments, but do not mix the two forms.

Configured channels do not need mirrored state, and stale state is allowed.
When a configured channel has state, its tag must exist in versions.json.
Use --allow-missing-releases on repair paths that will restore missing state.
EOF
}

channels_json="channels.json"
versions_json="versions.json"
allow_missing_releases=0
channels_option_set=0
versions_option_set=0
positional=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --allow-missing-releases)
      allow_missing_releases=1
      ;;
    --channels)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        echo "--channels requires a path" >&2
        exit 2
      fi
      channels_json=$1
      channels_option_set=1
      ;;
    --versions)
      shift
      if [ "$#" -eq 0 ] || [ -z "$1" ]; then
        echo "--versions requires a path" >&2
        exit 2
      fi
      versions_json=$1
      versions_option_set=1
      ;;
    --)
      shift
      while [ "$#" -gt 0 ]; do
        positional+=("$1")
        shift
      done
      break
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      positional+=("$1")
      ;;
  esac
  shift
done

if [ "${#positional[@]}" -gt 2 ]; then
  echo "too many positional paths" >&2
  usage >&2
  exit 2
fi

if [ "${#positional[@]}" -gt 0 ]; then
  if [ "$channels_option_set" -ne 0 ] || [ "$versions_option_set" -ne 0 ]; then
    echo "paths must be supplied either as options or as positional arguments" >&2
    usage >&2
    exit 2
  fi
  channels_json=${positional[0]}
  if [ "${#positional[@]}" -eq 2 ]; then
    versions_json=${positional[1]}
  fi
fi

for tool in grep jq; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

for json_file in "$channels_json" "$versions_json"; do
  if [ ! -f "$json_file" ]; then
    echo "JSON file not found: $json_file" >&2
    exit 1
  fi
  if ! jq empty "$json_file" >/dev/null; then
    echo "invalid JSON: $json_file" >&2
    exit 1
  fi
done

if ! jq -e '
  type == "object"
  and (keys | sort) == ["channels", "defaultChannel"]
  and (.defaultChannel | type == "string" and length > 0)
  and (.channels | type == "object")
' "$channels_json" >/dev/null; then
  echo "channel configuration must contain exactly: defaultChannel, channels" >&2
  exit 1
fi

if ! jq -e '.channels | type == "object"' "$versions_json" >/dev/null; then
  echo "versions manifest must contain a top-level channels object: $versions_json" >&2
  exit 1
fi

invalid=0
declare -A channel_output_owners=()
channel_output_suffixes=(
  ""
  "-aztec"
  "-aztec-anvil"
  "-aztec-bb"
  "-aztec-bin"
  "-aztec-cast"
  "-aztec-chisel"
  "-aztec-forge"
  "-aztec-nargo"
  "-aztec-wallet"
  "-bb"
  "-contracts"
  "-counter-contract-e2e"
  "-e2e"
  "-foundry"
  "-getting-started-e2e"
  "-nargo"
  "-noir"
)

channel_name_is_valid() {
  local channel=$1

  if [[ ! "$channel" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
    return 1
  fi

  case "$channel" in
    default|mirror|aztec|aztec-anvil|aztec-bb|aztec-bin|aztec-cast|aztec-chisel|aztec-contracts|aztec-forge|aztec-foundry|aztec-nargo|aztec-noir|aztec-wallet|bb|e2e|getting-started-e2e|nargo)
      return 1
      ;;
  esac

  return 0
}

register_channel_outputs() {
  local channel=$1
  local output
  local output_label
  local owner_label
  local suffix

  for suffix in "${channel_output_suffixes[@]}"; do
    output="${channel}${suffix}"
    if [ -n "${channel_output_owners[$output]+set}" ] && [ "${channel_output_owners[$output]}" != "$channel" ]; then
      output_label=$(jq -rn --arg output "$output" '$output | @json')
      owner_label=$(jq -rn --arg owner "${channel_output_owners[$output]}" '$owner | @json')
      echo "channel $channel conflicts with $owner_label at flake output $output_label" >&2
      invalid=1
      continue
    fi
    channel_output_owners[$output]=$channel
  done
}

while IFS= read -r channel_entry; do
  channel=$(jq -r '.key' <<<"$channel_entry")
  channel_label=$(jq -r '.key | @json' <<<"$channel_entry")

  if ! channel_name_is_valid "$channel"; then
    echo "channel $channel_label has an unsafe or reserved name" >&2
    invalid=1
  else
    register_channel_outputs "$channel"
  fi

  if ! jq -e '
    .value
    | if type == "object"
      then (keys | sort) == ["pattern", "tests"]
      else false
      end
  ' <<<"$channel_entry" >/dev/null; then
    echo "channel $channel_label must contain exactly: pattern, tests" >&2
    invalid=1
    continue
  fi

  pattern_valid=1
  if ! jq -e '
    .value.pattern
    | type == "string" and length > 0
  ' <<<"$channel_entry" >/dev/null; then
    echo "channel $channel_label pattern must be a non-empty string" >&2
    invalid=1
    pattern_valid=0
  fi

  if [ "$pattern_valid" -ne 0 ]; then
    pattern=$(jq -r '.value.pattern' <<<"$channel_entry")
    grep_status=0
    LC_ALL=C grep -E -- "$pattern" </dev/null >/dev/null 2>&1 || grep_status=$?
    if [ "$grep_status" -gt 1 ]; then
      echo "channel $channel_label pattern is not a valid grep -E regular expression" >&2
      invalid=1
    fi
  fi

  if ! jq -e '
    .value.tests
    | if type == "object"
      then (keys | sort) == ["counterContract", "gettingStarted"]
      else false
      end
  ' <<<"$channel_entry" >/dev/null; then
    echo "channel $channel_label tests must contain exactly: gettingStarted, counterContract" >&2
    invalid=1
    continue
  fi

  for test_name in gettingStarted counterContract; do
    if ! jq -e --arg test "$test_name" '
      .value.tests[$test] | type == "boolean"
    ' <<<"$channel_entry" >/dev/null; then
      echo "channel $channel_label test $test_name must be boolean" >&2
      invalid=1
    fi
  done
done < <(jq -c '.channels | to_entries[]' "$channels_json")

default_channel=$(jq -r '.defaultChannel' "$channels_json")
default_channel_label=$(jq -r '.defaultChannel | @json' "$channels_json")
if ! jq -e --arg channel "$default_channel" '.channels | has($channel)' "$channels_json" >/dev/null; then
  echo "default channel $default_channel_label is not configured" >&2
  invalid=1
fi

while IFS= read -r state_entry; do
  channel=$(jq -r '.key' <<<"$state_entry")
  channel_label=$(jq -r '.key | @json' <<<"$state_entry")

  if ! channel_name_is_valid "$channel"; then
    echo "versions channel $channel_label has an unsafe or reserved name" >&2
    invalid=1
  fi

  if ! jq -e '
    .value
    | if type == "object"
      then keys == ["tag"]
      else false
      end
  ' <<<"$state_entry" >/dev/null; then
    echo "versions channel $channel_label must contain exactly: tag" >&2
    invalid=1
    continue
  fi

  if ! jq -e '
    .value.tag | type == "string" and length > 0
  ' <<<"$state_entry" >/dev/null; then
    echo "versions channel $channel_label tag must be a non-empty string" >&2
    invalid=1
    continue
  fi

  if ! jq -e --arg channel "$channel" '.channels | has($channel)' "$channels_json" >/dev/null; then
    continue
  fi

  if [ "$allow_missing_releases" -eq 0 ]; then
    tag=$(jq -r '.value.tag' <<<"$state_entry")
    if ! jq -e --arg tag "$tag" '
      .releases
      | if type == "object" then .[$tag] != null else false end
    ' "$versions_json" >/dev/null; then
      tag_label=$(jq -rn --arg tag "$tag" '$tag | @json')
      echo "configured channel $channel_label points to missing release: $tag_label" >&2
      invalid=1
    fi
  fi
done < <(jq -c '.channels | to_entries[]' "$versions_json")

if [ "$invalid" -ne 0 ]; then
  exit 1
fi

configured_count=$(jq '.channels | length' "$channels_json")
state_count=$(jq '.channels | length' "$versions_json")
echo "channel configuration is valid ($configured_count configured, $state_count state entries)"
