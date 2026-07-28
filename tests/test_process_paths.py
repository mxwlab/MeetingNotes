import importlib
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def reload_process():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


class ProcessPathResolutionTests(unittest.TestCase):
    def test_ffmpeg_uses_path_binary_when_available(self):
        with mock.patch("shutil.which", return_value="/custom/bin/ffmpeg"):
            process = reload_process()
        self.assertEqual(process.FFMPEG, "/custom/bin/ffmpeg")

    def test_ffmpeg_falls_back_when_not_on_path(self):
        with mock.patch("shutil.which", return_value=None):
            process = reload_process()
        self.assertEqual(process.FFMPEG, "/opt/homebrew/bin/ffmpeg")

    def test_obsidian_dir_env_empty_means_skip(self):
        with mock.patch.dict(os.environ, {"OBSIDIAN_DIR": ""}):
            process = reload_process()
        self.assertEqual(process.OBSIDIAN_DIR, "")
        with mock.patch.object(process, "log"), mock.patch("os.makedirs") as makedirs:
            saved = process.save_to_obsidian("测试", "# 纪要", "测试.m4a")
        self.assertFalse(saved)
        makedirs.assert_not_called()

    def test_obsidian_dir_defaults_when_unset(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("OBSIDIAN_DIR", None)
            process = reload_process()
        self.assertTrue(process.OBSIDIAN_DIR.endswith("会议纪要"))


if __name__ == "__main__":
    unittest.main()
