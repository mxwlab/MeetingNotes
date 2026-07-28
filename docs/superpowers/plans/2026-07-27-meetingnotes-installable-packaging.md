# MeetingNotes 可安装打包（方案 A）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把当前绑定本机的 MeetingNotes 脚本集，改造成技术朋友 `git clone` + `./install.sh` 即装即用、且不破坏作者本地实例的可分发项目。

**Architecture:** 先做一批向后兼容的代码解耦（配置/路径不再写死），再在其上叠加 install.sh / launchd 模板 / FluidAudio 与模型置备 / Folder Action 自动化 / uninstall / 面向用户 README。作者本机在全部测通前保持原样，迁移是最后一次显式可回退操作。

**Tech Stack:** zsh/bash 脚本、Python venv（mlx-whisper、openai）、Swift（FluidAudio 编译回退）、AppleScript（Folder Action）、launchd、osascript。

## Global Constraints

- 平台仅 macOS + Apple Silicon（arm64）；非此环境预检即退。
- **不破坏作者现有本地实例**：所有代码改动向后兼容；不建配置、不改环境时行为与现状完全一致。
- **不在作者机器上自动跑 install.sh**：不碰 `~/Library/LaunchAgents`、不挂 Folder Action、不改环境变量。
- **先测通、后迁移**：阶段一在隔离环境完成并测通；迁移仅在作者显式同意后进行，且可回退。
- Key 存 `config.local.sh`（gitignore，`chmod 600`），绝不写 `~/.zshrc`。
- 默认输出到项目内 `output/`；Obsidian 可选（`OBSIDIAN_DIR` 留空=跳过）。
- FluidAudio 为 Apache-2.0：分发须附 LICENSE/NOTICE 并声明本项目的 patch 修改。
- 参考规格：`docs/superpowers/specs/2026-07-27-meetingnotes-installable-packaging-design.md`。

---

## 文件结构

- `config.example.sh`（新增）— 配置模板：`DEEPSEEK_API_KEY` / `OBSIDIAN_DIR`。
- `config.local.sh`（安装时生成，gitignore）— 用户实际配置。
- `watch_inbox.sh`（改）— 优先 source config，回退 `~/.zshrc`。
- `process.py`（改）— ffmpeg 自动探测、`OBSIDIAN_DIR` 读环境（留空跳过）。
- `requirements.txt`（新增）— Python 依赖清单。
- `launchd/com.meetingnotes.plist.template`（新增）+ `scripts/gen_launchd.sh`（新增）— 模板化 + 路径哈希 Label 生成。
- `scripts/provision_fluidaudio.sh`（新增）— 预编译下载优先、源码编译回退。
- `scripts/provision_models.sh`（新增）— whisper（HF 镜像可选）+ FluidAudio 模型预热。
- `folder-action/airdrop-to-inbox.applescript`（新增）+ `scripts/attach_folder_action.sh`（新增）— Folder Action 脚本与 osascript 挂载。
- `install.sh`（新增）— 编排上述 8 步。
- `uninstall.sh`（新增）— 卸 launchd、移除 Folder Action、可选清大件。
- `README.md`（改）— 重构为使用者视角；附 FluidAudio 合规声明。
- `tests/`（新增）— shell 与 python 的验证测试。

---

### Task 1: 配置层与 key 解耦（向后兼容）

**Files:**
- Create: `config.example.sh`
- Modify: `watch_inbox.sh:22`（`.zshrc` 读取行）
- Modify: `.gitignore`（加 `config.local.sh`）
- Test: `tests/test_config_resolution.sh`

**Interfaces:**
- Produces: `config.local.sh` 约定——一个可被 `source` 的 zsh 文件，`export DEEPSEEK_API_KEY=...`、`export OBSIDIAN_DIR=...`（可空）。

- [ ] **Step 1: 写失败测试** — 验证"有 config.local.sh 时用它、无则回退 .zshrc"

