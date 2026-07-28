# MeetingNotes 可安装打包（方案 A）设计规格

- 日期：2026-07-27
- 状态：待用户审阅
- 作者：Claude（与用户 brainstorming 得出）

## 1. 目标

把当前深度绑定本机的 MeetingNotes 脚本集，整理成一个技术朋友能 `git clone` 后跑一条 `./install.sh` 就装好、开箱自动出纪要的项目。这是"下载即用产品"的第一台阶（方案 B 的原生 `.app` / 签名公证不在本规格内）。

## 2. 目标用户与非目标

**目标用户**：3–5 位技术朋友（会用终端、能装 Homebrew）；也是既定的内测人群。

**非目标（YAGNI，明确不做）**：
- 不做 `.app` 双击安装、不做代码签名/公证（方案 B）。
- 不支持 Intel Mac / Windows / Linux（依赖 Apple Silicon 神经引擎）。
- 不替用户托管 DeepSeek key，不内置本地 LLM。
- 不为非技术小白做额外容错引导（待内测反馈后再评估）。

## 3. 已确认的关键决策

| 决策点 | 选择 | 理由 |
|---|---|---|
| DeepSeek API Key | 用户自带，install 时输入，写入本地配置文件 | 不替朋友付费/担责；技术用户注册 key 无压力 |
| 输出位置 | 默认写普通文件夹 `output/`；Obsidian 变可选 | 去掉"必须是 Obsidian 用户"门槛，扩大内测人群 |
| 安装受众 | 先面向 3–5 技术朋友 | 最小成本送达既定内测人群 |
| AirDrop 自动入库 | 用内置 **Folder Action** 替代快捷指令 | 可脚本化挂载、精准识别 AirDrop 文件、绕开 launchd 的 Downloads TCC 限制 |

## 3.1 硬约束：不破坏用户现有本地实例

打包工作绝不能搞坏用户当前能正常运行的本地 MeetingNotes 实例。据此：

- **代码改动全部向后兼容**：
  - `watch_inbox.sh`：有 `config.local.sh` 则 source 之，否则退回读 `~/.zshrc`（用户现机制不变）。
  - `process.py` 的 `OBSIDIAN_DIR`：配置里设了用配置，未设则保持现有默认 vault 路径。
  - ffmpeg：自动探测，探测不到退回现有写死路径。
  - 净效果：用户不新建任何配置、不改任何东西，现有流水线照常运行。
- **绝不在用户机器上自动执行 install.sh**：不生成/替换其 launchd plist、不碰 `~/Library/LaunchAgents`、不挂 Folder Action、不动其环境变量。这些只在他人全新安装时发生。
- **测试隔离**：验证 install.sh / Folder Action 用全新克隆到临时目录的方式，或先征得用户同意；绝不拿用户实时 Downloads→inbox 流程做实验。

## 3.2 分阶段推进：先测通，后迁移

- **阶段一（开发 + 测试）**：在隔离环境（临时目录全新克隆）完成打包版并按第 9 节验收标准全部测通。此阶段用户现有本地实例原封不动、继续照常使用。
- **阶段二（迁移）**：仅在阶段一全部通过、且用户明确同意后，才把用户本机切换到新流程（改用 `config.local.sh`、重生成 launchd、挂 Folder Action 等）。此迁移为一次显式、可回退操作，绝不自动发生、绝不在测通前进行。
  - **迁移必须先拆旧快捷指令**：用户本机现用"快捷指令搬 Downloads→inbox"。切到 Folder Action 前必须先停用/删除旧快捷指令，否则两套都触发、同一录音被重复处理。迁移步骤把"移除旧快捷指令"列为第一步。

### 测试方法学：Folder Action 无法在纯临时目录测

验收标准 #2（AirDrop→自动入库）天然需要真机 + 真 `~/Downloads` + 真授权弹窗，无法在"临时目录全新克隆、不碰实时 Downloads"的隔离环境里测掉。据此拆分测试环境：

- **inbox→出纪要（#1/#3/#4）**：在临时目录全新克隆里测，不碰用户实时环境。
- **AirDrop→自动入库（#2）**：在**独立的 macOS 测试用户账号**里做，或作为需用户在场、可回退的受控真机测试；绝不在测通前接管用户主账号的实时 Downloads→inbox 流程。

## 3.3 FluidAudio 再分发合规

