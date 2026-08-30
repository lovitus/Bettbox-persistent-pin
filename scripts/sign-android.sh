#!/usr/bin/env bash
set -euo pipefail

input_dir="${1:?usage: sign-android.sh INPUT_DIR OUTPUT_DIR KEYSTORE}"
output_dir="${2:?usage: sign-android.sh INPUT_DIR OUTPUT_DIR KEYSTORE}"
keystore="${3:?usage: sign-android.sh INPUT_DIR OUTPUT_DIR KEYSTORE}"

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

patterns=(
  '*-android-arm64-v8a.apk'
  '*-android-x86_64.apk'
  '*-android-armeabi-v7a.apk'
  '*-android-universal.apk'
)

for pattern in "${patterns[@]}"; do
  mapfile -t matches < <(find "$input_dir" -type f -name "$pattern" -print)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    echo "expected exactly one input matching ${pattern}, found ${#matches[@]}" >&2
    exit 1
  fi

  input="${matches[0]}"
  filename="$(basename "$input")"
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

output_count="$(find "$output_dir" -maxdepth 1 -type f -name '*.apk' | wc -l | tr -d ' ')"
[[ "$output_count" == 4 ]] || { echo "expected four signed APKs, found ${output_count}" >&2; exit 1; }
