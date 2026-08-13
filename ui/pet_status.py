"""纯函数：把后台流水线的状态/日志映射成菜单栏可显示的信息。不依赖 GUI 或第三方库。"""

IDLE_TITLE = "🐱 空闲"
FAIL_TITLE = "⚠️ 处理失败"


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
