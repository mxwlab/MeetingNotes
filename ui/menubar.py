import os
import shutil
import subprocess
import sys

import rumps


def _modern_status_bar_title(nsapp):
    """兼容新版 macOS：NSStatusItem 标题需通过 button 设置。"""
    title = nsapp._app["_title"] or nsapp._app["_name"]
    button = nsapp.nsstatusitem.button()
    if button is not None:
        button.setTitle_(title)


rumps.rumps.NSApp.setStatusBarTitle = _modern_status_bar_title

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from ui.pet_status import (  # noqa: E402
    FAIL_TITLE,
    IDLE_TITLE,
    latest_outcome,
    should_alert,
    title_from_pet_state,
)
from ui.provider_config import (  # noqa: E402
    save_custom,
    save_deepseek,
    validate_deepseek,
    validate_provider,
)

BASE = os.environ.get("MEETINGNOTES_BASE") or ROOT
CONFIG = os.path.join(BASE, "config.local.sh")
PET_STATE = os.path.join(BASE, ".pet_state")
WATCH_LOG = os.path.join(BASE, "logs", "watch.log")


def _dir(name, fallback):
    path = os.path.join(BASE, name)
    return path if os.path.exists(path) else os.path.join(BASE, fallback)


REC_DIR = _dir("录音", "inbox")
NOTE_DIR = _dir("纪要", "output")


def _read(path):
    try:
        with open(path, encoding="utf-8") as file:
            return file.read()
    except OSError:
        return ""


def _osa(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _which(name):
    return shutil.which(name) or (
        f"/opt/homebrew/bin/{name}"
        if os.path.exists(f"/opt/homebrew/bin/{name}")
        else None
    )


def notify(message, title="会议纪要"):
    """使用 terminal-notifier，并以 osascript 兜底。"""
    terminal_notifier = _which("terminal-notifier")
    if terminal_notifier:
        subprocess.run(
            [
                terminal_notifier,
                "-title",
                title,
                "-message",
                message,
                "-group",
                "meetingnotes",
            ],
            capture_output=True,
            check=False,
        )
        return
    subprocess.run(
        [
            "osascript",
            "-e",
            f"display notification {_osa(message)} with title {_osa(title)}",
        ],
        capture_output=True,
        check=False,
    )


class MeetingNotesApp(rumps.App):
    def __init__(self):
        super().__init__("MeetingNotes", title=IDLE_TITLE, quit_button="退出")
        initial_outcome = latest_outcome(_read(WATCH_LOG))
        self._alerted_marker = (
            initial_outcome.marker if initial_outcome.result == "fail" else None
        )
        self._failed = initial_outcome.result == "fail"
        self.fail_item = rumps.MenuItem(
            "⚠️ 上次处理失败 · 点此检查服务设置",
            callback=self.on_settings_deepseek,
        )
        self.menu = [
            rumps.MenuItem("打开「录音」文件夹", callback=self.open_rec),
            rumps.MenuItem("打开「纪要」文件夹", callback=self.open_notes),
            rumps.MenuItem("查看处理日志", callback=self.open_log),
            None,
            rumps.MenuItem("使用 DeepSeek…", callback=self.on_settings_deepseek),
            rumps.MenuItem("使用其他兼容服务…", callback=self.on_settings_custom),
        ]
        self._show_fail_item(self._failed)

    @rumps.events.before_start
    def restore_visibility(self):
        """撤销旧版本可能被 macOS 保留的隐藏状态。"""
        self._nsapp.nsstatusitem.setVisible_(True)

    @rumps.timer(2)
    def tick(self, _):
        outcome = latest_outcome(_read(WATCH_LOG))
        if should_alert(self._alerted_marker, outcome):
            self._alerted_marker = outcome.marker
            self._failed = True
            self._show_fail_item(True)
            notify(
                f"⚠️ 处理失败：{outcome.name}。可能是服务配置有误，点此检查设置。"
            )
        elif outcome.result == "ok":
            self._alerted_marker = None
            self._failed = False
            self._show_fail_item(False)
        state_title = title_from_pet_state(_read(PET_STATE))
        self.title = FAIL_TITLE if self._failed else state_title

    def _show_fail_item(self, on):
        key = self.fail_item.title
        if on and key not in self.menu:
            self.menu.insert_before(next(iter(self.menu)), self.fail_item)
        elif not on and key in self.menu:
            del self.menu[key]

    def open_rec(self, _):
        subprocess.run(["open", REC_DIR], check=False)

    def open_notes(self, _):
        subprocess.run(["open", NOTE_DIR], check=False)

    def open_log(self, _):
        subprocess.run(["open", WATCH_LOG], check=False)

    def _prompt(self, message, title, default="", secure=False):
        window = rumps.Window(
            message,
            title,
            default_text=default,
            ok="继续",
            cancel="取消",
            secure=secure,
        )
        window.width = 320
        result = window.run()
        return result.text.strip() if result.clicked == 1 else None

    def _retry_or_skip(self, reason):
        result = rumps.alert(
            "验证未通过",
            reason,
            ok="重试",
            cancel="取消",
            other="跳过并保存",
        )
        return {1: "retry", 0: "cancel", 2: "skip"}.get(result, "cancel")

    def on_settings_deepseek(self, _):
        while True:
            key = self._prompt(
                "请输入你的 DeepSeek API Key",
                "服务设置 · DeepSeek",
                secure=True,
            )
            if key is None:
                return
            ok, reason = validate_deepseek(key)
            if ok:
                save_deepseek(CONFIG, key)
                self._saved()
                return
            action = self._retry_or_skip(reason)
            if action == "skip":
                save_deepseek(CONFIG, key)
                self._saved()
                return
            if action == "cancel":
                return

    def on_settings_custom(self, _):
        base = self._prompt(
            "接口地址 Base URL（如你的网关地址）",
            "服务设置 · 其他服务 (1/3)",
            default="https://",
        )
        if not base:
            return
        model = self._prompt(
            "模型名（如 kimi-k2 / gpt-4o-mini）",
            "服务设置 · 其他服务 (2/3)",
        )
        if not model:
            return
        while True:
            key = self._prompt("API Key", "服务设置 · 其他服务 (3/3)", secure=True)
            if key is None:
                return
            ok, reason = validate_provider(base, model, key)
            if ok:
                save_custom(CONFIG, base, model, key)
                self._saved()
                return
            action = self._retry_or_skip(reason)
            if action == "skip":
                save_custom(CONFIG, base, model, key)
                self._saved()
                return
            if action == "cancel":
                return

    def _saved(self):
        self._alerted_marker = None
        self._failed = False
        self._show_fail_item(False)
        notify("服务已更新，下一条录音生效。")


if __name__ == "__main__":
    MeetingNotesApp().run()
