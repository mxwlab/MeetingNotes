# FluidAudio 本地引擎搭建（说话人分离 + Paraformer 中文转录）

本项目的转录和说话人分离依赖 [FluidAudio](https://github.com/FluidInference/FluidAudio)（Swift/CoreML，跑 Apple 神经引擎，纯本地）。`tools/FluidAudio` 未纳入本仓库（体积大 + 第三方），按下面步骤重建：

```bash
# 1) 克隆到 tools/
mkdir -p ~/MeetingNotes/tools && cd ~/MeetingNotes/tools
git clone https://github.com/FluidInference/FluidAudio.git

# 2) 加入本项目自定义的批量转写命令
cp ~/MeetingNotes/fluidaudio-patch/BatchTranscribeCommand.swift \
   FluidAudio/Sources/FluidAudioCLI/Commands/ASR/BatchTranscribeCommand.swift

# 3) 在 CLI 分发里注册（Sources/FluidAudioCLI/FluidAudioCLI.swift 的 switch 中，
#    "transcribe" case 后面加一行）：
#        case "batch-transcribe":
#            await BatchTranscribeCommand.run(arguments: Array(arguments.dropFirst(2)))

# 4) 编译（首次会下 CoreML 模型）
cd FluidAudio && swift build -c release --product fluidaudiocli
```

编好后二进制在 `tools/FluidAudio/.build/release/fluidaudiocli`，`process.py` 的 `DIARIZE_BIN` 指向它。

## 自定义命令 batch-transcribe
`BatchTranscribeCommand.swift`：VAD(VadManager) 按静音把长音频切成 ≤22s 片段 → Paraformer-large(zh，模型只加载一次)逐段转写 → 输出 `{"segments":[{"start","end","text"}]}`，并向 stderr 逐段打印 `PROGRESS i/N` 供上层驱动进度条。（因为 Paraformer 单次上限约 30s，长会议必须先切段。）

用法：`fluidaudiocli batch-transcribe <wav> --output <json> [--max-speech-s 22]`

> 注意：若从上游更新了 FluidAudio，需重新执行第 2、3 步把本命令加回去。
