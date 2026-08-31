#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
PYTHON="${MEETINGNOTES_PYTHON:-$BASE/venv/bin/python}"
# 主转录引擎 Qwen3-ASR（mlx-qwen3-asr）。预取到 HF 缓存，首场会无需现场静默下载。
# Whisper 仅作兜底，改为首次真正需要时再懒加载，不在安装阶段预下 2.9GB。
QWEN_REPO="${QWEN_MODEL_REPO:-mlx-community/Qwen3-ASR-1.7B-8bit}"
QWEN_REVISION="${QWEN_MODEL_REVISION:-a8379a2e2f9e313c9292cdf1af4055ab56d50d55}"
QWEN_MODEL_DIR="${QWEN_MODEL_DIR:-$BASE/models/qwen3-asr-1.7b-8bit}"
# 运行时 mlx-qwen3-asr 的 transcribe() 会隐式加载 Qwen3-ASR-0.6B 配套组件（下到 HF 缓存）。
# 不在安装期一并预置的话，朋友首次转录会临时联网下 ~1.8G，慢/受限网络还会卡 xet 假死。
QWEN_COMPANION_REPO="${QWEN_COMPANION_REPO:-Qwen/Qwen3-ASR-0.6B}"
export HF_ENDPOINT="${HF_ENDPOINT:-https://huggingface.co}"
# hf-xet 在部分网络下可能长时间静默停滞；首次安装优先使用可续传的
# 标准 HTTP 路径。高级用户仍可显式设为 0 重新启用 Xet。
export HF_HUB_DISABLE_XET="${HF_HUB_DISABLE_XET:-1}"
CANONICAL_HF="https://huggingface.co"

echo "使用 HF_ENDPOINT=$HF_ENDPOINT"

[[ -x "$PYTHON" ]] || {
  echo "找不到项目 Python: $PYTHON（请先安装 requirements.txt）" >&2
  exit 1
}

download_qwen() {
  # $1 = 使用的 HF_ENDPOINT。下到 HF 缓存，mlx-qwen3-asr 首次 load_model 直接命中。
  HF_ENDPOINT="$1" "$PYTHON" - "$QWEN_REPO" "$QWEN_REVISION" "$QWEN_MODEL_DIR" <<'PY'
import sys
from huggingface_hub import snapshot_download

repo_id, revision, local_dir = sys.argv[1:4]
snapshot_download(repo_id=repo_id, revision=revision, local_dir=local_dir)
PY
}

echo "正在下载 Qwen3-ASR 主转录模型: $QWEN_REPO@$QWEN_REVISION（首次较大，请耐心；已缓存则秒过）"
if ! download_qwen "$HF_ENDPOINT"; then
  # 用户显式配置的镜像可能因 /resolve/ 响应异常而失败；自动回退官方源重试一次。
  if [[ "$HF_ENDPOINT" != "$CANONICAL_HF" ]]; then
    echo "镜像 $HF_ENDPOINT 下载失败，回退官方源 $CANONICAL_HF 重试…" >&2
    download_qwen "$CANONICAL_HF" || {
      echo "官方源下载仍失败，请检查网络后重跑本脚本；如在受限网络可设置可用的 HF_ENDPOINT。" >&2
      exit 1
    }
  else
    echo "模型下载失败，请检查网络后重跑本脚本。" >&2
    exit 1
  fi
fi

download_companion() {
  # $1 = 使用的 HF_ENDPOINT。配套模型按 repo id 下到 HF 缓存（无 local_dir），
  # 运行时 transcribe() 首次 load 直接命中缓存，无需现场联网。
  HF_ENDPOINT="$1" "$PYTHON" - "$QWEN_COMPANION_REPO" <<'PY'
import sys
from huggingface_hub import snapshot_download

snapshot_download(repo_id=sys.argv[1])
PY
}

echo "正在下载 Qwen3-ASR 配套模型: $QWEN_COMPANION_REPO（首次转录必需，一并预置避免首场卡顿）"
if ! download_companion "$HF_ENDPOINT"; then
  if [[ "$HF_ENDPOINT" != "$CANONICAL_HF" ]]; then
    echo "镜像 $HF_ENDPOINT 下载配套模型失败，回退官方源 $CANONICAL_HF 重试…" >&2
    download_companion "$CANONICAL_HF" || {
      echo "官方源下载配套模型仍失败，请检查网络后重跑本脚本。" >&2
      exit 1
    }
  else
    echo "配套模型下载失败，请检查网络后重跑本脚本。" >&2
    exit 1
  fi
fi

echo "Qwen3-ASR 主模型 + 配套模型置备完成（Whisper 兜底模型将在首次需要时自动下载）"
