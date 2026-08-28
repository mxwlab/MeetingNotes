# 安装器重测 · 测试报告与问题记录（2026-08-28）

分支 `feat/installable-packaging` → 已并入 `main`。候选发布包 `MeetingNotes-mac-0.2.0-beta.2.zip`
（现构自当前 main，修复后 SHA-256 `942aa5cd2427f51c473eec29a917cb53fb841caf7db52a8aab49397d1a9a9d8a`）。

## 1. 测试目的与方法

用户要求重测「双击安装」的朋友体验。方法：在中文空格路径 + 隔离 HOME/`MEETINGNOTES_INSTALL_DIR`
/ 路径哈希 launchd label 下，真机冷跑发布包的原生三态 GUI 安装器，不触碰正式实例。

## 2. 现象

安装看似「卡在下载语音模型」。取证发现：重物全部下载成功（独立 Python、ffmpeg 7.1、
Qwen3-ASR-1.7B-8bit 2.3 GB 模型 finalize 落盘），但 **bootstrap 在模型步之后静默退出**，
`STEP 6 启动后台服务` 从未执行——后台服务 / 菜单栏 App / AirDrop Folder Action 全没装，
GUI 停在 ~86%。日志无报错、无 crash report，安装器 App 进程仍活着（读端 fd 仍开）。

## 3. 问题记录（根因 + 证据 + 修复）

### P1 · 进度管道断裂静默中止安装（严重）
- **根因**：安装进度/信息都写到安装器 GUI 的 stdout 管道。窗口关闭/卡死使读端断裂时，
  `set -eu` 的 bootstrap 任何一次 `echo`/`printf` 会因 SIGPIPE 被杀、或因写返回非零被
  errexit 中止。仅 `trap '' PIPE` 不够——裸 `echo` 到断裂管道返回非零仍会触发 set -e。
- **证据**：最小 zsh 复现：读端关闭后循环写的 `set -eu` 脚本以 **exit 141（128+13, SIGPIPE）**
  退出且到不了后续步骤；加 `trap '' PIPE` 后裸 `echo` 仍因 set -e 中止。
- **修复**（`scripts/bootstrap_mac.sh` + `scripts/installer_progress.sh`）：
  1. bootstrap 顶部 `trap '' PIPE`；
  2. GUI 模式把 stdout 接到一个「只读不断、自身也忽略 SIGPIPE」的转发器
     （`exec > >(trap '' PIPE; while read …; do print … 2>/dev/null || true; done)`），
     使 bootstrap 侧 stdout 永不破裂；带 `MEETINGNOTES_STDOUT_DRAINED` 守卫避免 settle 重执后嵌套；
  3. `mn_progress` 的 printf 追加 `2>/dev/null || true` 兜底。

### P2 · 模型进度 du 空值算术崩溃（严重）
- **根因**：`run_model_with_progress` 轮询 `downloaded=$(( $(du -sk "$model_dir" …) * 1024 ))`；
  模型目录尚未被 provision_models 建好时 du 返回空 → `$(( 空 * 1024 ))` 触发
  `bad math expression`，在 set -e 下中止安装。原有 `|| echo 0` 因 awk 空输入仍退 0 而失效。
- **证据**：`zsh -x` 定位到 `run_model_with_progress:13: bad math expression: operand expected at '* 1024 '`。
- **修复**：改为 `downloaded_kb="$(du … | awk …)"; downloaded=$(( ${downloaded_kb:-0} * 1024 ))`。

### P3 · Python/菜单栏步无活体进度，显假死（体验；2026-08-13 已记未修）
- **根因**：「准备运行环境」跑 `fetch_python.sh`（下 Python + pip 装 torch/mlx/numba… 数分钟），
  「安装菜单栏」跑 py2app（一两分钟），期间输出只进日志、对 GUI 不发事件，进度条定格像卡死。
- **修复**：`installer_progress.sh` 新增可复用 `mn_run_with_heartbeat <id> <pct> <title> <prefix> -- cmd…`，
  把慢命令放后台跑、每隔 `MN_HEARTBEAT_SECS`（默认 2s）发一条「…· 已用 Xs · 请勿关闭」的进度，
  如实透传命令退出码；bootstrap 的 Python 步与菜单栏构建步接入。

## 4. 新增测试（TDD，先红后绿）

| 测试 | 覆盖 |
|------|------|
| `tests/test_progress_sigpipe.sh` | echo + 进度写到断裂管道仍到达后续步骤；断言 bootstrap 有 `trap '' PIPE`、stdout 转发器、mn_progress 有 `\|\| true` |
| `tests/test_progress_heartbeat.sh` | 慢命令期间发出多条心跳、详情含「已用」、如实透传退出码；断言 Python 步接入心跳 |
| `tests/test_bootstrap_pipe_resilience.sh` | 集成：整段 bootstrap（打桩置备 + mock launchctl/plutil）在「stdout 读端断裂 + du 首轮空值」下仍跑满 STEP 6/7/8、执行菜单栏与 AirDrop 步 |

## 5. 验证结果

- 全套 **33 个测试通过**（11 Python + 22 shell）。
- 集成测试 `test_bootstrap_pipe_resilience.sh` 直接复刻事故条件（读端断裂 + du 空值），
  修复后跑满全部 8 步——**这是 P1/P2 修复的端到端证据**。
- 修复后重构发布包，确认 zip 内 `bootstrap_mac.sh`/`installer_progress.sh` 含全部修复标记。

## 6. 仍未完成的门禁（需人工 / 第二台机器）

1. **可见 GUI 冷装复跑**：用 beta.2 zip 真机双击走一遍，肉眼确认 Python 步进度条动起来、
   八步跑满、完成页正常、并拖录音出纪要。（我可自动跑无 GUI 的真实冷装到出纪要，但会有
   第二只小猫等系统副作用，需事后清理。）
2. 第二台干净 Apple Silicon Mac 无缓存冷装 + 重启自启 + 整段录音。
3. 真机物理 AirDrop 复测。
4. 发布截图、模型/传递依赖许可归档。
5. 用 beta.2 重发 GitHub Release（现公开 Release 仍是旧包）。
