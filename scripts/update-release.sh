#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update-release.sh <tag> [--dry-run] [--set-latest] [--set-channel NAME] [--versions-json PATH]

Collects confirmed release metadata for an Aztec tag and merges it into
versions.json by default. Use --dry-run to print the generated manifest fragment
without writing. Existing latest values are preserved unless --set-latest is
passed. Use --set-channel to update a named release channel pointer.

Required tools: curl, git, jq, nix.
EOF
}

tag=""
dry_run=0
set_latest=0
set_channel=""
versions_json="versions.json"

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --dry-run)
      dry_run=1
      ;;
    --set-latest)
      set_latest=1
      ;;
    --set-channel)
      shift
      set_channel=${1:-}
      if [ -z "$set_channel" ]; then
        echo "--set-channel requires a channel name" >&2
        exit 2
      fi
      ;;
    --versions-json)
      shift
      versions_json=${1:-}
      if [ -z "$versions_json" ]; then
        echo "--versions-json requires a path" >&2
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

for tool in curl git jq nix; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

aztec_repo="AztecProtocol/aztec-packages"
barretenberg_repo="AztecProtocol/barretenberg"
foundry_repo="foundry-rs/foundry"
aztec_repo_api="https://api.github.com/repos/$aztec_repo"
barretenberg_repo_api="https://api.github.com/repos/$barretenberg_repo"
foundry_repo_api="https://api.github.com/repos/$foundry_repo"
version=${tag#v}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

aztec_release_json="$tmp_dir/aztec-release.json"
barretenberg_release_json="$tmp_dir/barretenberg-release.json"
foundry_release_json="$tmp_dir/foundry-release.json"
aztec_checkout="$tmp_dir/aztec-checkout"
install_versions="$tmp_dir/install-versions"
manifest_json="$tmp_dir/manifest.json"
systems=(x86_64-linux aarch64-linux)

if ! git ls-remote --exit-code --tags "https://github.com/$aztec_repo.git" "refs/tags/$tag" >/dev/null; then
  echo "upstream tag not found in $aztec_repo: $tag" >&2
  exit 1
fi

curl --fail --location --silent --show-error \
  "$aztec_repo_api/releases/tags/$tag" \
  --output "$aztec_release_json" || true

curl --fail --location --silent --show-error \
  "$barretenberg_repo_api/releases/tags/$tag" \
  --output "$barretenberg_release_json" || true

curl --fail --location --silent --show-error \
  "https://install.aztec-labs.com/$version/versions" \
  --output "$install_versions" || true

git clone \
  --filter=blob:none \
  --depth 1 \
  --branch "$tag" \
  "https://github.com/$aztec_repo.git" \
  "$aztec_checkout" >/dev/null

git -C "$aztec_checkout" submodule update \
  --init \
  --depth 1 \
  noir/noir-repo >/dev/null

for ci3_source in "$aztec_checkout/ci3/source" "$aztec_checkout/ci3/source_bootstrap"; do
  sed -i '/source .*source_redis/d' "$ci3_source"
done

release_url="https://github.com/$aztec_repo/releases/tag/$tag"
if [ -s "$aztec_release_json" ]; then
  release_url=$(jq -r '.html_url // empty' "$aztec_release_json")
fi

node_version=""
noir_version=""
foundry_version=""
if [ -s "$install_versions" ]; then
  node_version=$(awk -F: '/^node:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$install_versions")
  noir_version=$(awk -F: '/^noir:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$install_versions")
  foundry_version=$(awk -F: '/^foundry:/ {gsub(/^[ \t]+/, "", $2); print $2}' "$install_versions")
fi

jq -n \
  --arg tag "$tag" \
  --arg version "$version" \
  --arg nodeVersion "$node_version" \
  --arg foundryVersion "$foundry_version" \
  --arg upstreamRepo "$aztec_repo" \
  --arg releaseUrl "$release_url" \
  --arg installBaseUrl "https://install.aztec-labs.com/$version" \
  '{
    latest: $tag,
    releases: {
      ($tag): {
        version: $version,
        nodeVersion: $nodeVersion,
        foundryVersion: $foundryVersion,
        upstream: {
          repository: $upstreamRepo,
          releaseUrl: $releaseUrl,
          installBaseUrl: $installBaseUrl
        },
        nodeRuntime: {
          path: $tag
        },
        systems: {},
        npm: {},
        npmDepsHash: "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
      }
    },
    unsupported: {}
  }' > "$manifest_json"

replace_manifest() {
  local next="$tmp_dir/manifest.next.json"
  jq "$@" "$manifest_json" > "$next"
  mv "$next" "$manifest_json"
}

add_unsupported_reason() {
  local reason=$1

  replace_manifest \
    --arg tag "$tag" \
    --arg reason "$reason" \
    '.unsupported[$tag].reasons = ((.unsupported[$tag].reasons // []) + [$reason])'
}

sri_from_digest() {
  local digest=$1

  case "$digest" in
    sha256:*)
      nix hash convert --hash-algo sha256 --to sri "${digest#sha256:}"
      ;;
    "")
      return 1
      ;;
    *)
      echo "unsupported GitHub asset digest format: $digest" >&2
      return 1
      ;;
  esac
}

