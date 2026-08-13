# MeetingNotes 菜单栏 App v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 MeetingNotes 加一个独立的 rumps 菜单栏 app：显示处理状态、图形化配置 LLM 服务、快捷打开文件夹/日志、处理失败时即时提醒——全程不改动现有后台流水线。

**Architecture:** 一个只观察状态（读 `.pet_state`/`watch.log`）+ 管配置（写 `config.local.sh`）的菜单栏程序，跑在独立 `venv-ui` 里。纯逻辑（状态映射、日志判定、配置读写、服务验证）抽成不依赖 GUI 的纯函数并单测；GUI 装配层用 rumps，手动验证。

**Tech Stack:** Python 3.10（现有 `venv` 的解释器）、`rumps`（菜单栏，基于 pyobjc）、`openai`（服务验证）、stdlib `unittest`。

## Global Constraints

- **不改现有文件的现有行为**：`watch_inbox.sh` / `watch_downloads.sh` / `process.py` / `pet.py` / 现有 `venv/` / launchd plist 一律不动。本计划只**新增**文件（唯一例外：`.gitignore` 追加一行）。
- **独立 venv**：所有 UI 依赖装进 `venv-ui/`，绝不动现有 `venv/`（内含 mlx/whisper 重依赖 + 已下模型）。
- **不进 launchd**：v1 手动启动，不注册自启、不挂 Folder Action（避免与现有唯一那套 watcher 冲突）。
- **配置写入**：写 `config.local.sh` 必须——先写临时文件再原子替换、权限 600、保留其它键（尤其 `OBSIDIAN_DIR`）与注释、值用 `shlex.quote` 转义。
- **通知机制**：失败提醒用 terminal-notifier→osascript 兜底（与 `process.py` 一致），不用 rumps 内建通知。
- **BASE 定位**：app 通过 `MEETINGNOTES_BASE` 环境变量或默认（`ui/` 上级目录）定位项目根，便于把 dev app 指向真实 `~/MeetingNotes` 测试。
- **受管配置键**：`DEEPSEEK_API_KEY`、`LLM_BASE_URL`、`LLM_MODEL`。DeepSeek 分支写 `DEEPSEEK_API_KEY` 并**移除** `LLM_BASE_URL`/`LLM_MODEL`（让 process.py 回落默认 deepseek）；自定义分支三者都写。
- **状态标题文案**：空闲=`🐱 空闲`，转录=`🎙️ {pct}%`（无数字时 `🎙️ 转录中`），生成=`📝 生成中`，失败态=`⚠️ 处理失败`。

---

## File Structure

- Create `ui/__init__.py` — 空包标识。
- Create `ui/pet_status.py` — 纯函数：状态标题、日志结局判定、失败去重判断。无第三方依赖。
- Create `ui/provider_config.py` — 配置读改写 + 服务验证。`openai` 仅在默认 client 工厂内**惰性 import**，故本模块不 import 时不需要 openai/rumps。
- Create `ui/menubar.py` — rumps App 装配（状态 Timer、菜单、设置流程、失败提醒）。唯一 import rumps 的文件。
- Create `tests/test_pet_status.py` — 覆盖 `ui/pet_status.py`。
- Create `tests/test_provider_config.py` — 覆盖 `ui/provider_config.py`。
- Create `requirements-ui.txt` — 钉住 UI 依赖（`rumps`、`openai`）。
- Create `MeetingNotes 设置.command` — 一键双击启动器。
- Modify `.gitignore` — 追加 `venv-ui/`。
- （执行期创建，不提交）`venv-ui/` — 独立虚拟环境。

> **执行前置**：本计划应在一个 git worktree 中执行（用 superpowers:using-git-worktrees 在开始时创建）。所有新增文件落在 worktree 内；测试真实数据时把 app 指向真实安装目录（见 Task 6）。

---

### Task 1: 隔离环境 + rumps 冒烟（最高风险先证）

验证 rumps/pyobjc 能在独立 venv 装好并真的在菜单栏显示一个项。这是全计划最大不确定性，先跑通再往下。

**Files:**
- Create: `requirements-ui.txt`
- Create: `ui/__init__.py`
- Create: `ui/_smoke.py`（临时冒烟脚本，Task 6 完成后删除）
- Create (执行期，不提交): `venv-ui/`

**Interfaces:**
- Consumes: 无
- Produces: 可用的 `venv-ui`（含 rumps、openai）；确认 rumps `App`/`Timer`/`Window`/`alert` 可用。