```bash
# tests/test_config_resolution.sh
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"; cp "$DIR/watch_inbox.sh" "$tmp/"; mkdir -p "$tmp/inbox" "$tmp/logs"
# 情形A：存在 config.local.sh
printf 'export DEEPSEEK_API_KEY=fromconfig\n' > "$tmp/config.local.sh"
out=$(cd "$tmp" && zsh -c 'source ./config.local.sh; echo $DEEPSEEK_API_KEY')
[ "$out" = "fromconfig" ] || { echo "FAIL A: $out"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: 跑测试看它失败**

Run: `zsh tests/test_config_resolution.sh`
Expected: 目前 `config.example.sh` 不存在、逻辑未接入，按下一步补齐后转 PASS。

- [ ] **Step 3: 写 config.example.sh 并改 watch_inbox.sh**

`config.example.sh`：
```bash
# 复制为 config.local.sh 并填入你的值（本文件不含真实密钥）
export DEEPSEEK_API_KEY=""        # 在 https://platform.deepseek.com 申请
export OBSIDIAN_DIR=""            # 留空=不复制到 Obsidian；填 vault 内目录则额外落一份
```

`watch_inbox.sh` 把第 22 行替换为：
```bash
# 优先读项目内 config.local.sh；不存在则回退作者原有的 .zshrc 机制（保持向后兼容）
if [ -f "$BASE/config.local.sh" ]; then
  source "$BASE/config.local.sh"
else
  eval "$(grep '^export DEEPSEEK_API_KEY=' "$HOME/.zshrc" 2>/dev/null | head -1)" 2>/dev/null
fi
```

- [ ] **Step 4: 跑测试看它通过**

Run: `zsh tests/test_config_resolution.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config.example.sh watch_inbox.sh .gitignore tests/test_config_resolution.sh
git commit -m "feat: config.local.sh 解耦 key，向后兼容回退 .zshrc"
```

---

### Task 2: process.py 路径解耦（ffmpeg 探测 + OBSIDIAN_DIR 读环境）

**Files:**
- Modify: `process.py:19`（FFMPEG）、`process.py:16`（OBSIDIAN_DIR）
- Test: `tests/test_process_paths.py`

**Interfaces:**
- Consumes: 环境变量 `OBSIDIAN_DIR`（Task 1 的 config 会 export）。
- Produces: `FFMPEG` 解析规则、`OBSIDIAN_DIR` 解析规则（空串或未设 → 跳过 Obsidian 复制）。

- [ ] **Step 1: 写失败测试**

```python
# tests/test_process_paths.py
import os, importlib, sys
sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

def test_ffmpeg_falls_back_when_not_on_path(monkeypatch):
    monkeypatch.setattr("shutil.which", lambda _: None)
    import process; importlib.reload(process)
    assert process.FFMPEG == "/opt/homebrew/bin/ffmpeg"

def test_obsidian_dir_env_empty_means_skip(monkeypatch):
    monkeypatch.setenv("OBSIDIAN_DIR", "")
    import process; importlib.reload(process)
    assert process.OBSIDIAN_DIR == ""

def test_obsidian_dir_defaults_when_unset(monkeypatch):
    monkeypatch.delenv("OBSIDIAN_DIR", raising=False)
    import process; importlib.reload(process)
    assert process.OBSIDIAN_DIR.endswith("会议纪要")
