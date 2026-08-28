import importlib, os, sys
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_pet_launch_spawns_native_pet_app_not_python():
    """桌面进度小猫应启动原生 MeetingNotesPet.app，而不是已删除的 python pet.py。"""
    process = load()
    assert process.PET_APP.endswith("MeetingNotesPet.app/Contents/MacOS/MeetingNotesPet"), process.PET_APP
    with mock.patch.object(process, "pet_set"), \
         mock.patch("subprocess.run"), \
         mock.patch("os.path.exists", return_value=True), \
         mock.patch("subprocess.Popen") as popen:
        process.pet_launch("会议录音")
    assert popen.called, "应启动原生小猫进程"
    argv = popen.call_args.args[0]
    assert argv == [process.PET_APP], argv
    # 必须把 MEETINGNOTES_BASE 传给小猫，它才能读对 .pet_state 与品牌图标
    env = popen.call_args.kwargs.get("env") or {}
    assert env.get("MEETINGNOTES_BASE") == process.BASE, env.get("MEETINGNOTES_BASE")


def test_pet_launch_skips_when_pet_app_missing():
    """没构建原生小猫时静默跳过（小猫是锦上添花，不能拖垮处理）。"""
    process = load()
    with mock.patch.object(process, "pet_set"), \
         mock.patch("subprocess.run"), \
         mock.patch("os.path.exists", return_value=False), \
         mock.patch("subprocess.Popen") as popen:
        process.pet_launch("会议录音")
    assert not popen.called, "小猫二进制不存在时不应尝试启动"


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn(); print("PASS", fn.__name__)
        except AssertionError as e:
            failed += 1; print("FAIL", fn.__name__, e)
    print("DONE failures=", failed)
    sys.exit(1 if failed else 0)
