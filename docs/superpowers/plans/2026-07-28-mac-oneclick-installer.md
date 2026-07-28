# MeetingNotes Mac 双击安装（A1.5）Implementation Plan

**Goal:** 把已验证的本地 MeetingNotes 引擎包装成面向非技术朋友的小型 zip：解压后右键打开一次 `开始使用.command`，填写 DeepSeek key，等待自动下载，即可通过桌面入口或 AirDrop 生成纪要。

**Architecture:** 保留现有处理流水线，在外层新增可重复执行的 bootstrap。发布包先把自身原子安顿到 `~/MeetingNotes`，再下载固定版本的独立 Python、静态 ffmpeg 与预编译 FluidAudio，复用现有模型、launchd 和 Folder Action 脚本。所有下载物做架构/可执行性校验，所有步骤用 marker 或产物校验保持幂等；用户界面只显示中文阶段进度，详细输出写入 `logs/bootstrap.log`。

**Constraints:** Apple Silicon macOS only；录音只在本机；默认 DeepSeek；不依赖 Homebrew/git/Xcode；未签名内测包；不做 Windows、自动更新或 `.app`；不得把 key、模型、用户录音、现有输出打进发布包。

**Reference:** `docs/superpowers/specs/2026-07-28-mac-oneclick-installer-design.md`

---

## Task 1：运行时路径与 LLM 配置解耦

**Files**
- Modify: `process.py`
- Modify: `watch_inbox.sh`
- Modify: `config.example.sh`
- Test: `tests/test_process_paths.py`
- Test: `tests/test_config_resolution.sh`

- [ ] 先补失败测试：
  - `MEETINGNOTES_PYTHON` 可覆盖 watcher 的 Python。
  - 项目自带 `bin/ffmpeg` 优先于 Homebrew 路径。
  - `LLM_BASE_URL` / `LLM_MODEL` 可覆盖默认值；未设置时仍为 DeepSeek。
- [ ] 修改 `watch_inbox.sh`：`PY="${MEETINGNOTES_PYTHON:-$BASE/venv/bin/python}"`，PATH 前置 `$BASE/bin`。
- [ ] 修改 `process.py`：ffmpeg 优先 `$BASE/bin/ffmpeg`；OpenAI client 和模型读取环境变量，默认保持当前 DeepSeek 配置。
- [ ] 在 `config.example.sh` 记录隐藏高级选项，不改变朋友默认流程。
- [ ] 运行：
  - `venv/bin/python -m unittest tests/test_process_paths.py`
  - `zsh tests/test_config_resolution.sh`

## Task 2：独立 Python 下载与依赖安装

**Files**
- Create: `scripts/fetch_python.sh`
- Create: `tests/test_fetch_python.sh`
- Modify: `requirements.txt`（仅在兼容性验证要求时）

- [x] 选定一个支持 arm64 macOS 的 python-build-standalone 固定版本、资产 URL 和 SHA-256；把版本、URL、校验值集中为脚本顶部可覆盖常量。
- [x] 写失败测试，以本地 fixture/mock curl 验证：
  - 已存在且版本正确时跳过。
  - 下载后必须校验 SHA-256，错包失败且不污染目标。
  - 解包后 Python 可执行，venv/依赖安装使用该解释器。
- [x] 实现断点友好下载到临时文件、校验、临时目录解包、原子移动到 `runtime/python`。
- [x] 创建 `venv` 并安装固定依赖；详细 pip 输出由调用方收进 bootstrap 日志。
- [x] 在不借用系统 Python 的隔离目录验证 `mlx-whisper` 与 `openai` 可 import；真实官方资产 SHA-256、arm64、venv、SSL、pip 均通过。另固定 `mlx==0.28.0`，避免新版本只提供 macOS 26 wheel。

## Task 3：静态 ffmpeg 下载

**Files**
- Create: `scripts/fetch_ffmpeg.sh`
- Create: `tests/test_fetch_ffmpeg.sh`
- Modify: `NOTICE`

- [x] 选定 imageio-ffmpeg 0.6.0 官方 PyPI arm64 wheel（FFmpeg 7.1、macOS 11+），固定 URL 与 SHA-256，并记录 GPL 来源。
- [x] 写失败测试：正确包安装到 `bin/ffmpeg`；校验失败不覆盖旧版本；现有可用固定版本幂等跳过。
- [x] 实现下载、校验、精确条目提取、arm64/`ffmpeg -version` 验证和原子替换。
- [x] 在 `NOTICE` 补齐 ffmpeg 构建来源和 GPL v2+ 义务；加入官方 `licenses/FFmpeg-COPYING.GPLv2`。真实 wheel 的 SHA-256、Mach-O arm64、系统库依赖、转码与二次运行均通过。

## Task 4：FluidAudio 预编译资产接线

**Files**
- Modify: `scripts/provision_fluidaudio.sh`
- Modify: `scripts/build_fluidaudio_from_source.sh`
- Modify: `tests/test_provision_fluidaudio.sh`
- Create: `scripts/build_fluidaudio_release_asset.sh`

- [x] 固定作者 Release 资产名 `fluidaudiocli-88d6d816-macos14-arm64.gz`、预留下载 URL 与 SHA-256；真正上传仍由 Task 8 发布门完成。
- [x] 补测试：默认预编译路径无需 Xcode；坏下载失败时只有检测到 Xcode 工具链才允许源码回退，否则给朋友可理解的错误。
- [x] 让预编译下载支持 SHA-256、gzip 临时解包、Mach-O arm64 校验和原子安装；保留源码回退供开发者使用。
- [x] 增加制作方构建脚本：从固定 FluidAudio revision 生成 arm64 CLI、运行 `--help`、检查依赖、输出确定性 gzip、SHA-256 与 build-info。
- [x] 真实构建验证：修复仓库移动后 SwiftPM `.build` 绝对路径缓存失效；最终资产 SHA-256 为 `cdd4d23cfe7c47c969846908d2557df6efd65621cbc75a8e59497f4361d3b9de`，仅依赖系统库，最低 macOS 14.0，隔离预编译安装与二次运行通过。

