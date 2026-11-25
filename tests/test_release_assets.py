"""Behavioral contract for the v1.20.1 release set; run on GitHub-hosted Linux."""
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
    "windows-amd64-portable.zip",
    "macos-arm64.dmg", "macos-amd64.dmg",
    "linux-amd64.AppImage", "linux-amd64.deb", "linux-amd64.rpm",
    "linux-arm64.deb", "linux-amd64-compatible.AppImage",
    "linux-amd64-compatible.deb", "linux-amd64-compatible.rpm",
    "android-standard-arm64-v8a.apk", "android-standard-armeabi-v7a.apk",
    "android-standard-universal.apk", "android-standard-x86_64.apk",
    "windows-amd64-standard-setup.exe", "windows-arm64-standard-setup.exe",
    "windows-amd64-compatible-standard-setup.exe",
    "macos-arm64-standard.dmg", "macos-amd64-standard.dmg",
    "linux-amd64-standard.AppImage", "linux-amd64-standard.deb", "linux-amd64-standard.rpm",
    "linux-arm64-standard.deb", "linux-amd64-compatible-standard.AppImage",
    "linux-amd64-compatible-standard.deb", "linux-amd64-compatible-standard.rpm",
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
            "Bettbox-1.20.1-macos-amd64-compatible.dmg",
            "Bettbox-1.19.4-macos-arm64.dmg",
            "Bettbox-1.20.1-windows-amd64-compatible-standard-portable.zip",
            "Bettbox-1.20.1-windows-amd64-standard-portable.zip",
            "Bettbox-1.20.1-windows-arm64-portable.zip",
            "Bettbox-1.20.1-android-arm64-v8a-standard.apk",
            "Bettbox-1.20.1-linux-amd64-standard-compatible.rpm",
            "raw-macos-payload.tar.gz", "unexpected\nasset", ".unexpected",
        )]
        cases += [("wrong_version", None)]
        for operation, value in cases:
            with self.subTest(operation=operation, value=value), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                for suffix in SUFFIXES:
                    (root / f"Bettbox-1.20.1-{suffix}").write_bytes(b"artifact fixture\n")
                if operation in ("missing", "empty", "symlink"):
                    target = root / f"Bettbox-1.20.1-{value}"
                    if operation == "empty":
                        target.write_bytes(b"")
                    else:
                        target.unlink()
                        if operation == "symlink":
                            target.symlink_to(root / "Bettbox-1.20.1-macos-arm64.dmg")
                elif operation == "extra":
                    (root / value).write_bytes(b"unreviewed artifact\n")
                version = "v1.19.4" if operation == "wrong_version" else "v1.20.1"
                result = subprocess.run(
                    ["bash", str(VALIDATOR), str(root), version],
                    capture_output=True, text=True, timeout=15,
                )
                if operation == "complete":
                    self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                else:
                    self.assertNotEqual(result.returncode, 0, operation)


class AndroidSigning(unittest.TestCase):
    def test_signs_and_verifies_both_editions(self):
        script = Path(__file__).resolve().parents[1] / "scripts/sign-android.sh"
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            tools = root / "build-tools/36.0.0"
            tools.mkdir(parents=True)
            # Exercise the script's file handling and verify calls without a keystore.
            commands = {
                "zipalign": 'case "$1" in -f) cp "$4" "$5" ;; -c) test -s "$4" ;; esac\n',
                "apksigner": (
                    'if [ "$1" = verify ]; then basename "$3" >> "$VERIFY_LOG"; exit; fi\n'
                    'while [ "$1" != --out ]; do shift; done\ncp "$3" "$2"\n'
                ),
            }
            for name, body in commands.items():
                executable = tools / name
                executable.write_text("#!/bin/sh\nset -eu\n" + body)
                executable.chmod(0o755)
            keystore = root / "test.jks"
            keystore.touch()
            raw, output, log = root / "raw", root / "signed", root / "verified"
            names = [f"Bettbox-1.20.1-{s}" for s in SUFFIXES if s.endswith(".apk")]
            for i, name in enumerate(names):
                artifact = raw / str(i)
                artifact.mkdir(parents=True)
                (artifact / name).write_text(name)
            env = dict(os.environ, ANDROID_SDK_ROOT=directory, RUNNER_TEMP=directory,
                       ANDROID_KEY_ALIAS="test", ANDROID_STORE_PASSWORD="test",
                       ANDROID_KEY_PASSWORD="test", VERIFY_LOG=str(log))
            args = ["bash", str(script), str(raw), str(output), str(keystore), "v1.20.1"]
            target = raw / "0" / names[0]
            duplicate = raw / "0" / names[-1]
            target.rename(duplicate)
            result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(log.exists())
            duplicate.rename(target)
            result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertCountEqual(log.read_text().splitlines(), names)
            self.assertCountEqual([p.name for p in output.iterdir()], names)
            for name in names:
                self.assertEqual((output / name).read_text(), name)


if __name__ == "__main__":
    unittest.main()
