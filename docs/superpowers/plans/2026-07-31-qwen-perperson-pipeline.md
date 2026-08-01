# Qwen3-ASR + 按人归纳 本地流水线 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把本地录音处理流水线的转录引擎换成 Qwen3-ASR-1.7B（MLX/Metal，整段），产物改为「按人归纳纪要」+「分段整理稿」，移除说话人分离与逐字稿。

**Architecture:** 音频 →ffmpeg 16k wav → `transcribe()`（Qwen 主 / Whisper 兜底，均整段、无时间戳）→ 原始转录文本 → 两次 LLM 加工：`summarize_perperson()`（按人归纳）与 `make_segmented_transcript()`（主题分段整理稿）→ 写 output/ 与可选 Obsidian。说话人分离(FluidAudio)与 `make_record` 逐字稿整段删除。

**Tech Stack:** Python 3.10 venv；`qwen3-asr-mlx`(Qwen3ASR)；`mlx-whisper`(兜底)；`mlx>=0.31`；`openai`→DeepSeek `deepseek-chat`；stdlib `unittest`。

## Global Constraints

- 本阶段**仅自用**，不做朋友分发/老 macOS 降级；`bootstrap_mac.sh`、发布打包、README 面向朋友的部分**不在本计划范围**（另开计划）。
- 转录引擎主用 `mlx-community/Qwen3-ASR-1.7B-bf16`（整段，Metal）；Qwen 失败时回退 `mlx-whisper`（`condition_on_previous_text=False`）。
- LLM 默认 `deepseek-chat`，`LLM_BASE_URL`/`LLM_MODEL` 可 env 覆盖（已有）。
- 录音仍只在本机处理，仅转录文本发 DeepSeek（隐私模型不变）。
- venv 现被本轮 spike 污染（funasr/qwen_asr/torchaudio 等 + mlx 被顶到 0.32），必须先按新 `requirements.txt` 重建。
- 测试用 stdlib `unittest`，运行解释器为 `venv/bin/python`；重的模型/网络一律 mock。
- 频繁提交；每个 Task 结束有独立可测产物。

---

### Task 1: 更新依赖并重建干净 venv

**Files:**
- Modify: `requirements.txt`

**Interfaces:**
- Produces: 干净 venv，`import mlx, mlx_whisper, qwen3_asr_mlx, openai` 全部可用；`qwen3_asr_mlx.Qwen3ASR` 可导入。

- [ ] **Step 1: 改 requirements.txt**

把 `mlx==0.28.0` 那段（含注释）替换为下面内容，并新增 qwen3-asr-mlx：

```text
# Runtime entry points.
mlx-whisper==0.4.3
openai==2.48.0

# Qwen3-ASR 主转录（Apple Silicon / Metal，需要较新 mlx；本阶段不再支持老 macOS）。
qwen3-asr-mlx>=0.1.1
mlx>=0.31
```

- [ ] **Step 2: 重建 venv**

```bash
cd /Users/moxiuwen/workspace/MeetingNotes
mv venv venv.polluted.bak
/Library/Frameworks/Python.framework/Versions/3.10/bin/python3 -m venv venv
venv/bin/python -m pip install --upgrade pip
venv/bin/python -m pip install -r requirements.txt
```

- [ ] **Step 3: 验证四个关键导入**

Run:
```bash
venv/bin/python -c "import mlx, mlx_whisper, qwen3_asr_mlx, openai; from qwen3_asr_mlx import Qwen3ASR; import importlib.metadata as m; print('mlx', m.version('mlx')); print('OK')"
```
Expected: 打印 `mlx 0.3x`（≥0.31）与 `OK`，无 ImportError。

- [ ] **Step 4: 确认没有污染残留**

Run: `venv/bin/python -c "import importlib.util as u; print('funasr', u.find_spec('funasr')); print('qwen_asr', u.find_spec('qwen_asr'))"`
Expected: 两个都是 `None`（旧 spike 包不在新 venv 里）。

- [ ] **Step 5: 删除备份并提交**

```bash
rm -rf venv.polluted.bak
git add requirements.txt
git commit -m "build: 转录引擎换 Qwen3-ASR，mlx 升到 0.31+，qwen3-asr-mlx 入依赖"
```

