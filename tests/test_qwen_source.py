import importlib, os, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


def test_prefers_local_snapshot_when_present():
    """有项目本地快照（含 config.json）时用本地路径——可复现/离线。"""
    process = load()
    with tempfile.TemporaryDirectory() as d:
        open(os.path.join(d, "config.json"), "w").close()
        process._QWEN_MODEL_ID = d
        assert process._resolve_qwen_source() == d


def test_falls_back_to_repo_id_when_local_missing():
    """本地快照不存在时回退到 HF 仓库名（走缓存/Hub），
    绝不把不存在的绝对路径丢给 load_model —— 否则它当成 repo_id 校验失败、静默退回 whisper（B4）。"""
    process = load()
    process._QWEN_MODEL_ID = "/no/such/models/qwen3-asr-1.7b-8bit"
    src = process._resolve_qwen_source()
    assert src == process._QWEN_REPO, src
    assert not src.startswith("/"), f"回退值必须是仓库名而非绝对路径: {src}"
    assert "/" in src and src.count("/") == 1, f"应为 namespace/repo_name 形式: {src}"


def test_falls_back_when_dir_exists_but_no_config():
    """目录在但缺 config.json（下载不全）也回退仓库名，别把半残目录当模型。"""
    process = load()
    with tempfile.TemporaryDirectory() as d:
        process._QWEN_MODEL_ID = d
        assert process._resolve_qwen_source() == process._QWEN_REPO


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn(); print("PASS", fn.__name__)
        except AssertionError as e:
            failed += 1; print("FAIL", fn.__name__, e)
        except Exception as e:
            failed += 1; print("ERROR", fn.__name__, e)
    print("DONE failures=", failed)
    sys.exit(1 if failed else 0)
