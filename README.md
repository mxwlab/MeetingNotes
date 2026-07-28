# MeetingNotes（声笺）

MeetingNotes 是一个面向 Apple Silicon Mac 的本地优先会议整理工具：录音在本机完成转录和说话人分离，再把转录文本交给 DeepSeek 整理为 Markdown 纪要。原始音频不会上传；使用 DeepSeek API 会产生相应的文本 API 费用。

## 系统要求

- macOS + Apple Silicon（`arm64`）
- Python 3.9 或更高版本
- Homebrew、Xcode Command Line Tools
- 可用的 DeepSeek API Key
- 约 3 GB 磁盘空间用于 Whisper 模型，另需 FluidAudio 模型缓存空间

## 安装

```bash
git clone <仓库地址> MeetingNotes
cd MeetingNotes
./install.sh
```

安装程序会依次检查环境、安装 ffmpeg、创建 Python 虚拟环境、置备 FluidAudio、下载并预热模型、写入本地配置、加载 launchd 后台任务，并编译/挂载 AirDrop Folder Action。

先检查环境而不安装任何东西：

```bash
./install.sh --dry-run
```

安装时会交互询问 DeepSeek Key 和可选的 Obsidian 目录。Key 写入项目内的 `config.local.sh`（权限 `600`，已被 git 忽略），不会修改 `~/.zshrc`。

也可以用于自动化安装：

```bash
DEEPSEEK_API_KEY='你的 key' OBSIDIAN_DIR='' ./install.sh --non-interactive
```

`OBSIDIAN_DIR` 留空表示不复制到 Obsidian；例如：

```bash
OBSIDIAN_DIR="$HOME/Documents/Obsidian Vault/会议纪要" ./install.sh --non-interactive
```

## 使用

安装完成后，把 `.m4a`、`.mp3`、`.wav`、`.mp4`、`.aac` 或 `.flac` 录音放入项目的 `inbox/`：

```text
inbox/  →  本地转录与整理  →  output/（转录.txt + 纪要.md）
                         ↘  done/（已处理原音频）
```

安装的后台任务会监听 `inbox/`。日志位于 `logs/watch.log`；失败时原音频会留在 `inbox/`，不会被丢弃。

安装程序还会把 AirDrop Folder Action 挂到 `~/Downloads`。首次触发时，macOS 可能询问是否允许自动化，请选择“允许”。只有 AirDrop quarantine 类型（`0059`/`59`）的音频会被送入 `inbox`，普通浏览器下载不会被搬运。若授权被拒或 Folder Action 挂载失败，仍可手动拖入 `inbox`。

## 配置与模型

- `DEEPSEEK_API_KEY`：DeepSeek API Key，在 [platform.deepseek.com](https://platform.deepseek.com) 申请。
- `OBSIDIAN_DIR`：可选的 Obsidian 目标目录，留空跳过同步。
- `HF_ENDPOINT`：模型下载地址，默认 `https://hf-mirror.com`。镜像不可用时可重跑安装并设置 `HF_ENDPOINT=https://huggingface.co`。
- `FLUIDAUDIO_PREBUILT_URL`：可选的 FluidAudio 预编译 CLI 地址；未设置或下载失败时，安装程序回退到 Swift 源码编译。

转录模型位于 `models/`，FluidAudio 源码和编译产物位于 `tools/`。这些目录体积较大且默认不进 Git。

纪要默认包含结构化摘要、讨论要点、决议、待办、风险，以及带说话人标签的“会议全程”。长录音会使用全局声纹聚类减少说话人标签漂移。

## 查看与停止后台任务

安装生成的服务 Label 含项目路径哈希，因此多个副本可以共存：

```bash
launchctl list | grep com.meetingnotes
tail -f logs/watch.log
```

通常不需要手动操作 launchd；需要排查时可使用 `./uninstall.sh --dry-run` 查看本项目将移除的精确目标。

## 卸载

默认卸载只移除本项目的 launchd 服务和 Folder Action，保留录音、纪要、配置以及可重建的大文件：

```bash
./uninstall.sh
```

非交互卸载：

```bash
./uninstall.sh --non-interactive
```

如果确认要删除 `venv/`、`models/`、`tools/`，显式加上：

```bash
./uninstall.sh --non-interactive --remove-runtime
```

`inbox/`、`output/`、`done/` 和 `config.local.sh` 始终保留。

## 排错

- 安装预检失败：确认设备为 Apple Silicon，运行 `xcode-select --install`，并确认 `brew` 在 PATH 中。
- 模型下载失败：按地区设置 `HF_ENDPOINT` 后重跑 `./install.sh`；模型下载支持断点续跑。
- FluidAudio 预热失败：确认网络可访问模型源，重跑安装；即使没有说话人分离，主流程仍可生成无说话人纪要。
- DeepSeek 报错：检查 Key、余额和模型名；纪要失败时原音频仍在 `inbox/`。
- 卡住的监听锁：确认没有正在处理的任务后删除项目内 `.watch.lock`，再重启监听。
- 没有使用 AirDrop：检查“文件夹操作设置”中的 Downloads 是否启用 MeetingNotes；也可以直接拖入 `inbox/`。

## 第三方许可

项目通过 `tools/FluidAudio` 使用 FluidAudio（Apache-2.0）。本项目在其源码上增加并注册了 `batch-transcribe` 命令；这是对 FluidAudio 的修改。分发 FluidAudio 源码或预编译二进制时，请同时提供原始 `LICENSE`、`NOTICE`（如上游附带）及本项目根目录的 [NOTICE](NOTICE)。

本项目的安装脚本也会在必要时从上游获取 FluidAudio 源码；具体版本和补丁步骤见 `scripts/build_fluidaudio_from_source.sh` 与 `fluidaudio-patch/SETUP.md`。
