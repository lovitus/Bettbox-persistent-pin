#!/usr/bin/env bash
set -euo pipefail

dist_dir="${1:?usage: validate-release-assets.sh DIST_DIR RELEASE_TAG}"
release_tag="${2:?usage: validate-release-assets.sh DIST_DIR RELEASE_TAG}"
[[ "$release_tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid stable release tag" >&2; exit 1; }
version="${release_tag#v}"

prefix="Bettbox-$version"
expected=("$prefix-windows-amd64-portable.zip" "$prefix-windows-amd64-compatible-portable.zip")
for edition in '' '-standard'; do
  for abi in arm64-v8a x86_64 armeabi-v7a universal; do
    expected+=("$prefix-android$edition-$abi.apk")
  done
  for arch in amd64 arm64 amd64-compatible; do
    expected+=("$prefix-windows-$arch$edition-setup.exe" "$prefix-linux-$arch$edition.deb")
  done
  for arch in arm64 amd64; do
    expected+=("$prefix-macos-$arch$edition.dmg")
  done
  for arch in amd64 amd64-compatible; do
    expected+=("$prefix-linux-$arch$edition.AppImage" "$prefix-linux-$arch$edition.rpm")
  done
done

for filename in "${expected[@]}"; do
  asset="$dist_dir/$filename"
  [[ -f "$asset" && ! -L "$asset" && -s "$asset" ]] || {
    echo "missing, empty or non-regular release asset: $filename" >&2
    exit 1
  }
done

# Run before adding source/provenance/checksums. Reject extra versions, retired
# variants, raw signing payloads, directories and other unreviewed artifacts.
shopt -s dotglob nullglob
actual=("$dist_dir"/*)
[[ ${#actual[@]} == ${#expected[@]} ]] || {
  echo "expected ${#expected[@]} release assets, found ${#actual[@]} directory entries" >&2
  exit 1
}
