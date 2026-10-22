import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SPEC = importlib.util.spec_from_file_location("bootstrap", Path(__file__).parents[1] / "bootstrap-tools.py")
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)


def archive(entries):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as output:
        for name, data, mode in entries:
            item = zipfile.ZipInfo(name)
            item.external_attr = mode << 16
            output.writestr(item, data)
    return buffer.getvalue()


class BootstrapTests(unittest.TestCase):
    def test_runtime_is_complete_and_keeps_executable_permissions(self):
        data = archive([("yt-dlp_macos", b"executable", 0o100755),
                        ("_internal/libpython.dylib", b"runtime", 0o100644)])
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            bootstrap.unpack(data, root)
            self.assertEqual((root / "_internal/libpython.dylib").read_bytes(), b"runtime")
            self.assertEqual((root / "yt-dlp_macos").stat().st_mode & 0o777, 0o755)
            self.assertEqual((root / "_internal/libpython.dylib").stat().st_mode & 0o777, 0o644)

    def test_rejects_traversal_absolute_paths_and_symlinks(self):
        for name, mode in [("../escape", 0o100644), ("/escape", 0o100644),
                           ("folder/../../escape", 0o100644), ("folder\\escape", 0o100644),
                           ("_internal/link", 0o120777)]:
            with self.subTest(name=name), tempfile.TemporaryDirectory() as directory:
                with self.assertRaises(RuntimeError):
                    bootstrap.unpack(archive([(name, b"outside", mode)]), Path(directory))

    def test_migrates_file_to_directory_and_replaces_old_runtime(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "yt-dlp"
            target.write_bytes(b"old onefile")
            for revision in [b"first runtime", b"updated runtime"]:
                stage = root / "stage"
                stage.mkdir()
                (stage / "yt-dlp_macos").write_bytes(revision)
                bootstrap.replace_tree(stage, target)
                self.assertEqual((target / "yt-dlp_macos").read_bytes(), revision)
                self.assertFalse((root / "yt-dlp.previous").exists())

    def test_bad_digest_never_replaces_existing_tool(self):
        release = b'{"tag_name":"test","assets":[{"name":"tool.zip","digest":"sha256:bad","browser_download_url":"https://example.test/tool"}]}'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "tool"
            target.write_bytes(b"working")
            with patch.object(bootstrap, "DEST", root), patch.object(bootstrap, "fetch", side_effect=[release, b"corrupt"]):
                with self.assertRaisesRegex(RuntimeError, "Checksum mismatch"):
                    bootstrap.install("test/repo", "tool.zip", "tool", directory=True)
            self.assertEqual(target.read_bytes(), b"working")


if __name__ == "__main__":
    unittest.main()
