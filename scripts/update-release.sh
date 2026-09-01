#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/update-release.sh <tag> [--repository OWNER/NAME] [--npm-scope @SCOPE] [--bb-package @SCOPE/NAME] [--dry-run] [--set-latest] [--set-channel NAME] [--channels-json PATH] [--versions-json PATH]

Collects confirmed release metadata for an Aztec tag and merges it into
versions.json by default. Use --dry-run to print the generated manifest fragment
without writing. Existing latest values are preserved unless --set-latest is
passed. Use --set-channel to update a channel declared in channels.json.

Required tools: curl, git, grep, jq, nix.
EOF
}

tag=""
dry_run=0
set_latest=0
set_channel=""
channels_json="channels.json"
versions_json="versions.json"
aztec_repo=""
npm_scope=""
bb_package=""
l1_artifacts_package=""

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
    --channels-json)
      shift
      channels_json=${1:-}
      if [ -z "$channels_json" ]; then
        echo "--channels-json requires a path" >&2
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
    --repository)
      shift
      aztec_repo=${1:-}
      if [ -z "$aztec_repo" ]; then
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

case "$aztec_repo" in
  */*) ;;
  "")
    echo "--repository is required" >&2
    exit 2
    ;;
  *)
    echo "repository must be an owner/name: $aztec_repo" >&2
    exit 2
    ;;
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

for tool in curl git grep jq nix; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "required tool not found: $tool" >&2
    exit 1
  fi
done

foundry_repo="foundry-rs/foundry"
aztec_repo_api="https://api.github.com/repos/$aztec_repo"
foundry_repo_api="https://api.github.com/repos/$foundry_repo"
version=${tag#v}
tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

aztec_release_json="$tmp_dir/aztec-release.json"
foundry_release_json="$tmp_dir/foundry-release.json"
install_versions="$tmp_dir/install-versions"
manifest_json="$tmp_dir/manifest.json"
systems=(x86_64-linux aarch64-linux)

die() {
  echo "$*" >&2
  exit 1
}

if [ -n "$set_channel" ]; then
  if [ ! -f "$channels_json" ]; then
    die "channel definitions not found: $channels_json"
  fi
  if ! jq -e --arg channel "$set_channel" '.channels[$channel] != null' "$channels_json" >/dev/null; then
    die "unknown release channel: $set_channel"
  fi

  channel_pattern=$(jq -r --arg channel "$set_channel" '.channels[$channel].pattern // empty' "$channels_json")
  if [ -z "$channel_pattern" ]; then
    die "release channel has no tag pattern: $set_channel"
  fi

  pattern_status=0
  printf "%s\n" "$tag" | grep -Eq -- "$channel_pattern" || pattern_status=$?
  if [ "$pattern_status" -gt 1 ]; then
    die "release channel has an invalid tag pattern: $set_channel"
  fi
  if [ "$pattern_status" -ne 0 ]; then
    die "tag $tag does not match channel $set_channel pattern: $channel_pattern"
  fi
fi

if ! git ls-remote --exit-code --tags "https://github.com/$aztec_repo.git" "refs/tags/$tag" >/dev/null; then
  echo "upstream tag not found in $aztec_repo: $tag" >&2
  exit 1
fi

if ! curl --fail --location --silent \
  "$aztec_repo_api/releases/tags/$tag" \
  --output "$aztec_release_json"; then
  : > "$aztec_release_json"
fi

curl --fail --location --silent --show-error \
  "https://install.aztec-labs.com/$version/versions" \
  --output "$install_versions" || die "missing Aztec install versions file for $version"

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
  --arg noirVersion "$noir_version" \
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
        noirVersion: $noirVersion,
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
    }
  }' > "$manifest_json"

replace_manifest() {
  local next="$tmp_dir/manifest.next.json"
  jq "$@" "$manifest_json" > "$next"
  mv "$next" "$manifest_json"
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
      echo "unrecognized GitHub asset digest format: $digest" >&2
      return 1
      ;;
  esac
}

asset_field() {
  local asset_name=$1
  local field=$2
  local release_file
  local value

  for release_file in "$aztec_release_json" "$foundry_release_json"; do
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

foundry_asset_suffix() {
  case "$1" in
    x86_64-linux) echo "linux_amd64" ;;
    aarch64-linux) echo "linux_arm64" ;;
    x86_64-darwin) echo "darwin_amd64" ;;
    aarch64-darwin) echo "darwin_arm64" ;;
    *)
      echo "unknown system: $1" >&2
      return 1
      ;;
  esac
}

noirup_asset_platform() {
  case "$1" in
    x86_64-linux) echo "x86_64-unknown-linux-gnu" ;;
    aarch64-linux) echo "aarch64-unknown-linux-gnu" ;;
    *)
      echo "unknown system: $1" >&2
      return 1
      ;;
  esac
}

noirup_release_tag() {
  case "$1" in
    [0-9]*)
      echo "v$1"
      ;;
    *)
      echo "$1"
      ;;
  esac
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
      die "missing GitHub release asset $asset_name"
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

add_prefetched_asset() {
  local system=$1
  local key=$2
  local name=$3
  local url=$4
  local hash

  hash=$(nix store prefetch-file --json "$url" | jq -r '.hash') || return 1

  replace_manifest \
    --arg tag "$tag" \
    --arg system "$system" \
    --arg key "$key" \
    --arg name "$name" \
    --arg url "$url" \
    --arg hash "$hash" \
    '.releases[$tag].systems[$system][$key] = {
      source: "noirup",
      name: $name,
      url: $url,
      hash: $hash
    }'
}

add_npm_package() {
  local key=$1
  local package=$2
  local package_version=${3:-$version}
  local encoded=${package//@/%40}
  local npm_json="$tmp_dir/npm-$key.json"
  local metadata_url=""
  local tarball=""
  local integrity=""
  local shasum=""

  encoded=${encoded//\//%2F}
  metadata_url="https://registry.npmjs.org/$encoded/$package_version"

  if ! curl --fail --location --silent --show-error "$metadata_url" --output "$npm_json"; then
    die "missing npm package $package@$package_version"
  fi

  tarball=$(jq -r '.dist.tarball // empty' "$npm_json")
  integrity=$(jq -r '.dist.integrity // empty' "$npm_json")
  shasum=$(jq -r '.dist.shasum // empty' "$npm_json")

  if [ -z "$tarball" ] || [ -z "$integrity" ]; then
    die "npm package $package@$package_version is missing tarball or integrity metadata"
  fi

  replace_manifest \
    --arg tag "$tag" \
    --arg key "$key" \
    --arg package "$package" \
    --arg version "$package_version" \
    --arg url "$tarball" \
    --arg hash "$integrity" \
    --arg shasum "$shasum" \
    '.releases[$tag].npm[$key] = {
      package: $package,
      version: $version,
      url: $url,
      hash: $hash,
      shasum: $shasum
    }'
}

resolve_npm_package_version() {
  local package=$1
  local preferred=$2
  local encoded=${package//@/%40}
  local package_json="$tmp_dir/npm-versions-${package##*/}.json"
  local qualifier=${preferred#*-}

  encoded=${encoded//\//%2F}
  curl --fail --location --silent --show-error \
    "https://registry.npmjs.org/$encoded" --output "$package_json" \
    || die "missing npm package $package"

  if jq -e --arg version "$preferred" '.versions[$version] != null' "$package_json" >/dev/null; then
    echo "$preferred"
    return
  fi

  jq -r --arg suffix "-$qualifier" \
    '.versions | keys[] | select(endswith($suffix))' "$package_json" \
    | sort -V \
    | tail -n 1
}

add_noirup_asset() {
  local system=$1
  local suffix
  local base_url
  local release_tag
  local name
  local url

  if [ -z "$noir_version" ]; then
    die "missing Noir version in install versions file"
  fi

  suffix=$(noirup_asset_platform "$system")
  release_tag=$(noirup_release_tag "$noir_version")
  base_url="https://github.com/noir-lang/noir/releases/download/$release_tag"
  name="noir-$suffix.tar.gz"
  url="$base_url/$name"

  add_prefetched_asset "$system" noir "$name" "$url" || die "missing noirup asset $url"
}

for system in "${systems[@]}"; do
  add_noirup_asset "$system"
done

if [ -n "$foundry_version" ]; then
  curl --fail --location --silent --show-error \
    "$foundry_repo_api/releases/tags/v$foundry_version" \
    --output "$foundry_release_json" || die "missing Foundry release v$foundry_version"

  if [ -s "$foundry_release_json" ]; then
    for system in "${systems[@]}"; do
      suffix=$(foundry_asset_suffix "$system")
      add_github_asset "$system" foundry "foundry_v${foundry_version}_${suffix}.tar.gz" 1
    done
  fi
else
  die "missing Foundry version in install versions file"
fi

add_npm_package aztec "$npm_scope/aztec"
add_npm_package cliWallet "$npm_scope/cli-wallet"
add_npm_package noirContractsJs "$npm_scope/noir-contracts.js"
add_npm_package noirTestContractsJs "$npm_scope/noir-test-contracts.js"
add_npm_package protocolContracts "$npm_scope/protocol-contracts"

bb_js_version=$(resolve_npm_package_version "$bb_package" "$version")
l1_artifacts_version=$(resolve_npm_package_version "$l1_artifacts_package" "$version")

[ -n "$bb_js_version" ] || die "could not resolve $bb_package for $version"
[ -n "$l1_artifacts_version" ] || die "could not resolve $l1_artifacts_package for $version"

add_npm_package bbJs "$bb_package" "$bb_js_version"
add_npm_package l1Artifacts "$l1_artifacts_package" "$l1_artifacts_version"

for system in "${systems[@]}"; do
  if ! jq -e --arg tag "$tag" --arg system "$system" '
    .releases[$tag].systems[$system].foundry?
    and .releases[$tag].systems[$system].noir?
  ' "$manifest_json" >/dev/null; then
    echo "release $tag is incomplete for $system; refusing to update $versions_json" >&2
    exit 1
  fi
done

if [ -f "$versions_json" ]; then
  existing_npm_deps_hash=$(jq -r --arg tag "$tag" '.releases[$tag].npmDepsHash // empty' "$versions_json")
  if [ -n "$existing_npm_deps_hash" ]; then
    replace_manifest \
      --arg tag "$tag" \
      --arg hash "$existing_npm_deps_hash" \
      '.releases[$tag].npmDepsHash = $hash'
  fi
fi

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
          | .[$setChannel] = { tag: $incoming.latest }
        else .channels
        end
      )
    | .releases = (
        reduce ($incoming.releases | to_entries[]) as $entry
          (.releases // {};
            .[$entry.key] = (
              ($entry.value) as $next |
              (.[$entry.key] // {}) as $existing |
              $next
              | .npmDepsHash = ($existing.npmDepsHash // $next.npmDepsHash)
            )
          )
      )
  ' "$versions_json" "$manifest_json" > "$next_versions"
  mv "$next_versions" "$versions_json"
else
  cp "$manifest_json" "$versions_json"
fi

echo "updated $versions_json for $tag"
