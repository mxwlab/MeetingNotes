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

**新流水线**：音频 → ffmpeg 转 16k wav → **Qwen3-ASR-1.7B 整段转录**（Metal）→ 两份产物：
1. **LLM 按人归纳纪要**（每人核心汇报 + 会议决策 + 待办[负责人] + 未明确归属要点）
2. **LLM 分段整理稿**（按主题分段 + 小标题 + 轻度纠错，可读，无说话人标注）

→ 写 output/ 与可选 Obsidian。

### 已定决策

| 主题 | 决定 |
|---|---|
| 主转录 | Qwen3-ASR-1.7B via `qwen3-asr-mlx`（bf16，Metal，整段） |
| 兜底 | 保留 `mlx-whisper` 作**代码级兜底**（Qwen 失败时用，加 `condition_on_previous_text=False`）；Whisper 模型本地已存在，**不额外打包/下载**（用户已定：留着，零成本） |
| 说话人分离 | **移除**（连同 FluidAudio 组件、预编译资产、Swift 置备一并删除，打包大幅简化） |
| 转录稿(替代逐字稿) | 移除 `make_record`；**保留一份转录稿，但由 LLM 按主题分段、配小标题、轻度纠错**（"分段整理稿"，可读，无说话人标注），不是 ASR 生肉；文件 `_整理稿.md` |
| 纪要格式 | 新增"按人归纳"：①按参会人的核心汇报/负责事项 ②会议决策 ③待办(任务\|负责人) ④未明确归属要点；软归属并注明不确定 |
| LLM | 沿用 DeepSeek `deepseek-chat`（可 env 覆盖 base_url/model） |
| 模型 | Qwen `mlx-community/Qwen3-ASR-1.7B-bf16`（~3.4GB，已实测，用户已定不用量化版） |
| 兼容性 | **先不考虑朋友/老 macOS**（用户已定）——自用优先，要求 Apple Silicon + 较新 macOS（mlx 0.31+）；朋友分发与降级变体本阶段不做 |

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

## 已定（用户 2026-07-31 拍板）

- 先不考虑朋友/老 macOS，自用优先，不做 Whisper-only 降级变体。
- Qwen 用 bf16，不用量化版。
- 保留 Whisper 代码级兜底（模型本地已有，零额外成本），不单独打包。
- 保留一份转录，但要**按段**（LLM 主题分段 + 小标题），不要连续大坨。

## 待办（进入实现计划细化）

- "按人归纳"与"分段整理稿"两个提示词定稿。
- 超长转录（>LLM 上下文）时的分块与分段合并策略。
- 产物文件命名与 Obsidian 同步格式。
