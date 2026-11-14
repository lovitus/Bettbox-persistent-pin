"""Exercise the source gate against supported and unreviewed matrix changes."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-source.sh"
CODE = SCRIPT.read_text().split("python3 - <<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
TARGETS = [
    ("android", "ubuntu-24.04", arch, False)
    for arch in ("arm64", "amd64", "arm", "universal")
] + [
    ("windows", "windows-2022", "amd64", False),
    ("windows", "windows-11-arm", "arm64", False),
    ("windows", "windows-2022", "amd64", True),
    ("macos", "macos-26", "arm64", False),
    ("macos", "macos-26", "amd64", False),
    ("linux", "ubuntu-22.04", "amd64", False),
    ("linux", "ubuntu-24.04-arm", "arm64", False),
    ("linux", "ubuntu-22.04", "amd64", True),
]


def matrix(include_lite):
    text = "jobs:\n  build:\n    strategy:\n      matrix:\n        include:\n"
    for platform in ("android", "windows", "macos", "linux"):
        for lite in ([False, True] if include_lite else [False]):
            for name, os_name, arch, compatible in TARGETS:
                if name != platform:
                    continue
                text += f"          - platform: {name}\n            os: {os_name}\n            arch: {arch}\n"
                if compatible:
                    text += "            compatible: true\n"
                if lite:
                    text += "            lite: true\n"
    return text + "\n    steps:\n      - run: echo build\n"


class SourceMatrix(unittest.TestCase):
    def test_supported_and_unreviewed_matrices(self):
        current = matrix(True)
        cases = [
            ("standard only", matrix(False), True),
            ("standard and Lite", current, True),
            ("signing metadata", current.replace("            arch: amd64\n", "            arch: amd64\n            sign: true\n", 1), True),
            ("reordered extra target", current.replace("\n    steps:", "          - arch: amd64\n            platform: linux\n            os: ubuntu-22.04\n            compatible: true\n            lite: true\n\n    steps:"), False),
            ("unknown field", current.replace("            arch: arm64\n", "            arch: arm64\n            variant: other\n", 1), False),
            ("duplicate field", current.replace("            arch: arm64\n", "            arch: arm64\n            arch: arm64\n", 1), False),
            ("unknown architecture", current.replace("arch: arm64", "arch: riscv64", 1), False),
            ("missing Lite marker", current.replace("            lite: true\n", "", 1), False),
            ("false Lite marker", current.replace("lite: true", "lite: false", 1), False),
            ("changed runner", current.replace("os: macos-26", "os: macos-27", 1), False),
        ]
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / ".github/workflows/build.yaml"
            target.parent.mkdir(parents=True)
            for label, text, accepted in cases:
                with self.subTest(label=label):
                    target.write_text(text)
                    result = subprocess.run(
                        ["python3", "-c", CODE], cwd=root,
                        capture_output=True, text=True, timeout=15,
                    )
                    self.assertEqual(result.returncode == 0, accepted, result.stderr)


if __name__ == "__main__":
    unittest.main()
