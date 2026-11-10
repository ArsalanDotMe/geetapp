import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import tempfile
import unittest
from types import SimpleNamespace
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

class ReleasePublishTests(unittest.TestCase):
    def test_publishes_only_dmg(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / 'build/releases/1.2.3'
            output.mkdir(parents=True)
            dmg = output / 'geet-apple-silicon.dmg'
            dmg.write_bytes(b'dmg')
            (output / 'release.json').write_text(json.dumps({
                'version': '1.2.3', 'commit': 'abc', 'signed': True,
                'sha256': {dmg.name: hashlib.sha256(b'dmg').hexdigest()},
            }))
            def run(*args, **kwargs):
                calls.append(args)
                if args[:3] == ('gh', 'repo', 'view'): return 'ArsalanDotMe/geetapp'
                if args[:3] == ('git', 'ls-remote', 'origin'): return '' if 'refs/tags/' in args[-1] else 'abc refs/heads/main'
            calls = []
            with patch.object(release, 'ROOT', root), patch.object(release, 'clean_commit', return_value='abc'), \
                 patch.object(release, 'verify_dmg'), patch.object(release, 'run', side_effect=run):
                release.publish(SimpleNamespace(version='1.2.3'))
            create = next(call for call in calls if call[:3] == ('gh', 'release', 'create'))
            self.assertEqual([arg for arg in create if isinstance(arg, Path) and arg != output / 'release-notes.md'], [dmg])
            self.assertNotIn('attached', (output / 'release-notes.md').read_text())

class FrameworkPackagingTests(unittest.TestCase):
    def fixture(self, root):
        framework = root / 'Python.framework'
        version = framework / 'Versions/3.14'
        (version / 'Resources').mkdir(parents=True)
        (version / 'Python').write_bytes(b'unchanged Mach-O')
        (version / 'Resources/Info.plist').write_bytes(b'unchanged metadata')
        shutil.copytree(version, framework / 'Versions/Current')
        shutil.copytree(version / 'Resources', framework / 'Resources')
        shutil.copy(version / 'Python', framework / 'Python')
        return framework

    def test_restores_versioned_layout_without_changing_code_or_metadata(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework = self.fixture(root)
            release.normalize_frameworks(root)
            release.normalize_frameworks(root)
            self.assertTrue((framework / 'Python').is_symlink())
            self.assertTrue((framework / 'Resources').is_symlink())
            self.assertTrue((framework / 'Versions/Current').is_symlink())
            self.assertEqual((framework / 'Python').read_bytes(), b'unchanged Mach-O')
            self.assertEqual((framework / 'Resources/Info.plist').read_bytes(), b'unchanged metadata')

    def test_rejects_differing_copies(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            framework = self.fixture(root)
            (framework / 'Python').write_bytes(b'different code')
            with self.assertRaisesRegex(RuntimeError, 'copies differ'):
                release.normalize_frameworks(root)
            self.assertEqual((framework / 'Python').read_bytes(), b'different code')
