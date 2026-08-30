#!/usr/bin/env bash
set -euo pipefail

dist_dir="${1:?usage: validate-release-assets.sh DIST_DIR}"

patterns=(
  'Bettbox-*-android-arm64-v8a.apk'
  'Bettbox-*-android-x86_64.apk'
  'Bettbox-*-android-armeabi-v7a.apk'
  'Bettbox-*-android-universal.apk'
  'Bettbox-*-windows-amd64-setup.exe'
  'Bettbox-*-windows-arm64-setup.exe'
  'Bettbox-*-windows-amd64-compatible-setup.exe'
  'Bettbox-*-macos-arm64.dmg'
  'Bettbox-*-macos-amd64.dmg'
  'Bettbox-*-macos-amd64-compatible.dmg'
  'Bettbox-*-linux-amd64.AppImage'
  'Bettbox-*-linux-amd64.deb'
  'Bettbox-*-linux-arm64.deb'
  'Bettbox-*-linux-amd64.rpm'
  'Bettbox-*-linux-amd64-compatible.deb'
)

for pattern in "${patterns[@]}"; do
  mapfile -t matches < <(find "$dist_dir" -maxdepth 1 -type f -name "$pattern" -print)
  if [[ "${#matches[@]}" -ne 1 ]]; then
    echo "expected exactly one release asset matching ${pattern}, found ${#matches[@]}" >&2
    exit 1
  fi
  [[ -s "${matches[0]}" ]] || { echo "empty release asset: ${matches[0]}" >&2; exit 1; }
done

if find "$dist_dir" -maxdepth 1 -type f -name 'raw-*' | grep -q .; then
  echo "raw unsigned signing payloads must not enter a release" >&2
  exit 1
fi
