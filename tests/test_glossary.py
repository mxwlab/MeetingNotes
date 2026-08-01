import importlib, sys, tempfile, os
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_update_and_load_roundtrip():
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._GLOSSARY_PATH = os.path.join(d, "g.txt")
        process.update_glossary(["InfluxDB", "联通"])
        process.update_glossary(["联通", "飞客码"])  # 去重合并
        assert process.load_glossary() == ["InfluxDB", "联通", "飞客码"]


def test_hint_injected_when_glossary_exists():
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._GLOSSARY_PATH = os.path.join(d, "g.txt")
        process.update_glossary(["飞客码"])
        captured = {}

        def fake_ask(system, user, max_tokens=4000):
            captured["sys"] = system
            return "# 会议纪要\n"

        with mock.patch.object(process, "log"), \
             mock.patch.object(process, "_ask", side_effect=fake_ask):
            process.summarize_minutes("t")
        assert "飞客码" in captured["sys"]
        assert "已知术语表" in captured["sys"]


def test_no_hint_when_empty():
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._GLOSSARY_PATH = os.path.join(d, "g.txt")
        assert process._glossary_hint() == ""


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
