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
    def test_ffmpeg_prefers_project_binary(self):
        project_ffmpeg = ROOT / "bin" / "ffmpeg"
        with mock.patch("os.path.isfile", return_value=True), \
             mock.patch("os.access", return_value=True), \
             mock.patch("shutil.which", return_value="/custom/bin/ffmpeg"):
            process = reload_process()
        self.assertEqual(process.FFMPEG, str(project_ffmpeg))

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

    def test_llm_settings_default_to_deepseek(self):
        with mock.patch.dict(os.environ, {}, clear=False):
            os.environ.pop("LLM_BASE_URL", None)
            os.environ.pop("LLM_MODEL", None)
            process = reload_process()
        self.assertEqual(process.LLM_BASE_URL, "https://api.deepseek.com")
        self.assertEqual(process.LLM_MODEL, "deepseek-v4-flash")

    def test_llm_settings_can_be_overridden(self):
        env = {
            "LLM_BASE_URL": "https://llm.example.test/v1",
            "LLM_MODEL": "example-model",
        }
        with mock.patch.dict(os.environ, env):
            process = reload_process()
        self.assertEqual(process.LLM_BASE_URL, env["LLM_BASE_URL"])
        self.assertEqual(process.LLM_MODEL, env["LLM_MODEL"])


if __name__ == "__main__":
    unittest.main()
