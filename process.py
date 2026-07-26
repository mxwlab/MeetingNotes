#!/usr/bin/env python3
import sys, os, datetime, shutil, subprocess, json, re, string
from collections import Counter

# 国内直连 huggingface.co 不稳定，默认走镜像（已设 HF_ENDPOINT 时不覆盖）
os.environ.setdefault("HF_ENDPOINT", "https://hf-mirror.com")

from openai import OpenAI

BASE = os.path.expanduser("~/MeetingNotes")
DONE = os.path.join(BASE, "done")
OUTPUT = os.path.join(BASE, "output")

# 纪要同时落一份到 Obsidian vault 的「会议纪要」文件夹（vault 不存在则跳过，不影响主流程）
OBSIDIAN_DIR = os.path.expanduser("~/Documents/Obsidian Vault/会议纪要")

FFMPEG = "/opt/homebrew/bin/ffmpeg"
# FluidAudio 说话人分离 CLI（本地 Apple 神经引擎，pyannote-community 流水线）；不存在则退回无说话人
DIARIZE_BIN = os.path.join(BASE, "tools", "FluidAudio", ".build", "release", "fluidaudiocli")

# 模型已用 curl 下到本地目录，优先从本地读，避免每次联网下载卡住；
# 本地不存在时回退到 HF 仓库名（走镜像下载）。
_LOCAL_MODEL = os.path.join(BASE, "models", "whisper-large-v3-mlx")
MODEL_WHISPER = _LOCAL_MODEL if os.path.exists(os.path.join(_LOCAL_MODEL, "weights.npz")) \
    else "mlx-community/whisper-large-v3-mlx"

client = OpenAI(
    api_key=os.environ.get("DEEPSEEK_API_KEY"),
    base_url="https://api.deepseek.com",
)
LLM_MODEL = "deepseek-v4-flash"

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
    "5) 严格按「说话人X：内容」逐行输出，不加标题、不寒暄。")
RECORD_SYS_PLAIN = (
    "你在整理会议的【逐字记录】，不是摘要。输入有识别错字、噪音字、缺标点。\n"
    "请：1) 保留全部内容，不概括不删减；2) 补标点、合理分段、修同音错字、删噪音字和口水重复；"
    "3) 听不清/拿不准处加「[?…]」；4) 不凭空加没出现的句子；5) 只输出整理后的正文，不加标题、不寒暄。")

def _split_chunks(text, size=3000):
    if len(text) <= size:
        return [text]
    parts, cur = [], ""
    for line in text.split("\n"):
        if len(cur) + len(line) + 1 > size and cur:
            parts.append(cur); cur = ""
        cur += line + "\n"
        while len(cur) > size:
            parts.append(cur[:size]); cur = cur[size:]
    if cur.strip():
        parts.append(cur)
    return parts

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
    状态文件三行：状态 / 录音名 / 进度百分比(转录时用，其余留空)。"""
    try:
        with open(PET_STATE, "w", encoding="utf-8") as f:
            f.write(f"{state}\n{name}\n{'' if pct is None else int(pct)}\n")
    except Exception:
        pass

def pet_progress(pct):
    pet_set("transcribe", _pet_name, pct)

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

def transcribe(wav_path):
    """转录并返回过滤后的分段 [{start,end,text},...]（带时间戳，供说话人分离对齐）。
    优先本地 Paraformer（中文更好，跑 ANE）；不可用/失败则退回 whisper。"""
    segs = transcribe_paraformer(wav_path)
    if segs is None:
        log("Paraformer 不可用/失败，退回 whisper")
        segs = transcribe_whisper(wav_path)
    return segs

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
        result = mlx_whisper.transcribe(wav_path, path_or_hf_repo=MODEL_WHISPER, language="zh")
    finally:
        if orig is not None:
            tmod.tqdm = orig
    segs = _clean_segments(result.get("segments") or [])
    if not segs and result.get("text"):        # 兜底：无分段就整段
        segs = [{"start": 0, "end": 0, "text": result["text"].strip()}]
    return segs

def diarize(wav_path):
    """FluidAudio 说话人分离，返回 [(start,end,speaker),...]；不可用/失败返回 None（退回无说话人）。"""
    if not os.path.exists(DIARIZE_BIN):
        return None
    out_json = wav_path + ".diar.json"
    try:
        subprocess.run([DIARIZE_BIN, "process", wav_path, "--output", out_json, "--threshold", "0.7"],
                       check=True, capture_output=True, timeout=600)
        d = json.load(open(out_json, encoding="utf-8"))
        turns = [(s["startTimeSeconds"], s["endTimeSeconds"], str(s["speakerId"]))
                 for s in d.get("segments", [])]
        return turns or None
    except Exception as e:
        log(f"说话人分离失败，退回无说话人：{str(e)[:80]}")
        return None
    finally:
        try:
            os.remove(out_json)
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
    prompt = PROMPT.format(transcript=transcript)
    if has_speakers:
        prompt = ("注意：转录文本已按说话人分行标注（说话人A/B/C…），"
                  "请在纪要中体现是谁提出、谁负责、谁拍板。\n\n") + prompt
    resp = client.chat.completions.create(
        model=LLM_MODEL,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.3,
    )
    return _clean_notes(resp.choices[0].message.content)

def make_record(transcript, has_speakers):
    """会议全程逐字记录：分块让 LLM 修错字补标点、忠实还原（不概括）。"""
    log("生成会议全程...")
    sysmsg = RECORD_SYS_SPK if has_speakers else RECORD_SYS_PLAIN
    chunks = _split_chunks(transcript, 3000)
    parts = []
    for i, c in enumerate(chunks, 1):
        log(f"会议全程 {i}/{len(chunks)} 块")
        parts.append(_ask(sysmsg, c, 5000))
    return "\n".join(p for p in parts if p).strip()


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

    pet_set("summarize", name)
    turns = diarize(wav)                          # 说话人分离（快，约十几秒）
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

    saved = save_to_obsidian(name, notes, os.path.basename(audio_path))

    try:
        os.remove(wav)
    except OSError:
        pass
    shutil.move(audio_path, os.path.join(DONE, os.path.basename(audio_path)))
    notify(f"✅ 纪要已生成{'并存入 Obsidian' if saved else ''}：{name}")
    pet_set("done", name)


def save_to_obsidian(name, notes, audio_filename):
    """把纪要写进 Obsidian vault 的会议纪要文件夹，带 frontmatter 便于检索。成功返回 True。"""
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
