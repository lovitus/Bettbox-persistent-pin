#!/usr/bin/env bash
set -euo pipefail

source_root="${1:?usage: verify-source.sh SOURCE_ROOT UPSTREAM_COMMIT}"
upstream_commit="${2:?usage: verify-source.sh SOURCE_ROOT UPSTREAM_COMMIT}"

cd "$source_root"

expected_subjects=$(cat <<'EOF'
fix(outboundgroup): avoid selecting timeout nodes when alive nodes exist
feat(group): add optional persistent pin mode for url-test/fallback
feat(group): add auto-unfix threshold for persistent pin
chore(group): enrich persistent pin counter logs
chore(builder): point updates and releases to lovitus builder
EOF
)
actual_subjects="$(git log --reverse --format='%s' "${upstream_commit}..HEAD")"
if [[ "$actual_subjects" != "$expected_subjects" ]]; then
  echo "unexpected commits applied after upstream ${upstream_commit}" >&2
  diff -u <(printf '%s\n' "$expected_subjects") <(printf '%s\n' "$actual_subjects") || true
  exit 1
fi
expected_files=$(cat <<'EOF'
core/Clash.Meta/adapter/outboundgroup/fallback.go
core/Clash.Meta/adapter/outboundgroup/groupbase.go
core/Clash.Meta/adapter/outboundgroup/parser.go
core/Clash.Meta/adapter/outboundgroup/urltest.go
core/Clash.Meta/adapter/outboundgroup/util.go
core/Clash.Meta/docs/config.yaml
core/Clash.Meta/hub/route/groups.go
lib/common/constant.dart
lib/views/about.dart
EOF
)
actual_files="$(git diff --name-only "${upstream_commit}..HEAD" | LC_ALL=C sort)"
if [[ "$actual_files" != "$expected_files" ]]; then
  echo "the patch changed files outside the reviewed scope" >&2
  diff -u <(printf '%s\n' "$expected_files") <(printf '%s\n' "$actual_files") || true
  exit 1
fi

git diff --check "${upstream_commit}..HEAD"

grep -Fq "const repository = 'lovitus/Bettbox-persistent-pin';" lib/common/constant.dart
grep -Fq "https://github.com/lovitus/Bettbox-persistent-pin" lib/views/about.dart
if grep -Fq "https://github.com/appshubcc/Bettbox" lib/views/about.dart; then
  echo "the About view still points to the upstream release repository" >&2
  exit 1
fi

grep -Fq 'PersistentPin                   bool' core/Clash.Meta/adapter/outboundgroup/parser.go
grep -Fq 'group:"persistent-pin,omitempty"' core/Clash.Meta/adapter/outboundgroup/parser.go
grep -Fq 'group:"pin-unhealthy-log-interval,omitempty"' core/Clash.Meta/adapter/outboundgroup/parser.go
grep -Fq 'group:"persistent-pin-auto-unfix-threshold,omitempty"' core/Clash.Meta/adapter/outboundgroup/parser.go
grep -Fq 'proxy.AliveForTestUrl(url)' core/Clash.Meta/adapter/outboundgroup/groupbase.go
grep -Fq 'persistentPinAutoUnfixThreshold' core/Clash.Meta/adapter/outboundgroup/urltest.go
grep -Fq 'persistentPinAutoUnfixThreshold' core/Clash.Meta/adapter/outboundgroup/fallback.go
grep -Fq 'PersistentPinAware' core/Clash.Meta/hub/route/groups.go

unformatted="$(gofmt -l \
  core/Clash.Meta/adapter/outboundgroup/fallback.go \
  core/Clash.Meta/adapter/outboundgroup/groupbase.go \
  core/Clash.Meta/adapter/outboundgroup/parser.go \
  core/Clash.Meta/adapter/outboundgroup/urltest.go \
  core/Clash.Meta/adapter/outboundgroup/util.go \
  core/Clash.Meta/hub/route/groups.go)"
if [[ -n "$unformatted" ]]; then
  echo "patched Go files are not gofmt-clean:" >&2
  printf '%s\n' "$unformatted" >&2
  exit 1
fi
