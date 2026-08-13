import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.pet_status import (title_from_pet_state, IDLE_TITLE,
                           latest_outcome, should_alert, Outcome,
                           )  # noqa: E402


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

    def test_idle_title_is_compact(self):
        self.assertEqual(IDLE_TITLE, "🐱")


OK_LOG = "[2026-08-11 23:40:32] 开始处理: 权限讨论.m4a\n[2026-08-11 23:41:00] ✅ 完成: 权限讨论.m4a\n"
FAIL_LOG = ("[2026-08-11 23:40:32] 开始处理: 坏文件.m4a\n"
            "[2026-08-11 23:40:35] ❌ 失败(退出码 1): 坏文件.m4a — 详见上方日志\n")
FAIL_THEN_OK = FAIL_LOG + "[2026-08-11 23:50:00] ✅ 完成: 好文件.m4a\n"


class OutcomeTests(unittest.TestCase):
    def test_none_when_empty(self):
        self.assertEqual(latest_outcome("").result, "none")

    def test_ok(self):
        self.assertEqual(latest_outcome(OK_LOG).result, "ok")

    def test_fail_extracts_name_and_marker(self):
        o = latest_outcome(FAIL_LOG)
        self.assertEqual(o.result, "fail")
        self.assertEqual(o.name, "坏文件.m4a")
        self.assertIn("坏文件.m4a", o.marker)

    def test_later_success_clears_fail(self):
        self.assertEqual(latest_outcome(FAIL_THEN_OK).result, "ok")

    def test_marker_stable_and_changes(self):
        o1 = latest_outcome(FAIL_LOG)
        self.assertEqual(o1.marker, latest_outcome(FAIL_LOG).marker)  # 同一失败稳定
        o2 = latest_outcome(FAIL_LOG.replace("23:40:35", "23:59:59"))
        self.assertNotEqual(o1.marker, o2.marker)                     # 新失败改变

    def test_should_alert_dedup(self):
        o = latest_outcome(FAIL_LOG)
        self.assertTrue(should_alert(None, o))
        self.assertFalse(should_alert(o.marker, o))                   # 同 marker 不重复
        self.assertFalse(should_alert(None, latest_outcome(OK_LOG)))  # 非失败不提醒


if __name__ == "__main__":
    unittest.main()
