#!/usr/bin/env python3
import sys, os, datetime, shutil, subprocess, json, re, string, wave, math
from collections import Counter

# 国内直连 huggingface.co 不稳定，默认走镜像（已设 HF_ENDPOINT 时不覆盖）
os.environ.setdefault("HF_ENDPOINT", "https://huggingface.co")

from openai import OpenAI

BASE = os.path.dirname(os.path.abspath(__file__))  # 项目根 = 本文件所在目录（随项目移动，无需改路径）
DONE = os.path.join(BASE, "done")
OUTPUT = os.path.join(BASE, "output")

# 未设置时保留作者现有默认值；显式设置为空串时跳过 Obsidian 同步。
_obsidian_dir = os.environ.get("OBSIDIAN_DIR")
OBSIDIAN_DIR = (
    os.path.expanduser("~/Documents/Obsidian Vault/会议纪要")
    if _obsidian_dir is None
    else os.path.expanduser(_obsidian_dir)
)

_project_ffmpeg = os.path.join(BASE, "bin", "ffmpeg")
FFMPEG = (
    _project_ffmpeg
    if os.path.isfile(_project_ffmpeg) and os.access(_project_ffmpeg, os.X_OK)
    else shutil.which("ffmpeg") or "/opt/homebrew/bin/ffmpeg"
)
# FluidAudio 说话人分离 CLI（本地 Apple 神经引擎，pyannote-community 流水线）；不存在则退回无说话人
DIARIZE_BIN = os.path.join(BASE, "tools", "FluidAudio", ".build", "release", "fluidaudiocli")
# 长录音不能只按 10 秒流式切块，否则声纹身份可能随时间漂移。
# 先用流式模式判断是否为多人，再用离线全局聚类统一整场身份。
LONG_DIARIZATION_SECONDS = 20 * 60
# 离线模型偶尔会把同一人的不同录音状态拆成多个类；声纹中心高于此相似度时合并。
SPEAKER_MERGE_COSINE = 0.88

# 模型已用 curl 下到本地目录，优先从本地读，避免每次联网下载卡住；
# 本地不存在时回退到 HF 仓库名（走镜像下载）。
_LOCAL_MODEL = os.path.join(BASE, "models", "whisper-large-v3-mlx")
MODEL_WHISPER = _LOCAL_MODEL if os.path.exists(os.path.join(_LOCAL_MODEL, "weights.npz")) \
    else "mlx-community/whisper-large-v3-mlx"

# 主转录：Qwen3-ASR（Apple Silicon / Metal，整段，无时间戳）。
_QWEN_MODEL_ID = "mlx-community/Qwen3-ASR-1.7B-bf16"
_qwen_model = None
def _load_qwen():
    global _qwen_model
    if _qwen_model is None:
        from qwen3_asr_mlx import Qwen3ASR
        _qwen_model = Qwen3ASR.from_pretrained(_QWEN_MODEL_ID)
    return _qwen_model

LLM_BASE_URL = os.environ.get("LLM_BASE_URL", "https://api.deepseek.com")
# 默认用非推理模型 deepseek-chat：逐字整理/结构化摘要不需要推理，
# 而推理模型（如 deepseek-v4-flash）会把 token 预算耗在推理上导致正文为空。
LLM_MODEL = os.environ.get("LLM_MODEL", "deepseek-chat")

client = OpenAI(
    api_key=os.environ.get("DEEPSEEK_API_KEY"),
    base_url=LLM_BASE_URL,
)

PROMPT = """你是资深会议纪要撰写者。下面是一段会议录音的转录文本，可能有口语、重复、语音识别错别字。
请整理成结构化的中文会议纪要，用 Markdown 输出。严格按下面的结构，不要寒暄、不要编造：

# 一句话摘要
（一句话概括本次会议的核心）

# 会议主题

# 参会人
（能从文本推断则列出，否则写"无"）

# 讨论要点
（按话题分条，每条一句话概括各方观点）

# 决议事项
（明确的决定；没有就写"本次无明确决议"）

# 待办事项
用表格：| 任务 | 负责人 | 截止时间 |（没有期限写"—"）

# 风险 / 待澄清
（遗留问题或需进一步确认的点；没有则省略本节）

要求：忠于原文，不编造；修正明显的识别错别字；口语化内容提炼成书面表达。

转录文本如下：
---
{transcript}
---"""