---

### Task 2: `transcribe_qwen()` + `transcribe()` 改 Qwen 主 / Whisper 兜底

**Files:**
- Modify: `process.py`（新增 `transcribe_qwen`；重写 `transcribe`，第 270–277 行）
- Test: `tests/test_transcribe_engine.py`（新建）

**Interfaces:**
- Consumes: 无。
- Produces:
  - `transcribe_qwen(wav_path: str) -> str`：整段转录文本；失败抛异常。
  - `transcribe(wav_path: str) -> str`：先 Qwen 后 Whisper，返回文本；两者皆失败返回 `""`。
  - 模块级 `_QWEN_MODEL_ID = "mlx-community/Qwen3-ASR-1.7B-bf16"`。
  - 注意：新 `transcribe` **返回纯文本 str**（旧版返回 segs 列表），下游 main 相应改。

- [ ] **Step 1: 写失败测试**

`tests/test_transcribe_engine.py`：
```python
import importlib, sys, types
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")

def test_transcribe_prefers_qwen():
    process = load()
    with mock.patch.object(process, "transcribe_qwen", return_value="QWEN文本") as q, \
         mock.patch.object(process, "transcribe_whisper", return_value="WHISPER文本") as w:
        assert process.transcribe("x.wav") == "QWEN文本"
    q.assert_called_once(); w.assert_not_called()

def test_transcribe_falls_back_to_whisper_on_qwen_error():
    process = load()
    with mock.patch.object(process, "transcribe_qwen", side_effect=RuntimeError("boom")), \
         mock.patch.object(process, "transcribe_whisper", return_value="WHISPER文本"), \
         mock.patch.object(process, "log"):
        assert process.transcribe("x.wav") == "WHISPER文本"

def test_transcribe_qwen_calls_model(monkeypatch=None):
    process = load()
    fake_model = mock.Mock()
    fake_model.transcribe.return_value = types.SimpleNamespace(text="  你好 ")
    with mock.patch.object(process, "_load_qwen", return_value=fake_model):
        assert process.transcribe_qwen("x.wav") == "你好"
```

- [ ] **Step 2: 跑测试确认失败**

Run: `venv/bin/python tests/test_transcribe_engine.py -v`
Expected: FAIL（`transcribe_qwen`/`_load_qwen` 不存在，或 transcribe 返回类型不符）。

- [ ] **Step 3: 实现**

在 `process.py` 顶部 `MODEL_WHISPER` 定义附近新增：
```python
_QWEN_MODEL_ID = "mlx-community/Qwen3-ASR-1.7B-bf16"
_qwen_model = None
def _load_qwen():
    global _qwen_model
    if _qwen_model is None:
        from qwen3_asr_mlx import Qwen3ASR
        _qwen_model = Qwen3ASR.from_pretrained(_QWEN_MODEL_ID)
    return _qwen_model

def transcribe_qwen(wav_path):
    """Qwen3-ASR 整段转录（Metal），返回纯文本。"""
    log("转录中(Qwen3-ASR)...")
    r = _load_qwen().transcribe(wav_path)
    return (getattr(r, "text", "") or "").strip()
```
把原 `transcribe`（270–277 行）整体替换为：
```python
def transcribe(wav_path):
    """整段转录：Qwen3-ASR 主，失败回退 whisper。返回纯文本。"""
    try:
        txt = transcribe_qwen(wav_path)
        if txt:
            return txt
        log("Qwen 返回空，回退 whisper")
    except Exception as e:
        log(f"Qwen 转录失败({str(e)[:80]})，回退 whisper")
    return transcribe_whisper(wav_path)
```
把 `transcribe_whisper`（308 行起）改为返回**纯文本**并加抗重复参数：找到其中 `result = mlx_whisper.transcribe(...)` 一行，改为
```python
        result = mlx_whisper.transcribe(wav_path, path_or_hf_repo=MODEL_WHISPER,
                                        language="zh", condition_on_previous_text=False)
```
并让函数 `return "".join(s["text"] for s in result["segments"]).strip()`（替换其原本返回 segs 的结尾；若原本经 `_clean_segments` 处理 segs，改为对 `result["segments"]` 先过滤 `_is_hallu` 再拼文本）。