- [ ] **Step 1: 用现有解释器建独立 venv**

Run:
```bash
./venv/bin/python -m venv venv-ui
./venv-ui/bin/python -m pip install --upgrade pip
```

- [ ] **Step 2: 写依赖清单并安装**

`requirements-ui.txt`:
```
rumps>=0.4.0
openai>=1.0.0
```

Run:
```bash
./venv-ui/bin/pip install -r requirements-ui.txt
```
Expected: 成功装上 rumps + pyobjc + openai（无编译报错）。若 pyobjc 轮子失败，停下报告——这是最大风险点。

- [ ] **Step 3: 写冒烟脚本 `ui/_smoke.py`**

```python
import rumps

class Smoke(rumps.App):
    def __init__(self):
        super().__init__("MeetingNotesSmoke", title="🐱 冒烟")
        self.menu = ["点我测试 Window", "点我测试 alert"]

    @rumps.clicked("点我测试 Window")
    def w(self, _):
        r = rumps.Window("输入点东西", "Window 测试", default_text="hi",
                         ok="确定", cancel="取消", secure=False).run()
        rumps.alert("你输入了", f"clicked={r.clicked} text={r.text!r}")

    @rumps.clicked("点我测试 alert")
    def a(self, _):
        n = rumps.alert("三按钮", "选一个", ok="重试", cancel="取消", other="跳过并保存")
        rumps.alert("结果", f"返回码={n}")

if __name__ == "__main__":
    Smoke().run()
```

`ui/__init__.py`: 空文件。

- [ ] **Step 4: 手动运行冒烟，确认菜单栏出现**

Run:
```bash
./venv-ui/bin/python ui/_smoke.py
```
Expected（人工确认）：
1. 顶栏出现 `🐱 冒烟` 项；
2. 点「测试 Window」弹出输入框，输入后 alert 回显 `clicked` 与 `text`；
3. 点「测试 alert」弹三按钮，记下「重试/取消/跳过并保存」各自返回码（供 Task 6 用）。
   - 关注 `secure=True` 是否被支持（隐藏输入用）；若报错，记下、Task 6 改用普通输入。

按 Ctrl+C 退出。**若菜单栏项不出现或依赖装不上，停下报告，不继续后续任务。**

- [ ] **Step 5: Commit**

```bash
git add requirements-ui.txt ui/__init__.py ui/_smoke.py
git commit -m "chore(ui): 独立 venv-ui + rumps 冒烟验证通过"
```

---

### Task 2: `title_from_pet_state`（状态 → 菜单栏标题）

**Files:**
- Create: `ui/pet_status.py`
- Test: `tests/test_pet_status.py`

**Interfaces:**
- Consumes: 无
- Produces: `title_from_pet_state(text: str) -> str`；常量 `IDLE_TITLE = "🐱 空闲"`、`FAIL_TITLE = "⚠️ 处理失败"`。

- [ ] **Step 1: 写失败测试**

`tests/test_pet_status.py`:
```python
import sys, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.pet_status import title_from_pet_state, IDLE_TITLE  # noqa: E402


class TitleTests(unittest.TestCase):
    def test_transcribe_with_pct(self):
        self.assertEqual(title_from_pet_state("transcribe\n权限讨论\n42\n"), "🎙️ 42%")

    def test_transcribe_without_pct(self):
        self.assertEqual(title_from_pet_state("transcribe\n权限讨论\n\n"), "🎙️ 转录中")

    def test_summarize(self):
        self.assertEqual(title_from_pet_state("summarize\n权限讨论\n10\n"), "📝 生成中")

    def test_done_is_idle(self):
        self.assertEqual(title_from_pet_state("done\n权限讨论\n"), IDLE_TITLE)

    def test_empty_or_garbage_is_idle(self):
        self.assertEqual(title_from_pet_state(""), IDLE_TITLE)
        self.assertEqual(title_from_pet_state("???"), IDLE_TITLE)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./venv-ui/bin/python -m unittest tests.test_pet_status -v`
Expected: FAIL（`ModuleNotFoundError: ui.pet_status`）。

- [ ] **Step 3: 写最小实现**

`ui/pet_status.py`:
```python
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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./venv-ui/bin/python -m unittest tests.test_pet_status -v`
Expected: PASS（5 项）。

- [ ] **Step 5: Commit**

```bash
git add ui/pet_status.py tests/test_pet_status.py
git commit -m "feat(ui): 状态→菜单栏标题映射 title_from_pet_state"
```