asset_field() {
  local asset_name=$1
  local field=$2
  local release_file
  local value

  for release_file in "$aztec_release_json" "$barretenberg_release_json" "$foundry_release_json"; do
    if [ ! -s "$release_file" ]; then
      continue
    fi

    value=$(jq -r --arg name "$asset_name" --arg field "$field" \
      '.assets[]? | select(.name == $name) | .[$field] // empty' \
      "$release_file" | head -n 1)

    if [ -n "$value" ]; then
      echo "$value"
      return 0
    fi
  done
}

system_asset_suffix() {
  case "$1" in
    x86_64-linux) echo "amd64-linux" ;;
    aarch64-linux) echo "arm64-linux" ;;
    x86_64-darwin) echo "amd64-darwin" ;;
    aarch64-darwin) echo "arm64-darwin" ;;
    *)
      echo "unsupported system: $1" >&2
      return 1
      ;;
  esac
}

foundry_asset_suffix() {
  case "$1" in
    x86_64-linux) echo "linux_amd64" ;;
    aarch64-linux) echo "linux_arm64" ;;
    x86_64-darwin) echo "darwin_amd64" ;;
    aarch64-darwin) echo "darwin_arm64" ;;
    *)
      echo "unsupported system: $1" >&2
      return 1
      ;;
  esac
}

aztec_noir_platform_tag() {
  case "$1" in
    x86_64-linux) echo "linux-gnu-x86_64" ;;
    aarch64-linux) echo "linux-gnu-aarch64" ;;
    *)
      echo "unsupported system: $1" >&2
      return 1
      ;;
  esac
}

aztec_noir_cache_name() {
  local system=$1
  local platform
  local cache_hash

  platform=$(aztec_noir_platform_tag "$system")

  cache_hash=$(
    cd "$aztec_checkout/noir"
    CI=1 \
      CURRENT_VERSION="$version" \
      REF_NAME="$tag" \
      PLATFORM_TAG="$platform" \
      USE_TEST_CACHE=0 \
      ./bootstrap.sh hash
  )

  echo "noir-$cache_hash.tar.gz"
}

system_has_asset() {
  local system=$1
  local key=$2

  jq -e \
    --arg tag "$tag" \
    --arg system "$system" \
    --arg key "$key" \
    '.releases[$tag].systems[$system][$key] != null' \
    "$manifest_json" >/dev/null
}

add_github_asset() {
  local system=$1
  local key=$2
  local asset_name=$3
  local required=$4
  local url=""
  local digest=""
  local hash=""

  url=$(asset_field "$asset_name" browser_download_url)
  digest=$(asset_field "$asset_name" digest)

  if [ -z "$url" ]; then
    if [ "$required" = "1" ]; then
      add_unsupported_reason "missing GitHub release asset $asset_name"
    fi
    return
  fi

  if ! hash=$(sri_from_digest "$digest"); then
    echo "prefetching $asset_name because GitHub digest was unavailable"
    hash=$(nix store prefetch-file --json "$url" | jq -r '.hash')
  fi

  replace_manifest \
    --arg tag "$tag" \
    --arg system "$system" \
    --arg key "$key" \
    --arg name "$asset_name" \
    --arg url "$url" \
    --arg hash "$hash" \
    '.releases[$tag].systems[$system][$key] = {
      name: $name,
      url: $url,
      hash: $hash
    }'
}

