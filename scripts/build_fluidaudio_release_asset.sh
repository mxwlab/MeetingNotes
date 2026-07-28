#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
BUILD_SCRIPT="$BASE/scripts/build_fluidaudio_from_source.sh"
BIN="$BASE/tools/FluidAudio/.build/release/fluidaudiocli"
UPSTREAM_REF="88d6d8166880dee1ac7c32c80f8e10cd782f8ca8"
SHORT_REF="${UPSTREAM_REF[1,8]}"
ASSET_NAME="fluidaudiocli-${SHORT_REF}-macos14-arm64.gz"
OUTPUT_DIR="${1:-$BASE/dist/fluidaudio}"
ASSET="$OUTPUT_DIR/$ASSET_NAME"

[[ -x "$BUILD_SCRIPT" ]] || {
  echo "缺少构建脚本: $BUILD_SCRIPT" >&2
  exit 1
}
command -v swift >/dev/null || {
  echo "缺少 Swift/Xcode 工具链" >&2
  exit 1
}

"$BUILD_SCRIPT"
[[ -x "$BIN" ]] && "$BIN" --help >/dev/null 2>&1 || {
  echo "FluidAudio CLI 构建后不可用" >&2
  exit 1
}
file "$BIN" | grep -q "Mach-O 64-bit executable arm64" || {
  echo "构建产物不是 arm64 Mach-O" >&2
  exit 1
}

min_macos="$(otool -l "$BIN" | awk '
  /LC_BUILD_VERSION/ { in_build = 1; next }
  in_build && /minos/ { print $2; exit }
')"
[[ -n "$min_macos" ]] || {
  echo "无法读取最低 macOS 版本" >&2
  exit 1
}

unexpected_deps="$(otool -L "$BIN" | tail -n +2 | awk '
  {
    dep = $1
    if (dep !~ "^/usr/lib/" && dep !~ "^/System/Library/") print dep
  }
')"
[[ -z "$unexpected_deps" ]] || {
  echo "发现非系统动态库依赖：" >&2
  echo "$unexpected_deps" >&2
  exit 1
}

mkdir -p "$OUTPUT_DIR"
gzip -n -c -9 "$BIN" > "$ASSET"
asset_sha="$(shasum -a 256 "$ASSET" | awk '{print $1}')"
printf '%s  %s\n' "$asset_sha" "$ASSET_NAME" > "$ASSET.sha256"
{
  echo "FluidAudio upstream: https://github.com/FluidInference/FluidAudio"
  echo "Upstream revision: $UPSTREAM_REF"
  echo "MeetingNotes patch: fluidaudio-patch/BatchTranscribeCommand.swift"
  echo "Minimum macOS: $min_macos"
  echo "Architecture: arm64"
  echo "SHA-256: $asset_sha"
  echo
  echo "Dynamic dependencies:"
  otool -L "$BIN"
} > "$ASSET.build-info.txt"

echo "FluidAudio Release 资产已生成："
echo "  $ASSET"
echo "  SHA-256: $asset_sha"
echo "  最低 macOS: $min_macos"
