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
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = slow_create
        buf = io.StringIO()
        with mock.patch.object(self.process, "_get_client", return_value=fake_client):
            with redirect_stdout(buf):
                out = self.process._ask("sys", "user")
        self.assertEqual(out, "最终结果")
        self.assertIn("仍在等待模型响应", buf.getvalue())

    def test_fast_call_stays_quiet(self):
        fake_client = mock.Mock()
        fake_client.chat.completions.create.return_value = _FakeResp("秒回")
        buf = io.StringIO()
        with mock.patch.object(self.process, "_get_client", return_value=fake_client):
            with redirect_stdout(buf):
                out = self.process._ask("sys", "user")
        self.assertEqual(out, "秒回")
        self.assertNotIn("仍在等待模型响应", buf.getvalue())

    def test_missing_key_raises_clear_error(self):
        """没配 DEEPSEEK_API_KEY 时 import 不崩，首次真正调 LLM 才报明确中文错误。"""
        with mock.patch.dict(os.environ, {"DEEPSEEK_API_KEY": ""}, clear=False):
            process2 = reload_process()      # 全新模块，_client 未初始化
            with self.assertRaises(RuntimeError) as ctx:
                process2._ask("sys", "user")
            self.assertIn("DEEPSEEK_API_KEY", str(ctx.exception))

    def test_retries_then_raises(self):
        """LLM 调用失败会重试，重试耗尽后抛最后一个异常。"""
        fake_client = mock.Mock()
        fake_client.chat.completions.create.side_effect = RuntimeError("网络断了")
        buf = io.StringIO()
        with mock.patch.object(self.process, "_get_client", return_value=fake_client), \
             mock.patch.object(self.process, "log"), \
             mock.patch.object(self.process.time, "sleep"), \
             redirect_stdout(buf):
            with self.assertRaises(RuntimeError) as ctx:
                self.process._ask("sys", "user", retries=2)
        self.assertIn("网络断了", str(ctx.exception))
        self.assertEqual(fake_client.chat.completions.create.call_count, 3)  # 1 次 + 2 次重试


if __name__ == "__main__":
    unittest.main()
