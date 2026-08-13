# MeetingNotes（声笺）

把会议录音变成按议题组织、可搜索的 Markdown 会议纪要。

录音转码和语音识别全部在你的 Mac 本机完成；只有识别后的文字会发送给 DeepSeek 整理。原始录音不会上传。

## 最简单的安装方式

需要一台运行 macOS 14 或更高版本的 Apple Silicon Mac（M1/M2/M3/M4/M5），以及你自己的 DeepSeek API Key。不需要预装 Homebrew、Python、Git 或 Xcode。

1. 从 GitHub Releases 下载 `MeetingNotes-mac-*.zip`。
2. 双击 zip 解压。
3. 第一次右键点 `开始使用.command`，选择「打开」，再确认一次「打开」。
4. MeetingNotes 安装助手会说明预计时间和下载体积；粘贴 DeepSeek API Key 后点击「验证并安装」。
5. 在同一个窗口查看总进度、当前任务和预计剩余时间。安装完成后点击「打开录音文件夹」即可开始使用。

安装（不含模型）约 2 分钟。首次处理需要额外磁盘与时间，请预留：运行环境（venv 约 1.1 GB）+ 语音模型，整体占用约 3–4 GB；且**第一条录音处理时还会再补下一批模型（对齐/兜底等），首次从拖入到出结果可能要等 4 分钟左右且中途没有界面提示，属正常，请耐心等待**。之后的录音就快了。

安装过程中可以继续使用电脑，但不要关闭安装窗口。技术详情默认收起，需要排查时可点击「查看详细信息」。未签名内测包第一次必须“右键 → 打开”，之后不需要重复。详细截图说明见 [新手安装图文教程](docs/新手安装图文教程.md)。

## 日常使用

安装后，桌面会出现「MeetingNotes 录音」入口：

- 把录音拖进去即可：常见音视频格式都支持（`.m4a`、`.mp3`、`.wav`、`.mp4`、`.mov`、`.aac`、`.flac`、`.aiff`、`.opus` 等，由内置 ffmpeg 解码）。无法识别为音频的文件会弹通知说明并挪进内部 `skipped` 目录，不会静默无反应。
- 也可以直接从 iPhone AirDrop；首次出现自动化授权时选择「允许」。
- 录音在 `~/MeetingNotes/录音`，生成结果在 `~/MeetingNotes/纪要`。
- 处理成功的原始录音会移入内部 `done` 目录；失败时会留在录音目录，不会丢失。

```text
录音 → 本机转码 / 转录 → 文字发送 DeepSeek → 按议题的 Markdown 纪要
```

普通浏览器下载的音频不会被 AirDrop 自动规则误搬入；只有 macOS 标记为 AirDrop 接收的音频会自动处理。

屏幕顶部还会出现 MeetingNotes 状态：空闲时显示 `🐱 空闲`，转录时显示进度，生成纪要时显示 `📝 生成中`，失败时显示警告并发送通知。菜单栏 App 会在登录后自动启动；点击它可以打开录音/纪要文件夹、查看日志或重新设置 DeepSeek/其他兼容服务。

## 隐私与费用

- 原始音频始终留在本机。
- 转录文字会发送给你配置的 DeepSeek 账号。
- DeepSeek 按文本 Token 收费，请确保账户有余额。
- API Key 仅保存在 `~/MeetingNotes/config.local.sh`，文件权限为 `600`。
- 安装日志不会记录 API Key。

## 安装失败怎么办

直接重新双击 `开始使用.command`。下载和置备步骤支持重复运行，已完成的内容会跳过，本地配置、录音和纪要不会被覆盖。

详细日志位于：

```text
~/MeetingNotes/logs/bootstrap.log
```

常见情况：

- 提示 API Key 无效：回到 DeepSeek 控制台重新复制。
- 提示余额不足：充值后重试。
- 模型或运行环境下载失败：检查网络后重新双击。
- AirDrop 没自动处理：把文件手动拖到桌面「MeetingNotes 录音」入口，效果相同。

## 高级配置

大多数朋友无需修改配置。需要切换其他 OpenAI 兼容服务时，可在 `config.local.sh` 中设置：

```bash
export LLM_BASE_URL="https://你的服务地址"
export LLM_MODEL="你的模型名"
```

可选设置 `OBSIDIAN_DIR`，让纪要额外复制到 Obsidian 目录。默认留空，仅写入 `~/MeetingNotes/纪要`。

## 卸载

在 Finder 打开 `~/MeetingNotes`，右键打开终端后运行：

```bash
./uninstall.sh
```

默认只移除后台服务、菜单栏自启、AirDrop 自动规则和本项目创建的桌面入口，保留录音、纪要、配置、模型及运行环境。

如果也要删除可重新下载的运行环境：

```bash
./uninstall.sh --remove-runtime
```

`--remove-runtime` 还会删除可重新构建的菜单栏 App 和 UI 环境。`录音`、`纪要`、`done` 和 `config.local.sh` 始终保留。

## 开发者与旧安装方式

仓库仍保留 `install.sh`，供开发者从源码安装和调试；朋友内测请优先使用 Release zip。发布包由 `./build_release.sh <version>` 从显式白名单生成，不包含模型、运行时、录音、纪要、日志或本地配置。

## 第三方许可

首次安装下载的 FFmpeg 7.1 构建启用了 GPL 组件，适用 GPL v2 或更高版本。完整声明和许可证见 [NOTICE](NOTICE) 与 `licenses/`。
