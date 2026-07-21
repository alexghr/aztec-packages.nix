#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mirror-channels.sh [--channel NAME] [--tag TAG]

Mirrors release channels declared in channels.json. Resolved channel tags and
release metadata are stored in versions.json.

With --tag, mirrors that exact tag. If --channel is omitted, the tag is mirrored
to every channel whose pattern matches it. Without --tag, resolves the latest
upstream tag matching each selected channel pattern.
EOF
}

channel=""
tag=""
channels_json="channels.json"
versions_json="versions.json"
aztec_repo_url="https://github.com/AztecProtocol/aztec-packages.git"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --channel)
      shift
      channel=${1:-}
      if [ -z "$channel" ]; then
        echo "--channel requires a channel name" >&2
        exit 2
      fi
      ;;
    --tag)
      shift
      tag=${1:-}
      if [ -z "$tag" ]; then
        echo "--tag requires a release tag" >&2
        exit 2
      fi
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      echo "unexpected argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for tool in git jq sort; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

if [ ! -f "$versions_json" ]; then
  echo "versions manifest not found: $versions_json" >&2
  exit 1
fi

if [ ! -f "$channels_json" ]; then
  echo "channel definitions not found: $channels_json" >&2
  exit 1
fi

scripts/check-channels.sh \
  --allow-missing-releases \
  --channels "$channels_json" \
  --versions "$versions_json"

if [ -n "$channel" ] && ! jq -e --arg channel "$channel" '.channels[$channel] != null' "$channels_json" >/dev/null; then
  echo "unknown release channel: $channel" >&2
  exit 1
fi

normalize_tag() {
  case "$1" in
    v*) echo "$1" ;;
    *) echo "v$1" ;;
  esac
}

latest_matching_tag() {
  local pattern=$1

  git ls-remote --tags "$aztec_repo_url" \
    | sed -n 's#.*refs/tags/##p' \
    | grep -v '\^{}' \
    | grep -E "$pattern" \
    | sort -V \
    | tail -n 1
}

tag_matches_pattern() {
  local selected_tag=$1
  local pattern=$2

  printf "%s\n" "$selected_tag" | grep -Eq "$pattern"
}

mirror_tag() {
  local selected_channel=$1
  local selected_tag=$2
  local args=()
  local previous_tag=""

  if [ -n "$selected_channel" ]; then
    args+=(--channel "$selected_channel")
    previous_tag=$(jq -r --arg channel "$selected_channel" '.channels[$channel].tag // ""' "$versions_json")
  fi

  scripts/mirror-release.sh "${args[@]}" "$selected_tag"

  if [ -n "$previous_tag" ] && [ "$previous_tag" != "$selected_tag" ]; then
    remove_release "$previous_tag"
  fi
}

remove_release() {
  local release_tag=$1
  local next_versions
  local node_runtime_path

  if [ -z "$release_tag" ] || ! jq -e --arg tag "$release_tag" '.releases[$tag] != null' "$versions_json" >/dev/null; then
    return
  fi

  if jq -e --arg tag "$release_tag" --slurpfile configured "$channels_json" '
    .latest == $tag
    or any(
      (.channels // {} | to_entries[]?);
      . as $state
      | $state.value.tag == $tag
        and ($configured[0].channels | has($state.key))
    )
  ' "$versions_json" >/dev/null; then
    echo "kept release $release_tag because it is still referenced"
    return
  fi

  node_runtime_path=$(jq -r --arg tag "$release_tag" '.releases[$tag].nodeRuntime.path // $tag' "$versions_json")
  next_versions=$(mktemp)
  jq --arg tag "$release_tag" '
    del(.releases[$tag])
  ' "$versions_json" > "$next_versions"
  mv "$next_versions" "$versions_json"

  case "$node_runtime_path" in
    ""|/*|*/*|*..*)
      echo "skipping unsafe node-runtime path for $release_tag: $node_runtime_path" >&2
      ;;
    *)
      rm -rf -- "node-runtime/$node_runtime_path"
      ;;
  esac

  echo "removed previous release $release_tag"
}

if [ -n "$tag" ]; then
  tag=$(normalize_tag "$tag")
  mirrored=0

  while IFS= read -r channel_json; do
    selected_channel=$(printf "%s" "$channel_json" | jq -r '.key')
    pattern=$(printf "%s" "$channel_json" | jq -r '.value.pattern // ""')

    if [ -z "$pattern" ] || [ "$pattern" = "null" ]; then
      echo "channel $selected_channel has no pattern" >&2
      exit 1
    fi

    if ! tag_matches_pattern "$tag" "$pattern"; then
      if [ -n "$channel" ]; then
        echo "tag $tag does not match channel $selected_channel pattern: $pattern" >&2
        exit 1
      fi
      continue
    fi

    mirror_tag "$selected_channel" "$tag"
    mirrored=$((mirrored + 1))
  done < <(
    if [ -n "$channel" ]; then
      jq -r --arg channel "$channel" '
        .channels | to_entries[]
        | select(.key == $channel)
        | @json
      ' "$channels_json"
    else
      jq -r '
        .channels | to_entries[]
        | @json
      ' "$channels_json"
    fi
  )

  if [ "$mirrored" -eq 0 ]; then
    echo "tag $tag did not match any configured channel"
  fi

  echo "mirrored $mirrored channel(s)"
  exit 0
fi

mirrored=0
while IFS= read -r channel_json; do
  selected_channel=$(printf "%s" "$channel_json" | jq -r '.key')
  pattern=$(printf "%s" "$channel_json" | jq -r '.value.pattern // ""')
  current_tag=$(jq -r --arg channel "$selected_channel" '.channels[$channel].tag // ""' "$versions_json")

  if [ -z "$pattern" ] || [ "$pattern" = "null" ]; then
    echo "channel $selected_channel has no pattern" >&2
    exit 1
  fi

  next_tag=$(latest_matching_tag "$pattern")
  if [ -z "$next_tag" ]; then
    echo "no upstream tag matched channel $selected_channel pattern: $pattern" >&2
    exit 1
  fi

  if [ "$current_tag" = "$next_tag" ] && jq -e --arg tag "$next_tag" '.releases[$tag] != null' "$versions_json" >/dev/null; then
    echo "channel $selected_channel already mirrors $next_tag"
    continue
  fi

  mirror_tag "$selected_channel" "$next_tag"
  mirrored=$((mirrored + 1))
done < <(
  if [ -n "$channel" ]; then
    jq -r --arg channel "$channel" '
      .channels | to_entries[]
      | select(.key == $channel)
      | @json
    ' "$channels_json"
  else
    jq -r '
      .channels | to_entries[]
      | @json
    ' "$channels_json"
  fi
)

echo "mirrored $mirrored channel(s)"