---

### Task 3: `latest_outcome` + `should_alert`（日志结局判定与失败去重）

**Files:**
- Modify: `ui/pet_status.py`
- Test: `tests/test_pet_status.py`（追加）

**Interfaces:**
- Consumes: 无
- Produces:
  - `@dataclass(frozen=True) class Outcome: result: str; name: str; marker: str`（`result ∈ {"ok","fail","none"}`）
  - `latest_outcome(log_text: str) -> Outcome`：扫描 `watch.log`，取最后一个终态事件（`✅ 完成` / `❌ 失败`）。失败时 `marker` = 该失败行原文（含时间戳，事件唯一）。
  - `should_alert(prev_marker: str | None, outcome: Outcome) -> bool`：`outcome.result == "fail" and outcome.marker != prev_marker`。

- [ ] **Step 1: 追加失败测试**

在 `tests/test_pet_status.py` 顶部 import 行改为：
```python
from ui.pet_status import (title_from_pet_state, IDLE_TITLE,
                           latest_outcome, should_alert, Outcome)  # noqa: E402
```
追加测试类：
```python
OK_LOG = "[2026-08-11 23:40:32] 开始处理: 权限讨论.m4a\n[2026-08-11 23:41:00] ✅ 完成: 权限讨论.m4a\n"
FAIL_LOG = ("[2026-08-11 23:40:32] 开始处理: 坏文件.m4a\n"
            "[2026-08-11 23:40:35] ❌ 失败(退出码 1): 坏文件.m4a — 详见上方日志\n")
FAIL_THEN_OK = FAIL_LOG + "[2026-08-11 23:50:00] ✅ 完成: 好文件.m4a\n"


class OutcomeTests(unittest.TestCase):
    def test_none_when_empty(self):
        self.assertEqual(latest_outcome("").result, "none")

    def test_ok(self):
        self.assertEqual(latest_outcome(OK_LOG).result, "ok")

    def test_fail_extracts_name_and_marker(self):
        o = latest_outcome(FAIL_LOG)
        self.assertEqual(o.result, "fail")
        self.assertEqual(o.name, "坏文件.m4a")
        self.assertIn("坏文件.m4a", o.marker)

    def test_later_success_clears_fail(self):
        self.assertEqual(latest_outcome(FAIL_THEN_OK).result, "ok")

    def test_marker_stable_and_changes(self):
        o1 = latest_outcome(FAIL_LOG)
        self.assertEqual(o1.marker, latest_outcome(FAIL_LOG).marker)  # 同一失败稳定
        o2 = latest_outcome(FAIL_LOG.replace("23:40:35", "23:59:59"))
        self.assertNotEqual(o1.marker, o2.marker)                     # 新失败改变

    def test_should_alert_dedup(self):
        o = latest_outcome(FAIL_LOG)
        self.assertTrue(should_alert(None, o))
        self.assertFalse(should_alert(o.marker, o))                   # 同 marker 不重复
        self.assertFalse(should_alert(None, latest_outcome(OK_LOG)))  # 非失败不提醒
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./venv-ui/bin/python -m unittest tests.test_pet_status -v`
Expected: FAIL（`ImportError: cannot import name 'latest_outcome'`）。

- [ ] **Step 3: 追加实现**

在 `ui/pet_status.py` 追加：
```python
import re
from dataclasses import dataclass

_DONE_RE = re.compile(r"✅ 完成:\s*(.+?)\s*$")
_FAIL_RE = re.compile(r"❌ 失败(?:\([^)]*\))?:\s*(.+?)(?:\s+—.*)?$")


@dataclass(frozen=True)
class Outcome:
    result: str   # "ok" | "fail" | "none"
    name: str
    marker: str


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
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./venv-ui/bin/python -m unittest tests.test_pet_status -v`
Expected: PASS（全部）。

- [ ] **Step 5: Commit**

```bash
git add ui/pet_status.py tests/test_pet_status.py
git commit -m "feat(ui): 日志结局判定 latest_outcome + 失败去重 should_alert"
```

---

### Task 4: `config.local.sh` 读改写（保留其它键、原子、600）

**Files:**
- Create: `ui/provider_config.py`
- Test: `tests/test_provider_config.py`

