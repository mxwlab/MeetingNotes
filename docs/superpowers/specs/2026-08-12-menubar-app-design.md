# MeetingNotes 菜单栏 App（项目 B · v1）设计

日期：2026-08-12
分支：`feat/menubar-app`（在 git worktree 中开发，避免影响现用工作树）
状态：设计已确认，进入实现计划

## 背景与目标

**北极星**：给这个后台工具一个持久的"控制面板"，把此前散落在弹框/shell 文件/一只小猫里的
配置与状态收进一处。

直接动因：让非 DeepSeek 的 OpenAI 兼容服务也能图形化配置（原 #3），并解决其连带痛点——
配置靠手改 `config.local.sh`、状态只能看小猫、"跳过并保存"后重设没有入口。讨论中放弃了
"先弹框(A)再 GUI(B)"，直接做 B；但加了一条**硬约束**。

### 硬约束：绝不影响"现在这版"的使用

关键事实：用户机器上"正在跑的这版"就运行在本工作目录——launchd 服务直接执行
`/Users/moxiuwen/workspace/MeetingNotes/watch_inbox.sh`，用本目录的 `venv`、`process.py`、
`config.local.sh`。因此隔离是硬要求：

- 现有 `watch_inbox.sh` / `watch_downloads.sh` / `process.py` 行为**一律不改**。
- 现有 `venv/`（流水线在用）**不动**；菜单栏 app 用**独立 `venv-ui/`**。
- **不新增 launchd 自启项**；v1 手动启动。
- 小猫 `pet.py` 不动，app 仅**只读** `.pet_state`，两者并存。
- 开发调试在 **git worktree** 中进行，用户工作树不受影响。
- `config.local.sh` 仅在用户**主动点保存**时才写，且保留其它键、保持 600 权限。

### 非目标（v2 再议）

历史纪要列表、术语/人名编辑、替代小猫、launchd 自启与装机集成、Windows。

## 方案：独立 rumps 菜单栏程序

技术选型 **Python `rumps`**（基于 pyobjc）。理由：能 pip 装进现有生态、**不需要 Xcode/签名/公证**，
与现有 Python 代码同栈；相较 SwiftUI 独立 app 成本最低、与"零依赖 zip 分发"冲突最小。

一个常驻菜单栏项，v1 做四件事：

### 1. 状态显示
- 菜单栏**标题即状态**，读 `.pet_state`（三行：状态 / 录音名 / 进度）。
- 映射：`transcribe`→`🎙️ {pct}%`；`summarize`→`📝 生成中`；`done` 或无有效状态→`🐱 空闲`。
- `rumps.Timer` 每 ~2 秒刷新。纯函数 `title_from_pet_state(text) -> str` 便于单测。
- **优先级**：一旦处于失败警示态（见 §4），标题固定为 `⚠️ 处理失败`，压过 `.pet_state` 派生的标题；
  警示清除后恢复由 `.pet_state` 决定的标题。

### 2. 服务设置
菜单两条目天然分流，无需三按钮弹框：
- **使用 DeepSeek…**：弹窗填 Key → 验证（`GET api.deepseek.com/models`）→ 保存。
- **使用其他兼容服务…**：依次弹窗 Base URL → 模型名 → API Key（隐藏）→ 验证
  （用 openai client 向 `{base_url}` 发一条 `max_tokens=1` 的最小 `chat/completions`）→ 保存。
- 两条都用 `rumps.Window` 收集输入；验证失败弹 **[重试] / [跳过并保存]**（跳过=不验证直接写盘，
  用于"配置其实对、只是网关古怪或网络抽风"）。
- 同一入口既是首次设置也是重设：再点一次即覆盖，这就是"跳过并保存"后的重设路径。
- 保存写 `config.local.sh`：更新受管键 `DEEPSEEK_API_KEY`（自定义分支 Key 仍存此名，`process.py` 零改）、
  `LLM_BASE_URL`、`LLM_MODEL`；**保留** `OBSIDIAN_DIR` 及其它行/注释；权限 600；值用 `shlex.quote` 转义。
- 保存后通知："服务已更新，下一条录音生效。"

### 3. 快捷入口
菜单项：打开「录音」文件夹、打开「纪要」文件夹、查看处理日志（`open` 对应路径 / `watch.log`）。

### 4. 失败感知与即时提醒（让"跳过并保存"安全闭环）
现状缺口：`process.py` 仅在成功和"格式不支持"时弹通知；遇到 LLM 报错/转录崩等**真失败会
直接抛异常、不弹任何通知**，文件默默留在 inbox。故本节不只是引导，也补上"失败静默"的窟窿。

