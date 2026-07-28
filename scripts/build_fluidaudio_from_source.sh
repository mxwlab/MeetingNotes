#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
FLUID_DIR="$BASE/tools/FluidAudio"
PATCH_SOURCE="$BASE/fluidaudio-patch/BatchTranscribeCommand.swift"
PATCH_TARGET="$FLUID_DIR/Sources/FluidAudioCLI/Commands/ASR/BatchTranscribeCommand.swift"
CLI_SOURCE="$FLUID_DIR/Sources/FluidAudioCLI/FluidAudioCLI.swift"
BIN="$FLUID_DIR/.build/release/fluidaudiocli"

UPSTREAM_URL="${FLUIDAUDIO_GIT_URL:-https://github.com/FluidInference/FluidAudio.git}"
# This is the upstream revision used by the currently verified local build.
UPSTREAM_REF="${FLUIDAUDIO_GIT_REF:-88d6d8166880dee1ac7c32c80f8e10cd782f8ca8}"

command -v git >/dev/null || { echo "缺少 git，无法获取 FluidAudio 源码" >&2; exit 1; }
command -v swift >/dev/null || { echo "缺少 Swift 工具链，请先安装 Xcode Command Line Tools" >&2; exit 1; }
[[ -f "$PATCH_SOURCE" ]] || { echo "缺少批量转写补丁: $PATCH_SOURCE" >&2; exit 1; }

# 目录存在但既非 git 检出也无 Package.swift（例如预编译回退时残留的空 .build 目录），
# 视为无效残留，清除后重新克隆。
if [[ -d "$FLUID_DIR" && ! -d "$FLUID_DIR/.git" && ! -f "$FLUID_DIR/Package.swift" ]]; then
  rm -rf "$FLUID_DIR"
fi

if [[ ! -d "$FLUID_DIR" ]]; then
  mkdir -p "${FLUID_DIR:h}"
  echo "正在克隆 FluidAudio…"
  git clone "$UPSTREAM_URL" "$FLUID_DIR"
  git -C "$FLUID_DIR" checkout --detach "$UPSTREAM_REF"
elif [[ ! -f "$FLUID_DIR/Package.swift" ]]; then
  echo "已有目录不是有效的 FluidAudio 源码树: $FLUID_DIR" >&2
  exit 1
fi

[[ -f "$CLI_SOURCE" ]] || { echo "找不到 FluidAudio CLI 入口: $CLI_SOURCE" >&2; exit 1; }
mkdir -p "${PATCH_TARGET:h}"
cp "$PATCH_SOURCE" "$PATCH_TARGET"

if ! grep -q 'case "batch-transcribe":' "$CLI_SOURCE"; then
  patched="$CLI_SOURCE.meetingnotes.$$"
  trap 'rm -f "$patched"' EXIT
  awk '
    { print }
    /await TranscribeCommand\.run\(arguments: Array\(arguments\.dropFirst\(2\)\)\)/ {
      print "        case \"batch-transcribe\":"
      print "            await BatchTranscribeCommand.run(arguments: Array(arguments.dropFirst(2)))"
      inserted = 1
    }
    END { if (!inserted) exit 42 }
  ' "$CLI_SOURCE" > "$patched" || {
    echo "无法在 FluidAudioCLI.swift 中定位 transcribe 命令，未修改源码" >&2
    exit 1
  }
  mv "$patched" "$CLI_SOURCE"
fi

echo "正在编译 FluidAudio CLI…"
(
  cd "$FLUID_DIR"
  swift build -c release --product fluidaudiocli
)

[[ -x "$BIN" ]] || { echo "FluidAudio 编译完成但未找到 CLI: $BIN" >&2; exit 1; }
echo "FluidAudio 源码编译完成: $BIN"
