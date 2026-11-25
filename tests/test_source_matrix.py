"""Exercise the source gate against supported and unreviewed matrix changes."""
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/verify-source.sh"
CODE = SCRIPT.read_text().split("<<'PY'\n", 1)[1].rsplit("\nPY", 1)[0]
V197 = "5df714e0d5f133f3a4146dc2b1adfb2311f5f0d0"
V198 = "88b9597ad88f597e61a2843ad6fe33d5bdee8950"
V1201 = "bd94edb933e0b87c968d91bc4cb2f2043999a061"
PORTABLE_UPLOAD = """      - name: Upload Windows Portable Artifact
        if: matrix.platform == 'windows' && matrix.arch == 'amd64' && matrix.standard != true
        uses: actions/upload-artifact@v7
        with:
          name: Bettbox-${{ matrix.platform }}-${{ matrix.arch }}${{ matrix.compatible == true && '-compatible' || '' }}-portable
          path: ./dist/*.zip
          archive: false
          overwrite: true
"""
PACKAGER = """void main() {
  final makePortable =
      (args['portable'] as bool?) ?? (arch == 'amd64' && !standard);
  if (makePortable) {
    final portableOutputBaseName =
        'Bettbox-$appVersion-windows-$desc-portable.zip';
  }
}
"""
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


def matrix(*variants):
    text = "jobs:\n  build:\n    strategy:\n      matrix:\n        include:\n"
    for platform in ("android", "windows", "macos", "linux"):
        for variant in variants:
            for name, os_name, arch, compatible in TARGETS:
                if name != platform:
                    continue
                text += f"          - platform: {name}\n            os: {os_name}\n            arch: {arch}\n"
                if compatible:
                    text += "            compatible: true\n"
                if variant:
                    text += f"            {variant}: true\n"
    return text + "\n    steps:\n" + PORTABLE_UPLOAD


class SourceMatrix(unittest.TestCase):
    def check_gate(self, workflow, accepted, commit=V1201, packager=PACKAGER):
        with tempfile.TemporaryDirectory() as root:
            target = Path(root) / ".github/workflows/build.yaml"
            target.parent.mkdir(parents=True)
            target.write_text(workflow)
            package = Path(root) / "windows/packaging/exe/package_windows.dart"
            package.parent.mkdir(parents=True)
            package.write_text(packager)
            result = subprocess.run(
                ["python3", "-c", CODE, commit], cwd=root,
                capture_output=True, text=True, timeout=15,
            )
            self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_versioned_matrices(self):
        layouts = [(None,), (None, "lite"), (None, "standard")]
        for commit, expected in zip([V197, V198, V1201], layouts):
            for layout in layouts:
                with self.subTest(commit=commit, layout=layout):
                    self.check_gate(matrix(*layout), layout == expected, commit)

    def test_supported_and_unreviewed_matrices(self):
        current = matrix(None, "standard")
        cases = [
            ("missing plain variant", matrix("standard"), False),
            ("duplicate complete variant", matrix(None, "standard", "standard"), False),
            ("unexpected third variant", matrix(None, "standard", "lite"), False),
            ("signing metadata", current.replace("            arch: amd64\n", "            arch: amd64\n            sign: true\n", 1), True),
            ("reordered extra target", current.replace("\n    steps:", "          - arch: amd64\n            platform: linux\n            os: ubuntu-22.04\n            compatible: true\n            lite: true\n\n    steps:"), False),
            ("unknown field", current.replace("            arch: arm64\n", "            arch: arm64\n            variant: other\n", 1), False),
            ("duplicate field", current.replace("            arch: arm64\n", "            arch: arm64\n            arch: arm64\n", 1), False),
            ("unknown architecture", current.replace("arch: arm64", "arch: riscv64", 1), False),
            ("missing Standard marker", current.replace("            standard: true\n", "", 1), False),
            ("false Standard marker", current.replace("standard: true", "standard: false", 1), False),
            ("changed runner", current.replace("os: macos-26", "os: macos-27", 1), False),
        ]
        for label, text, accepted in cases:
            with self.subTest(label=label):
                self.check_gate(text, accepted)

    def test_portable_contract(self):
        current = matrix(None, "standard")
        for marker in [PORTABLE_UPLOAD, " && matrix.standard != true", "-portable", "./dist/*.zip"]:
            with self.subTest(upload_marker=marker):
                self.check_gate(current.replace(marker, ""), False)
        # Restoring the old compatible-only rule would silently lose the new ZIP.
        self.check_gate(current.replace(" && matrix.arch", " && matrix.compatible == true && matrix.arch", 1), False)
        self.check_gate(current, False, packager=PACKAGER.replace("(arch ==", "(compatible && arch ==", 1))
        self.check_gate(current + PORTABLE_UPLOAD, False)
        for marker in [" && !standard", "if (makePortable)", "-portable.zip"]:
            with self.subTest(package_marker=marker):
                self.check_gate(current, False, packager=PACKAGER.replace(marker, ""))


if __name__ == "__main__":
    unittest.main()
