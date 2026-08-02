#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
grep -Fq 'HF_ENDPOINT:-https://huggingface.co' \
  "$ROOT/scripts/provision_models.sh" \
  || { echo "FAIL canonical Hugging Face endpoint is not the default"; exit 1; }
grep -Fq 'HF_HUB_DISABLE_XET:-1' \
  "$ROOT/scripts/provision_models.sh" \
  || { echo "FAIL Xet is not disabled by default"; exit 1; }
# 预取的是 Qwen 主模型，不再是 whisper/FluidAudio。
grep -Fq 'Qwen3-ASR-1.7B-8bit' "$ROOT/scripts/provision_models.sh" \
  || { echo "FAIL Qwen primary model is not provisioned"; exit 1; }
grep -Fqi 'fluidaudio' "$ROOT/scripts/provision_models.sh" \
  && { echo "FAIL FluidAudio should no longer be referenced"; exit 1; } || true

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/scripts" "$project/mock-bin"
cp "$ROOT/scripts/provision_models.sh" "$project/scripts/"

# 桩 python：把收到的 repo 参数与 HF_ENDPOINT 落到标记文件，供断言。
cat > "$project/mock-bin/python" <<'EOF'
#!/bin/zsh
set -eu
marker="${MEETINGNOTES_FETCH_MARKER:?}"
print -r -- "$HF_ENDPOINT" > "$marker.endpoint"
# provision 传参为:  python - <repo>
print -r -- "$2" > "$marker.repo"
EOF
chmod +x "$project/mock-bin/python"

marker="$tmp/fetch"
HF_ENDPOINT="https://huggingface.co" \
MEETINGNOTES_FETCH_MARKER="$marker" \
MEETINGNOTES_PYTHON="$project/mock-bin/python" \
  "$project/scripts/provision_models.sh"

[[ -f "$marker.repo" ]] || { echo "FAIL downloader was not invoked"; exit 1; }
[[ "$(<"$marker.repo")" == "mlx-community/Qwen3-ASR-1.7B-8bit" ]] \
  || { echo "FAIL wrong model repo: $(<"$marker.repo")"; exit 1; }
[[ "$(<"$marker.endpoint")" == "https://huggingface.co" ]] \
  || { echo "FAIL HF endpoint override"; exit 1; }

echo "PASS"