# 「会议全程」逐字记录提示词：忠实还原、不概括，顺手修错字补标点
RECORD_SYS_SPK = (
    "你在整理会议的【逐字记录】，不是摘要。输入每行以「说话人X：」标注，有识别错字、噪音字、缺标点。\n"
    "请：1) 逐行保留每人全部内容，不概括不删减不合并不同人；2) 补标点、修同音错字、删噪音字和口水重复；"
    "3) 听不清/拿不准处就地加「[?…]」写你的判断或存疑；4) 不凭空加没出现的句子；"
    "5) 严格按「说话人X：内容」逐行输出，不加标题、不寒暄；"
    "6) A/B/C 等标签必须与输入完全一致，绝对不能改成说话人1/2/3 或其他新标签。")
RECORD_SYS_PLAIN = (
    "你在整理会议的【逐字记录】，不是摘要。输入有识别错字、噪音字、缺标点。\n"
    "请：1) 保留全部内容，不概括不删减；2) 补标点、合理分段、修同音错字、删噪音字和口水重复；"
    "3) 听不清/拿不准处加「[?…]」；4) 不凭空加没出现的句子；5) 只输出整理后的正文，不加标题、不寒暄。")

def _split_chunks(text, size=3000):
    """按长度分块；带说话人标签的长行在每个续块前重复原标签。

    不能直接从长行中间硬切，否则后续块看不到「说话人A：」，
    整理模型可能擅自创造「说话人1」等新标签。
    """
    if len(text) <= size:
        return [text]
    units = []
    for line in text.splitlines():
        match = re.match(r"^(说话人[^：:\n]+[：:])", line)
        prefix = match.group(1) if match else ""
        body = line[len(prefix):]
        budget = max(1, size - len(prefix) - 1)
        if len(line) <= size:
            units.append(line)
            continue
        while len(body) > budget:
            cut = budget
            # 尽量在后 1/3 的中文标点处切，减少从半句话开始的续块。
            floor = budget * 2 // 3
            candidates = [body.rfind(mark, floor, budget) for mark in "。！？；，"]
            best = max(candidates)
            if best >= floor:
                cut = best + 1
            units.append(prefix + body[:cut])
            body = body[cut:]
        if body:
            units.append(prefix + body)

    parts, cur = [], ""
    for unit in units:
        if cur and len(cur) + len(unit) + 1 > size:
            parts.append(cur.rstrip())
            cur = ""
        cur += unit + "\n"
    if cur.strip():
        parts.append(cur.rstrip())
    return parts


def _repair_record_labels(text, source_chunk):
    """只允许输出使用输入块中真实存在的说话人标签。"""
    allowed = list(dict.fromkeys(
        re.findall(r"(?m)^(说话人[^：:\n]+)[：:]", source_chunk)
    ))
    if not allowed:
        return text

    def replace(match):
        label = match.group(1)
        if label in allowed:
            return label + "："
        if len(allowed) == 1:
            return allowed[0] + "："
        numeric = re.fullmatch(r"说话人(\d+)", label)
        if numeric:
            index = int(numeric.group(1)) - 1
            if 0 <= index < len(allowed):
                return allowed[index] + "："
        return match.group(0)

    return re.sub(r"(?m)^(说话人[^：:\n]+)[：:]", replace, text)


def _format_record_spacing(text):
    """统一会议全程排版：每段说话人发言之间固定保留一行空白。"""
    text = text.strip()
    return re.sub(r"\n+(?=说话人[^：:\n]+[：:])", "\n\n", text)


# whisper 中文幻觉词（静音/噪声段容易吐这些视频平台口水话）
_HALLU = ["点赞", "订阅", "转发", "打赏", "明镜", "点点栏目", "字幕志愿者", "感谢观看",
          "谢谢观看", "请不吝", "关注我", "下期再见", "Amara", "字幕组", "请订阅", "多谢大家"]

def _is_hallu(text):
    """whisper 幻觉行（点赞订阅那类）/ 单字重复退化 → True 丢弃。"""
    t = re.sub(r"[，。！？、\s,.!?]", "", text)
    if len(t) < 2:
        return True
    if sum(p in text for p in _HALLU) >= 2:
        return True
    if len(t) >= 6 and Counter(t).most_common(1)[0][1] >= len(t) * 0.6:
        return True
    return False

def log(msg):
    print(f"[{datetime.datetime.now():%H:%M:%S}] {msg}", flush=True)

