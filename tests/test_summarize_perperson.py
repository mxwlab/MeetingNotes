import importlib, sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_perperson_prompt_and_passthrough():
    process = load()
    captured = {}

    def fake_ask(system, user, max_tokens=4000):
        captured["system"] = system
        return "# 会议纪要\n## 按参会人归纳\n..."

    with mock.patch.object(process, "log"), \
         mock.patch.object(process, "_ask", side_effect=fake_ask):
        out = process.summarize_perperson("转录文本")
    assert "按参会人" in captured["system"]
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
