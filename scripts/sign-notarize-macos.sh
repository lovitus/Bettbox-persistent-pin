#!/usr/bin/env bash
set -euo pipefail

payload_dir="${1:?usage: sign-notarize-macos.sh PAYLOAD_DIR OUTPUT_DIR}"
output_dir="${2:?usage: sign-notarize-macos.sh PAYLOAD_DIR OUTPUT_DIR}"

: "${MACOS_CERTIFICATE_P12:?MACOS_CERTIFICATE_P12 is required}"
: "${MACOS_CERTIFICATE_PASSWORD:?MACOS_CERTIFICATE_PASSWORD is required}"
: "${MACOS_SIGN_IDENTITY:?MACOS_SIGN_IDENTITY is required}"
: "${APP_STORE_CONNECT_API_KEY_P8:?APP_STORE_CONNECT_API_KEY_P8 is required}"
: "${APP_STORE_CONNECT_KEY_ID:?APP_STORE_CONNECT_KEY_ID is required}"
: "${APP_STORE_CONNECT_ISSUER_ID:?APP_STORE_CONNECT_ISSUER_ID is required}"
: "${RUNNER_TEMP:?RUNNER_TEMP is required}"

work_dir="$(mktemp -d "$RUNNER_TEMP/bettbox-macos-sign.XXXXXX")"
keychain="$work_dir/signing.keychain-db"
p12_file="$work_dir/developer-id.p12"
api_key_file="$work_dir/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8"
keychain_password="$(openssl rand -hex 32)"
mounted_volume=""
original_keychains=()
while IFS= read -r keychain_entry; do
  keychain_entry="${keychain_entry#"${keychain_entry%%[![:space:]]*}"}"
  keychain_entry="${keychain_entry#\"}"
  keychain_entry="${keychain_entry%\"}"
  [[ -n "$keychain_entry" ]] && original_keychains+=("$keychain_entry")
done < <(security list-keychains -d user)