- [ ] **Step 4: 跑测试确认通过**

Run: `venv/bin/python tests/test_transcribe_engine.py -v`
Expected: 3 项 PASS。

- [ ] **Step 5: 提交**

```bash
git add process.py tests/test_transcribe_engine.py
git commit -m "feat: 转录改 Qwen3-ASR 主/whisper 兜底，返回纯文本"
```

---

### Task 3: `make_segmented_transcript()` — LLM 主题分段整理稿

**Files:**
- Modify: `process.py`（新增函数；复用 `_ask`）
- Test: `tests/test_segmented_transcript.py`（新建）

**Interfaces:**
- Consumes: `_ask(system, user, max_tokens)`（已存在，482 行）。
- Produces: `make_segmented_transcript(transcript: str) -> str`：返回带小标题的分段 Markdown；空输入返回 `""`。

- [ ] **Step 1: 写失败测试**

`tests/test_segmented_transcript.py`：
```python
import importlib, sys
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT))
def load():
    sys.modules.pop("process", None); return importlib.import_module("process")

def test_segments_via_llm():
    process = load()
    with mock.patch.object(process, "log"), \
         mock.patch.object(process, "_ask", return_value="## 话题一\n内容...") as a:
        out = process.make_segmented_transcript("说了一大坨没有分段的转录文本")
    assert "## 话题一" in out
    assert a.call_count >= 1

def test_empty_returns_empty():
    process = load()
    with mock.patch.object(process, "log"):
        assert process.make_segmented_transcript("   ") == ""
```

- [ ] **Step 2: 跑测试确认失败**

Run: `venv/bin/python tests/test_segmented_transcript.py -v`
Expected: FAIL（函数不存在）。

- [ ] **Step 3: 实现**

在 `process.py` 新增（放在 `summarize` 附近）：
```python
SEGMENT_SYS = (
    "你在把一段会议转录整理成【分段整理稿】(不是摘要,不删内容)。转录无标点分段、有少量错字。\n"
    "请:1) 按话题切分为若干段,每段前加一个简短小标题(## 开头);2) 段内补标点、修明显同音错字、"
    "删口水重复,但不概括、不删信息;3) 不凭空添加没出现的内容;4) 只输出整理稿正文。")

def make_segmented_transcript(transcript):
    """把整段转录整理成带小标题的分段可读稿(无说话人)。"""
    if not transcript.strip():
        return ""
    log("生成分段整理稿...")
    parts = []
    for i, c in enumerate(_chunk_text(transcript, 6000), 1):
        parts.append(_ask(SEGMENT_SYS, c, 6000))
    return "\n\n".join(p for p in parts if p).strip()
```
并新增一个简单分块工具（替代已删的 `_split_chunks`）：
```python
def _chunk_text(text, size):
    """按长度粗分块(在句末标点就近切),供 LLM 加工超长文本。"""
    if len(text) <= size:
        return [text]
    out, i = [], 0
    while i < len(text):
        j = min(i + size, len(text))
        k = max((text.rfind(p, i + size // 2, j) for p in "。！？；\n"), default=-1)
        if k > i:
            j = k + 1
        out.append(text[i:j]); i = j
    return out
```

- [ ] **Step 4: 跑测试确认通过**

Run: `venv/bin/python tests/test_segmented_transcript.py -v`
Expected: 2 项 PASS。

- [ ] **Step 5: 提交**

```bash
git add process.py tests/test_segmented_transcript.py
git commit -m "feat: 新增 LLM 主题分段整理稿 make_segmented_transcript"
```

---

### Task 4: `summarize_perperson()` — 按人归纳纪要

**Files:**
- Modify: `process.py`（新增 `summarize_perperson`；旧 `summarize` 保留供参考或删，见 Task 6）
- Test: `tests/test_summarize_perperson.py`（新建）

**Interfaces:**
- Consumes: `_ask`。
- Produces: `summarize_perperson(transcript: str) -> str`：返回含「按参会人归纳/会议决策/待办/未明确归属」的 Markdown 纪要。

- [ ] **Step 1: 写失败测试**