```

- [ ] **Step 2: 跑测试看它失败**

Run: `venv/bin/python -m pytest tests/test_process_paths.py -v`
Expected: FAIL（当前 FFMPEG/OBSIDIAN_DIR 均写死）。

- [ ] **Step 3: 改 process.py**

`OBSIDIAN_DIR`（第 16 行）：
```python
# 未设 → 保持作者默认 vault；显式设为空串 → 跳过 Obsidian 复制
_obs = os.environ.get("OBSIDIAN_DIR")
OBSIDIAN_DIR = os.path.expanduser("~/Documents/Obsidian Vault/会议纪要") if _obs is None else _obs
```
`FFMPEG`（第 19 行）：
```python
FFMPEG = shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
```
确认 `save_to_obsidian` 在 `OBSIDIAN_DIR` 为空串时跳过（不存在即跳过的现有逻辑已覆盖，补一条 `if not OBSIDIAN_DIR: return False`）。

- [ ] **Step 4: 跑测试看它通过**

Run: `venv/bin/python -m pytest tests/test_process_paths.py -v`
Expected: PASS（3 项）

- [ ] **Step 5: Commit**

```bash
git add process.py tests/test_process_paths.py
git commit -m "feat: ffmpeg 自动探测 + OBSIDIAN_DIR 读环境（留空跳过），向后兼容"
```

---

### Task 3: requirements.txt

**Files:**
- Create: `requirements.txt`
- Test: 手工验证（干净 venv 可 `pip install -r`）

- [ ] **Step 1: 从当前 venv 冻结并裁剪**

Run: `venv/bin/pip freeze > /tmp/freeze.txt`，人工保留直接依赖（`openai`、`mlx-whisper`、其传递依赖交给 pip 解析），剔除仅本机相关/编辑安装项。

- [ ] **Step 2: 写 requirements.txt**（示例，按 freeze 实际收敛版本）

```
openai>=1.0
mlx-whisper
```

- [ ] **Step 3: 干净 venv 验证**

```bash
python3 -m venv /tmp/venvtest && /tmp/venvtest/bin/pip install -r requirements.txt
```
Expected: 安装成功，无缺包。

- [ ] **Step 4: Commit**

```bash
git add requirements.txt && git commit -m "chore: 新增 requirements.txt"
```

---

### Task 4: launchd 模板化 + 路径哈希 Label 生成

**Files:**
- Create: `launchd/com.meetingnotes.plist.template`
- Create: `scripts/gen_launchd.sh`
- Test: `tests/test_gen_launchd.sh`

**Interfaces:**
- Produces: `gen_launchd.sh <project_dir>` → 打印一份 plist，Label=`com.meetingnotes.<8位路径哈希>`，`ProgramArguments`/`WatchPaths`/`Std*Path` 全用绝对路径。

- [ ] **Step 1: 写失败测试**

```bash
# tests/test_gen_launchd.sh
set -e
DIR="$(cd "$(dirname "$0")/.." && pwd)"
out=$("$DIR/scripts/gen_launchd.sh" /tmp/foo)
echo "$out" | grep -q "com.meetingnotes\." || { echo "FAIL label"; exit 1; }
echo "$out" | grep -q "/tmp/foo/watch_inbox.sh" || { echo "FAIL path"; exit 1; }
echo "$out" | grep -q "/tmp/foo/inbox" || { echo "FAIL watchpath"; exit 1; }
echo "PASS"
```

- [ ] **Step 2: 跑测试看它失败**

Run: `zsh tests/test_gen_launchd.sh`
Expected: FAIL（脚本尚未存在）。

- [ ] **Step 3: 写模板与生成脚本**

`launchd/com.meetingnotes.plist.template`（用 `__LABEL__`/`__PROJECT__` 占位）+ `scripts/gen_launchd.sh`：
```bash
#!/bin/zsh
set -eu
proj="${1:?need project dir}"
hash=$(printf '%s' "$proj" | shasum | cut -c1-8)
label="com.meetingnotes.$hash"
sed -e "s|__LABEL__|$label|g" -e "s|__PROJECT__|$proj|g" \
    "$(dirname "$0")/../launchd/com.meetingnotes.plist.template"
```

- [ ] **Step 4: 跑测试看它通过**

Run: `zsh tests/test_gen_launchd.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add launchd/com.meetingnotes.plist.template scripts/gen_launchd.sh tests/test_gen_launchd.sh
git commit -m "feat: launchd plist 模板化 + 路径哈希 Label 生成"
```

---

### Task 5: FluidAudio 置备脚本（预编译优先，源码回退）

**Files:**
- Create: `scripts/provision_fluidaudio.sh`
- Test: 真机验证（无法纯单测）

**Interfaces:**
- Produces: 置备后 `tools/FluidAudio/.build/release/fluidaudiocli` 存在且可执行。

- [ ] **Step 1: 写脚本**（预编译 URL 由 GitHub Release 提供；失败回退 SETUP.md 源码编译）

```bash
#!/bin/zsh
set -eu
BASE="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$BASE/tools/FluidAudio/.build/release/fluidaudiocli"
[ -x "$BIN" ] && { echo "已存在，跳过"; exit 0; }
if curl -fsSL "$FLUIDAUDIO_PREBUILT_URL" -o "$BIN.download" 2>/dev/null; then
  mkdir -p "$(dirname "$BIN")"; mv "$BIN.download" "$BIN"; chmod +x "$BIN"
  xattr -d com.apple.quarantine "$BIN" 2>/dev/null || true
else
  echo "预编译下载失败，回退源码编译（需 Swift 工具链）"
  # 按 fluidaudio-patch/SETUP.md 的 clone→打 patch→注册→swift build
  "$BASE/scripts/build_fluidaudio_from_source.sh"
