"""#7 回归：LLM 调用是阻塞的，慢模型下会长时间无输出、像卡死。
_ask 应在等待期间周期性打印心跳日志；快调用（早于一个间隔返回）则不打扰。"""
import importlib
import io
import os
import sys
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def reload_process():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


class _FakeResp:
    def __init__(self, text):
        msg = mock.Mock()
        msg.content = text
        choice = mock.Mock()
        choice.message = msg
        self.choices = [choice]


class HeartbeatTests(unittest.TestCase):
    def setUp(self):
        os.environ["MEETINGNOTES_HEARTBEAT_SECS"] = "0.2"
        self.addCleanup(os.environ.pop, "MEETINGNOTES_HEARTBEAT_SECS", None)
        self.process = reload_process()

    def test_slow_call_emits_heartbeat(self):
        def slow_create(*a, **k):
            time.sleep(0.7)          # 跨过好几个 0.2s 心跳间隔
            return _FakeResp("最终结果")
        buf = io.StringIO()
        with mock.patch.object(self.process.client.chat.completions, "create",
                               side_effect=slow_create):
            with redirect_stdout(buf):
                out = self.process._ask("sys", "user")
        self.assertEqual(out, "最终结果")
        self.assertIn("仍在等待模型响应", buf.getvalue())

    def test_fast_call_stays_quiet(self):
        buf = io.StringIO()
        with mock.patch.object(self.process.client.chat.completions, "create",
                               return_value=_FakeResp("秒回")):
            with redirect_stdout(buf):
                out = self.process._ask("sys", "user")
        self.assertEqual(out, "秒回")
        self.assertNotIn("仍在等待模型响应", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
