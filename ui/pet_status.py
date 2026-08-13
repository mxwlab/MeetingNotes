"""纯函数：把后台流水线的状态/日志映射成菜单栏可显示的信息。不依赖 GUI 或第三方库。"""

import re
from dataclasses import dataclass

IDLE_TITLE = "🐱 空闲"
FAIL_TITLE = "⚠️ 处理失败"

_DONE_RE = re.compile(r"✅ 完成:\s*(.+?)\s*$")
_FAIL_RE = re.compile(r"❌ 失败(?:\([^)]*\))?:\s*(.+?)(?:\s+—.*)?$")


@dataclass(frozen=True)
class Outcome:
    result: str   # "ok" | "fail" | "none"
    name: str
    marker: str


def title_from_pet_state(text: str) -> str:
    """.pet_state 内容(三行: 状态/录音名/进度) → 菜单栏标题。异常/未知一律显示空闲。"""
    lines = (text or "").splitlines()
    state = lines[0].strip() if lines else ""
    pct = lines[2].strip() if len(lines) >= 3 else ""
    if state == "transcribe":
        return f"🎙️ {pct}%" if pct.isdigit() else "🎙️ 转录中"
    if state == "summarize":
        return "📝 生成中"
    return IDLE_TITLE


def latest_outcome(log_text: str) -> Outcome:
    """取日志中最后一个终态事件(完成/失败)。失败的 marker=该行原文(含时间戳,事件唯一)。"""
    for line in reversed((log_text or "").splitlines()):
        m = _FAIL_RE.search(line)
        if m:
            return Outcome("fail", m.group(1).strip(), line.strip())
        m = _DONE_RE.search(line)
        if m:
            return Outcome("ok", m.group(1).strip(), "")
    return Outcome("none", "", "")


def should_alert(prev_marker, outcome: Outcome) -> bool:
    """仅当出现新的失败(marker 与上次已提醒的不同)时才提醒。"""
    return outcome.result == "fail" and outcome.marker != prev_marker
