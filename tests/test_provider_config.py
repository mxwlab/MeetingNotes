import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.provider_config import (  # noqa: E402
    apply_updates,
    save_custom,
    save_deepseek,
    validate_deepseek,
    validate_provider,
)


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
        text = Path(p).read_text()
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
        text = Path(p).read_text()
        self.assertIn("export DEEPSEEK_API_KEY=sk-deep", text)
        self.assertNotIn("LLM_BASE_URL", text)
        self.assertNotIn("LLM_MODEL", text)
        self.assertIn('export OBSIDIAN_DIR="/vault"', text)


class _FakeClient:
    def __init__(self, exc=None):
        self.chat = mock.Mock()
        self.chat.completions = mock.Mock()
        if exc:
            self.chat.completions.create.side_effect = exc
        else:
            self.chat.completions.create.return_value = mock.Mock()


class ValidateTests(unittest.TestCase):
    def test_success(self):
        ok, msg = validate_provider(
            "https://gw", "m", "k", client_factory=lambda base, key: _FakeClient()
        )
        self.assertTrue(ok)
        self.assertEqual(msg, "")

    def test_failure_returns_reason(self):
        ok, msg = validate_provider(
            "https://gw",
            "m",
            "k",
            client_factory=lambda base, key: _FakeClient(Exception("401 Unauthorized")),
        )
        self.assertFalse(ok)
        self.assertIn("401", msg)

    def test_deepseek_uses_default_base(self):
        captured = {}

        def factory(base, key):
            captured["base"] = base
            return _FakeClient()

        ok, _ = validate_deepseek("k", client_factory=factory)
        self.assertTrue(ok)
        self.assertEqual(captured["base"], "https://api.deepseek.com")


if __name__ == "__main__":
    unittest.main()