FluidAudio 为 **Apache-2.0** 许可（permissive，允许再分发二进制与源码）。本项目在 `fluidaudio-patch/` 对其做了修改（新增并注册 `BatchTranscribeCommand.swift`）。据此，公开分发（含把预编译 `fluidaudiocli` 挂到 GitHub Release）**合法可行**，但需满足 Apache-2.0 条款：

- 随分发附带 FluidAudio 的 `LICENSE` 与 `NOTICE`（本地已有 `tools/FluidAudio/LICENSE` 与 `ThirdPartyLicenses`）。
- 在显著位置**声明本项目对 FluidAudio 做了修改**（Apache-2.0 §4b）。
- 保留原始版权与归属声明。
- FluidAudio 内含的 CoreML 模型多为 MIT/Apache-2.0，随模型附带其各自许可即可。

结论：② 不再是发布阻塞项，转为"发布前需备齐 LICENSE/NOTICE + 修改声明"的合规待办。

## 4. 现状盘点（打包要处理的写死项）

仓库仅跟踪 12 个文件；大件走 `.gitignore` 在安装时重建：`venv/`、`models/`（whisper ~3GB）、`tools/FluidAudio`（Swift 编译产物）。

需要从"写死本机"改为"安装时生成/探测"的点：
- `launchd/com.moxiuwen.meetingnotes.plist`：绝对路径 `/Users/moxiuwen/...` 与固定 Label。
- `process.py`：`FFMPEG = /opt/homebrew/bin/ffmpeg`（写死）、`OBSIDIAN_DIR`（写死单一 vault）。
- `watch_inbox.sh`：从 `~/.zshrc` 读 `DEEPSEEK_API_KEY`。
- AirDrop 入库依赖用户手动搭的快捷指令（不可脚本安装）。

## 5. 架构：install.sh 的职责（8 步）

1. **环境预检**：确认 macOS + Apple Silicon（`uname -m` == arm64）；校验 `python3` 版本满足 mlx-whisper 要求；检查/引导安装 Homebrew、Xcode 命令行工具（FluidAudio 源码编译回退还需 Swift 工具链，走预编译二进制路径则不需要）。非 Apple Silicon 友好报错并退出，不半途失败。
2. **系统依赖**：`brew install ffmpeg`；`process.py` 改为自动探测 ffmpeg 路径（`command -v ffmpeg`）。
3. **Python 环境**：建 `venv/`，`pip install -r requirements.txt`（新增依赖清单：openai、mlx-whisper 等，从当前 venv 冻结得出）。
4. **声纹分离组件（FluidAudio）**：优先从 GitHub Release 下载预编译二进制，`xattr -d com.apple.quarantine` 清隔离属性；失败则回退按 `fluidaudio-patch/SETUP.md` 源码编译（源码编译需 Swift 工具链，见预检）。分发合规见 3.3。
5. **下模型（两套来源，分别处理）**：
   - **whisper（MLX）**：`process.py` 顶部写死了 `HF_ENDPOINT=https://hf-mirror.com`（国内镜像）。墙外用户镜像可能更慢/失效，墙内用户又需要它——install.sh 让镜像**可选/可探测**（提供 `HF_ENDPOINT` 覆盖入口），README 明确说明如何按地区切换。这是最易卡住安装的一步。
   - **FluidAudio 的 CoreML 模型（Paraformer/声纹）**：由 FluidAudio 首次运行自行下载，install 阶段跑一次预热触发下载并校验成功。
6. **配 key**：交互式提示输入 DeepSeek key，写入项目根 `config.local.sh`（gitignore）。提供 `config.example.sh` 模板。彻底不碰 `~/.zshrc`。
7. **输出位置**：默认 `output/`。`config.local.sh` 含 `OBSIDIAN_DIR=`（留空=跳过）。`process.py` 的 `OBSIDIAN_DIR` 改为读配置。
8. **后台自启 + AirDrop 自动化**：
   - 用模板 + 当前路径生成 launchd plist，Label 按项目路径加哈希（避免多副本撞名，沿用 ai-continuity 思路），装入 `~/Library/LaunchAgents` 并 load。
   - 挂载 Folder Action（见第 6 节）。
   - 配套 `uninstall.sh` 干净卸载（卸 launchd、移除 Folder Action、保留用户数据）。

## 6. AirDrop 自动入库：Folder Action 设计

**问题背景**：AirDrop 文件固定落到 `~/Downloads`（系统不可配）。后台 launchd 受 TCC 限制读不到 `~/Downloads`（给 LaunchAgent 授 Full Disk Access 不可靠，macOS 11.4 起已坏、设置里灰置）。