**Interfaces:**
- Consumes: 无
- Produces:
  - `apply_updates(existing_text: str, set_map: dict[str,str], unset_keys=()) -> str`：更新/插入 `export KEY=值`（值 `shlex.quote`），删除 `unset_keys` 的行，其它行/注释/顺序原样保留。
  - `save_deepseek(path: str, api_key: str) -> None`
  - `save_custom(path: str, base_url: str, model: str, api_key: str) -> None`
  - 两个 save 都：读原文件(不存在按空)、apply_updates、原子写、chmod 600。

- [ ] **Step 1: 写失败测试**

`tests/test_provider_config.py`:
```python
import os, sys, stat, tempfile, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from ui.provider_config import apply_updates, save_deepseek, save_custom  # noqa: E402


class ApplyUpdatesTests(unittest.TestCase):
    def test_update_existing_and_preserve_others(self):
        existing = ('export DEEPSEEK_API_KEY="old"\n'
                    'export OBSIDIAN_DIR="/vault/会议"\n'
                    '# 我的注释\n')
        out = apply_updates(existing, {"DEEPSEEK_API_KEY": "new"})
        self.assertIn("export DEEPSEEK_API_KEY=new", out)   # shlex.quote 简单串不加引号
        self.assertIn('export OBSIDIAN_DIR="/vault/会议"', out)  # 原样保留
        self.assertIn("# 我的注释", out)
        self.assertNotIn('"old"', out)

    def test_insert_when_absent(self):
        out = apply_updates("", {"LLM_MODEL": "kimi-k2"})
        self.assertIn("export LLM_MODEL=kimi-k2", out)

    def test_unset_removes_line(self):
        existing = 'export LLM_BASE_URL="https://gw"\nexport LLM_MODEL="kimi"\n'
        out = apply_updates(existing, {"DEEPSEEK_API_KEY": "k"},
                            unset_keys=("LLM_BASE_URL", "LLM_MODEL"))
        self.assertNotIn("LLM_BASE_URL", out)
        self.assertNotIn("LLM_MODEL", out)
        self.assertIn("export DEEPSEEK_API_KEY=k", out)

    def test_quotes_values_with_spaces(self):
        out = apply_updates("", {"OBSIDIAN_DIR": "/a b/会议"})
        self.assertIn("export OBSIDIAN_DIR='/a b/会议'", out)


class SaveTests(unittest.TestCase):
    def _tmp(self):
        d = tempfile.mkdtemp()
        return os.path.join(d, "config.local.sh")

    def test_save_custom_writes_three_keys_and_600(self):
        p = self._tmp()
        with open(p, "w") as f:
            f.write('export OBSIDIAN_DIR="/vault"\n')
        save_custom(p, "https://gw/v1", "kimi-k2", "sk-x")
        text = open(p).read()
        self.assertIn("export LLM_BASE_URL=https://gw/v1", text)
        self.assertIn("export LLM_MODEL=kimi-k2", text)
        self.assertIn("export DEEPSEEK_API_KEY=sk-x", text)
        self.assertIn('export OBSIDIAN_DIR="/vault"', text)  # 保留
        self.assertEqual(stat.S_IMODE(os.stat(p).st_mode), 0o600)

    def test_save_deepseek_unsets_custom(self):
        p = self._tmp()
        with open(p, "w") as f:
            f.write('export LLM_BASE_URL="https://gw"\nexport LLM_MODEL="kimi"\n'
                    'export OBSIDIAN_DIR="/vault"\n')
        save_deepseek(p, "sk-deep")
        text = open(p).read()
        self.assertIn("export DEEPSEEK_API_KEY=sk-deep", text)
        self.assertNotIn("LLM_BASE_URL", text)
        self.assertNotIn("LLM_MODEL", text)
        self.assertIn('export OBSIDIAN_DIR="/vault"', text)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./venv-ui/bin/python -m unittest tests.test_provider_config -v`
Expected: FAIL（`ModuleNotFoundError: ui.provider_config`）。

- [ ] **Step 3: 写实现**

