import importlib, sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_minutes_prompt_and_passthrough():
    process = load()
    captured = {}

    def fake_ask(system, user, max_tokens=4000):
        captured["system"] = system
        return "# 会议纪要\n## 讨论要点\n..."

    with mock.patch.object(process, "log"), \
         mock.patch.object(process, "_ask", side_effect=fake_ask):
        out = process.summarize_minutes("转录文本")
    sysmsg = captured["system"]
    # 按议题的结构 + 各维度都要在提示词里
    for token in ["TL;DR", "会中出现的人名", "讨论要点", "会议决策", "待办", "悬而未决", "风险", "关键实体", "解释"]:
        assert token in sysmsg, token
    # 按议题、不按人:避免无说话人信息时套错人
    for token in ["按议题", "不要写", "不要按人"]:
        assert token in sysmsg, token
    assert out.startswith("# 会议纪要")


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn(); print("PASS", fn.__name__)
        except Exception as e:
            failed += 1; print("FAIL", fn.__name__, "->", repr(e))
    print("DONE failures=", failed)
    sys.exit(1 if failed else 0)
