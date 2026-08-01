# 转录引擎换 Qwen3-ASR + 按人归纳纪要 设计

日期：2026-07-31
状态：设计待用户复审

## 背景与依据（多轮实测结论）

围绕"逐字稿准确度差、会出现错别字/幻觉"的问题，对多个 ASR 做了完整录音实测（工业智能语义基座会议，71 分钟，中英混技术会）：

- **现用 FluidAudio Paraformer**：移植版弱化，标准普通话也转成乱码（"外卖的要求是到到策地环""三零零件六件件"）。
- **Whisper large-v3**：给时间戳、能做说话人分离、快、已集成；但**自信幻觉**——把 InfluxDB 编成 "iceberg"、把"清源"认成"白青园"，长音频还有重复退化。
- **满血 FunASR Paraformer / Qwen-0.6B(CPU)**：或慢或差。
- **Qwen3-ASR-1.7B（qwen3-asr-mlx，Metal 加速）**：**整段转录内容最准**（InfluxDB、清源、联通、京东、张波、郭总均正确），快于实时（71 分钟约 11 分钟），无重复退化。
- 用户以在场事实核对：**Qwen 在关键项(人名/数据库/数据源)4 项中对 3 项，Whisper 幻觉编词**。

**关键约束发现**：qwen3-asr-mlx 只返回 `text/language/duration`，**无时间戳** → 无法与说话人分离时段对齐；按说话人时段切碎逐段喂 Qwen 会让音频 LLM 失去上下文而崩坏（实测变成"烧肉咸鱼"胡话）。有时间戳的 Qwen 运行时在 Mac 上慢到不可用。

**产品取舍（用户已定）**：内容准确度 > 说话人精确归属。**放弃硬性说话人分离与逐字稿**，改为对准确的整段转录做 **LLM 按人归纳**。实测该方案能识别 ~10 位参会人的核心汇报、决策、待办（负责人），且关键实体全对，honest 局限是归属为"软推断"（部分人只能标"负责X的人"，偶有归错）。

## 方案

**新流水线**：音频 → ffmpeg 转 16k wav → **Qwen3-ASR-1.7B 整段转录**（Metal）→ 保存原始转录 `_转录.txt`（无说话人标注）→ **LLM 按人归纳纪要**（每人核心汇报 + 会议决策 + 待办[负责人] + 未明确归属要点）→ 写 output/ 与可选 Obsidian。

### 已定决策

| 主题 | 决定 |
|---|---|
| 主转录 | Qwen3-ASR-1.7B via `qwen3-asr-mlx`（bf16，Metal，整段） |
| 兜底 | Qwen 失败/不可用时回退 `mlx-whisper`（整段，加 `condition_on_previous_text=False`） |
| 说话人分离 | **移除**（连同 FluidAudio 组件、预编译资产、Swift 置备一并删除，打包大幅简化） |
| 逐字稿(会议全程) | 移除 `make_record`；仅保留原始转录文本 `_转录.txt` 作参考 |
| 纪要格式 | 新增"按人归纳"：①按参会人的核心汇报/负责事项 ②会议决策 ③待办(任务\|负责人) ④未明确归属要点；软归属并注明不确定 |
| LLM | 沿用 DeepSeek `deepseek-chat`（可 env 覆盖 base_url/model） |
| 打包 | bootstrap 装 `qwen3-asr-mlx`，首次下载 Qwen 模型(~3.4GB bf16)；`mlx` 升到 0.31+ |
| 兼容性 | mlx 0.31+ 无老 macOS wheel → **要求 Apple Silicon + 较新 macOS**（下载页标注）；老系统朋友暂不支持 |

## 架构与改动

- `process.py`：
  - `transcribe()` → `transcribe_qwen()` 主、`transcribe_whisper()` 兜底；删 `transcribe_paraformer` / `diarize` / `label_transcript` / `make_record` 调用。
  - `summarize()` → 改为"按人归纳"提示词与结构（保留结构化摘要精神，新增按人分组）。
  - 移除 FluidAudio 相关常量与 warmup。
- `requirements.txt`：`mlx` 0.31+；新增 `qwen3-asr-mlx`；`mlx-whisper` 保留作兜底。
- 置备脚本：删 `provision_fluidaudio.sh` / `build_fluidaudio_*`；新增 Qwen 模型预取；`provision_models.sh` 保留 Whisper 兜底模型（可选）。
- `folder-action` / launchd / bootstrap：去掉 FluidAudio 步骤。
- 文档：README / 图文教程更新（系统要求、无说话人说明）。

## 风险与诚实局限

- **软归属不精确**：无硬分离，某句话到底谁说的做不到；依赖会上自报家门。技术会通常够用，但要在纪要里注明"归属为推断"。
- **兼容性收窄**：mlx 0.31+ 放弃老 macOS，朋友群体变小（用户自身 macOS 26 无碍）。
- **首次下载更大**：多下 Qwen 模型 ~3.4GB（可后续加量化版减小）。
- **速度**：整段 Qwen ~0.15x 实时，71 分钟约 11 分钟；比 Whisper(调参后 437s)略慢但可接受。
- **venv 需先清理**：本轮 spike 污染了 venv（funasr/qwen 等 + mlx 被顶到 0.32），先重建到干净基础再改。

## 验收标准

1. 干净重建 venv 后，对一段真实中英混会议：Qwen 整段转录成功，关键实体(如 InfluxDB/清源)正确，无重复退化崩溃。
2. 生成的"按人归纳"纪要包含：按参会人的核心汇报、会议决策、待办(负责人)、未明确归属要点，并注明归属为推断。
3. Qwen 不可用时自动回退 Whisper，流程不崩。
4. 打包：bootstrap 在干净环境装好 qwen3-asr-mlx + 下 Qwen 模型；不再依赖 FluidAudio/Swift。
5. 速度：71 分钟录音端到端在可接受时间内（目标 <20 分钟）完成。

## 待办（进入实现计划细化）

- 是否同时保留 Whisper 模型下载（兜底）vs 仅按需——权衡首次下载体积。
- Qwen 模型是否用量化版(8bit/4bit)减小体积并实测质量。
- "按人归纳"提示词定稿与超长转录的分块策略。
- 老 macOS 朋友的降级路径（是否保留一个 Whisper-only 变体）。