**方案**：用 macOS 内置 Folder Action（AppleScript），它跑在用户登录会话里、天然有 Downloads 访问权。

- **精准识别 AirDrop 文件**：读扩展属性 `com.apple.quarantine`，类型值 `59` 即 AirDrop 来源（浏览器/邮件值不同），只搬 AirDrop 的音频，不误搬其他下载。参考实现：menushka 的 gist。
- **搬运逻辑复用现有守卫**：Folder Action 触发后把匹配音频交给 `watch_downloads.sh` 的既有逻辑（非空 + 大小连续三次不变才搬），正好对上官方"处理前等文件写完"的建议，避免竞态。
- **脚本化挂载**：install.sh 用 `osascript`（System Events 的 Folder Actions 套件）自动挂载到 Downloads 并启用 Folder Actions，用户仅需一次性在弹窗点"允许自动化"授权。
- **降级**：Folder Action 挂载失败或用户拒绝授权时，回退到"手动拖入 inbox"，并在 README 附快捷指令导入作为备选。

**待落地时验证的风险**：`osascript` 挂载 Folder Action 的可行性有把握但未在目标机实测；实现阶段先单独验证一遍再写进 install.sh。Folder Actions 在极繁忙文件夹可能漏触发——对偶发录音场景可接受。

## 7. 新增与改动文件

**新增**：
- `install.sh` — 主安装脚本（上述 8 步）。
- `uninstall.sh` — 卸载。
- `requirements.txt` — Python 依赖清单。
- `config.example.sh` — 配置模板（key、OUTPUT_DIR、OBSIDIAN_DIR）。
- `folder-action/搬运录音.applescript`（或等价）— AirDrop Folder Action 脚本。
- 面向使用者的安装/使用 README（区别于开发笔记）。

**改动（小改，保持行为）**：
- `process.py`：ffmpeg 路径自动探测；`OBSIDIAN_DIR` 改读配置（留空跳过）。
- `watch_inbox.sh`：`source config.local.sh` 取代读 `~/.zshrc`。
- `watch_downloads.sh`：确认可被 Folder Action 调用（逻辑不变）。
- launchd plist：改为 install 时按模板生成。
- `.gitignore`：加入 `config.local.sh`。

## 8. 失败模式与降级

- 非 Apple Silicon → 预检即退，明确告知不支持。
- 无 Homebrew / Xcode CLT → 提示安装命令后退出。
- FluidAudio 预编译下载失败 → 源码编译回退；再失败 → 说话人分离缺席，主流程仍出无说话人纪要（现有行为）。
- 模型下载失败 → 报错并可重跑 install。
- Folder Action 授权被拒 → 回退手动拖入 inbox。
- DeepSeek key 无效/余额不足 → 原音频留 inbox 不丢，日志提示（现有行为）。

## 9. 验收标准

- 在一台干净的 Apple Silicon Mac 上 `git clone` + `./install.sh` 后：
  1. 把录音拖进 `inbox/` → 数十秒内 `output/` 出结构化纪要 + 会议全程。
  2. 从 iPhone AirDrop 一段录音 → 自动从 Downloads 入 inbox → 自动出纪要，全程不手动。
  3. 未配 Obsidian 也能正常出纪要；配了 `OBSIDIAN_DIR` 则额外落一份到 vault。
  4. `./uninstall.sh` 后 launchd 任务与 Folder Action 移除，用户录音/纪要数据保留。

## 10. 遗留问题

- `osascript` 挂载 Folder Action 的目标机实测（实现阶段先验证）。
- FluidAudio 预编译二进制的托管方式（GitHub Release 资产）与跨机 Apple Silicon 兼容确认。
- requirements.txt 从当前 venv 冻结时需剔除仅本机相关的包。
- 发布前备齐 FluidAudio 的 LICENSE/NOTICE 与修改声明（见 3.3）。

## 11. 留给实现计划的打磨项（非规格阻塞）

- `config.local.sh` 明文存 key → `chmod 600` 并在文档提示。
- `uninstall.sh` 明确是否清除 `venv/models/tools` 等数 GB 大件（建议交互询问），用户录音/纪要数据默认保留。
- README：倾向重构现有一份为"使用者视角"，避免与开发笔记两份并存维护。
- `deepseek-v4-flash` 等模型名可能随上游变动，README 注明改 `LLM_MODEL` 的位置以降支持成本。
