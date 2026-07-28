#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
project="$tmp/project"
fluid="$project/tools/FluidAudio"
mkdir -p "$project/scripts" \
         "$project/fluidaudio-patch" \
         "$fluid/Sources/FluidAudioCLI/Commands/ASR" \
         "$project/mock-bin"
cp "$ROOT/scripts/build_fluidaudio_from_source.sh" "$project/scripts/"
cp "$ROOT/fluidaudio-patch/BatchTranscribeCommand.swift" "$project/fluidaudio-patch/"
cat > "$fluid/Sources/FluidAudioCLI/FluidAudioCLI.swift" <<'EOF'
switch command {
case "transcribe":
    await TranscribeCommand.run(arguments: Array(arguments.dropFirst(2)))
case "multi-stream":
    break
}
EOF
touch "$fluid/Package.swift"
cat > "$project/mock-bin/swift" <<'EOF'
#!/bin/zsh
set -eu
[[ "$*" == "build -c release --product fluidaudiocli" ]] \
  || { echo "unexpected swift args: $*" >&2; exit 2; }
mkdir -p .build/release
cat > .build/release/fluidaudiocli <<'BIN'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
BIN
chmod +x .build/release/fluidaudiocli
EOF
chmod +x "$project/mock-bin/swift"

PATH="$project/mock-bin:$PATH" "$project/scripts/build_fluidaudio_from_source.sh"
cmp "$project/fluidaudio-patch/BatchTranscribeCommand.swift" \
    "$fluid/Sources/FluidAudioCLI/Commands/ASR/BatchTranscribeCommand.swift"
grep -q 'case "batch-transcribe":' "$fluid/Sources/FluidAudioCLI/FluidAudioCLI.swift" \
  || { echo "FAIL command registration"; exit 1; }
PATH="$project/mock-bin:$PATH" "$project/scripts/build_fluidaudio_from_source.sh"
[[ "$(grep -c 'case "batch-transcribe":' "$fluid/Sources/FluidAudioCLI/FluidAudioCLI.swift")" == 1 ]] \
  || { echo "FAIL non-idempotent registration"; exit 1; }

echo "PASS"
