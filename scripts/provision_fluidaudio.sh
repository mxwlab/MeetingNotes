#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
BIN="$BASE/tools/FluidAudio/.build/release/fluidaudiocli"
BUILD_SCRIPT="$BASE/scripts/build_fluidaudio_from_source.sh"
PREBUILT_URL="${FLUIDAUDIO_PREBUILT_URL:-}"

if [[ -x "$BIN" ]] && "$BIN" --help >/dev/null 2>&1; then
  echo "FluidAudio 已存在且可用，跳过置备"
  exit 0
fi

installed_prebuilt=false
if [[ -n "$PREBUILT_URL" ]]; then
  # 仅预编译下载路径需要预建目标目录；源码编译路径由构建脚本自行 clone，
  # 提前 mkdir 会让 tools/FluidAudio 提前存在，从而破坏构建脚本的"源码树是否存在"判断。
  mkdir -p "${BIN:h}"
  download="$BIN.download.$$"
  trap 'rm -f "$download"' EXIT
  echo "正在下载 FluidAudio 预编译 CLI…"
  if curl -fsSL "$PREBUILT_URL" -o "$download"; then
    chmod +x "$download"
    xattr -d com.apple.quarantine "$download" 2>/dev/null || true
    if "$download" --help >/dev/null 2>&1; then
      mv "$download" "$BIN"
      installed_prebuilt=true
      echo "FluidAudio 预编译 CLI 安装完成"
    else
      echo "下载的 FluidAudio CLI 无法运行，将回退源码编译" >&2
    fi
  else
    echo "FluidAudio 预编译下载失败，将回退源码编译" >&2
  fi
else
  echo "未配置 FLUIDAUDIO_PREBUILT_URL，将从源码编译"
fi

if [[ "$installed_prebuilt" != true ]]; then
  [[ -x "$BUILD_SCRIPT" ]] || {
    echo "缺少源码构建脚本: $BUILD_SCRIPT" >&2
    exit 1
  }
  "$BUILD_SCRIPT"
fi

if [[ ! -x "$BIN" ]] || ! "$BIN" --help >/dev/null 2>&1; then
  echo "FluidAudio CLI 置备后仍不可用: $BIN" >&2
  exit 1
fi

echo "FluidAudio CLI 验证通过: $BIN"
