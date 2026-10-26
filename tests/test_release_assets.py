"""Behavioral contract for the v1.19.7 release set; run on GitHub-hosted Linux."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


SUFFIXES = (
    "android-arm64-v8a.apk", "android-armeabi-v7a.apk",
    "android-universal.apk", "android-x86_64.apk",
    "windows-amd64-setup.exe", "windows-arm64-setup.exe",
    "windows-amd64-compatible-setup.exe", "windows-amd64-compatible-portable.zip",
    "macos-arm64.dmg", "macos-amd64.dmg",
    "linux-amd64.AppImage", "linux-amd64.deb", "linux-amd64.rpm",
    "linux-arm64.deb", "linux-amd64-compatible.AppImage",
    "linux-amd64-compatible.deb", "linux-amd64-compatible.rpm",
)
VALIDATOR = Path(os.environ.get(
    "ASSET_VALIDATOR", Path(__file__).resolve().parents[1] / "scripts/validate-release-assets.sh"
)).resolve()


class ReleaseAssets(unittest.TestCase):
    def test_upstream_release_contract(self):
        # These are package-name/size fixtures, not signed or runnable binaries.
        # Real package construction, installation and signing are separate jobs.
        cases = [("complete", None)]
        cases += [("missing", suffix) for suffix in SUFFIXES]
        cases += [("empty", SUFFIXES[0]), ("symlink", SUFFIXES[0])]
        cases += [("extra", name) for name in (
            "Bettbox-1.19.7-macos-amd64-compatible.dmg",
            "Bettbox-1.19.4-macos-arm64.dmg",
            "raw-macos-payload.tar.gz", "unexpected.txt",
        )]
        cases += [("wrong_version", None)]
        for operation, value in cases:
            with self.subTest(operation=operation, value=value), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for suffix in SUFFIXES:
                    (root / f"Bettbox-1.19.7-{suffix}").write_bytes(b"artifact fixture\n")
                if operation in ("missing", "empty", "symlink"):
                    target = root / f"Bettbox-1.19.7-{value}"
                    if operation == "empty":
                        target.write_bytes(b"")
                    else:
                        target.unlink()
                        if operation == "symlink":
                            target.symlink_to(root / "Bettbox-1.19.7-macos-arm64.dmg")
                elif operation == "extra":
                    (root / value).write_bytes(b"unreviewed artifact\n")
                version = "v1.19.4" if operation == "wrong_version" else "v1.19.7"
                result = subprocess.run(
                    ["bash", str(VALIDATOR), str(root), version],
                    capture_output=True, text=True, timeout=15,
                )
                if operation == "complete":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0, operation)


if __name__ == "__main__":
    unittest.main()