add_npm_package() {
  local key=$1
  local package=$2
  local encoded=${package//@/%40}
  local npm_json="$tmp_dir/npm-$key.json"
  local metadata_url=""
  local tarball=""
  local integrity=""
  local shasum=""

  encoded=${encoded//\//%2F}
  metadata_url="https://registry.npmjs.org/$encoded/$version"

  if ! curl --fail --location --silent --show-error "$metadata_url" --output "$npm_json"; then
    add_unsupported_reason "missing npm package $package@$version"
    return
  fi

  tarball=$(jq -r '.dist.tarball // empty' "$npm_json")
  integrity=$(jq -r '.dist.integrity // empty' "$npm_json")
  shasum=$(jq -r '.dist.shasum // empty' "$npm_json")

  if [ -z "$tarball" ] || [ -z "$integrity" ]; then
    add_unsupported_reason "npm package $package@$version is missing tarball or integrity metadata"
    return
  fi

  replace_manifest \
    --arg tag "$tag" \
    --arg key "$key" \
    --arg package "$package" \
    --arg url "$tarball" \
    --arg hash "$integrity" \
    --arg shasum "$shasum" \
    '.releases[$tag].npm[$key] = {
      package: $package,
      url: $url,
      hash: $hash,
      shasum: $shasum
    }'
}

add_barretenberg_asset() {
  local system=$1
  local suffix

  suffix=$(system_asset_suffix "$system")
  add_github_asset "$system" barretenberg "barretenberg-avm-$suffix.tar.gz" 0
  if ! system_has_asset "$system" barretenberg; then
    add_github_asset "$system" barretenberg "barretenberg-$suffix.tar.gz" 1
  fi
}

add_aztec_noir_cache_asset() {
  local system=$1
  local cache_name
  local url
  local hash

  cache_name=$(aztec_noir_cache_name "$system")
  url="https://build-cache.aztec-labs.com/$cache_name"

  if ! hash=$(nix store prefetch-file --json "$url" | jq -r '.hash'); then
    add_unsupported_reason "missing Aztec Noir cache artifact $cache_name"
    return
  fi

  replace_manifest \
    --arg tag "$tag" \
    --arg system "$system" \
    --arg name "$cache_name" \
    --arg url "$url" \
    --arg hash "$hash" \
    '.releases[$tag].systems[$system].noir = {
      name: $name,
      url: $url,
      hash: $hash
    }'
}

for system in "${systems[@]}"; do
  add_barretenberg_asset "$system"
done

for system in "${systems[@]}"; do
  add_aztec_noir_cache_asset "$system"
done

if [ -n "$foundry_version" ]; then
  curl --fail --location --silent --show-error \
    "$foundry_repo_api/releases/tags/v$foundry_version" \
    --output "$foundry_release_json" || add_unsupported_reason "missing Foundry release v$foundry_version"

  if [ -s "$foundry_release_json" ]; then
    for system in "${systems[@]}"; do
      suffix=$(foundry_asset_suffix "$system")
      add_github_asset "$system" foundry "foundry_v${foundry_version}_${suffix}.tar.gz" 1
    done
  fi
else
  add_unsupported_reason "missing Foundry version in install versions file"
fi

add_npm_package aztec "@aztec/aztec"
add_npm_package cli "@aztec/cli"
add_npm_package cliWallet "@aztec/cli-wallet"
add_npm_package bbJs "@aztec/bb.js"
add_npm_package noirContractsJs "@aztec/noir-contracts.js"
add_npm_package noirTestContractsJs "@aztec/noir-test-contracts.js"
add_npm_package protocolContracts "@aztec/protocol-contracts"
add_npm_package l1Artifacts "@aztec/l1-artifacts"

replace_manifest \
  --arg tag "$tag" \
  '.releases[$tag].systems |= with_entries(select(.value.barretenberg? and .value.foundry? and .value.noir?))'

replace_manifest \
  --arg tag "$tag" \
  'if ((.unsupported[$tag].reasons // []) | length) == 0
   then del(.unsupported[$tag])
   else .
   end'

if [ "$dry_run" -eq 1 ]; then
  jq . "$manifest_json"
  exit 0
fi

if [ -f "$versions_json" ]; then
  next_versions="$tmp_dir/versions.next.json"
  jq -s --arg setLatest "$set_latest" --arg setChannel "$set_channel" '
    .[0] as $base |
    .[1] as $incoming |
    $base
    | .latest = (if ($setLatest == "1") or (.latest == null) then $incoming.latest else .latest end)
    | .channels = (
        if $setChannel != ""
        then
          (.channels // {})
          | .[$setChannel] = ((.[$setChannel] // {}) + { tag: $incoming.latest })
        else .channels
        end
      )
    | .releases = ((.releases // {}) + $incoming.releases)
    | .unsupported = ((.unsupported // {}) + ($incoming.unsupported // {}))
  ' "$versions_json" "$manifest_json" > "$next_versions"
  mv "$next_versions" "$versions_json"
else
  cp "$manifest_json" "$versions_json"
fi

echo "updated $versions_json for $tag"
