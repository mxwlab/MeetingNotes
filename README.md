# 会议录音自动整理工具 · 使用说明

把会议录音变成 Markdown 会议纪要：**本地转录（不上传音频）→ DeepSeek 整理成纪要**。

## 目录结构
```
~/MeetingNotes/
├── inbox/     ← 把录音放这里（或让快捷指令自动送进来）
├── output/    ← 生成的「转录.txt」和「纪要.md」
├── done/      ← 处理完的原始音频归档在此
├── logs/      ← 运行日志
├── models/    ← 本地 whisper 模型（3GB，已下好，无需联网）
├── venv/      ← Python 环境
├── process.py       ← 核心处理脚本
└── watch_inbox.sh   ← inbox 监听脚本（launchd 调用）
    watch_downloads.sh ← 把 Downloads 里的录音搬进 inbox（快捷指令调用）
```

## 日常怎么用
- **手动**：把录音（.m4a 等）拖进 `inbox/`，几十秒后 `output/` 里自动出纪要。
- **半自动（已配快捷指令后）**：AirDrop 录音到 Mac → 快捷指令自动把它从 Downloads 送进 inbox → 自动出纪要。全程不用管。

支持格式：m4a / mp3 / wav / mp4 / aac / flac。

生成的纪要会**自动复制一份到 Obsidian**：`~/Documents/Obsidian Vault/会议纪要/`，文件名如「洛阳会议纪要 2026-07-25.md」，带 `tags: [会议纪要]` frontmatter，可在 Obsidian 里按标签检索。（vault 不存在时自动跳过，不影响主流程。）改路径见 `process.py` 里的 `OBSIDIAN_DIR`。

## 管理 inbox 自动监听（launchd）
```bash
# 看实时日志（最常用）
tail -f ~/MeetingNotes/logs/watch.log

# 关闭自动处理
launchctl unload ~/Library/LaunchAgents/com.moxiuwen.meetingnotes.plist

# 开启自动处理
launchctl load -w ~/Library/LaunchAgents/com.moxiuwen.meetingnotes.plist

# 查看是否在运行（有输出即已加载）
launchctl list | grep meetingnotes
```

## 关键配置
- **转录模型**：`mlx-community/whisper-large-v3-mlx`，已用 curl 下到 `models/`，本地读取不联网。想换更快的小模型，改 `process.py` 里 `MODEL_WHISPER`。
- **纪要模型**：DeepSeek `deepseek-v4-flash`（快且便宜；要更高质量可改 `process.py` 里 `LLM_MODEL` 为 `deepseek-v4-pro`）。纪要结构：一句话摘要 / 会议主题 / 参会人 / 讨论要点 / 决议事项 / 待办表格 / 风险·待澄清。
- **反幻觉过滤**：转录后自动清掉 whisper 在静音段吐的"点赞订阅/嘶嘶嘶"类噪声。
- **说话人分离**：本地 FluidAudio（`tools/FluidAudio`，跑 Apple 神经引擎）分辨"谁说了什么"，纪要带说话人视角（谁提的/谁负责/谁拍板）。分离失败自动退回无说话人纪要。
- **双文档产出**：一篇 Obsidian 笔记内含 ①结构化纪要 + ②`# 会议全程`（说话人标注的逐字记录，修错字补标点）。
- **中文转录用 Paraformer**：本地 FluidAudio 的 Paraformer-large(中文，跑神经引擎)，比 whisper 中文更准更快；whisper 作兜底。长音频经自写的 `batch-transcribe`(VAD 切段 + Paraformer 批量)处理。
- **已知局限**：极端方言 Paraformer 会重复字、whisper 会换错字；电话单声道两人分离偏弱（靠 DeepSeek 按内容补分）。都是最坏情况，普通话多人会议效果好。
- **API Key**：在 `~/.zshrc` 的 `DEEPSEEK_API_KEY`。launchd 不加载 .zshrc，`watch_inbox.sh` 会单独读取它。
- **ffmpeg**：已 `brew install ffmpeg`（转录解码音频用）。

## 排错
- 处理失败时，原音频**保留在 inbox**不会丢，日志在 `logs/watch.log`。
- 常见原因：DeepSeek 余额不足（去 platform.deepseek.com 充值）、API 模型名变更（改 `LLM_MODEL`）。
- 卡死残留锁：`rm -rf ~/MeetingNotes/.watch.lock`（脚本已含 2 小时自动清理）。