def notify(message, title="会议纪要", sound="Glass"):
    """弹一条 macOS 桌面通知，失败也不影响主流程。
    优先用 terminal-notifier（从 launchd 后台弹更可靠），没有则回退 osascript。"""
    tn = shutil.which("terminal-notifier") or "/opt/homebrew/bin/terminal-notifier"
    if os.path.exists(tn):
        try:
            subprocess.run([tn, "-title", title, "-message", message, "-sound", sound,
                            "-group", "meetingnotes"],
                           check=False, capture_output=True, timeout=10)
            return
        except Exception:
            pass
    try:
        script = (f"display notification {json.dumps(message)} "
                  f"with title {json.dumps(title)} sound name {json.dumps(sound)}")
        subprocess.run(["osascript", "-e", script],
                       check=False, capture_output=True, timeout=10)
    except Exception:
        pass

PET_STATE = os.path.join(BASE, ".pet_state")
PET_SCRIPT = os.path.join(BASE, "pet.py")
_pet_name = ""

def pet_set(state, name="", pct=None):
    """写状态文件驱动桌面小猫；小猫是锦上添花，任何异常都不影响主流程。
    状态文件三行：状态 / 录音名 / 进度百分比。"""
    try:
        with open(PET_STATE, "w", encoding="utf-8") as f:
            f.write(f"{state}\n{name}\n{'' if pct is None else int(pct)}\n")
    except Exception:
        pass

def pet_progress(pct):
    pet_set("transcribe", _pet_name, pct)

def pet_summary_progress(pct):
    pet_set("summarize", _pet_name, pct)

