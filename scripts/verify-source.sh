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

python3 - "$(git rev-parse --verify "${upstream_commit}^{commit}")" <<'PY'
from pathlib import Path
import re
import sys

# Only these reviewed releases may use the older artifact layouts.
legacy_variants = {
    "5df714e0d5f133f3a4146dc2b1adfb2311f5f0d0": None,  # v1.19.7
    "88b9597ad88f597e61a2843ad6fe33d5bdee8950": "lite",  # v1.19.8
}
variant = legacy_variants.get(sys.argv[1], "standard")

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
    match = re.fullmatch(r"          - platform: (\S+)", line)
    if match:
        if current:
            entries.append(current)
        current = {"platform": match.group(1)}
        continue
    match = re.fullmatch(r"            (os|arch|compatible|lite|standard|sign): (\S+)", line)
    if match and current is not None:
        key, value = match.groups()
        if key in current:
            raise SystemExit(f"duplicate matrix field: {line!r}")
        if key in {"compatible", "lite", "standard", "sign"}:
            if value not in {"true", "false"}:
                raise SystemExit(f"invalid boolean matrix field: {line!r}")
            value = value == "true"
        current[key] = value
        continue
    if line.strip() and not line.lstrip().startswith("#"):
        raise SystemExit(f"unreviewed upstream matrix syntax: {line!r}")
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
    {"platform": "macos", "os": "macos-26", "arch": "arm64"},
    {"platform": "macos", "os": "macos-26", "arch": "amd64"},
    {"platform": "linux", "os": "ubuntu-22.04", "arch": "amd64"},
    {"platform": "linux", "os": "ubuntu-24.04-arm", "arch": "arm64"},
    {"platform": "linux", "os": "ubuntu-22.04", "arch": "amd64", "compatible": True},
]

for entry in entries:
    entry.pop("sign", None)  # Signing metadata does not change the artifact target.
plain = [entry for entry in entries if "lite" not in entry and "standard" not in entry]
marked = [entry for entry in entries if "lite" in entry or "standard" in entry]
expected_marked = [dict(entry, **{variant: True}) for entry in expected] if variant else []
if plain != expected or marked != expected_marked:
    raise SystemExit(
        "upstream build matrix changed; update and review this builder before publishing\n"
        f"expected_plain={expected!r}\nactual_plain={plain!r}\n"
        f"expected_marked={expected_marked!r}\nactual_marked={marked!r}"
    )

if variant == "standard":
    # Both plain Windows amd64 jobs (normal and compatible) produce a ZIP.
    portable_upload = """      - name: Upload Windows Portable Artifact
        if: matrix.platform == 'windows' && matrix.arch == 'amd64' && matrix.standard != true
        uses: actions/upload-artifact@v7
        with:
          name: Bettbox-${{ matrix.platform }}-${{ matrix.arch }}${{ matrix.compatible == true && '-compatible' || '' }}-portable
          path: ./dist/*.zip
          archive: false
          overwrite: true"""
    build_steps = text[end:].split("\n  upload:", 1)[0]
    steps = re.split(r"(?=^      - name: )", build_steps, flags=re.MULTILINE)
    if sum(step.rstrip() == portable_upload for step in steps) != 1:
        raise SystemExit("upstream Windows portable upload step changed")
    packager = Path("windows/packaging/exe/package_windows.dart").read_text(encoding="utf-8")
    for marker in (
        "  final makePortable =\n      (args['portable'] as bool?) ?? (arch == 'amd64' && !standard);",
        "  if (makePortable) {",
        "    final portableOutputBaseName =\n        'Bettbox-$appVersion-windows-$desc-portable.zip';",
    ):
        if f"\n{marker}\n" not in packager:
            raise SystemExit(f"upstream Windows portable packaging marker changed: {marker}")
PY
