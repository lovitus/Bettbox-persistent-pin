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

python3 - <<'PY'
from pathlib import Path
import re

workflow = Path(".github/workflows/build.yaml")
if not workflow.is_file():
    raise SystemExit("upstream build workflow is missing")

text = workflow.read_text(encoding="utf-8")
marker = "      matrix:\n        include:\n"
try:
    start = text.index(marker) + len(marker)
    end = text.index("\n    steps:", start)
except ValueError as exc:
    raise SystemExit("could not locate the upstream build matrix") from exc

entries = []
current = None
for line in text[start:end].splitlines():
    match = re.match(r"\s+- platform:\s*(\S+)\s*$", line)
    if match:
        if current:
            entries.append(current)
        current = {"platform": match.group(1)}
        continue
    match = re.match(r"\s+(os|arch|compatible):\s*(\S+)\s*$", line)
    if match and current is not None:
        key, value = match.groups()
        current[key] = value == "true" if key == "compatible" else value
if current:
    entries.append(current)

expected = [
    {"platform": "android", "os": "ubuntu-24.04", "arch": "arm64"},
    {"platform": "android", "os": "ubuntu-24.04", "arch": "amd64"},
    {"platform": "android", "os": "ubuntu-24.04", "arch": "arm"},
    {"platform": "android", "os": "ubuntu-24.04", "arch": "universal"},
    {"platform": "windows", "os": "windows-2022", "arch": "amd64"},
    {"platform": "windows", "os": "windows-11-arm", "arch": "arm64"},
    {"platform": "windows", "os": "windows-2022", "arch": "amd64", "compatible": True},
    {"platform": "macos", "os": "macos-15", "arch": "arm64"},
    {"platform": "macos", "os": "macos-15", "arch": "amd64"},
    {"platform": "macos", "os": "macos-15", "arch": "amd64", "compatible": True},
    {"platform": "linux", "os": "ubuntu-22.04", "arch": "amd64"},
    {"platform": "linux", "os": "ubuntu-24.04-arm", "arch": "arm64"},
    {"platform": "linux", "os": "ubuntu-22.04", "arch": "amd64", "compatible": True},
]

if entries != expected:
    raise SystemExit(
        "upstream build matrix changed; update and review this builder before publishing\n"
        f"expected={expected!r}\nactual={entries!r}"
    )
PY
