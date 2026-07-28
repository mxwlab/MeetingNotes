#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
mkdir -p "$project/scripts" \
         "$project/tests/fixtures" \
         "$project/tools/FluidAudio/.build/release" \
         "$project/mock-bin"
cp "$ROOT/scripts/provision_models.sh" "$project/scripts/"
cp "$ROOT/tests/fixtures/tiny.wav" "$project/tests/fixtures/"

cat > "$project/mock-bin/python" <<'EOF'
#!/bin/zsh
set -eu
model_dir="$2"
mkdir -p "$model_dir"
print -r -- "$HF_ENDPOINT" > "$model_dir/hf_endpoint.txt"
print -r -- "$3" > "$model_dir/repo.txt"
touch "$model_dir/config.json" "$model_dir/weights.npz"
EOF
cat > "$project/tools/FluidAudio/.build/release/fluidaudiocli" <<'EOF'
#!/bin/zsh
set -eu
[[ "$1" == "process" ]] || exit 2
while (( $# )); do
  [[ "$1" == "--output" ]] && { print -r -- '{}' > "$2"; exit 0; }
  shift
done
exit 3
EOF
chmod +x "$project/mock-bin/python" \
         "$project/tools/FluidAudio/.build/release/fluidaudiocli"

HF_ENDPOINT="https://huggingface.co" \
MEETINGNOTES_PYTHON="$project/mock-bin/python" \
  "$project/scripts/provision_models.sh"

model="$project/models/whisper-large-v3-mlx"
[[ -f "$model/config.json" && -f "$model/weights.npz" ]] \
  || { echo "FAIL whisper model"; exit 1; }
[[ "$(<"$model/hf_endpoint.txt")" == "https://huggingface.co" ]] \
  || { echo "FAIL HF endpoint override"; exit 1; }
[[ "$(<"$model/repo.txt")" == "mlx-community/whisper-large-v3-mlx" ]] \
  || { echo "FAIL model repo"; exit 1; }

# A complete local model should make a second run skip the downloader.
cat > "$project/mock-bin/python" <<'EOF'
#!/bin/zsh
echo "downloader should have been skipped" >&2
exit 9
EOF
MEETINGNOTES_PYTHON="$project/mock-bin/python" \
  "$project/scripts/provision_models.sh"

echo "PASS"
