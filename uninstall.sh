#!/bin/zsh
set -eu

BASE="${0:A:h}"
DRY_RUN=false
NON_INTERACTIVE=false
REMOVE_RUNTIME=false

usage() {
  cat <<'EOF'
用法: ./uninstall.sh [--dry-run] [--non-interactive] [--remove-runtime]

  --dry-run          显示将移除的服务，不执行任何删除
  --non-interactive  不询问，默认保留 venv/models/tools
  --remove-runtime   同时删除可重建的运行环境、模型和菜单栏 App

inbox/output/done 中的录音与纪要始终保留。
config.local.sh 默认保留，便于重新安装。
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    --remove-runtime) REMOVE_RUNTIME=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

path_hash="$(printf '%s' "$BASE" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"
plist="$HOME/Library/LaunchAgents/$label.plist"
compiled="$HOME/Library/Scripts/Folder Action Scripts/MeetingNotes-$path_hash.scpt"
downloads="${MEETINGNOTES_DOWNLOADS_DIR:-$HOME/Downloads}"
detach_source="$BASE/folder-action/detach-folder-action.applescript"
menubar_label="com.moxiuwen.meetingnotes.menubar"
menubar_plist="$HOME/Library/LaunchAgents/$menubar_label.plist"

if [[ "$DRY_RUN" == true ]]; then
  echo "Dry run：将卸载 $label"
  echo "  launchd plist: $plist"
  echo "  Folder Action script: $compiled"
  echo "  菜单栏 launchd plist: $menubar_plist"
  echo "  用户数据保留: $BASE/inbox, $BASE/output, $BASE/done"
  echo "  本地配置保留: $BASE/config.local.sh"
  if [[ "$REMOVE_RUNTIME" == true ]]; then
    echo "  将删除可重建大件: venv/models/tools/runtime/bin/venv-ui/build/dist"
  else
    echo "  可重建大件默认保留: $BASE/venv, $BASE/models, $BASE/tools, $BASE/runtime, $BASE/bin"
  fi
  exit 0
fi

echo "正在卸载 $label…"
if command -v launchctl >/dev/null; then
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
fi
rm -f "$plist"
echo "已移除 launchd 服务"

if command -v launchctl >/dev/null; then
  launchctl bootout "gui/$(id -u)/$menubar_label" >/dev/null 2>&1 || true
fi
rm -f "$menubar_plist"
echo "已移除菜单栏自启服务"

detached=false
if [[ -f "$detach_source" && -d "$downloads" && -e "$compiled" ]] \
    && command -v osascript >/dev/null; then
  if osascript "$detach_source" "$downloads" "$compiled"; then
    detached=true
  else
    echo "Folder Action 自动解绑失败，请在“文件夹操作设置”中手动移除 MeetingNotes。" >&2
  fi
elif [[ ! -e "$compiled" ]]; then
  detached=true
fi

if [[ "$detached" == true ]]; then
  rm -f "$compiled"
  echo "已移除 AirDrop Folder Action"
else
  echo "为避免留下失效关联，编译脚本暂未删除: $compiled" >&2
fi

desktop_entry="$HOME/Desktop/MeetingNotes 录音"
if [[ -L "$desktop_entry" ]] \
  && [[ "$(readlink "$desktop_entry")" == "$BASE/录音" ]]; then
  rm -f "$desktop_entry"
  echo "已移除桌面录音入口"
fi

if [[ "$NON_INTERACTIVE" != true && "$REMOVE_RUNTIME" != true ]]; then
  print -n -- "是否删除可重建的 venv/models/tools/runtime/bin 大件？[y/N] "
  read -r answer
  case "${answer:l}" in
    y|yes) REMOVE_RUNTIME=true ;;
  esac
fi

if [[ "$REMOVE_RUNTIME" == true ]]; then
  # Targets are fixed children of this project; user recordings and notes are
  # deliberately outside this list.
  rm -rf "$BASE/venv" "$BASE/models" "$BASE/tools" "$BASE/runtime" "$BASE/bin" \
    "$BASE/venv-ui" "$BASE/build" "$BASE/dist"
  echo "已删除运行环境、模型和菜单栏 App（可通过安装引导重建）"
else
  echo "已保留 venv/models/tools/runtime/bin"
fi

echo "卸载完成。inbox/output/done 与 config.local.sh 均已保留。"
