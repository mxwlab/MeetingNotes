import importlib, os, sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_main_writes_three_artifacts():
    process = load()
    out = ROOT / "output"
    with mock.patch.object(process, "log"), mock.patch.object(process, "pet_launch"), \
         mock.patch.object(process, "pet_set"), mock.patch.object(process, "pet_summary_progress"), \
         mock.patch.object(process, "notify"), \
         mock.patch("subprocess.run"), mock.patch("shutil.move"), mock.patch("os.remove"), \
         mock.patch.object(process, "transcribe", return_value="转录文本"), \
         mock.patch.object(process, "make_segmented_transcript", return_value="## 段\n整理"), \
         mock.patch.object(process, "summarize_minutes", return_value="# 会议纪要\n内容"), \
         mock.patch.object(process, "save_to_obsidian", return_value=False), \
         mock.patch("os.path.exists", return_value=True):
        process.main("/x/测试录音.m4a")
    files = list(out.glob("*测试录音*"))
    names = " ".join(f.name for f in files)
    try:
        assert "_转录.txt" in names, names
        assert "_整理稿.md" in names, names
        assert "_纪要.md" in names, names
    finally:
        for f in files:
            f.unlink()


def test_main_empty_transcript_moves_to_skipped_without_llm():
    """空转录：不调 LLM、不写任何产物，录音挪进 skipped 并明确通知。"""
    process = load()
    skipped_dir = ROOT / "skipped"
    moved = {}
    def fake_move(src, dst):
        moved["dst"] = str(dst)
        return dst
    with mock.patch.object(process, "log"), mock.patch.object(process, "pet_launch"), \
         mock.patch.object(process, "pet_set"), mock.patch.object(process, "pet_stop"), \
         mock.patch.object(process, "notify") as notify, \
         mock.patch("subprocess.run"), \
         mock.patch.object(process, "transcribe", return_value="   "), \
         mock.patch.object(process, "make_segmented_transcript") as tidy, \
         mock.patch.object(process, "summarize_minutes") as minutes, \
         mock.patch("shutil.move", side_effect=fake_move), \
         mock.patch("os.path.exists", return_value=True):
        process.main("/x/静音.m4a")
    assert moved, "应把静音录音挪进 skipped"
    assert skipped_dir.name in moved["dst"].split(os.sep), moved["dst"]
    tidy.assert_not_called()
    minutes.assert_not_called()
    assert any("语音" in c.args[0] for c in notify.call_args_list), notify.call_args_list


def test_main_missing_ffmpeg_notifies_and_keeps_file():
    """ffmpeg 不存在：明确提示、不挪文件（是安装问题不是文件问题）。"""
    process = load()
    with mock.patch.object(process, "log"), mock.patch.object(process, "pet_launch"), \
         mock.patch.object(process, "pet_stop"), \
         mock.patch.object(process, "notify") as notify, \
         mock.patch("subprocess.run", side_effect=FileNotFoundError), \
         mock.patch.object(process, "transcribe") as transcribe, \
         mock.patch("shutil.move") as move, \
         mock.patch("os.path.exists", return_value=True):
        process.main("/x/录音.m4a")
    transcribe.assert_not_called()
    move.assert_not_called()
    assert any("ffmpeg" in c.args[0] for c in notify.call_args_list), notify.call_args_list


def test_main_llm_failure_keeps_transcript_and_audio():
    """整理稿 LLM 失败：保留已写出的转录，不写纪要，录音留在 inbox 待重试。"""
    process = load()
    out = ROOT / "output"
    with mock.patch.object(process, "log"), mock.patch.object(process, "pet_launch"), \
         mock.patch.object(process, "pet_set"), mock.patch.object(process, "pet_stop"), \
         mock.patch.object(process, "notify"), \
         mock.patch("subprocess.run"), \
         mock.patch.object(process, "transcribe", return_value="转录文本"), \
         mock.patch.object(process, "make_segmented_transcript",
                          side_effect=RuntimeError("网络断了")), \
         mock.patch.object(process, "summarize_minutes") as minutes, \
         mock.patch("shutil.move") as move, \
         mock.patch("os.path.exists", return_value=True):
        process.main("/x/半途失败.m4a")
    minutes.assert_not_called()
    move.assert_not_called()
    files = list(out.glob("*半途失败*"))
    names = " ".join(f.name for f in files)
    try:
        assert "_转录.txt" in names, names
        assert "_整理稿.md" not in names, names
        assert "_纪要.md" not in names, names
    finally:
        for f in files:
            f.unlink()


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