cleanup() {
  if [[ -n "$mounted_volume" ]]; then
    hdiutil detach "$mounted_volume" >/dev/null 2>&1 || true
  fi
  if (( ${#original_keychains[@]} > 0 )); then
    security list-keychains -d user -s "${original_keychains[@]}" >/dev/null 2>&1 || true
  fi
  security delete-keychain "$keychain" >/dev/null 2>&1 || true
  rm -rf "$work_dir"
}
trap cleanup EXIT

printf '%s' "$MACOS_CERTIFICATE_P12" | openssl base64 -d -A > "$p12_file"
printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" | openssl base64 -d -A > "$api_key_file"
chmod 600 "$p12_file" "$api_key_file"

security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$p12_file" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"

if ! security find-identity -v -p codesigning "$keychain" | grep -Fq "\"${MACOS_SIGN_IDENTITY}\""; then
  echo "the requested Developer ID identity was not found in the imported certificate" >&2
  exit 1
fi

archive_count="$(find "$payload_dir" -type f -name 'macos-payload.tar.gz' | wc -l | tr -d ' ')"
[[ "$archive_count" -eq 1 ]] || { echo "expected one macOS payload archive, found ${archive_count}" >&2; exit 1; }
archive="$(find "$payload_dir" -type f -name 'macos-payload.tar.gz' -print -quit)"

extract_dir="$work_dir/payload"
mkdir -p "$extract_dir" "$output_dir"
tar -xzf "$archive" -C "$extract_dir"

app_count="$(find "$extract_dir" -type d -name 'Bettbox.app' -prune -print | wc -l | tr -d ' ')"
[[ "$app_count" -eq 1 ]] || { echo "expected one Bettbox.app, found ${app_count}" >&2; exit 1; }
app="$(find "$extract_dir" -type d -name 'Bettbox.app' -prune -print -quit)"

name_file="$extract_dir/macos-dmg-name.txt"
[[ -s "$name_file" ]] || { echo "macos-dmg-name.txt is missing" >&2; exit 1; }
dmg_name="$(tr -d '\r\n' < "$name_file")"
[[ "$dmg_name" == Bettbox-*.dmg ]] || { echo "unexpected DMG name: ${dmg_name}" >&2; exit 1; }

sign_macho_files() {
  local root="$1"
  local candidate

  while IFS= read -r -d '' candidate; do
    if file -b "$candidate" | grep -q 'Mach-O'; then
      codesign --force --timestamp --options runtime --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" "$candidate"
    fi
  done < <(find "$root" -type f -print0)
}

sign_nested_containers() {
  local root="$1"
  local candidate

  while IFS= read -r -d '' candidate; do
    codesign --force --timestamp --options runtime --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" "$candidate"
  done < <(find "$root" -depth -type d \( -name '*.framework' -o -name '*.xpc' -o -name '*.appex' -o -name '*.app' \) -print0)
}

# LaunchAtLogin ships two helper applications inside ZIP resources. The Apple
# notary service expands nested containers, so these helpers must be
# distribution-signed before the outer application is signed.
helper_resource_dir="$app/Contents/Resources/LaunchAtLogin_LaunchAtLogin.bundle/Contents/Resources"
for helper_archive_name in LaunchAtLoginHelper.zip LaunchAtLoginHelper-with-runtime.zip; do
  helper_archive="$helper_resource_dir/$helper_archive_name"
  [[ -f "$helper_archive" ]] || { echo "missing embedded helper archive: ${helper_archive_name}" >&2; exit 1; }

  helper_work_dir="$work_dir/${helper_archive_name%.zip}"
  mkdir -p "$helper_work_dir"
  ditto -x -k "$helper_archive" "$helper_work_dir"

  helper_app="$helper_work_dir/LaunchAtLoginHelper.app"
  [[ -d "$helper_app" ]] || { echo "embedded helper application is missing from ${helper_archive_name}" >&2; exit 1; }

  helper_entitlements="$helper_work_dir/distribution-entitlements.plist"
  codesign -d --entitlements :- "$helper_app" 2>&1 \
    | awk 'found || index($0, "<?xml") { found=1; print }' > "$helper_entitlements"
  plutil -lint "$helper_entitlements" >/dev/null
  if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$helper_entitlements" >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c 'Delete :com.apple.security.get-task-allow' "$helper_entitlements"
  fi

  sign_macho_files "$helper_app"
  sign_nested_containers "$helper_app/Contents"
  codesign --force --timestamp --options runtime --entitlements "$helper_entitlements" \
    --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" "$helper_app"
  codesign --verify --deep --strict --verbose=2 "$helper_app"
  if codesign -d --entitlements :- "$helper_app" 2>&1 | grep -Fq 'com.apple.security.get-task-allow'; then
    echo "embedded helper still contains get-task-allow: ${helper_archive_name}" >&2
    exit 1
  fi

  rm -f "$helper_archive"
  ditto -c -k --keepParent "$helper_app" "$helper_archive"
done

# Sign every outer Mach-O payload first, then code containers from the inside out.
sign_macho_files "$app"
sign_nested_containers "$app/Contents"

codesign --force --timestamp --options runtime --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" "$app"
codesign --verify --deep --strict --verbose=2 "$app"

dmg_stage="$work_dir/dmg-root"
mkdir -p "$dmg_stage"
ditto "$app" "$dmg_stage/Bettbox.app"
ln -s /Applications "$dmg_stage/Applications"

dmg_path="$output_dir/$dmg_name"
hdiutil create -volname Bettbox -srcfolder "$dmg_stage" -ov -format UDZO "$dmg_path" >/dev/null
codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" --keychain "$keychain" "$dmg_path"
codesign --verify --verbose=2 "$dmg_path"

submission_json="$work_dir/notary-submission.json"
if ! xcrun notarytool submit "$dmg_path" \
  --key "$api_key_file" \
  --key-id "$APP_STORE_CONNECT_KEY_ID" \
  --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
  --wait \
  --output-format json > "$submission_json"; then
  sed -n '1,200p' "$submission_json" >&2
  exit 1
fi
sed -n '1,200p' "$submission_json"

submission_id="$(plutil -extract id raw -o - "$submission_json")"
submission_status="$(plutil -extract status raw -o - "$submission_json")"
if [[ "$submission_status" != Accepted ]]; then
  xcrun notarytool log "$submission_id" \
    --key "$api_key_file" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID" > "$work_dir/notary-log.json" || true
  sed -n '1,400p' "$work_dir/notary-log.json" >&2
  exit 1
fi
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path"
spctl --assess --type open --context context:primary-signature --verbose=2 "$dmg_path"

attach_output="$(hdiutil attach -nobrowse -readonly "$dmg_path")"
printf '%s\n' "$attach_output"
mounted_volume="$(printf '%s\n' "$attach_output" | awk -F '\t' '$NF ~ /^\/Volumes\// { print $NF }' | tail -n 1)"
[[ -d "$mounted_volume/Bettbox.app" ]] || { echo "the notarized DMG did not mount with Bettbox.app" >&2; exit 1; }
codesign --verify --deep --strict --verbose=2 "$mounted_volume/Bettbox.app"
spctl --assess --type execute --verbose=2 "$mounted_volume/Bettbox.app"
hdiutil detach "$mounted_volume" >/dev/null
mounted_volume=""
