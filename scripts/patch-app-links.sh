#!/usr/bin/env bash
set -euo pipefail

source_root="${1:-.}"

python3 - "$source_root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
replacements = {
    root / "lib/common/constant.dart": (
        "const repository = 'appshubcc/Bettbox';",
        "const repository = 'lovitus/Bettbox-persistent-pin';",
    ),
    root / "lib/views/about.dart": (
        "https://github.com/appshubcc/Bettbox",
        "https://github.com/lovitus/Bettbox-persistent-pin",
    ),
}

for path, (old, new) in replacements.items():
    if not path.is_file():
        raise SystemExit(f"required upstream file is missing: {path}")
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"expected exactly one occurrence of {old!r} in {path}, found {count}"
        )
    path.write_text(text.replace(old, new), encoding="utf-8")
PY
