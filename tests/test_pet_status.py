import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.pet_status import title_from_pet_state, IDLE_TITLE  # noqa: E402


class TitleTests(unittest.TestCase):
    def test_transcribe_with_pct(self):
        self.assertEqual(title_from_pet_state("transcribe\n权限讨论\n42\n"), "🎙️ 42%")

    def test_transcribe_without_pct(self):
        self.assertEqual(title_from_pet_state("transcribe\n权限讨论\n\n"), "🎙️ 转录中")

    def test_summarize(self):
        self.assertEqual(title_from_pet_state("summarize\n权限讨论\n10\n"), "📝 生成中")

    def test_done_is_idle(self):
        self.assertEqual(title_from_pet_state("done\n权限讨论\n"), IDLE_TITLE)

    def test_empty_or_garbage_is_idle(self):
        self.assertEqual(title_from_pet_state(""), IDLE_TITLE)
        self.assertEqual(title_from_pet_state("???"), IDLE_TITLE)


if __name__ == "__main__":
    unittest.main()
