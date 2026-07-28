#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_binary() {
  local path="$1"
  mkdir -p "${path:h}"
  cat > "$path" <<'EOF'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
EOF
  chmod +x "$path"
}

# Prebuilt path: curl supplies a runnable raw arm64-style executable.
prebuilt="$tmp/prebuilt"
mkdir -p "$prebuilt/scripts" "$prebuilt/mock-bin"
cp "$ROOT/scripts/provision_fluidaudio.sh" "$prebuilt/scripts/"
cat > "$prebuilt/mock-bin/curl" <<'EOF'
#!/bin/zsh
set -eu
out=""
while (( $# )); do
  [[ "$1" == "-o" ]] && { out="$2"; shift 2; continue; }
  shift
done
cat > "$out" <<'BIN'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
BIN
EOF
chmod +x "$prebuilt/mock-bin/curl"
PATH="$prebuilt/mock-bin:$PATH" \
  FLUIDAUDIO_PREBUILT_URL="https://example.invalid/fluidaudiocli" \
  "$prebuilt/scripts/provision_fluidaudio.sh"
[[ -x "$prebuilt/tools/FluidAudio/.build/release/fluidaudiocli" ]] \
  || { echo "FAIL prebuilt install"; exit 1; }

# Fallback path: failed download delegates to the source builder.
fallback="$tmp/fallback"
mkdir -p "$fallback/scripts" "$fallback/mock-bin"
cp "$ROOT/scripts/provision_fluidaudio.sh" "$fallback/scripts/"
cat > "$fallback/mock-bin/curl" <<'EOF'
#!/bin/zsh
exit 22
EOF
cat > "$fallback/scripts/build_fluidaudio_from_source.sh" <<'EOF'
#!/bin/zsh
base="${0:A:h:h}"
bin="$base/tools/FluidAudio/.build/release/fluidaudiocli"
mkdir -p "${bin:h}"
cat > "$bin" <<'BIN'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
BIN
chmod +x "$bin"
EOF
chmod +x "$fallback/mock-bin/curl" "$fallback/scripts/build_fluidaudio_from_source.sh"
PATH="$fallback/mock-bin:$PATH" \
  FLUIDAUDIO_PREBUILT_URL="https://example.invalid/missing" \
  "$fallback/scripts/provision_fluidaudio.sh"
[[ -x "$fallback/tools/FluidAudio/.build/release/fluidaudiocli" ]] \
  || { echo "FAIL source fallback"; exit 1; }

echo "PASS"