`ui/provider_config.py`:
```python
"""图形化服务设置：读改写 config.local.sh（保留其它键）+ 用最小请求验证 LLM 服务。
openai 仅在默认 client 工厂内惰性 import，故本模块导入本身不需要 openai。"""
import os
import re
import shlex

DEFAULT_DEEPSEEK_BASE = "https://api.deepseek.com"
DEFAULT_DEEPSEEK_MODEL = "deepseek-chat"


def apply_updates(existing_text: str, set_map: dict, unset_keys=()) -> str:
    """更新/插入 export KEY=值(shlex.quote)；删除 unset_keys；其它行原样保留。"""
    unset = set(unset_keys)
    seen = set()
    out_lines = []
    for line in (existing_text or "").splitlines():
        m = re.match(r"\s*export\s+([A-Za-z_][A-Za-z0-9_]*)=", line)
        key = m.group(1) if m else None
        if key in unset:
            continue
        if key in set_map:
            out_lines.append(f"export {key}={shlex.quote(set_map[key])}")
            seen.add(key)
        else:
            out_lines.append(line)
    for key, val in set_map.items():
        if key not in seen:
            out_lines.append(f"export {key}={shlex.quote(val)}")
    return "\n".join(out_lines) + "\n"


def _atomic_write_600(path: str, text: str) -> None:
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def _read(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def save_deepseek(path: str, api_key: str) -> None:
    text = apply_updates(_read(path), {"DEEPSEEK_API_KEY": api_key},
                         unset_keys=("LLM_BASE_URL", "LLM_MODEL"))
    _atomic_write_600(path, text)


def save_custom(path: str, base_url: str, model: str, api_key: str) -> None:
    text = apply_updates(_read(path), {
        "DEEPSEEK_API_KEY": api_key,
        "LLM_BASE_URL": base_url,
        "LLM_MODEL": model,
    })
    _atomic_write_600(path, text)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./venv-ui/bin/python -m unittest tests.test_provider_config -v`
Expected: PASS（全部）。

- [ ] **Step 5: Commit**

```bash
git add ui/provider_config.py tests/test_provider_config.py
git commit -m "feat(ui): config.local.sh 读改写(保留其它键/原子/600)"
```

---

### Task 5: 服务验证 `validate_provider`（最小 chat 请求，client 可注入）

**Files:**
- Modify: `ui/provider_config.py`
- Test: `tests/test_provider_config.py`（追加）

**Interfaces:**
- Consumes: `DEFAULT_DEEPSEEK_BASE`、`DEFAULT_DEEPSEEK_MODEL`
- Produces:
  - `validate_provider(base_url, model, api_key, *, client_factory=None) -> tuple[bool, str]`：
    用 `client_factory(base_url, api_key)` 造 client，发 `max_tokens=1` 的最小 chat 请求；成功 `(True, "")`，失败 `(False, 中文原因)`。`client_factory` 缺省时惰性造 openai client。
  - `validate_deepseek(api_key, *, client_factory=None) -> tuple[bool, str]`：
    = `validate_provider(DEFAULT_DEEPSEEK_BASE, DEFAULT_DEEPSEEK_MODEL, api_key, ...)`。

- [ ] **Step 1: 追加失败测试**

在 `tests/test_provider_config.py` import 行追加 `validate_provider, validate_deepseek`，并追加：
```python
from unittest import mock  # 顶部已有 unittest；补 mock


class _FakeClient:
    def __init__(self, exc=None):
        self._exc = exc
        self.chat = mock.Mock()
        self.chat.completions = mock.Mock()
        if exc:
            self.chat.completions.create.side_effect = exc
        else:
            self.chat.completions.create.return_value = mock.Mock()


class ValidateTests(unittest.TestCase):
    def test_success(self):
        ok, msg = validate_provider("https://gw", "m", "k",
                                    client_factory=lambda b, k: _FakeClient())
        self.assertTrue(ok)
        self.assertEqual(msg, "")

    def test_failure_returns_reason(self):
        ok, msg = validate_provider("https://gw", "m", "k",
            client_factory=lambda b, k: _FakeClient(exc=Exception("401 Unauthorized")))
        self.assertFalse(ok)
        self.assertIn("401", msg)

    def test_deepseek_uses_default_base(self):
        captured = {}
        def factory(base, key):
            captured["base"] = base
            return _FakeClient()
        ok, _ = validate_deepseek("k", client_factory=factory)
        self.assertTrue(ok)
        self.assertEqual(captured["base"], "https://api.deepseek.com")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `./venv-ui/bin/python -m unittest tests.test_provider_config -v`
Expected: FAIL（`ImportError: cannot import name 'validate_provider'`）。

- [ ] **Step 3: 追加实现**

在 `ui/provider_config.py` 追加：
```python
def _default_client_factory(base_url: str, api_key: str):
    from openai import OpenAI          # 惰性 import：本模块被单测导入时无需 openai
    return OpenAI(base_url=base_url, api_key=api_key)


