#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
PYTHON="${MEETINGNOTES_PYTHON:-$BASE/venv/bin/python}"
MODEL_REPO="${WHISPER_MODEL_REPO:-mlx-community/whisper-large-v3-mlx}"
MODEL_DIR="$BASE/models/whisper-large-v3-mlx"
FLUIDAUDIO_BIN="$BASE/tools/FluidAudio/.build/release/fluidaudiocli"
FIXTURE="$BASE/tests/fixtures/tiny.wav"
export HF_ENDPOINT="${HF_ENDPOINT:-https://hf-mirror.com}"

echo "使用 HF_ENDPOINT=$HF_ENDPOINT"

[[ -x "$PYTHON" ]] || {
  echo "找不到项目 Python: $PYTHON（请先安装 requirements.txt）" >&2
  exit 1
}

download_model() {
  # $1 = 使用的 HF_ENDPOINT
  HF_ENDPOINT="$1" "$PYTHON" - "$MODEL_DIR" "$MODEL_REPO" <<'PY'
import sys
from huggingface_hub import snapshot_download

model_dir, repo_id = sys.argv[1:3]
snapshot_download(
    repo_id=repo_id,
    local_dir=model_dir,
    allow_patterns=["config.json", "weights.npz"],
)
PY
}

CANONICAL_HF="https://huggingface.co"

if [[ -f "$MODEL_DIR/config.json" && -f "$MODEL_DIR/weights.npz" ]]; then
  echo "Whisper MLX 模型已存在，跳过下载"
else
  echo "正在下载 Whisper MLX 模型: $MODEL_REPO（HF_ENDPOINT=$HF_ENDPOINT）"
  if ! download_model "$HF_ENDPOINT"; then
    # 常见于默认镜像（hf-mirror.com）对该仓库的 /resolve/ 返回异常导致
    # LocalEntryNotFoundError。自动回退官方源重试一次，避免首装硬失败。
    if [[ "$HF_ENDPOINT" != "$CANONICAL_HF" ]]; then
      echo "镜像 $HF_ENDPOINT 下载失败，回退官方源 $CANONICAL_HF 重试…" >&2
      download_model "$CANONICAL_HF" || {
        echo "官方源下载仍失败，请检查网络后重跑本脚本；如在受限网络可设置可用的 HF_ENDPOINT。" >&2
        exit 1
      }
    else
      echo "模型下载失败，请检查网络后重跑本脚本。" >&2
      exit 1
    fi
  fi
fi

[[ -f "$MODEL_DIR/config.json" && -f "$MODEL_DIR/weights.npz" ]] || {
  echo "Whisper 模型下载不完整，可重新运行本脚本继续下载" >&2
  exit 1
}

[[ -x "$FLUIDAUDIO_BIN" ]] || {
  echo "找不到 FluidAudio CLI: $FLUIDAUDIO_BIN（请先运行 provision_fluidaudio.sh）" >&2
  exit 1
}
[[ -f "$FIXTURE" ]] || {
  echo "找不到模型预热音频: $FIXTURE" >&2
  exit 1
}

warmup_output="$(mktemp -t meetingnotes-fluidaudio-warmup)"
trap 'rm -f "$warmup_output"' EXIT
echo "正在预热 FluidAudio 说话人分离模型…"
if ! "$FLUIDAUDIO_BIN" process "$FIXTURE" \
    --output "$warmup_output" --threshold 0.7; then
  echo "FluidAudio 模型预热失败，请检查网络后重新运行本脚本" >&2
  exit 1
fi
[[ -s "$warmup_output" ]] || {
  echo "FluidAudio 预热未产生结果文件，请重新运行本脚本" >&2
  exit 1
}

echo "Whisper 与 FluidAudio 模型置备完成"
