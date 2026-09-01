#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/mirror-release.sh [--channel NAME] [--repository OWNER/NAME] [--npm-scope @SCOPE] [--bb-package @SCOPE/NAME] <tag>

Mirrors an Aztec upstream release into this flake:

  - updates versions.json and, when provided, the channel pointer
  - updates per-release node-runtime package pins
  - regenerates the per-release node-runtime lockfile
  - refreshes the release npmDepsHash by rebuilding aztec-node-runtime

The tag may be passed with or without the leading "v".
EOF
}

channel=""
repository=""
npm_scope=""
bb_package=""
l1_artifacts_package=""
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
    --repository)
      shift
      repository=${1:-}
      if [ -z "$repository" ]; then
        echo "--repository requires an owner/name" >&2
        exit 2
      fi
      ;;
    --npm-scope)
      shift
      npm_scope=${1:-}
      if [ -z "$npm_scope" ]; then
        echo "--npm-scope requires a scope" >&2
        exit 2
      fi
      ;;
    --bb-package)
      shift
      bb_package=${1:-}
      if [ -z "$bb_package" ]; then
        echo "--bb-package requires a scoped package name" >&2
        exit 2
      fi
      ;;
    --l1-artifacts-package)
      shift
      l1_artifacts_package=${1:-}
      if [ -z "$l1_artifacts_package" ]; then
        echo "--l1-artifacts-package requires a scoped package name" >&2
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

case "$l1_artifacts_package" in
  @*/*) ;;
  "")
    echo "--l1-artifacts-package is required" >&2
    exit 2
    ;;
  *)
    echo "L1 artifacts package must be scoped: $l1_artifacts_package" >&2
    exit 2
    ;;
esac

case "$bb_package" in
  @*/*) ;;
  "")
    echo "--bb-package is required" >&2
    exit 2
    ;;
  *)
    echo "BB package must be scoped: $bb_package" >&2
    exit 2
    ;;
esac

case "$repository" in
  */*) ;;
  "")
    echo "--repository is required" >&2
    exit 2
    ;;
  *)
    echo "repository must be an owner/name: $repository" >&2
    exit 2
    ;;
esac

case "$npm_scope" in
  @*) ;;
  "")
    echo "--npm-scope is required" >&2
    exit 2
    ;;
  *)
    echo "npm scope must start with @: $npm_scope" >&2
    exit 2
    ;;
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

update_args=("$tag" --repository "$repository" --npm-scope "$npm_scope" --bb-package "$bb_package" --l1-artifacts-package "$l1_artifacts_package")
if [ -n "$channel" ]; then
  update_args+=(--set-channel "$channel")
fi
if [ "$channel" = "v4-stable" ] || [ "${MIRROR_SET_LATEST:-0}" = "1" ]; then
  update_args+=(--set-latest)
fi

scripts/update-release.sh "${update_args[@]}"

aztec_package=$(jq -r --arg tag "$tag" '.releases[$tag].npm.aztec.package' "$versions_json")
aztec_package_version=$(jq -r --arg tag "$tag" '.releases[$tag].npm.aztec.version // .releases[$tag].version' "$versions_json")
bb_js_package=$(jq -r --arg tag "$tag" '.releases[$tag].npm.bbJs.package' "$versions_json")
bb_js_package_version=$(jq -r --arg tag "$tag" '.releases[$tag].npm.bbJs.version // .releases[$tag].version' "$versions_json")
cli_wallet_package=$(jq -r --arg tag "$tag" '.releases[$tag].npm.cliWallet.package' "$versions_json")
cli_wallet_package_version=$(jq -r --arg tag "$tag" '.releases[$tag].npm.cliWallet.version // .releases[$tag].version' "$versions_json")

jq -n \
  --arg version "$version" \
  --arg aztecPackage "$aztec_package" \
  --arg aztecPackageVersion "$aztec_package_version" \
  --arg bbJsPackage "$bb_js_package" \
  --arg bbJsPackageVersion "$bb_js_package_version" \
  --arg cliWalletPackage "$cli_wallet_package" \
  --arg cliWalletPackageVersion "$cli_wallet_package_version" \
  '{
    name: "aztec-node-runtime",
    version: $version,
    private: true,
    type: "module",
    dependencies: {
      ($aztecPackage): $aztecPackageVersion,
      ($bbJsPackage): $bbJsPackageVersion,
      ($cliWalletPackage): $cliWalletPackageVersion
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
