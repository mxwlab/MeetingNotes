#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
BIN_DIR="$BASE/bin"
FFMPEG_BIN="$BIN_DIR/ffmpeg"
FFMPEG_MARKER="$BIN_DIR/.ffmpeg.sha256"

# imageio-ffmpeg 0.6.0 的官方 PyPI arm64 wheel；其中包含 FFmpeg 7.1。
# 文件页：https://pypi.org/project/imageio-ffmpeg/0.6.0/#files
FFMPEG_VERSION="${MEETINGNOTES_FFMPEG_VERSION:-7.1}"
FFMPEG_URL="${MEETINGNOTES_FFMPEG_URL:-https://files.pythonhosted.org/packages/40/5c/f3d8a657d362cc93b81aab8feda487317da5b5d31c0e1fdfd5e986e55d17/imageio_ffmpeg-0.6.0-py3-none-macosx_11_0_arm64.whl}"
FFMPEG_SHA256="${MEETINGNOTES_FFMPEG_SHA256:-b1ae3173414b5fc5f538a726c4e48ea97edc0d2cdc11f103afee655c463fa742}"
FFMPEG_ARCHIVE_ENTRY="${MEETINGNOTES_FFMPEG_ARCHIVE_ENTRY:-imageio_ffmpeg/binaries/ffmpeg-macos-aarch64-v7.1}"

fail() {
  echo "ffmpeg 置备失败：$1" >&2
  exit 1
}

ffmpeg_matches() {
  local candidate="$1"
  [[ -x "$candidate" ]] || return 1
  "$candidate" -version 2>&1 | head -1 | grep -Eq "^ffmpeg version ${FFMPEG_VERSION}([. -]|$)"
}

if ffmpeg_matches "$FFMPEG_BIN" \
  && [[ -f "$FFMPEG_MARKER" ]] \
  && [[ "$(<"$FFMPEG_MARKER")" == "$FFMPEG_SHA256" ]]; then
  echo "ffmpeg ${FFMPEG_VERSION} 已存在，跳过"
  exit 0
fi

mkdir -p "$BIN_DIR"
download="$(mktemp "$BIN_DIR/.ffmpeg-download.XXXXXX")"
candidate="$(mktemp "$BIN_DIR/.ffmpeg-candidate.XXXXXX")"
cleanup_fetch_ffmpeg() {
  rm -f "$download" "$candidate"
}
trap cleanup_fetch_ffmpeg EXIT

echo "正在下载 ffmpeg ${FFMPEG_VERSION}…"
curl --fail --location --retry 3 --continue-at - \
  "$FFMPEG_URL" -o "$download" \
  || fail "下载失败，请检查网络后重新运行"

actual_sha="$(shasum -a 256 "$download" | awk '{print $1}')"
[[ "$actual_sha" == "$FFMPEG_SHA256" ]] \
  || fail "下载文件校验不通过（期待 $FFMPEG_SHA256，实际 $actual_sha）"

unzip -p "$download" "$FFMPEG_ARCHIVE_ENTRY" > "$candidate" \
  || fail "下载包内未找到 ffmpeg"
chmod +x "$candidate"
xattr -d com.apple.quarantine "$candidate" 2>/dev/null || true

if [[ "${MEETINGNOTES_SKIP_ARCH_CHECK:-false}" != true ]]; then
  file "$candidate" | grep -q "Mach-O 64-bit executable arm64" \
    || fail "下载的 ffmpeg 不是 Apple Silicon arm64 可执行文件"
fi
ffmpeg_matches "$candidate" \
  || fail "下载的 ffmpeg 无法运行或版本不符"

previous=""
if [[ -e "$FFMPEG_BIN" ]]; then
  previous="$BIN_DIR/.ffmpeg-previous.$$"
  mv "$FFMPEG_BIN" "$previous"
fi
if ! mv "$candidate" "$FFMPEG_BIN"; then
  [[ -n "$previous" && -e "$previous" ]] && mv "$previous" "$FFMPEG_BIN"
  fail "无法把 ffmpeg 安装到 $FFMPEG_BIN"
fi
[[ -n "$previous" && -e "$previous" ]] && rm -f "$previous"
printf '%s\n' "$FFMPEG_SHA256" > "$FFMPEG_MARKER"

echo "ffmpeg ${FFMPEG_VERSION} 安装完成"
