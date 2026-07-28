#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
BIN="$BASE/tools/FluidAudio/.build/release/fluidaudiocli"
BUILD_SCRIPT="$BASE/scripts/build_fluidaudio_from_source.sh"
ASSET_NAME="fluidaudiocli-88d6d816-macos14-arm64.gz"
PREBUILT_URL="${FLUIDAUDIO_PREBUILT_URL:-https://github.com/mxwlab/meetingnotes-runtime-assets/releases/download/fluidaudio-88d6d816/$ASSET_NAME}"
PREBUILT_SHA256="${FLUIDAUDIO_PREBUILT_SHA256:-cdd4d23cfe7c47c969846908d2557df6efd65621cbc75a8e59497f4361d3b9de}"

if [[ -x "$BIN" ]] && "$BIN" --help >/dev/null 2>&1; then
  echo "FluidAudio 已存在且可用，跳过置备"
  exit 0
fi

installed_prebuilt=false
download_dir="$(mktemp -d "$BASE/.fluidaudio-download.XXXXXX")"
download="$download_dir/$ASSET_NAME"
candidate="$download_dir/fluidaudiocli"
trap 'rm -rf "$download_dir"' EXIT

echo "正在下载 FluidAudio 预编译 CLI…"
if curl --fail --silent --show-error --location --retry 3 \
  "$PREBUILT_URL" -o "$download"; then
  actual_sha="$(shasum -a 256 "$download" | awk '{print $1}')"
  if [[ "$actual_sha" != "$PREBUILT_SHA256" ]]; then
    echo "FluidAudio 下载校验失败，将检查源码编译回退" >&2
  elif ! gzip -dc "$download" > "$candidate"; then
    echo "FluidAudio 下载包无法解压，将检查源码编译回退" >&2
  else
    chmod +x "$candidate"
    xattr -d com.apple.quarantine "$candidate" 2>/dev/null || true
    arch_ok=true
    if [[ "${FLUIDAUDIO_SKIP_ARCH_CHECK:-false}" != true ]]; then
      file "$candidate" | grep -q "Mach-O 64-bit executable arm64" || arch_ok=false
    fi
    if [[ "$arch_ok" == true ]] && "$candidate" --help >/dev/null 2>&1; then
      mkdir -p "${BIN:h}"
      mv "$candidate" "$BIN"
      installed_prebuilt=true
      echo "FluidAudio 预编译 CLI 安装完成"
    else
      echo "下载的 FluidAudio CLI 不是可用的 Apple Silicon 版本，将检查源码编译回退" >&2
    fi
  fi
else
  echo "FluidAudio 预编译下载失败，将检查源码编译回退" >&2
fi

if [[ "$installed_prebuilt" != true ]]; then
  if ! command -v xcode-select >/dev/null \
    || ! xcode-select -p >/dev/null 2>&1 \
    || ! command -v swift >/dev/null \
    || ! command -v git >/dev/null; then
    echo "FluidAudio 预编译文件获取失败。正常安装无需安装 Xcode；请检查网络后重新双击安装。" >&2
    echo "只有开发者机器检测到 Xcode 工具链时才会尝试源码编译。" >&2
    exit 1
  fi
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