`tests/test_summarize_perperson.py`：
```python
import importlib, sys
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT))
def load():
    sys.modules.pop("process", None); return importlib.import_module("process")

def test_perperson_prompt_and_passthrough():
    process = load()
    captured = {}
    def fake_ask(system, user, max_tokens=4000):
        captured["system"] = system; return "# 会议纪要\n## 按参会人归纳\n..."
    with mock.patch.object(process, "log"), mock.patch.object(process, "_ask", side_effect=fake_ask):
        out = process.summarize_perperson("转录文本")
    assert "按参会人" in captured["system"]      # 用的是按人归纳提示词
    assert out.startswith("# 会议纪要")
```

- [ ] **Step 2: 跑测试确认失败**

Run: `venv/bin/python tests/test_summarize_perperson.py -v`
Expected: FAIL（函数不存在）。

- [ ] **Step 3: 实现**

在 `process.py` 新增（提示词用已实测有效的那版）：
```python
PERPERSON_SYS = (
    "你是会议纪要专家。下面是一场会议的完整转录(内容较准,但无说话人标注,有少量错字)。请:\n"
    "1) 尽力从上下文识别每位参会人(有自称/被点名的用名字,否则用「负责X的人」);\n"
    "2) 【按参会人归纳】逐个列出其核心汇报/发言要点与负责事项;\n"
    "3) 单列【会议决策】;4) 单列【待办事项】(任务|负责人);\n"
    "5) 实在无法归属的重要内容放【未明确归属的要点】。\n"
    "实事求是,不编造没出现的人或事,不确定就注明。以 Markdown 输出,首行为 `# 会议纪要`。")

def summarize_perperson(transcript):
    """按参会人归纳纪要(软归属,不依赖说话人分离)。"""
    log("生成按人归纳纪要...")
    return _clean_notes(_ask(PERPERSON_SYS, transcript, 4000))
```

- [ ] **Step 4: 跑测试确认通过**

Run: `venv/bin/python tests/test_summarize_perperson.py -v`
Expected: PASS。

- [ ] **Step 5: 提交**

```bash
git add process.py tests/test_summarize_perperson.py
git commit -m "feat: 新增按人归纳纪要 summarize_perperson"
```

---

### Task 5: 重写 `main()` — 新产物(纪要 + 整理稿)，去分离/去逐字稿

**Files:**
- Modify: `process.py`（`main`，537 行起）
- Test: `tests/test_main_artifacts.py`（新建）

**Interfaces:**
- Consumes: `transcribe`, `summarize_perperson`, `make_segmented_transcript`, `save_to_obsidian`。
- Produces: 处理后在 `output/` 生成 `{stamp}_{name}_转录.txt`(原始)、`{stamp}_{name}_整理稿.md`、`{stamp}_{name}_纪要.md`；Obsidian 写入纪要。

- [ ] **Step 1: 写失败测试**

`tests/test_main_artifacts.py`（mock 掉转录/LLM/ffmpeg/搬移，断言三个产物文件写出）：
```python
import importlib, sys, os
from pathlib import Path
from unittest import mock
ROOT = Path(__file__).resolve().parents[1]; sys.path.insert(0, str(ROOT))
def load():
    sys.modules.pop("process", None); return importlib.import_module("process")

def test_main_writes_three_artifacts(tmp_path=None):
    process = load()
    out = ROOT / "output"
    with mock.patch.object(process, "log"), mock.patch.object(process, "pet_launch"), \
         mock.patch.object(process, "pet_set"), mock.patch.object(process, "pet_summary_progress"), \
         mock.patch.object(process, "notify"), \
         mock.patch("subprocess.run"), mock.patch("shutil.move"), mock.patch("os.remove"), \
         mock.patch.object(process, "transcribe", return_value="转录文本"), \
         mock.patch.object(process, "make_segmented_transcript", return_value="## 段\n整理"), \
         mock.patch.object(process, "summarize_perperson", return_value="# 会议纪要\n内容"), \
         mock.patch.object(process, "save_to_obsidian", return_value=False), \
         mock.patch("os.path.exists", return_value=True):
        process.main("/x/测试录音.m4a")
    files = list(out.glob("*测试录音*"))
    names = " ".join(f.name for f in files)
    assert "_转录.txt" in names and "_整理稿.md" in names and "_纪要.md" in names
    for f in files:  # 清理本测试产物
        f.unlink()
