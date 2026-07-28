#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
SOURCE="$BASE/folder-action/airdrop-to-inbox.applescript"
ATTACH_SOURCE="$BASE/folder-action/attach-folder-action.applescript"
WATCHER="$BASE/watch_downloads.sh"
DOWNLOADS="${MEETINGNOTES_DOWNLOADS_DIR:-$HOME/Downloads}"
SCRIPT_DIR="${MEETINGNOTES_FOLDER_ACTION_DIR:-$HOME/Library/Scripts/Folder Action Scripts}"
path_hash="$(printf '%s' "$BASE" | shasum | cut -c1-8)"
COMPILED="$SCRIPT_DIR/MeetingNotes-$path_hash.scpt"
dry_run=false

if [[ "${1:-}" == "--dry-run" ]]; then
  dry_run=true
elif (( $# > 0 )); then
  echo "用法: attach_folder_action.sh [--dry-run]" >&2
  exit 2
fi

[[ -f "$SOURCE" ]] || { echo "找不到 Folder Action 源文件: $SOURCE" >&2; exit 1; }
[[ -f "$ATTACH_SOURCE" ]] || { echo "找不到 Folder Action 挂载脚本: $ATTACH_SOURCE" >&2; exit 1; }
[[ -x "$WATCHER" ]] || { echo "找不到可执行的下载监听脚本: $WATCHER" >&2; exit 1; }
[[ -d "$DOWNLOADS" ]] || { echo "找不到 Downloads 目录: $DOWNLOADS" >&2; exit 1; }
command -v osacompile >/dev/null || { echo "找不到 osacompile" >&2; exit 1; }

mkdir -p "$SCRIPT_DIR"
generated="$(mktemp -t meetingnotes-folder-action)"
trap 'rm -f "$generated"' EXIT

# Escape the watcher path once for the AppleScript string literal, then again
# for sed's replacement expression.
watcher_literal="${WATCHER//\\/\\\\}"
watcher_literal="${watcher_literal//\"/\\\"}"
sed_replacement="${watcher_literal//&/\\&}"
sed_replacement="${sed_replacement//|/\\|}"
sed "s|__WATCHER__|$sed_replacement|g" "$SOURCE" > "$generated"
osacompile -o "$COMPILED" "$generated"

if [[ "$dry_run" == true ]]; then
  echo "Folder Action 编译验证通过（未挂载）: $COMPILED"
  exit 0
fi

# 全新 Mac 上 Folder Actions 从未启用时，若在同一次调用里“启用 + 创建 folder
# action”会报 -1728（Can't get folder action）。先用独立进程启用并提交子系统，
# 再执行挂载；挂载失败则重试一次，给 Folder Actions 守护进程留出启动时间。
osascript -e 'tell application "System Events" to set folder actions enabled to true' \
  >/dev/null 2>&1 || true

if ! osascript "$ATTACH_SOURCE" "$DOWNLOADS" "$COMPILED" 2>/dev/null; then
  osascript "$ATTACH_SOURCE" "$DOWNLOADS" "$COMPILED"
fi

echo "已挂载 AirDrop Folder Action；首次触发如出现自动化授权，请点“允许”。"
