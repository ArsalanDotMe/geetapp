import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('release', Path(__file__).parents[1] / 'release.py')
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)

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