```

- [ ] **Step 2: 跑测试确认失败**

Run: `venv/bin/python tests/test_main_artifacts.py -v`
Expected: FAIL（main 仍走旧的分离/逐字稿逻辑，产物名不含 `_整理稿.md`）。

- [ ] **Step 3: 实现**

把 `main` 中「转录→分离→label→summarize→make_record→拼 notes→写文件」那段（约 542–571 行）替换为：
```python
    wav = os.path.join(OUTPUT, f".tmp_{stamp}.wav")
    subprocess.run([FFMPEG, "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", wav],
                   check=True, capture_output=True)

    transcript = transcribe(wav)                     # Qwen 主 / whisper 兜底(纯文本)
    pet_set("summarize", name, 10)

    raw_path = os.path.join(OUTPUT, f"{stamp}_{name}_转录.txt")
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(transcript)

    tidy = make_segmented_transcript(transcript)     # 分段整理稿
    tidy_path = os.path.join(OUTPUT, f"{stamp}_{name}_整理稿.md")
    with open(tidy_path, "w", encoding="utf-8") as f:
        f.write(tidy + "\n")

    notes = summarize_perperson(transcript)          # 按人归纳纪要
    out_path = os.path.join(OUTPUT, f"{stamp}_{name}_纪要.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(notes)
    log(f"完成: {out_path}")
    pet_summary_progress(98)

    saved = save_to_obsidian(name, notes, os.path.basename(audio_path))
    pet_summary_progress(100)
```
（保留其后 `os.remove(wav)` / `shutil.move` 归档 / `notify` / `pet_set("done")` 不变。）

- [ ] **Step 4: 跑测试确认通过**

Run: `venv/bin/python tests/test_main_artifacts.py -v`
Expected: PASS（三个产物文件名齐全）。

- [ ] **Step 5: 提交**

```bash
git add process.py tests/test_main_artifacts.py
git commit -m "feat: main 产出 纪要+分段整理稿+原始转录，去除分离与逐字稿"
```

---

### Task 6: 删除死代码(FluidAudio/说话人/逐字稿) + 清理测试与脚本

**Files:**
- Modify: `process.py`（删除多个函数与常量）
- Delete: `scripts/provision_fluidaudio.sh`, `scripts/build_fluidaudio_from_source.sh`, `scripts/build_fluidaudio_release_asset.sh`, `tests/test_provision_fluidaudio.sh`, `tests/test_build_fluidaudio_from_source.sh`, `tests/test_build_fluidaudio_release_asset.sh`, `tests/test_record_fallback.py`
- Modify: `tests/test_process_paths.py`（若引用了被删符号则同步改）

**Interfaces:**
- Produces: `process.py` 不再定义/调用 `diarize`, `label_transcript`, `transcribe_paraformer`, `make_record`, `_repair_record_labels`, `_split_chunks`, `_format_record_spacing`, `_load_diarization`, `_wav_duration`, `DIARIZE_BIN`, `RECORD_SYS_SPK/PLAIN`, `LONG_DIARIZATION_SECONDS`, `SPEAKER_MERGE_COSINE`；`import process` 干净。

- [ ] **Step 1: 删除 process.py 中的死函数与常量**

删除这些定义：`DIARIZE_BIN`(29)、`LONG_DIARIZATION_SECONDS`、`SPEAKER_MERGE_COSINE`、`RECORD_SYS_SPK/RECORD_SYS_PLAIN`(83–91)、`_split_chunks`(94)、`_repair_record_labels`(135)、`_format_record_spacing`(159)、`transcribe_paraformer`(279)、`_wav_duration`(328)、`_load_diarization`(336)、`diarize`(399)、`label_transcript`(449)、`make_record`(505)、以及旧 `summarize`(490，若已被 `summarize_perperson` 取代)。保留 `_is_hallu`、`_clean_segments`、`transcribe_whisper`、`_ask`、`_clean_notes`、`_chunk_text`。

- [ ] **Step 2: 删除相关脚本与测试文件**

```bash
git rm scripts/provision_fluidaudio.sh scripts/build_fluidaudio_from_source.sh scripts/build_fluidaudio_release_asset.sh \
       tests/test_provision_fluidaudio.sh tests/test_build_fluidaudio_from_source.sh \
       tests/test_build_fluidaudio_release_asset.sh tests/test_record_fallback.py
```

- [ ] **Step 3: 确认 import 干净 + 无残留引用**

Run:
```bash
venv/bin/python -c "import process; print('import ok')"
grep -nE "diarize|make_record|transcribe_paraformer|DIARIZE_BIN|label_transcript" process.py || echo "无残留引用"
```
Expected: 打印 `import ok` 与 `无残留引用`。

- [ ] **Step 4: 跑全部 Python 测试确保没连带打破**

Run: `for t in tests/test_*.py; do echo "== $t"; venv/bin/python "$t" || break; done`
Expected: 每个测试文件 OK（`test_process_paths.py`、Task2–5 新测试均通过）。若 `test_process_paths.py` 引用了被删符号，改掉对应断言后再跑。

- [ ] **Step 5: 提交**

```bash
git add -A
git commit -m "refactor: 移除 FluidAudio 说话人分离与逐字稿相关死代码与测试"
```

---

### Task 7: 真机端到端验收（真实录音）

**Files:**
- 无代码改动；产出验收记录（可写入 `docs/superpowers/sdd/` 或口头汇报）。

**Interfaces:**
- Consumes: 完整改造后的 `process.py`。

- [ ] **Step 1: 准备一段真实中英混录音**

用已有的 `done/工业智能语义基座会议纪要.m4a`（或另一段真实会议）。

- [ ] **Step 2: 跑真实处理**

Run:
```bash
cd /Users/moxiuwen/workspace/MeetingNotes
source ./config.local.sh 2>/dev/null || true
cp "done/工业智能语义基座会议纪要.m4a" inbox/验收.m4a
venv/bin/python -c "import process; process.main('inbox/验收.m4a')"
```
Expected: 无异常；`output/` 出现 `*验收_转录.txt`、`*验收_整理稿.md`、`*验收_纪要.md`。

- [ ] **Step 3: 人工核对质量(关键项)**

Run: `grep -c -e InfluxDB -e 清源 output/*验收_转录.txt`
Expected: 关键实体正确出现（InfluxDB/清源 命中）；`_纪要.md` 含「按参会人归纳/会议决策/待办」；`_整理稿.md` 有 `##` 小标题分段、可读。

- [ ] **Step 4: 兜底路径抽查(可选)**

临时让 Qwen 失效以确认回退：
```bash
venv/bin/python -c "import process; process.transcribe_qwen=lambda w:(_ for _ in ()).throw(RuntimeError('x')); print(len(process.transcribe('output/.tmp_probe.wav')) if False else 'skip')"
```
或在 Task 2 单测已覆盖，此步可略。

- [ ] **Step 5: 清理验收产物**

```bash
rm -f output/*验收_* done/验收.m4a
```

---

## Self-Review

- **Spec coverage:** 主转录换 Qwen(Task2)✓；Whisper 兜底(Task2)✓；移除分离/FluidAudio(Task6)✓；移除逐字稿 make_record(Task6)✓；分段整理稿(Task3)✓；按人归纳纪要(Task4)✓；bf16 模型(Task2 常量)✓；venv 重建 mlx0.31+(Task1)✓；保留原始转录 `_转录.txt`(Task5)✓；隐私不变(仅文本发 LLM，Task4/5)✓；朋友打包=超范围(Global Constraints 声明)✓。
- **Placeholder scan:** 无 TODO/TBD；每个 code step 含真实代码。
- **Type consistency:** `transcribe()` 全流程按返回 `str` 使用（Task2 定义、Task5 main 消费一致）；`_chunk_text(text,size)` 在 Task3 定义、Task3 使用；`summarize_perperson`/`make_segmented_transcript` 名称在 Task4/3/5 一致。
- 已知风险:mlx-whisper 0.4.3 在 mlx 0.31+ 上曾见重复/异常;因其仅为兜底,Task2 已加 `condition_on_previous_text=False` 缓解,若仍不稳作为已知兜底降级项(不阻塞自用主路径 Qwen)。
