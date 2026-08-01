import importlib, sys
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
