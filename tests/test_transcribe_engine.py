import importlib, sys, types
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_transcribe_prefers_qwen():
    process = load()
    with mock.patch.object(process, "transcribe_qwen", return_value="QWEN文本") as q, \
         mock.patch.object(process, "transcribe_whisper", return_value="WHISPER文本") as w:
        assert process.transcribe("x.wav") == "QWEN文本"
    q.assert_called_once()
    w.assert_not_called()


def test_transcribe_falls_back_to_whisper_on_qwen_error():
    process = load()
    with mock.patch.object(process, "transcribe_qwen", side_effect=RuntimeError("boom")), \
         mock.patch.object(process, "transcribe_whisper", return_value="WHISPER文本"), \
         mock.patch.object(process, "log"):
        assert process.transcribe("x.wav") == "WHISPER文本"


def test_transcribe_qwen_calls_model():
    process = load()
    with mock.patch.object(process, "_load_qwen", return_value=object()), \
         mock.patch.object(process, "_run_qwen",
                           return_value=types.SimpleNamespace(text="  你好 ")), \
         mock.patch.object(process, "log"), \
         mock.patch.object(process, "pet_progress"):
        assert process.transcribe_qwen("x.wav") == "你好"


def test_transcribe_qwen_reports_progress():
    process = load()

    def fake_run(wav, model, on_progress=None):
        if on_progress:
            on_progress({"event": "chunk_completed", "progress": 0.5})  # 模拟库上报进度
        return types.SimpleNamespace(text="hi")

    with mock.patch.object(process, "_load_qwen", return_value=object()), \
         mock.patch.object(process, "_run_qwen", side_effect=fake_run), \
         mock.patch.object(process, "log"), \
         mock.patch.object(process, "pet_progress") as pp:
        out = process.transcribe_qwen("x.wav")
    assert out == "hi"
    assert pp.called  # on_progress 被接到 pet_progress


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
