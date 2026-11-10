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

class InstallerContentsTests(unittest.TestCase):
    def verify_fixture(self, extra=None, target='/Applications'):
        def run(*args, **kwargs):
            if args[:2] == ('hdiutil', 'attach'):
                mount = Path(args[args.index('-mountpoint') + 1])
                (mount / 'Geet.app').mkdir()
                (mount / 'Applications').symlink_to(target)
                (mount / '.DS_Store').write_bytes(b'Finder layout')
                (mount / '.background.tiff').write_bytes(b'background')
                if extra:
                    (mount / extra).touch()

        with patch.object(release, 'run', side_effect=run), patch.object(release, 'verify_installer_layout'), \
                patch.object(release, 'verify_app') as verify:
            release.verify_dmg(Path('preview.dmg'), signed=False)
            verify.assert_called_once()

    def test_accepts_two_installation_items_and_hidden_layout(self):
        self.verify_fixture()

    def test_rejects_extra_visible_files(self):
        for extra in ('Install.txt', 'Licenses'):
            with self.subTest(extra=extra), self.assertRaisesRegex(AssertionError, 'only geet and Applications'):
                self.verify_fixture(extra=extra)

    def test_rejects_incorrect_applications_shortcut(self):
        with self.assertRaises(AssertionError):
            self.verify_fixture(target='/tmp')

@unittest.skipUnless(importlib.util.find_spec('ds_store'), 'Install scripts/requirements-release.txt')
class InstallerWindowTests(unittest.TestCase):
    def fixture(self, root, bounds):
        from ds_store import DSStore
        with DSStore.open(str(root / '.DS_Store'), 'w+') as store:
            store['.']['bwsp'] = {'WindowBounds': bounds, 'ShowToolbar': False}
            store['.']['icvp'] = {'iconSize': 128}
            store['Geet.app']['Iloc'] = (176, 170)
            store['Applications']['Iloc'] = (464, 170)

    def test_window_includes_title_bar_and_fits_background(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            self.fixture(root, '{{200, 200}, {640, 412}}')
            release.verify_installer_layout(root)

    def test_rejects_clipped_or_oversized_window(self):
        for size in ('640, 380', '920, 436'):
            with self.subTest(size=size), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                self.fixture(root, '{{200, 200}, {' + size + '}}')
                with self.assertRaisesRegex(AssertionError, 'fit its background'):
                    release.verify_installer_layout(root)

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
