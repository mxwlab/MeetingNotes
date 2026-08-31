#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/provision_models.sh"

# --- 静态断言：源码约定 ---
grep -Fq 'HF_ENDPOINT:-https://huggingface.co' "$SCRIPT" \
  || { echo "FAIL canonical Hugging Face endpoint is not the default"; exit 1; }
grep -Fq 'HF_HUB_DISABLE_XET:-1' "$SCRIPT" \
  || { echo "FAIL Xet is not disabled by default"; exit 1; }
grep -Fq 'QWEN_MODEL_REVISION:-a8379a2e2f9e313c9292cdf1af4055ab56d50d55' "$SCRIPT" \
  || { echo "FAIL Qwen model revision is not pinned"; exit 1; }
grep -Fq 'snapshot_download(repo_id=repo_id, revision=revision, local_dir=local_dir)' "$SCRIPT" \
  || { echo "FAIL pinned Qwen revision is not downloaded locally"; exit 1; }
# 预取的是 Qwen 主模型，不再是 whisper/FluidAudio。
grep -Fq 'Qwen3-ASR-1.7B-8bit' "$SCRIPT" \
  || { echo "FAIL Qwen primary model is not provisioned"; exit 1; }
# 运行时 mlx-qwen3-asr 的 transcribe() 会隐式加载 Qwen3-ASR-0.6B 配套组件；
# 不一并预置的话，朋友首次转录会临时联网下 ~1.8G 且可能卡 xet（回归防护）。
grep -Fq 'Qwen/Qwen3-ASR-0.6B' "$SCRIPT" \
  || { echo "FAIL Qwen3-ASR-0.6B companion is not provisioned"; exit 1; }
grep -Fq 'snapshot_download(repo_id=sys.argv[1])' "$SCRIPT" \
  || { echo "FAIL companion model is not fetched into HF cache"; exit 1; }
grep -Fqi 'fluidaudio' "$SCRIPT" \
  && { echo "FAIL FluidAudio should no longer be referenced"; exit 1; } || true

# --- 行为断言：用桩 python 记录每次下载调用（provision 现在下 8bit 主模型 + 0.6B 配套） ---
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/scripts" "$project/mock-bin"
cp "$SCRIPT" "$project/scripts/"

# 桩 python：记录每次调用 `-` 之后的全部参数（一行一次），以及 HF_ENDPOINT。
cat > "$project/mock-bin/python" <<'EOF'
#!/bin/zsh
set -eu
marker="${MEETINGNOTES_FETCH_MARKER:?}"
print -r -- "$HF_ENDPOINT" > "$marker.endpoint"
# provision 调用形如：python - <repo> [<revision> <local-dir>]
print -r -- "$argv[2,-1]" >> "$marker.calls"
EOF
chmod +x "$project/mock-bin/python"

marker="$tmp/fetch"
HF_ENDPOINT="https://huggingface.co" \
MEETINGNOTES_FETCH_MARKER="$marker" \
MEETINGNOTES_PYTHON="$project/mock-bin/python" \
  "$project/scripts/provision_models.sh"

[[ -f "$marker.calls" ]] || { echo "FAIL downloader was not invoked"; exit 1; }

# 8bit 主模型：repo + 固定 revision + 落到项目本地快照目录
grep -q "mlx-community/Qwen3-ASR-1.7B-8bit a8379a2e2f9e313c9292cdf1af4055ab56d50d55 .*models/qwen3-asr-1.7b-8bit" "$marker.calls" \
  || { echo "FAIL 8bit primary model call missing/incorrect: $(cat "$marker.calls")"; exit 1; }
# 0.6B 配套模型：只按 repo id 下到 HF 缓存（无 local_dir）
grep -qx "Qwen/Qwen3-ASR-0.6B" "$marker.calls" \
  || { echo "FAIL 0.6B companion model was not fetched: $(cat "$marker.calls")"; exit 1; }
[[ "$(<"$marker.endpoint")" == "https://huggingface.co" ]] \
  || { echo "FAIL HF endpoint override"; exit 1; }

echo "PASS"
