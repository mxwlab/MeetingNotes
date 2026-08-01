import importlib, sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_segments_via_llm():
    process = load()
    with mock.patch.object(process, "log"), \
         mock.patch.object(process, "_ask", return_value="## 话题一\n内容...") as a:
        out = process.make_segmented_transcript("说了一大坨没有分段的转录文本")
    assert "## 话题一" in out
    assert a.call_count >= 1


def test_empty_returns_empty():
    process = load()
    with mock.patch.object(process, "log"):
        assert process.make_segmented_transcript("   ") == ""


def test_chunk_text_splits_long():
    process = load()
    chunks = process._chunk_text("句子。" * 5000, 6000)
    assert len(chunks) >= 2
    assert "".join(chunks) == "句子。" * 5000


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