def validate_provider(base_url, model, api_key, *, client_factory=None):
    """发一条 max_tokens=1 的最小 chat 请求探活。成功(True,"")；失败(False,中文原因)。"""
    factory = client_factory or _default_client_factory
    try:
        client = factory(base_url, api_key)
        client.chat.completions.create(
            model=model, max_tokens=1,
            messages=[{"role": "user", "content": "hi"}],
        )
        return True, ""
    except Exception as e:               # 网络/鉴权/模型名等任何异常都归为验证失败
        return False, f"验证未通过：{e}"


def validate_deepseek(api_key, *, client_factory=None):
    return validate_provider(DEFAULT_DEEPSEEK_BASE, DEFAULT_DEEPSEEK_MODEL,
                             api_key, client_factory=client_factory)
```

- [ ] **Step 4: 跑测试确认通过**

Run: `./venv-ui/bin/python -m unittest tests.test_provider_config -v`
Expected: PASS（全部）。

- [ ] **Step 5: Commit**

```bash
git add ui/provider_config.py tests/test_provider_config.py
git commit -m "feat(ui): 服务验证 validate_provider(最小chat, client可注入)"
```

---

### Task 6: `ui/menubar.py` 装配（状态/入口/设置/失败提醒）

把 Task 2–5 的纯逻辑装进 rumps App。此任务以**手动端到端验证**为主（GUI）。

**Files:**
- Create: `ui/menubar.py`
- Delete: `ui/_smoke.py`（冒烟脚本使命完成）

**Interfaces:**
- Consumes: `ui.pet_status`（`title_from_pet_state`, `latest_outcome`, `should_alert`, `IDLE_TITLE`, `FAIL_TITLE`）、`ui.provider_config`（`save_deepseek`, `save_custom`, `validate_provider`, `validate_deepseek`, `DEFAULT_DEEPSEEK_BASE`）
- Produces: 可运行的菜单栏 app（`python ui/menubar.py`）。

- [ ] **Step 1: 写 `ui/menubar.py`**

> 说明：`alert` 三按钮返回码以 Task 1 Step 4 实测为准（rumps 通常 ok=1 / cancel=0 / other=2）；下方按常见值 `1/0/2` 写，若实测不同，改这里的判断。`rumps.Window(..., secure=True)` 若 Task 1 报不支持，去掉 `secure`。

```python
import os
import subprocess
import rumps

from ui.pet_status import (title_from_pet_state, latest_outcome, should_alert,
                           IDLE_TITLE, FAIL_TITLE)
from ui.provider_config import (save_deepseek, save_custom,
                                validate_provider, validate_deepseek,
                                DEFAULT_DEEPSEEK_BASE)