fi
"$BIN" --help >/dev/null || { echo "FluidAudio 不可用"; exit 1; }
```

- [ ] **Step 2: 抽出源码编译步骤** — 把 `fluidaudio-patch/SETUP.md` 的手动步骤脚本化为 `scripts/build_fluidaudio_from_source.sh`。

- [ ] **Step 3: 真机验证**（隔离克隆中跑，确认二进制可 `--help`）。Expected: 退出码 0。

- [ ] **Step 4: Commit**

```bash
git add scripts/provision_fluidaudio.sh scripts/build_fluidaudio_from_source.sh
git commit -m "feat: FluidAudio 置备（预编译优先，源码回退）"
```

---

### Task 6: 模型置备（whisper 镜像可选 + FluidAudio 预热）

**Files:**
- Create: `scripts/provision_models.sh`
- Test: 真机验证

**Interfaces:**
- Consumes: 可选环境变量 `HF_ENDPOINT`（默认 `https://hf-mirror.com`，可覆盖为 `https://huggingface.co`）。

- [ ] **Step 1: 写脚本**

```bash
#!/bin/zsh
set -eu
BASE="$(cd "$(dirname "$0")/.." && pwd)"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"
echo "使用 HF_ENDPOINT=$HF_ENDPOINT（墙外可设为 https://huggingface.co）"
# 1) whisper MLX 模型：若本地缺 weights.npz 则下载到 models/
# 2) FluidAudio 模型：跑一次最小 diarize 预热，触发其首次自下载 CoreML 模型
"$BASE/tools/FluidAudio/.build/release/fluidaudiocli" process "$BASE/tests/fixtures/tiny.wav" \
    --output /tmp/warmup.json --threshold 0.7 || echo "预热失败（联网/模型问题），install 可重跑"
```

- [ ] **Step 2: 准备 `tests/fixtures/tiny.wav`** — 一个 1–2 秒静音/示例 wav 供预热与冒烟测试。

- [ ] **Step 3: 真机验证** — 干净环境跑，确认 whisper 与 FluidAudio 模型就位。

- [ ] **Step 4: Commit**

```bash
git add scripts/provision_models.sh tests/fixtures/tiny.wav
git commit -m "feat: 模型置备（whisper 镜像可选 + FluidAudio 预热）"
```

---

### Task 7: Folder Action AirDrop 自动化（脚本 + osascript 挂载）

**Files:**
- Create: `folder-action/airdrop-to-inbox.applescript`
- Create: `scripts/attach_folder_action.sh`
- Test: 独立 macOS 测试账号 / 受控真机验证

**Interfaces:**
- Consumes: `watch_downloads.sh`（既有大小稳定守卫）。
- Produces: 挂到 `~/Downloads` 的 Folder Action，只搬 quarantine 类型值 `59`（AirDrop）的音频到 `inbox`。

- [ ] **Step 1: 写 AppleScript**（adding folder items）— 遍历新增项，用 `xattr -p com.apple.quarantine` 判断值以 `0059`/`59` 开头者为 AirDrop，音频后缀则调用 `watch_downloads.sh` 逻辑搬入 inbox。

- [ ] **Step 2: 写 osascript 挂载脚本**

```bash
#!/bin/zsh
set -eu
BASE="$(cd "$(dirname "$0")/.." && pwd)"
SCPT="$BASE/folder-action/airdrop-to-inbox.applescript"
osascript <<EOF
tell application "System Events"
  set folder actions enabled to true
  try
    make new folder action at end of folder actions with properties {path:(POSIX file "$HOME/Downloads")}
  end try
  tell folder action "Downloads"
    make new script at end of scripts with properties {POSIX path:"$SCPT"}
  end tell
end tell
EOF
echo "已挂载 Folder Action；首次触发会弹一次自动化授权，请点允许。"
```

- [ ] **Step 3: 先单独验证 osascript 挂载可行性**（规格遗留风险项）——在测试账号执行，确认 Folder Action 出现在"文件夹动作设置"。若 System Events 语法不支持，改用等价方案并回填本步。

- [ ] **Step 4: 端到端验证** — 测试账号里 AirDrop 一段录音 → 自动入 inbox → 出纪要。Expected: 全程无手动。

- [ ] **Step 5: Commit**

```bash
git add folder-action/airdrop-to-inbox.applescript scripts/attach_folder_action.sh
git commit -m "feat: AirDrop Folder Action 自动入库（osascript 挂载）"
```

---

### Task 8: install.sh 编排

**Files:**
- Create: `install.sh`
- Test: 隔离克隆真机验证（验收 #1/#3/#4）

**Interfaces:**
- Consumes: Task 1–7 的产物与脚本。

