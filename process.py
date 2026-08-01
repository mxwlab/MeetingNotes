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
    """Qwen3-ASR 整段转录（Metal），返回纯文本。

    转录放后台线程，主线程按「已用时/预估总时」上报进度（qwen3-asr-mlx
    无内部进度钩子）。单次 transcribe 调用，不影响质量，仅避免小猫/日志看着不动。"""
    log("转录中(Qwen3-ASR)...")
    import threading, time
    try:
        with wave.open(wav_path) as w:
            audio_sec = w.getnframes() / (w.getframerate() or 16000)
    except Exception:
        audio_sec = 0
    est_total = max(30.0, audio_sec * 0.22)   # 经验实时率 ≈0.22（Metal）
    box = {}
    def _run():
        try:
            box["r"] = _load_qwen().transcribe(wav_path)
        except Exception as e:
            box["err"] = e
    th = threading.Thread(target=_run, daemon=True)
    t0 = time.time(); th.start()
    last_log = 0.0
    while th.is_alive():
        elapsed = time.time() - t0
        pet_progress(min(95, int(elapsed / est_total * 100)))
        if elapsed - last_log >= 30:          # 日志每 ~30s 也动一下
            log(f"转录中(Qwen3-ASR) {min(95, int(elapsed / est_total * 100))}%…")
            last_log = elapsed
        th.join(timeout=2)
    if "err" in box:
        raise box["err"]
    pet_progress(100)
    r = box.get("r")
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

def _ask(system, user, max_tokens=4000):
    resp = client.chat.completions.create(
        model=LLM_MODEL, temperature=0.3, max_tokens=max_tokens,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
    )
    c = resp.choices[0].message.content or ""
    return re.sub(r"<think>.*?</think>", "", c, flags=re.S).strip()

def _chunk_text(text, size):
    """按长度粗分块（在句末标点就近切），供 LLM 加工超长文本。"""
    if len(text) <= size:
        return [text]
    out, i = [], 0
    while i < len(text):
        j = min(i + size, len(text))
        if j < len(text):
            k = max((text.rfind(p, i + size // 2, j) for p in "。！？；\n"), default=-1)
            if k > i:
                j = k + 1
        out.append(text[i:j])
        i = j
    return out

SEGMENT_SYS = (
    "你在把一段会议转录整理成【分段整理稿】(不是摘要,不删内容)。转录无标点分段、有少量错字。\n"
    "请:1) 按话题切分为若干段,每段前加一个简短小标题(## 开头);2) 段内补标点、修明显同音错字、"
    "删口水重复,但不概括、不删信息;3) 不凭空添加没出现的内容;4) 只输出整理稿正文。")

def make_segmented_transcript(transcript):
    """把整段转录整理成带小标题的分段可读稿(无说话人)。"""
    if not transcript.strip():
        return ""
    log("生成分段整理稿...")
    parts = [_ask(SEGMENT_SYS, c, 6000) for c in _chunk_text(transcript, 6000)]
    return "\n\n".join(p for p in parts if p).strip()

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

    # 转 16k 单声道 wav
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