## Task 5：双击 bootstrap、安顿目录与原生 key 流程

**Files**
- Create: `开始使用.command`
- Create: `scripts/bootstrap_mac.sh`
- Create: `scripts/prompt_deepseek_key.applescript`
- Create: `tests/test_bootstrap_mac.sh`

- [x] 写全 mock 编排测试，覆盖：
  - 非 arm64 立即停止且零写入。
  - 从 Downloads 解压目录运行时复制到 `~/MeetingNotes`，排除 `.git`、模型、venv、录音、纪要、日志和本地配置。
  - 已在 `~/MeetingNotes` 时不自复制。
  - 第二次运行不重复下载、不覆盖 config、不重复生成服务。
  - 任一步失败可重跑续接。
- [x] `开始使用.command` 只负责解析自身路径、清理 quarantine（允许时）、调用 bootstrap、在失败时保留窗口并指出重跑方式。
- [x] bootstrap 以 1/8 中文步骤显示进度，技术输出追加到 `logs/bootstrap.log`，错误信息包含“发生了什么 / 怎么重试 / 日志在哪”。
- [x] 首次安顿使用 staging + 原子移动；已有 `~/MeetingNotes` 时先 staging 程序文件再增量更新，严格排除并保留 config、inbox/output/done、logs、models、runtime、venv 与 FluidAudio。
- [x] 用原生对话框录入 key：
  - 首次自动打开 DeepSeek key 页面。
  - 支持取消并安全退出。
  - 通过轻量 API 请求当场验证；401/余额或网络错误给不同提示。
  - 写入 shell-safe、mode 600 的 `config.local.sh`，不把 key 输出到日志。
- [x] 依次调用 Python、ffmpeg、FluidAudio、模型置备，再生成 launchd 与 Folder Action。隔离测试覆盖非 arm64 零写入、中文/空格路径安顿、数据排除、配置 mode 600、日志不泄 key、二次运行保留配置，以及中途失败后重跑完成；AppleScript 原生对话框编译通过。

## Task 6：朋友可见目录、桌面入口与后台服务

**Files**
- Modify: `scripts/gen_launchd.sh`
- Modify: `scripts/attach_folder_action.sh`
- Modify: `watch_downloads.sh`
- Modify: `uninstall.sh`
- Modify/Create tests for the above

- [x] 明确兼容映射：内部继续使用 `inbox/output`，朋友可见 `录音/纪要` 为同目录的稳定符号链接，避免改动处理流水线。
- [x] 桌面创建“MeetingNotes 录音”符号链接，存在且指向正确时幂等跳过；冲突文件不覆盖并明确报错。
- [x] launchd 显式设置自带 `venv/bin/python` 与项目 `bin` 优先 PATH，不依赖登录 shell。
- [x] Folder Action 继续只接收 AirDrop quarantine `0059`，`watch_downloads.sh` 优先搬入朋友可见 `录音` 入口，旧安装无该入口时兼容回退 `inbox`。
- [x] 卸载识别 A1.5 资产：默认保留录音、纪要、配置和全部 runtime；`--remove-runtime` 才删除 venv/models/tools/runtime/bin；桌面入口只有精确指向本安装时才移除，同名外部入口测试确认保留。

## Task 7：发布包构建与用户文档

**Files**
- Create: `build_release.sh`
- Create: `tests/test_build_release.sh`
- Modify: `README.md`
- Modify: `docs/新手安装图文教程.md`
- Modify: `.gitignore`

- [ ] 建立显式 allowlist，而非从工作树整体压缩；发布包只含启动器、运行代码、脚本、模板、测试 fixture、许可证与入门文档。
- [ ] 测试 zip 内绝不含：`.git`、`config.local.sh`、key、`venv/runtime/models/tools/FluidAudio` 源码、`inbox/output/done/logs` 用户内容、`__pycache__`。
- [ ] 构建产物命名 `MeetingNotes-mac-<version>.zip`，同时输出 SHA-256 和 manifest；构建两次内容可复现（时间戳固定）。
- [ ] README 首屏改成朋友流程：下载 → 解压 → 右键打开 → 填 key → 等待 → 拖录音。
- [ ] 图文教程补真实截图并说明唯一 Gatekeeper 操作、隐私边界、约 3GB 下载、失败重跑和卸载。

## Task 8：整装验收与发布

- [ ] 运行所有自动化测试：`zsh tests/*.sh`（逐个）和 Python 测试。
- [ ] 从构建 zip 解压到带空格/中文的临时路径，使用 mock 网络完成零写系统状态的全编排测试。
- [ ] 在未装 Homebrew、未装 Xcode CLT 的 Apple Silicon 测试账户/测试机完成真实验收：
  - 右键打开一次。
  - key 错误与正确路径。
  - Python/ffmpeg/FluidAudio/模型首次下载。
  - 桌面拖入录音生成纪要。
  - 真实 AirDrop 生成纪要。
  - 第二次双击幂等。
  - 默认卸载保留数据。
- [ ] 检查日志无 key、zip 无用户数据、录音处理期间无音频网络上传。
- [ ] 只有上述验收通过后创建 GitHub prerelease，上传 zip、SHA-256、FluidAudio 资产和安装说明。

## Completion Gate

A1.5 只有在“全新 Apple Silicon Mac、无 Homebrew/Xcode、非技术用户除右键打开和填 key 外零终端输入”真实通过后才算完成。Mock 测试或作者开发机通过不能替代此门槛。
