import importlib, sys, tempfile, os
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_people_hint_and_injection():
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._PEOPLE_PATH = os.path.join(d, "p.txt")
        open(process._PEOPLE_PATH, "w", encoding="utf-8").write("张清源\n陈罡\n")
        hint = process._people_hint()
        assert "张清源" in hint and "陈罡" in hint
        assert "已知参会人" in hint
        cap = {}

        def fake_ask(system, user, max_tokens=4000):
            cap["s"] = system
            return "# 会议纪要\n"

        with mock.patch.object(process, "log"), \
             mock.patch.object(process, "_ask", side_effect=fake_ask):
            process.summarize_perperson("t")
        assert "张清源" in cap["s"]  # 名单注入到了归纳提示词


def test_people_empty_returns_empty():
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._PEOPLE_PATH = os.path.join(d, "p.txt")
        assert process._people_hint() == ""


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