- Timer 每 ~2 秒只读 `watch.log`，纯函数
  `latest_outcome(logtext) -> (result, name, marker)`：按时间顺序看最后的
  `开始处理/✅ 完成/❌ 失败` 事件序列；`result∈{ok,fail,none}`，`marker` 为该失败事件的
  唯一标识（时间戳+名字），用于去重。
- **即时提醒**：一旦检测到**新的**失败（marker 与上次已提醒的不同），立刻——
  - 弹 **macOS 通知**「⚠️ 处理失败：{name}。可能是服务配置有误，点此检查设置。」——
    用与 `process.py` 一致的 terminal-notifier→osascript 兜底机制（后台可靠弹出，不用 rumps 内建通知）。
  - 菜单栏**标题翻成警示态** `⚠️ 处理失败`（不开菜单也看得见）。
  - 记住该 marker，避免每 2 秒重复提醒。
- **菜单内**同时常驻醒目项 **「⚠️ 上次处理失败 · 点此检查服务设置」**（点击进设置；旁边"查看日志"）。
- 用户重设成功、或后续有一次成功处理 → 警示态、菜单项、去重 marker 全部复位清除。
- 全程不改 `process.py`——失败情报由 app 从日志观察得来，隔离不破。

## 组件（全部新增，现有文件不改）

| 文件 | 职责 |
|---|---|
| `ui/menubar.py` | rumps App：标题状态、菜单装配、Timer 轮询、失败警示项、快捷入口 |
| `ui/provider_config.py` | 服务设置：弹窗取值、验证（openai client）、读改写 `config.local.sh`、跳过逻辑 |
| `ui/pet_status.py` | 纯函数：`title_from_pet_state`、`latest_outcome`（便于单测，不依赖 GUI） |
| `venv-ui/` | 独立 venv：`rumps`、`pyobjc`、`openai`（gitignore） |
| `MeetingNotes 设置.command` | 一键双击启动器（用 `venv-ui` 跑 `ui/menubar.py`）；也是 app 未运行时的重设入口 |
| `.gitignore` | 追加 `venv-ui/` |

## 错误处理
- 验证网络异常 / 非 200 → 视为验证失败 → [重试]/[跳过并保存]，附 HTTP 码或错误摘要。
- 任一弹窗点取消 → 中止本次设置，**不写配置**。
- `.pet_state` 缺失/格式坏 → 显示 `🐱 空闲`。
- `watch.log` 缺失/无法读 → 不显示失败警示（静默降级）。
- 写 `config.local.sh` 失败（权限等）→ 通知报错，不破坏原文件（先写临时文件再原子替换）。

## 测试策略
- `ui/pet_status.py`：`title_from_pet_state` 覆盖各状态串；`latest_outcome` 覆盖
  成功/失败/无记录/失败后又成功等日志序列，并断言失败事件的 `marker` 稳定（同一失败不变、
  新失败改变）以支撑去重。纯函数，unittest。
- 失败提醒去重与优先级：给定"失败→再失败→成功"的日志推进，断言只对每个新 marker 提醒一次、
  且成功后警示态清除、标题恢复。
- `ui/provider_config.py`：
  - 读改写 `config.local.sh`：断言 `LLM_BASE_URL/LLM_MODEL/DEEPSEEK_API_KEY` 写入正确、
    `OBSIDIAN_DIR` 与注释保留、权限 600、值正确转义。
  - 验证逻辑：mock openai client / HTTP，覆盖成功、401、网络异常。
  - 跳过路径：不调用验证也能写盘。
- rumps App 本体（GUI/菜单栏渲染）手动验证：独立 venv 启动、四类状态标题、设置流程走通、
  失败警示出现与消失。
- 现有测试套件全绿（确认未触碰现有流程）。

## 实现顺序（详见后续 plan）
1. 建 worktree + `venv-ui`，验证 `rumps` 能在独立 venv 装好并弹出菜单栏项（最高不确定性，先证。）
2. `ui/pet_status.py` + 单测（纯函数，零依赖）。
3. `ui/provider_config.py` + 单测（含读改写 config、验证、跳过）。
4. `ui/menubar.py` 装配四件：状态、快捷入口、服务设置、失败警示。
5. `MeetingNotes 设置.command` 启动器；`.gitignore` 追加。
6. 手动端到端验证；确认现有流水线不受影响。
