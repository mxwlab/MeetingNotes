import importlib
import sys
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def reload_process():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


class RecordFallbackTests(unittest.TestCase):
    """会议全程安全网：LLM 正文为空（如推理模型耗尽 token 预算）时，
    不能让「会议全程」空白，应回退到原始转录。"""

    def test_make_record_falls_back_to_raw_when_llm_returns_empty(self):
        process = reload_process()
        transcript = "说话人A：你好呀\n说话人B：在的在的"
        with mock.patch.object(process, "log"), \
             mock.patch.object(process, "pet_summary_progress"), \
             mock.patch.object(process, "_ask", return_value=""):
            record = process.make_record(transcript, True)
        self.assertTrue(record.strip(), "会议全程回退后不应为空")
        self.assertIn("说话人A", record)
        self.assertIn("说话人B", record)

    def test_make_record_uses_llm_output_when_present(self):
        process = reload_process()
        transcript = "说话人A：你好呀"
        with mock.patch.object(process, "log"), \
             mock.patch.object(process, "pet_summary_progress"), \
             mock.patch.object(process, "_ask", return_value="说话人A：你好呀。"):
            record = process.make_record(transcript, True)
        self.assertIn("你好呀。", record)


if __name__ == "__main__":
    unittest.main()
