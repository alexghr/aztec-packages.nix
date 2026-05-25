#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mirror-release.sh <tag>

Mirrors an Aztec upstream release into this flake:

  - updates versions.json and marks the release as latest
  - updates node-runtime/package.json dependency pins
  - regenerates node-runtime/package-lock.json
  - refreshes the release npmDepsHash by rebuilding aztec-node-runtime

The tag may be passed with or without the leading "v".
EOF
}

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

for tool in jq nix npm; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

tag=$1
case "$tag" in
  v*) ;;
  *) tag="v$tag" ;;
esac

version=${tag#v}
node_runtime_dir="node-runtime"
package_json="$node_runtime_dir/package.json"
versions_json="versions.json"
build_attr=${MIRROR_BUILD_ATTR:-.#aztec-node-runtime}
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

if [ ! -f "$package_json" ]; then
  echo "node runtime package file not found: $package_json" >&2
  exit 1
fi

scripts/update-release.sh "$tag" --set-latest

update_json_file "$package_json" \
  --arg version "$version" \
  '.version = $version
   | .dependencies["@aztec/aztec"] = $version
   | .dependencies["@aztec/bb.js"] = $version
   | .dependencies["@aztec/cli-wallet"] = $version'

npm install \
  --package-lock-only \
  --ignore-scripts \
  --no-audit \
  --no-fund \
  --prefix "$node_runtime_dir"

set_npm_deps_hash "$fake_hash"

build_log="$tmp_dir/npm-deps-hash.log"
if nix build -L --no-link "$build_attr" > "$build_log" 2>&1; then
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
nix build -L --no-link "$build_attr"

echo "mirrored $tag"
