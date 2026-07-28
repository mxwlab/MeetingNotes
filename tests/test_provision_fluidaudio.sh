#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_fake_binary() {
  local binary_path="$1"
  mkdir -p "${binary_path:h}"
  cat > "$binary_path" <<'EOF'
#!/bin/zsh
[[ "${1:-}" == "--help" ]] && exit 0
exit 1
EOF
  chmod +x "$binary_path"
}

# Prebuilt path: curl supplies a checksummed gzip asset.
prebuilt="$tmp/prebuilt"
mkdir -p "$prebuilt/scripts" "$prebuilt/mock-bin"
cp "$ROOT/scripts/provision_fluidaudio.sh" "$prebuilt/scripts/"
make_fake_binary "$tmp/fluidaudiocli"
gzip -n -c "$tmp/fluidaudiocli" > "$tmp/fluidaudiocli.gz"
prebuilt_sha="$(shasum -a 256 "$tmp/fluidaudiocli.gz" | awk '{print $1}')"
cat > "$prebuilt/mock-bin/curl" <<'EOF'
#!/bin/zsh
set -eu
out=""
while (( $# )); do
  [[ "$1" == "-o" ]] && { out="$2"; shift 2; continue; }
  shift
done
cp "${FLUIDAUDIO_TEST_ASSET:?}" "$out"
EOF
chmod +x "$prebuilt/mock-bin/curl"
PATH="$prebuilt/mock-bin:$PATH" \
  FLUIDAUDIO_PREBUILT_URL="https://example.invalid/fluidaudiocli" \
  FLUIDAUDIO_PREBUILT_SHA256="$prebuilt_sha" \
  FLUIDAUDIO_TEST_ASSET="$tmp/fluidaudiocli.gz" \
  FLUIDAUDIO_SKIP_ARCH_CHECK=true \
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
cat > "$fallback/mock-bin/xcode-select" <<'EOF'
#!/bin/zsh
[[ "${1:-}" == "-p" ]] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 1
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
chmod +x "$fallback/mock-bin/curl" "$fallback/mock-bin/xcode-select" \
  "$fallback/scripts/build_fluidaudio_from_source.sh"
PATH="$fallback/mock-bin:$PATH" \
  FLUIDAUDIO_PREBUILT_URL="https://example.invalid/missing" \
  FLUIDAUDIO_PREBUILT_SHA256="$prebuilt_sha" \
  "$fallback/scripts/provision_fluidaudio.sh"
[[ -x "$fallback/tools/FluidAudio/.build/release/fluidaudiocli" ]] \
  || { echo "FAIL source fallback"; exit 1; }

# A friend machine without Xcode must get a clear retry message, not an
# attempted source build.
no_toolchain="$tmp/no-toolchain"
mkdir -p "$no_toolchain/scripts" "$no_toolchain/mock-bin"
cp "$ROOT/scripts/provision_fluidaudio.sh" "$no_toolchain/scripts/"
cp "$fallback/mock-bin/curl" "$no_toolchain/mock-bin/"
cat > "$no_toolchain/mock-bin/xcode-select" <<'EOF'
#!/bin/zsh
exit 1
EOF
chmod +x "$no_toolchain/mock-bin"/*
if PATH="$no_toolchain/mock-bin:/usr/bin:/bin" \
  FLUIDAUDIO_PREBUILT_URL="https://example.invalid/missing" \
  FLUIDAUDIO_PREBUILT_SHA256="$prebuilt_sha" \
  "$no_toolchain/scripts/provision_fluidaudio.sh" \
    >"$tmp/no-toolchain.log" 2>&1; then
  echo "FAIL missing prebuilt accepted without Xcode"
  exit 1
fi
grep -q "无需安装 Xcode" "$tmp/no-toolchain.log" \
  || { echo "FAIL no-Xcode guidance"; cat "$tmp/no-toolchain.log"; exit 1; }

echo "PASS"
