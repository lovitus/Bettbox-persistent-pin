#!/usr/bin/env bash
set -euo pipefail

dist_dir="${1:?usage: validate-release-assets.sh DIST_DIR RELEASE_TAG}"
release_tag="${2:?usage: validate-release-assets.sh DIST_DIR RELEASE_TAG}"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid stable release tag" >&2; exit 1; }
version="${release_tag#v}"

patterns=(
  'Bettbox-*-android-arm64-v8a.apk'
  'Bettbox-*-android-x86_64.apk'
  'Bettbox-*-android-armeabi-v7a.apk'
  'Bettbox-*-android-universal.apk'
  'Bettbox-*-windows-amd64-setup.exe'
  'Bettbox-*-windows-arm64-setup.exe'
  'Bettbox-*-windows-amd64-compatible-setup.exe'
  'Bettbox-*-windows-amd64-compatible-portable.zip'
  'Bettbox-*-macos-arm64.dmg'
  'Bettbox-*-macos-amd64.dmg'
  'Bettbox-*-linux-amd64-compatible.AppImage'
  'Bettbox-*-linux-amd64-compatible.rpm'
  'Bettbox-*-linux-amd64.AppImage'
  'Bettbox-*-linux-amd64.deb'
  'Bettbox-*-linux-arm64.deb'
  'Bettbox-*-linux-amd64.rpm'
  'Bettbox-*-linux-amd64-compatible.deb'
)

expected=()
for pattern in "${patterns[@]}"; do
  filename="${pattern/\*/$version}"
  expected+=("$filename")
  asset="$dist_dir/$filename"
  [[ -f "$asset" && ! -L "$asset" && -s "$asset" ]] || {
    echo "missing, empty or non-regular release asset: $filename" >&2
    exit 1
  }
done

# Run before adding source/provenance/checksums. Reject extra versions, retired
# variants, raw signing payloads, directories and other unreviewed artifacts.
diff -u \
  <(printf '%s\n' "${expected[@]}" | LC_ALL=C sort) \
  <(find "$dist_dir" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort)
