import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.provider_config import apply_updates, save_custom, save_deepseek  # noqa: E402


class ApplyUpdatesTests(unittest.TestCase):
    def test_update_existing_and_preserve_others(self):
        existing = ('export DEEPSEEK_API_KEY="old"\n'
                    'export OBSIDIAN_DIR="/vault/会议"\n'
                    '# 我的注释\n')
        out = apply_updates(existing, {"DEEPSEEK_API_KEY": "new"})
        self.assertIn("export DEEPSEEK_API_KEY=new", out)
        self.assertIn('export OBSIDIAN_DIR="/vault/会议"', out)
        self.assertIn("# 我的注释", out)
        self.assertNotIn('"old"', out)

    def test_insert_when_absent(self):
        out = apply_updates("", {"LLM_MODEL": "kimi-k2"})
        self.assertIn("export LLM_MODEL=kimi-k2", out)

    def test_unset_removes_line(self):
        existing = 'export LLM_BASE_URL="https://gw"\nexport LLM_MODEL="kimi"\n'
        out = apply_updates(existing, {"DEEPSEEK_API_KEY": "k"},
                            unset_keys=("LLM_BASE_URL", "LLM_MODEL"))
        self.assertNotIn("LLM_BASE_URL", out)
        self.assertNotIn("LLM_MODEL", out)
        self.assertIn("export DEEPSEEK_API_KEY=k", out)

    def test_quotes_values_with_spaces(self):
        out = apply_updates("", {"OBSIDIAN_DIR": "/a b/会议"})
        self.assertIn("export OBSIDIAN_DIR='/a b/会议'", out)


class SaveTests(unittest.TestCase):
    def _tmp(self):
        d = tempfile.mkdtemp()
        return os.path.join(d, "config.local.sh")

    def test_save_custom_writes_three_keys_and_600(self):
        p = self._tmp()
        with open(p, "w") as f:
            f.write('export OBSIDIAN_DIR="/vault"\n')
        save_custom(p, "https://gw/v1", "kimi-k2", "sk-x")
        text = open(p).read()
        self.assertIn("export LLM_BASE_URL=https://gw/v1", text)
        self.assertIn("export LLM_MODEL=kimi-k2", text)
        self.assertIn("export DEEPSEEK_API_KEY=sk-x", text)
        self.assertIn('export OBSIDIAN_DIR="/vault"', text)
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600)

    def test_save_deepseek_unsets_custom(self):
        p = self._tmp()
        with open(p, "w") as f:
            f.write('export LLM_BASE_URL="https://gw"\nexport LLM_MODEL="kimi"\n'
                    'export OBSIDIAN_DIR="/vault"\n')
        save_deepseek(p, "sk-deep")
        text = open(p).read()
        self.assertIn("export DEEPSEEK_API_KEY=sk-deep", text)
        self.assertNotIn("LLM_BASE_URL", text)
        self.assertNotIn("LLM_MODEL", text)
        self.assertIn('export OBSIDIAN_DIR="/vault"', text)


if __name__ == "__main__":
    unittest.main()