def pet_launch(name):
    """启动桌面小猫（detached，不阻塞主流程；失败静默）。"""
    global _pet_name
    _pet_name = name
    try:
        subprocess.run(["pkill", "-f", PET_SCRIPT], capture_output=True)  # 关掉上一只(如"完成"未关的)
    except Exception:
        pass
    pet_set("transcribe", name, 0)
    try:
        subprocess.Popen([sys.executable, PET_SCRIPT],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
    except Exception:
        pass

class _ProgressTqdm:
    """替换 mlx_whisper 内部的 tqdm，按帧数上报真实转录进度给小猫。
    只需支持它用到的：作为上下文管理器 + update(delta)。任何异常都吞掉，绝不影响转录。"""
    def __init__(self, *a, total=None, **k):
        self.total = total or 1
        self.n = 0
    def __enter__(self): return self
    def __exit__(self, *a): return False
    def update(self, delta):
        try:
            self.n += delta
            pet_progress(min(100, int(self.n / self.total * 100)))
        except Exception:
            pass
    def close(self): pass
    def set_description(self, *a, **k): pass
    def set_postfix(self, *a, **k): pass
    def refresh(self): pass

def _clean_segments(raw_segs):
    """过滤 whisper/paraformer 幻觉 + 折叠重复噪声字。raw_segs: [{start,end,text}]。"""
    segs, dropped = [], 0
    for s in raw_segs:
        t = re.sub(r"(.)\1{2,}", r"\1", (s.get("text") or "").strip())  # 嘶嘶嘶→嘶
        if t and not _is_hallu(t):
            segs.append({"start": s.get("start", 0), "end": s.get("end", 0), "text": t})
        else:
            dropped += len((s.get("text") or ""))
    if dropped > 0:
        log(f"反幻觉过滤：清掉约 {dropped} 字噪声/幻觉")
    return segs

def transcribe_qwen(wav_path):
    """Qwen3-ASR 整段转录（Metal），返回纯文本。"""
    log("转录中(Qwen3-ASR)...")
    r = _load_qwen().transcribe(wav_path)
    return (getattr(r, "text", "") or "").strip()

def transcribe(wav_path):
    """整段转录：Qwen3-ASR 主，失败回退 whisper。返回纯文本 str。"""
    try:
        txt = transcribe_qwen(wav_path)
        if txt:
            return txt
        log("Qwen 返回空，回退 whisper")
    except Exception as e:
        log(f"Qwen 转录失败({str(e)[:80]})，回退 whisper")
    return transcribe_whisper(wav_path)

def transcribe_paraformer(wav_path):
    """调 FluidAudio batch-transcribe（VAD 切段 + Paraformer 中文，本地 ANE）。失败返回 None。"""
    if not os.path.exists(DIARIZE_BIN):
        return None
    log("转录中(Paraformer)...")
    out_json = wav_path + ".asr.json"
    try:
        proc = subprocess.Popen([DIARIZE_BIN, "batch-transcribe", wav_path, "--output", out_json],
                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        for line in proc.stderr:                       # 逐段进度驱动小猫进度条
            m = re.search(r"PROGRESS (\d+)/(\d+)", line)
            if m:
                done, total = int(m.group(1)), max(1, int(m.group(2)))
                pet_progress(min(99, int(done / total * 100)))
        proc.wait()
        if proc.returncode != 0:
            log(f"Paraformer 退出码 {proc.returncode}")
            return None
        d = json.load(open(out_json, encoding="utf-8"))
        return _clean_segments(d.get("segments", [])) or None
    except Exception as e:
        log(f"Paraformer 异常：{str(e)[:80]}")
        return None
    finally:
        try:
            os.remove(out_json)
        except OSError:
            pass

def transcribe_whisper(wav_path):
    """whisper 兜底转录（带 tqdm 真实进度）。"""
    log(f"转录中(whisper): {os.path.basename(wav_path)}")
    import mlx_whisper, importlib, types
    tmod = importlib.import_module("mlx_whisper.transcribe")
    orig = getattr(tmod, "tqdm", None)
    try:
        tmod.tqdm = types.SimpleNamespace(tqdm=_ProgressTqdm)  # 打补丁拿真实进度
    except Exception:
        orig = None
    try:
        result = mlx_whisper.transcribe(wav_path, path_or_hf_repo=MODEL_WHISPER,
                                        language="zh", condition_on_previous_text=False)
    finally:
        if orig is not None:
            tmod.tqdm = orig
    segs = _clean_segments(result.get("segments") or [])
    text = "".join(s["text"] for s in segs).strip()
    return text or (result.get("text") or "").strip()

def _wav_duration(wav_path):
    try:
        with wave.open(wav_path, "rb") as f:
            return f.getnframes() / max(1, f.getframerate())
    except Exception:
        return 0


def _load_diarization(path, merge_similar=False):
    d = json.load(open(path, encoding="utf-8"))
    segments = d.get("segments", [])
    aliases = {}

    if merge_similar:
        # 每个初始类别计算按时长和质量加权的声纹中心，再合并明显属于同一人的类别。
        sums, weights = {}, {}
        for s in segments:
            sp = str(s["speakerId"])
            emb = s.get("embedding") or []
            norm = math.sqrt(sum(x * x for x in emb))
            if not emb or norm <= 0:
                continue
            duration = max(0.1, s["endTimeSeconds"] - s["startTimeSeconds"])
            weight = duration * max(0.01, s.get("qualityScore", 1.0))
            vec = [x / norm for x in emb]
            if sp not in sums:
                sums[sp] = [0.0] * len(vec)
                weights[sp] = 0.0
            for i, x in enumerate(vec):
                sums[sp][i] += x * weight
            weights[sp] += weight

        centers = {}
        for sp, total in sums.items():
            vec = [x / weights[sp] for x in total]
            norm = math.sqrt(sum(x * x for x in vec))
            if norm > 0:
                centers[sp] = [x / norm for x in vec]

        parent = {sp: sp for sp in centers}

        def root(sp):
            while parent[sp] != sp:
                parent[sp] = parent[parent[sp]]
                sp = parent[sp]
            return sp

        def union(a, b):
            ra, rb = root(a), root(b)
            if ra != rb:
                parent[rb] = ra

        speaker_ids = list(centers)
        for i, a in enumerate(speaker_ids):
            for b in speaker_ids[i + 1:]:
                similarity = sum(x * y for x, y in zip(centers[a], centers[b]))
                if similarity >= SPEAKER_MERGE_COSINE:
                    union(a, b)
        aliases = {sp: root(sp) for sp in centers}

        merged_count = len(set(aliases.values()))
        if merged_count < len(centers):
            log(f"全局声纹合并：{len(centers)} 类 → {merged_count} 人")

    return [
        (s["startTimeSeconds"], s["endTimeSeconds"],
         aliases.get(str(s["speakerId"]), str(s["speakerId"])))
        for s in segments
    ]


def diarize(wav_path):
    """FluidAudio 说话人分离。

    短录音使用快速流式模式；20 分钟以上改用离线全局聚类，
    避免长录音后半段发生说话人身份漂移。任一阶段失败均安全回退。
    """
    if not os.path.exists(DIARIZE_BIN):
        return None
    stream_json = wav_path + ".diar.stream.json"
    offline_json = wav_path + ".diar.offline.json"
    try:
        subprocess.run([DIARIZE_BIN, "process", wav_path, "--output", stream_json, "--threshold", "0.7"],
                       check=True, capture_output=True, timeout=600)
        stream_turns = _load_diarization(stream_json)
        if not stream_turns:
            return None

        duration = _wav_duration(wav_path)
        speakers = {sp for _, _, sp in stream_turns}
        if duration < LONG_DIARIZATION_SECONDS or len(speakers) < 2:
            return stream_turns

        log(f"长录音({duration / 60:.0f}分钟)：切换到全局说话人分离")
        try:
            subprocess.run([
                DIARIZE_BIN, "process", wav_path,
                "--mode", "offline",
                "--min-speakers", "2",
                "--max-speakers", "6",
                "--output", offline_json,
            ], check=True, capture_output=True, timeout=1200)
            offline_turns = _load_diarization(offline_json, merge_similar=True)
            if offline_turns:
                offline_speakers = len({sp for _, _, sp in offline_turns})
                log(f"全局说话人分离完成：自动识别 {offline_speakers} 人")
                return offline_turns
            log("全局说话人分离未返回片段，退回快速模式")
        except Exception as e:
            log(f"全局说话人分离失败，退回快速模式：{str(e)[:80]}")
        return stream_turns
    except Exception as e:
        log(f"说话人分离失败，退回无说话人：{str(e)[:80]}")
        return None
    finally:
        for path in (stream_json, offline_json):
            try:
                os.remove(path)
            except OSError:
                pass

def label_transcript(segs, turns):
    """把转录分段按时间归到说话人，合并连续同人 → 「说话人A：…」文本。
    turns 为空则返回无说话人纯文本。返回 (文本, 是否带说话人, 说话人数)。"""
    if not turns:
        return "".join(s["text"] for s in segs).strip(), False, 0

    def assign(seg):
        best, ov_best, near, nd = None, 0.0, None, 1e9
        mid = (seg["start"] + seg["end"]) / 2
        for st, en, sp in turns:
            ov = min(seg["end"], en) - max(seg["start"], st)
            if ov > ov_best:
                ov_best, best = ov, sp
            d = min(abs(mid - st), abs(mid - en))
            if d < nd:
                nd, near = d, sp
        return best or near

    rows = []
    for s in segs:
        sp = assign(s)
        if rows and rows[-1][0] == sp:
            rows[-1][1] += s["text"]
        else:
            rows.append([sp, s["text"]])
    order = {}
    for sp, _ in rows:
        if sp not in order:
            i = len(order)
            order[sp] = "说话人" + (string.ascii_uppercase[i] if i < 26 else str(i + 1))
    lines = [f"{order[sp]}：{txt.strip()}" for sp, txt in rows if txt.strip()]
    return "\n".join(lines), True, len(order)

def _ask(system, user, max_tokens=4000):
    resp = client.chat.completions.create(
        model=LLM_MODEL, temperature=0.3, max_tokens=max_tokens,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
    )
    c = resp.choices[0].message.content or ""
    return re.sub(r"<think>.*?</think>", "", c, flags=re.S).strip()

def summarize(transcript, has_speakers=False):
    log("生成会议纪要...")
    pet_summary_progress(20)
    prompt = PROMPT.format(transcript=transcript)
    if has_speakers:
        prompt = ("注意：转录文本已按说话人分行标注（说话人A/B/C…），"
                  "请在纪要中体现是谁提出、谁负责、谁拍板。\n\n") + prompt
    resp = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3,
    )
    pet_summary_progress(35)
    return _clean_notes(resp.choices[0].message.content)

def make_record(transcript, has_speakers):
    """会议全程逐字记录：分块让 LLM 修错字补标点、忠实还原（不概括）。"""
    log("生成会议全程...")
    sysmsg = RECORD_SYS_SPK if has_speakers else RECORD_SYS_PLAIN
    chunks = _split_chunks(transcript, 3000)
    parts = []
    for i, c in enumerate(chunks, 1):
        log(f"会议全程 {i}/{len(chunks)} 块")
        cleaned = _ask(sysmsg, c, 5000)
        # 安全网：LLM（尤其推理模型）可能把 token 预算耗在推理上、正文返回空；
        # 此时回退到原始转录该块，绝不让「会议全程」空白。
        if cleaned.strip():
            parts.append(_repair_record_labels(cleaned, c))
        else:
            log(f"会议全程第 {i} 块正文为空，回退原始转录")
            parts.append(c)
        pet_summary_progress(35 + round(i / len(chunks) * 60))
    return _format_record_spacing("\n".join(p for p in parts if p))


def _clean_notes(notes):
    """去掉模型有时加的开场白/代码围栏，让纪要从第一个标题开始。"""
    text = notes.strip()
    if text.startswith("```"):
        text = text.split("\n", 1)[-1]
        if text.rstrip().endswith("```"):
            text = text.rstrip()[:-3].rstrip()
    idx = text.find("# ")
    if idx > 0:
        text = text[idx:]
    return text.strip() + "\n"

def main(audio_path):
    if not os.path.exists(audio_path):
        log(f"文件不存在: {audio_path}"); return
    stamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    name = os.path.splitext(os.path.basename(audio_path))[0]

    # 开始/进度靠桌面小猫显示，不再发系统通知（只在完成/失败时通知，兜底离开工位的情况）
    pet_launch(name)

    # 转 16k 单声道 wav（whisper 与 FluidAudio 共用）
    wav = os.path.join(OUTPUT, f".tmp_{stamp}.wav")
    subprocess.run([FFMPEG, "-y", "-i", audio_path, "-ar", "16000", "-ac", "1", wav],
                   check=True, capture_output=True)

    segs = transcribe(wav)                       # 转录（带进度）

    pet_set("summarize", name, 0)
    turns = diarize(wav)                          # 说话人分离（快，约十几秒）
    pet_summary_progress(15)
    transcript, has_spk, nspk = label_transcript(segs, turns)
    if has_spk:
        log(f"说话人分离：{nspk} 人")

    raw_path = os.path.join(OUTPUT, f"{stamp}_{name}_转录.txt")
    with open(raw_path, "w", encoding="utf-8") as f:
        f.write(transcript)

    minutes = summarize(transcript, has_spk)      # 结构化纪要
    record = make_record(transcript, has_spk)     # 会议全程逐字记录
    notes = minutes.rstrip() + "\n\n---\n\n# 会议全程\n\n" + record + "\n"

    out_path = os.path.join(OUTPUT, f"{stamp}_{name}_纪要.md")
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(notes)
    log(f"完成: {out_path}")
    pet_summary_progress(98)

    saved = save_to_obsidian(name, notes, os.path.basename(audio_path))
    pet_summary_progress(100)

    try:
        os.remove(wav)
    except OSError:
        pass
    shutil.move(audio_path, os.path.join(DONE, os.path.basename(audio_path)))
    notify(f"✅ 纪要已生成{'并存入 Obsidian' if saved else ''}：{name}")
    pet_set("done", name)


def save_to_obsidian(name, notes, audio_filename):
    """把纪要写进 Obsidian vault 的会议纪要文件夹，带 frontmatter 便于检索。成功返回 True。"""
    if not OBSIDIAN_DIR:
        log("未配置 OBSIDIAN_DIR，跳过写入 Obsidian")
        return False
    vault_parent = os.path.dirname(OBSIDIAN_DIR)
    if not os.path.isdir(vault_parent):
        log(f"未找到 Obsidian vault({vault_parent})，跳过写入 Obsidian")
        return False
    os.makedirs(OBSIDIAN_DIR, exist_ok=True)
    today = datetime.date.today().isoformat()
    # 文件名用「录音名 日期」，同名（同日重复处理）则加时分秒
    md_name = f"{name} {today}.md"
    md_path = os.path.join(OBSIDIAN_DIR, md_name)
    if os.path.exists(md_path):
        md_path = os.path.join(OBSIDIAN_DIR, f"{name} {today} {datetime.datetime.now():%H%M%S}.md")
    frontmatter = (
        "---\n"
        "tags: [会议纪要]\n"
        f"date: {today}\n"
        f"source: {audio_filename}\n"
        "---\n\n"
    )
    with open(md_path, "w") as f:
        f.write(frontmatter + notes)
    log(f"已写入 Obsidian: {md_path}")
    return True

if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except Exception:
        name = os.path.splitext(os.path.basename(sys.argv[1]))[0]
        notify(f"❌ 处理失败：{name}，请查看日志", sound="Basso")
        pet_set("fail", name)
        raise