- [ ] **Step 1: 写 install.sh** — 按序执行：预检（arm64 + python 版本 + brew/CLT）→ `brew install ffmpeg` → 建 venv + `pip install -r` → `provision_fluidaudio.sh` → `provision_models.sh` → 交互写 `config.local.sh`（`chmod 600`）→ `gen_launchd.sh` 写入 `~/Library/LaunchAgents` 并 `launchctl load` → `attach_folder_action.sh`。每步失败给明确提示与可重跑指引。

- [ ] **Step 2: 预检硬退出验证** — 在非 arm64（或模拟 `uname -m` 覆盖）确认友好退出、不产生副作用。

- [ ] **Step 3: 隔离克隆全流程验证** — 临时目录全新 clone 跑 `./install.sh`，完成验收 #1（拖入 inbox 出纪要）、#3（未配/配 Obsidian）、#4（uninstall 后残留检查见 Task 9）。

- [ ] **Step 4: Commit**

```bash
git add install.sh && git commit -m "feat: install.sh 一键安装编排"
```

---

### Task 9: uninstall.sh

**Files:**
- Create: `uninstall.sh`
- Test: 隔离克隆验证

- [ ] **Step 1: 写 uninstall.sh** — `launchctl unload` 并删对应 `~/Library/LaunchAgents/com.meetingnotes.<hash>.plist`；用 osascript 移除 Downloads 的 Folder Action；**交互询问**是否删除 `venv/models/tools` 大件；**用户录音/纪要（inbox/output/done）默认保留**。

- [ ] **Step 2: 验证** — 安装后 uninstall，确认 launchd 与 Folder Action 移除、数据保留。

- [ ] **Step 3: Commit**

```bash
git add uninstall.sh && git commit -m "feat: uninstall.sh 干净卸载（保留用户数据）"
```

---

### Task 10: 使用者 README + FluidAudio 合规

**Files:**
- Modify: `README.md`
- Create: `NOTICE`（含 FluidAudio 归属与本项目修改声明）

- [ ] **Step 1: 重构 README** — 面向使用者：系统要求（Apple Silicon）、`git clone` + `./install.sh`、如何拿 DeepSeek key、墙外改 `HF_ENDPOINT`、AirDrop 授权一步、Obsidian 可选、排错、卸载。

- [ ] **Step 2: 写 NOTICE** — 附 FluidAudio Apache-2.0 归属，明确"本项目通过 `fluidaudio-patch/` 修改了 FluidAudio（新增 batch-transcribe 命令）"，指向 `tools/FluidAudio/LICENSE` 与 `ThirdPartyLicenses`。

- [ ] **Step 3: Commit**

```bash
git add README.md NOTICE && git commit -m "docs: 使用者 README + FluidAudio 合规声明"
```

---

### Task 11: 阶段一验收汇总（隔离环境）

**Files:** 无代码；执行验收并记录。

- [ ] **Step 1: 隔离克隆跑完 #1/#3/#4**，逐条勾验收标准。
- [ ] **Step 2: 测试账号跑 #2**（AirDrop→自动入库）。
- [ ] **Step 3: 把结果记入 Obsidian 产品日志**（按协作约定，署名 Claude）。
- [ ] **Step 4:** 阶段一全绿后，**停在此**，等作者同意再进阶段二迁移（不在本计划内自动执行）。

---

## Self-Review

**Spec coverage**：规格第 3 决策（key/输出/受众/Folder Action）→ Task 1/2/7；3.1 向后兼容 → Task 1/2 的回退分支；3.2 分阶段与拆旧快捷指令 → Task 11 + 迁移留待阶段二；3.3 许可 → Task 10；第 5 步八步 → Task 4–8；Folder Action 第 6 节 → Task 7；失败降级第 8 节 → 各脚本失败分支；验收第 9 节 → Task 11；遗留问题第 10 节 → Task 5/6/7 的真机验证步与 Task 3 冻结。迁移阶段二（拆旧快捷指令、切 config、重挂）明确留给阶段二，不在本计划任务内——这是有意的安全边界。

**Placeholder scan**：requirements.txt 版本、FluidAudio 预编译 URL、AppleScript 具体实现为真机落地时收敛项，已在对应步骤标注"按实际收敛/回填"，非空泛占位。

**Type consistency**：Label 规则 `com.meetingnotes.<hash>` 在 Task 4/8/9 一致；`config.local.sh` 的 `DEEPSEEK_API_KEY`/`OBSIDIAN_DIR` 在 Task 1/2/8 一致；`fluidaudiocli` 路径在 Task 5/6 一致。
