#!/bin/zsh
# ── 发版前手动 e2e：验证「首次转录零联网即可成功」 ────────────────────────────
#
# 守的回归：安装只 provision 8bit 主模型时，运行时 transcribe() 会隐式再下
# Qwen3-ASR-0.6B（~1.8G）；不预置的话朋友首次转录临时联网、慢/受限网络卡 xet 假死。
# 本脚本把 HF 强制离线（HF_HUB_OFFLINE=1）后跑一次真实转录：若还能成功，证明
# 已装模型足够、首次运行不需要任何联网；若 0.6B 缺失，离线转录会失败 → 测试红。
#
# 默认复用本机已装实例的模型（不重新下 4G）。
# 用法：
#   tests/e2e/test_first_run_offline.sh                # 复用 ~/MeetingNotes 已装模型
#   MN_BASE=/path/to/install tests/e2e/...             # 指定安装目录
#   E2E_REAL_PROVISION=1 tests/e2e/...                 # 隔离沙盒真跑 provision（会下 4G）
#
set -eu

MN_BASE="${MN_BASE:-$HOME/MeetingNotes}"
PYTHON="${MEETINGNOTES_PYTHON:-$MN_BASE/venv/bin/python}"
FFMPEG="${FFMPEG:-$MN_BASE/bin/ffmpeg}"
MODEL_PATH="${QWEN_MODEL_PATH:-$MN_BASE/models/qwen3-asr-1.7b-8bit}"
COMPANION_DIR_NAME="models--Qwen--Qwen3-ASR-0.6B"

fail() { echo "❌ FAIL: $1" >&2; exit 1; }

[[ -x "$PYTHON" ]] || fail "找不到安装实例的 python: $PYTHON（先装好正式实例或用 MN_BASE 指定）"
command -v "$FFMPEG" >/dev/null 2>&1 || FFMPEG="$(command -v ffmpeg || true)"
[[ -n "$FFMPEG" ]] || fail "找不到 ffmpeg"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# ── 可选：隔离沙盒里真跑 provision（会真实下载 8bit + 0.6B 到隔离缓存） ──────────
if [[ "${E2E_REAL_PROVISION:-0}" == "1" ]]; then
  echo "[E2E] 真·provision 模式：隔离 HOME 全新下载模型（8bit + 0.6B）…"
  export HOME="$work/home"
  export HF_HOME="$work/home/.cache/huggingface"
  mkdir -p "$HOME"
  ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
  MEETINGNOTES_PYTHON="$PYTHON" QWEN_MODEL_DIR="$work/models/qwen3-asr-1.7b-8bit" \
    "$ROOT/scripts/provision_models.sh" || fail "provision_models.sh 执行失败"
  MODEL_PATH="$work/models/qwen3-asr-1.7b-8bit"
  HF_HUB_CACHE_DIR="$HF_HOME/hub"
else
  HF_HUB_CACHE_DIR="${HF_HOME:-$HOME/.cache/huggingface}/hub"
fi

# ── 前置：确认 provision 应产出的两个模型都在 ────────────────────────────────
[[ -f "$MODEL_PATH/config.json" ]] || fail "8bit 本地快照缺失: $MODEL_PATH（provision 未完成？）"
[[ -d "$HF_HUB_CACHE_DIR/$COMPANION_DIR_NAME" ]] \
  || fail "0.6B 配套模型未预置到 HF 缓存: $HF_HUB_CACHE_DIR/$COMPANION_DIR_NAME —— 这正是要防的回归"

# ── 造 5 秒测试音频 ──────────────────────────────────────────────────────────
wav="$work/probe5s.wav"
"$FFMPEG" -f lavfi -i "sine=frequency=440:duration=5" -ar 16000 -ac 1 "$wav" -y >/dev/null 2>&1 \
  || fail "ffmpeg 生成测试音频失败"

# ── 强制离线跑真实转录：成功=首次运行零联网可用 ─────────────────────────────
echo "[E2E] HF_HUB_OFFLINE=1 离线转录中（复用已装模型，不联网）…"
HF_HUB_OFFLINE=1 HF_HUB_DISABLE_XET=1 QWEN_MODEL_PATH="$MODEL_PATH" \
  "$PYTHON" - "$MODEL_PATH" "$wav" <<'PY' || fail "离线转录失败——说明首次运行仍需联网（很可能 0.6B 未预置）"
import sys, os
os.environ.setdefault("HF_ENDPOINT", "https://huggingface.co")
model_path, wav = sys.argv[1], sys.argv[2]
from mlx_qwen3_asr import load_model, transcribe
model, _ = load_model(model_path)
r = transcribe(wav, model=model, language="Chinese")
txt = getattr(r, "text", "") or ""
print(f"[E2E] 离线转录成功，返回文本长度={len(txt)}")
PY

echo "✅ PASS: 首次转录在完全离线下成功——已装模型足够，朋友首次使用不会因缺模型/xet 而卡死"
