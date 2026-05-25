#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/inspect-artifacts.sh <path-or-url>...

Accepts directories, files, tar archives, or HTTP(S) URLs. Archives are unpacked
to a temporary directory before inspection.
EOF
}

if [ "$#" -eq 0 ]; then
  usage >&2
  exit 2
fi

tmp_root=$(mktemp -d)
trap 'rm -rf "$tmp_root"' EXIT

have() {
  command -v "$1" >/dev/null 2>&1
}

is_url() {
  case "$1" in
    http://*|https://*) return 0 ;;
    *) return 1 ;;
  esac
}

download_url() {
  local url=$1
  local out=$2

  if ! have curl; then
    echo "curl is required to inspect URLs" >&2
    exit 1
  fi

  curl --fail --location --silent --show-error "$url" --output "$out"
}

unpack_archive() {
  local archive=$1
  local out_dir=$2

  mkdir -p "$out_dir"

  case "$archive" in
    *.tar.gz|*.tgz)
      tar -xzf "$archive" -C "$out_dir"
      ;;
    *.tar.zst|*.zst)
      if ! have zstd; then
        echo "zstd is required to unpack $archive" >&2
        exit 1
      fi
      tar --use-compress-program='zstd -d' -xf "$archive" -C "$out_dir"
      ;;
    *.tar)
      tar -xf "$archive" -C "$out_dir"
      ;;
    *)
      return 1
      ;;
  esac
}

materialize_input() {
  local input=$1
  local index=$2
  local work="$tmp_root/input-$index"
  local source=$input

  mkdir -p "$work"

  if is_url "$input"; then
    source="$work/download"
    case "$input" in
      *.tar.gz|*.tgz) source="$source.tar.gz" ;;
      *.tar.zst|*.zst) source="$source.tar.zst" ;;
      *.tar) source="$source.tar" ;;
    esac
    download_url "$input" "$source"
  fi

  if [ -d "$source" ]; then
    printf '%s\n' "$source"
    return
  fi

  if [ ! -e "$source" ]; then
    echo "not found: $input" >&2
    exit 1
  fi

  local unpacked="$work/unpacked"
  if unpack_archive "$source" "$unpacked"; then
    printf '%s\n' "$unpacked"
  else
    printf '%s\n' "$source"
  fi
}

candidate_files() {
  local root=$1

  if [ -f "$root" ]; then
    printf '%s\0' "$root"
    return
  fi

  find "$root" -type f \( -perm -0100 -o -name '*.so' -o -name '*.node' \) -print0
}

classify_binary() {
  local file_path=$1
  local file_output=$2
  local ldd_output=$3
  local interp_output=$4

  if [[ "$file_output" != *ELF* ]]; then
    echo "classification: non-ELF or script"
  elif [[ "$file_output" == *"statically linked"* ]]; then
    echo "classification: fully static ELF"
  elif [[ -n "$interp_output" ]]; then
    if grep -q "not found" <<<"$ldd_output"; then
      echo "classification: dynamically linked ELF with missing libraries"
    else
      echo "classification: dynamically linked ELF, likely autoPatchelfHook candidate"
    fi
  else
    echo "classification: ELF without visible interpreter; inspect manually"
  fi
}

inspect_file() {
  local file_path=$1
  local file_output=""
  local ldd_output=""
  local interp_output=""

  echo
  echo "==> $file_path"

  if have file; then
    file_output=$(file "$file_path" || true)
    echo "$file_output"
  else
    echo "file: unavailable"
  fi

  if have ldd; then
    echo "-- ldd"
    ldd_output=$(ldd "$file_path" 2>&1 || true)
    echo "$ldd_output"
  fi

  if have readelf; then
    echo "-- ELF interpreter"
    interp_output=$(readelf -l "$file_path" 2>/dev/null | sed -n 's/.*Requesting program interpreter: \(.*\)]/\1/p' || true)
    if [ -n "$interp_output" ]; then
      echo "$interp_output"
    else
      echo "none detected"
    fi
  fi

  if have patchelf; then
    echo "-- patchelf"
    patchelf --print-interpreter "$file_path" 2>/dev/null || true
    patchelf --print-rpath "$file_path" 2>/dev/null || true
  fi

  classify_binary "$file_path" "$file_output" "$ldd_output" "$interp_output"
}

index=0
for input in "$@"; do
  index=$((index + 1))
  root=$(materialize_input "$input" "$index")
  echo "Inspecting $input"

  found=0
  while IFS= read -r -d '' file_path; do
    found=1
    inspect_file "$file_path"
  done < <(candidate_files "$root")

  if [ "$found" -eq 0 ]; then
    echo "No executable, .so, or .node files found under $root"
  fi
done
