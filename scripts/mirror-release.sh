#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mirror-release.sh [--channel NAME] <tag>

Mirrors an Aztec upstream release into this flake:

  - updates versions.json and, when provided, the channel pointer
  - updates per-release node-runtime package pins
  - regenerates the per-release node-runtime lockfile
  - refreshes the release npmDepsHash by rebuilding aztec-node-runtime

The tag may be passed with or without the leading "v".
EOF
}

channel=""
tag=""

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
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      if [ -n "$tag" ]; then
        echo "only one tag may be provided" >&2
        exit 2
      fi
      tag=$1
      ;;
  esac
  shift
done

if [ -z "$tag" ]; then
  usage >&2
  exit 2
fi

for tool in jq nix npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

case "$tag" in
  v*) ;;
  *) tag="v$tag" ;;
esac

version=${tag#v}
node_runtime_dir="node-runtime/$tag"
package_json="$node_runtime_dir/package.json"
versions_json="versions.json"
build_attr=${MIRROR_BUILD_ATTR:-}
fake_hash="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

update_json_file() {
  local file=$1
  shift

  local next="$tmp_dir/$(basename "$file").next"
  jq "$@" "$file" > "$next"
  mv "$next" "$file"
}

set_npm_deps_hash() {
  local hash=$1

  update_json_file "$versions_json" \
    --arg tag "$tag" \
    --arg hash "$hash" \
    '.releases[$tag].npmDepsHash = $hash'
}

extract_got_hash() {
  local log_file=$1

  sed -nE 's/^.*got:[[:space:]]*(sha256-[A-Za-z0-9+\/=]+).*$/\1/p' "$log_file" | tail -n 1
}

nix_build_node_runtime() {
  if [ -n "$build_attr" ]; then
    nix build -L --no-link "$build_attr"
  else
    nix build -L --no-link \
      --file scripts/release-package.nix \
      --argstr tag "$tag" \
      --argstr package node-runtime
  fi
}

mkdir -p "$node_runtime_dir"

update_args=("$tag")
if [ -n "$channel" ]; then
  update_args+=(--set-channel "$channel")
fi
if [ "$channel" = "v4-stable" ] || [ "${MIRROR_SET_LATEST:-0}" = "1" ]; then
  update_args+=(--set-latest)
fi

scripts/update-release.sh "${update_args[@]}"

jq -n \
  --arg version "$version" \
  '{
    name: "aztec-node-runtime",
    version: $version,
    private: true,
    type: "module",
    dependencies: {
      "@aztec/aztec": $version,
      "@aztec/bb.js": $version,
      "@aztec/cli-wallet": $version
    }
  }' > "$package_json"

npm install \
  --package-lock-only \
  --ignore-scripts \
  --no-audit \
  --no-fund \
  --prefix "$node_runtime_dir"

if git rev-parse --show-toplevel >/dev/null 2>&1; then
  git add "$package_json" "$node_runtime_dir/package-lock.json"
fi

set_npm_deps_hash "$fake_hash"

build_log="$tmp_dir/npm-deps-hash.log"
if nix_build_node_runtime > "$build_log" 2>&1; then
  echo "nix build succeeded with the existing npmDepsHash"
  exit 0
fi

npm_deps_hash=$(extract_got_hash "$build_log")
if [ -z "$npm_deps_hash" ]; then
  cat "$build_log" >&2
  echo "could not extract npmDepsHash from nix build output" >&2
  exit 1
fi

set_npm_deps_hash "$npm_deps_hash"
nix_build_node_runtime

echo "mirrored $tag"
