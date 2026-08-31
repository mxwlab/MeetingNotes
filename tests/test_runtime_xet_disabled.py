"""运行时必须禁用 hf-xet（回归防护）。

背景：安装脚本 provision_models.sh 已设 HF_HUB_DISABLE_XET=1，但运行时（process.py
被 watch_inbox/launchd 拉起）此前没设。若首次运行需要联网拉取模型（如未预置的
配套模型），xet 在慢/受限网络会静默停滞，表现为“转录卡死”。process.py 必须在导入
早期把 xet 关掉作为兜底，任何运行时联网都走可续传 HTTP。
"""
import importlib
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def test_process_import_disables_xet_by_default():
    """导入 process 后，HF_HUB_DISABLE_XET 默认应为 '1'。"""
    os.environ.pop("HF_HUB_DISABLE_XET", None)
    sys.modules.pop("process", None)
    importlib.import_module("process")
    assert os.environ.get("HF_HUB_DISABLE_XET") == "1"


def test_process_respects_explicit_xet_override():
    """高级用户显式设 0 重新启用 Xet 时不被覆盖（setdefault 语义）。"""
    os.environ["HF_HUB_DISABLE_XET"] = "0"
    try:
        sys.modules.pop("process", None)
        importlib.import_module("process")
        assert os.environ.get("HF_HUB_DISABLE_XET") == "0"
    finally:
        os.environ.pop("HF_HUB_DISABLE_XET", None)


def test_source_sets_xet_via_setdefault():
    """源码里用 setdefault 显式关闭 xet（静态防护，防止有人删掉这行）。"""
    src = (ROOT / "process.py").read_text(encoding="utf-8")
    assert 'os.environ.setdefault("HF_HUB_DISABLE_XET", "1")' in src
