#!/usr/bin/env bash
set -euo pipefail

usage='usage: sign-android.sh INPUT_DIR OUTPUT_DIR KEYSTORE RELEASE_TAG'
input_dir="${1:?$usage}"
output_dir="${2:?$usage}"
keystore="${3:?$usage}"
release_tag="${4:?$usage}"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'invalid stable release tag' >&2; exit 1; }

: "${ANDROID_KEY_ALIAS:?ANDROID_KEY_ALIAS is required}"
: "${ANDROID_STORE_PASSWORD:?ANDROID_STORE_PASSWORD is required}"
: "${ANDROID_KEY_PASSWORD:?ANDROID_KEY_PASSWORD is required}"
: "${ANDROID_SDK_ROOT:?ANDROID_SDK_ROOT is required}"

build_tools="$(find "$ANDROID_SDK_ROOT/build-tools" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
zipalign="$build_tools/zipalign"
apksigner="$build_tools/apksigner"
[[ -x "$zipalign" ]] || { echo "zipalign was not found" >&2; exit 1; }
[[ -x "$apksigner" ]] || { echo "apksigner was not found" >&2; exit 1; }
[[ -f "$keystore" ]] || { echo "Android keystore was not found" >&2; exit 1; }

mkdir -p "$output_dir"
work_dir="$(mktemp -d "${RUNNER_TEMP:?RUNNER_TEMP is required}/bettbox-android-sign.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

# Keep artifact subdirectories separate so duplicate names cannot be overwritten
# during download. Validate the entire input set before using the signing key.
shopt -s globstar nullglob dotglob
apks=("$input_dir"/**/*.apk)
[[ ${#apks[@]} == 8 ]] || { echo "expected eight input APKs, found ${#apks[@]}" >&2; exit 1; }
inputs=()
for edition in '' '-standard'; do
  for abi in arm64-v8a x86_64 armeabi-v7a universal; do
    filename="Bettbox-${release_tag#v}-android$edition-$abi.apk"
    matches=("$input_dir"/**/"$filename")
    if [[ ${#matches[@]} != 1 || ! -f "${matches[0]:-}" || -L "${matches[0]:-}" || ! -s "${matches[0]:-}" ]]; then
      echo "expected exactly one nonempty regular input: $filename" >&2
      exit 1
    fi
    inputs+=("${matches[0]}")
  done
done

for input in "${inputs[@]}"; do
  filename="${input##*/}"
  aligned="$work_dir/$filename"
  output="$output_dir/$filename"

  "$zipalign" -f -p 4 "$input" "$aligned"
  "$apksigner" sign \
    --ks "$keystore" \
    --ks-key-alias "$ANDROID_KEY_ALIAS" \
    --ks-pass env:ANDROID_STORE_PASSWORD \
    --key-pass env:ANDROID_KEY_PASSWORD \
    --out "$output" \
    "$aligned"
  "$apksigner" verify --verbose "$output"
  "$zipalign" -c -v 4 "$output" >/dev/null
done

outputs=("$output_dir"/*.apk)
[[ ${#outputs[@]} == 8 ]] || { echo "expected eight signed APKs, found ${#outputs[@]}" >&2; exit 1; }