BASE = os.environ.get("MEETINGNOTES_BASE") or os.path.dirname(
    os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(BASE, "config.local.sh")
PET_STATE = os.path.join(BASE, ".pet_state")
WATCH_LOG = os.path.join(BASE, "logs", "watch.log")


def _dir(name, fallback):
    p = os.path.join(BASE, name)
    return p if os.path.exists(p) else os.path.join(BASE, fallback)


REC_DIR = _dir("录音", "inbox")
NOTE_DIR = _dir("纪要", "output")


def _read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def notify(message, title="会议纪要"):
    """terminal-notifier → osascript 兜底(与 process.py 一致)。"""
    tn = shutil_which("terminal-notifier")
    if tn:
        subprocess.run([tn, "-title", title, "-message", message,
                        "-group", "meetingnotes"], capture_output=True)
        return
    subprocess.run(["osascript", "-e",
                    f'display notification {_osa(message)} with title {_osa(title)}'],
                   capture_output=True)


def _osa(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def shutil_which(name):
    import shutil
    return shutil.which(name) or (
        f"/opt/homebrew/bin/{name}" if os.path.exists(f"/opt/homebrew/bin/{name}") else None)


class MeetingNotesApp(rumps.App):
    def __init__(self):
        super().__init__("MeetingNotes", title=IDLE_TITLE, quit_button="退出")
        self._alerted_marker = None
        self._failed = False
        self.fail_item = rumps.MenuItem("⚠️ 上次处理失败 · 点此检查服务设置",
                                        callback=self.on_settings_deepseek)
        self.menu = [
            rumps.MenuItem("打开「录音」文件夹", callback=self.open_rec),
            rumps.MenuItem("打开「纪要」文件夹", callback=self.open_notes),
            rumps.MenuItem("查看处理日志", callback=self.open_log),
            None,
            rumps.MenuItem("使用 DeepSeek…", callback=self.on_settings_deepseek),
            rumps.MenuItem("使用其他兼容服务…", callback=self.on_settings_custom),
        ]

    # ---- 状态 + 失败提醒轮询 ----
    @rumps.timer(2)
    def tick(self, _):
        outcome = latest_outcome(_read(WATCH_LOG))
        if should_alert(self._alerted_marker, outcome):
            self._alerted_marker = outcome.marker
            self._failed = True
            self._show_fail_item(True)
            notify(f"⚠️ 处理失败：{outcome.name}。可能是服务配置有误，点此检查设置。")
        elif outcome.result == "ok":
            self._alerted_marker = None
            self._failed = False
            self._show_fail_item(False)
        self.title = FAIL_TITLE if self._failed else title_from_pet_state(_read(PET_STATE))

    def _show_fail_item(self, on):
        key = self.fail_item.title
        if on and key not in self.menu:
            self.menu.insert_before(next(iter(self.menu)), self.fail_item)
        elif not on and key in self.menu:
            del self.menu[key]

    # ---- 快捷入口 ----
    def open_rec(self, _): subprocess.run(["open", REC_DIR])
    def open_notes(self, _): subprocess.run(["open", NOTE_DIR])
    def open_log(self, _): subprocess.run(["open", WATCH_LOG])

    # ---- 服务设置 ----
    def _prompt(self, message, title, default="", secure=False):
        w = rumps.Window(message, title, default_text=default,
                         ok="继续", cancel="取消", secure=secure)
        w.width = 320
        r = w.run()
        return r.text.strip() if r.clicked == 1 else None

    def _retry_or_skip(self, reason):
        """返回 'retry' / 'skip' / 'cancel'（返回码以 Task1 实测为准: ok=1,cancel=0,other=2）。"""
        n = rumps.alert("验证未通过", reason, ok="重试", cancel="取消", other="跳过并保存")
        return {1: "retry", 0: "cancel", 2: "skip"}.get(n, "cancel")

    def on_settings_deepseek(self, _):
        while True:
            key = self._prompt("请输入你的 DeepSeek API Key", "服务设置 · DeepSeek", secure=True)
            if key is None:
                return
            ok, reason = validate_deepseek(key)
            if ok:
                save_deepseek(CONFIG, key); self._saved(); return
            act = self._retry_or_skip(reason)
            if act == "skip":
                save_deepseek(CONFIG, key); self._saved(); return
            if act == "cancel":
                return

    def on_settings_custom(self, _):
        base = self._prompt("接口地址 Base URL（如你的网关地址）",
                            "服务设置 · 其他服务 (1/3)", default="https://")
        if not base:
            return
        model = self._prompt("模型名（如 kimi-k2 / gpt-4o-mini）", "服务设置 · 其他服务 (2/3)")
        if not model:
            return
        while True:
            key = self._prompt("API Key", "服务设置 · 其他服务 (3/3)", secure=True)
            if key is None:
                return
            ok, reason = validate_provider(base, model, key)
            if ok:
                save_custom(CONFIG, base, model, key); self._saved(); return
            act = self._retry_or_skip(reason)
            if act == "skip":
                save_custom(CONFIG, base, model, key); self._saved(); return
            if act == "cancel":
                return

    def _saved(self):
        self._alerted_marker = None
        self._failed = False
        self._show_fail_item(False)
        notify("服务已更新，下一条录音生效。")


if __name__ == "__main__":
    MeetingNotesApp().run()
```

- [ ] **Step 2: 删除冒烟脚本**

Run: `git rm ui/_smoke.py`

- [ ] **Step 3: 手动验证四件功能（指向真实安装目录）**

Run:
```bash
MEETINGNOTES_BASE="/Users/moxiuwen/workspace/MeetingNotes" ./venv-ui/bin/python ui/menubar.py
```
人工确认：
1. **状态**：顶栏显示 `🐱 空闲`；此时往真实 inbox 拖/AirDrop 一条录音，标题应随后变 `🎙️ %`→`📝 生成中`→回 `🐱 空闲`。
2. **快捷入口**：三项分别打开 录音/纪要 文件夹与 `watch.log`。
3. **服务设置**：走「使用其他兼容服务…」，Base/模型/Key 三步；填错触发「验证未通过」→ 选「跳过并保存」；确认 `config.local.sh` 写入了 `LLM_BASE_URL/LLM_MODEL/DEEPSEEK_API_KEY` 且 `OBSIDIAN_DIR` 保留、权限 600（`ls -l@` 或 `stat`）。**验证后把配置改回你的真实可用值**（再走一遍设置或手动还原）。
4. **失败提醒**：往 inbox 拖一个**非音频**文件（如 `.txt`）触发处理失败；~2 秒内应弹通知、标题变 `⚠️ 处理失败`、菜单顶部出现失败项；随后成功处理一条正常录音后，失败态清除。

- [ ] **Step 4: 跑全部单测确认无回归**

Run: `./venv-ui/bin/python -m unittest tests.test_pet_status tests.test_provider_config -v`
Expected: PASS。

- [ ] **Step 5: Commit**

```bash
git add ui/menubar.py
git rm --cached ui/_smoke.py 2>/dev/null || true
git commit -m "feat(ui): 菜单栏 App 装配(状态/入口/服务设置/失败即时提醒)"
```

---

### Task 7: 启动器 + gitignore + 最终验证

**Files:**
- Create: `MeetingNotes 设置.command`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: `venv-ui/`、`ui/menubar.py`
- Produces: 双击即启动 app 的 `.command`。

- [ ] **Step 1: 写启动器**

`MeetingNotes 设置.command`:
```bash
#!/bin/zsh
# 双击启动 MeetingNotes 菜单栏 app（状态/服务设置/失败提醒）。
BASE="${0:A:h}"
exec "$BASE/venv-ui/bin/python" "$BASE/ui/menubar.py"
```

Run: `chmod +x "MeetingNotes 设置.command"`

- [ ] **Step 2: 追加 gitignore**

在 `.gitignore` 的「Python 虚拟环境」块追加一行 `venv-ui/`（紧跟现有 `venv/` 之后）。

- [ ] **Step 3: 手动验证双击启动**

在 Finder 里双击 `MeetingNotes 设置.command`（或 `open "MeetingNotes 设置.command"`），确认菜单栏 app 起来。
> 注意：此启动器 BASE=自身所在目录（worktree）。要指向真实安装数据测试仍用 Task 6 的 `MEETINGNOTES_BASE` 方式；启动器的最终归宿是随 app 装进真实安装目录（v1.5 装机集成时接入）。

- [ ] **Step 4: 确认工作区干净、现有测试全绿**

Run:
```bash
git status --short
./venv/bin/python -m unittest discover -s tests -p 'test_*.py'   # 现有套件不受影响
```
Expected: 干净；现有 Python 测试全 PASS（确认没碰坏现有流程）。

- [ ] **Step 5: Commit**

```bash
git add "MeetingNotes 设置.command" .gitignore
git commit -m "feat(ui): 双击启动器 + gitignore 忽略 venv-ui"
```

---

## Self-Review

**Spec 覆盖核对：**
- 状态显示 → Task 2（标题映射）+ Task 6（Timer 装配）✓
- 服务设置（DeepSeek/自定义、验证、跳过、保留其它键、600）→ Task 4/5（逻辑）+ Task 6（流程）✓
- 快捷入口（录音/纪要/日志）→ Task 6 ✓
- 失败感知与即时提醒（观察 watch.log、去重、通知、标题翻警示、菜单项、成功后清除）→ Task 3（判定+去重）+ Task 6（装配）✓
- 标题优先级（失败态压过 pet_state）→ Task 6 `tick` 中 `FAIL_TITLE if self._failed` ✓
- 隔离约束（独立 venv-ui、只增文件、不进 launchd、worktree）→ Global Constraints + Task 1/7 ✓
- 通知用 terminal-notifier→osascript → Task 6 `notify` ✓
- 配置原子/600/转义 → Task 4 ✓
- 测试策略（纯函数单测 + GUI 手动）→ Task 2–5 单测、Task 6 手动 ✓

**占位符扫描：** 无 TBD/TODO；GUI 步骤给了完整代码 + 明确的人工确认项。

**类型一致性：** `Outcome(result,name,marker)`、`should_alert(prev_marker,outcome)`、`title_from_pet_state`、`apply_updates/save_deepseek/save_custom`、`validate_provider/validate_deepseek` 在 Task 6 的调用与 Task 2–5 定义一致。

**已知待实测点（已在任务中标注，非占位符）：** ① pyobjc 轮子能否装（Task 1 硬门槛）；② `rumps.Window(secure=True)` 是否支持；③ `rumps.alert` 三按钮返回码——三者均在 Task 1 Step 4 实测，Task 6 按实测收敛。
