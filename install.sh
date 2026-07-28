#!/bin/zsh
set -eu

BASE="${0:A:h}"
DRY_RUN=false
NON_INTERACTIVE=false

usage() {
  cat <<'EOF'
用法: ./install.sh [--dry-run] [--non-interactive]

  --dry-run          只执行环境预检并显示安装步骤，不写入任何状态
  --non-interactive  从 DEEPSEEK_API_KEY / OBSIDIAN_DIR 读取配置
EOF
}

while (( $# > 0 )); do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --non-interactive) NON_INTERACTIVE=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

step() {
  echo
  echo "==> $1"
}

fail() {
  echo "安装失败：$1" >&2
  echo "修复后可重新运行 ./install.sh；已完成的步骤会安全跳过或更新。" >&2
  exit 1
}

require_file() {
  [[ -e "$BASE/$1" ]] || fail "项目文件缺失：$1"
}

step "1/8 环境预检"
os_name="${MEETINGNOTES_UNAME_S:-$(uname -s)}"
arch="${MEETINGNOTES_UNAME_M:-$(uname -m)}"
[[ "$os_name" == "Darwin" ]] || fail "仅支持 macOS，当前系统为 $os_name"
[[ "$arch" == "arm64" ]] || fail "仅支持 Apple Silicon（arm64），当前架构为 $arch"

PYTHON="${MEETINGNOTES_PYTHON:-$(command -v python3 || true)}"
[[ -n "$PYTHON" && -x "$PYTHON" ]] || fail "未找到 python3"
python_version="$("$PYTHON" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')" \
  || fail "无法读取 Python 版本"
python_major="${python_version%%.*}"
python_minor="${python_version#*.}"
python_minor="${python_minor%%.*}"
if (( python_major < 3 || (python_major == 3 && python_minor < 9) )); then
  fail "需要 Python 3.9 或更高版本，当前为 $python_version"
fi

command -v brew >/dev/null || fail "未找到 Homebrew，请先安装：https://brew.sh"
command -v xcode-select >/dev/null || fail "缺少 xcode-select，请先安装 Xcode Command Line Tools"
xcode-select -p >/dev/null 2>&1 || fail "请先运行 xcode-select --install 安装命令行工具"

for required in \
  requirements.txt \
  watch_inbox.sh \
  watch_downloads.sh \
  scripts/provision_fluidaudio.sh \
  scripts/provision_models.sh \
  scripts/gen_launchd.sh \
  scripts/attach_folder_action.sh \
  launchd/com.meetingnotes.plist.template; do
  require_file "$required"
done
echo "环境预检通过：macOS $arch，Python $python_version"

if [[ "$DRY_RUN" == true ]]; then
  cat <<'EOF'

Dry run：以下步骤将在正式安装时执行：
  2/8 安装或确认 ffmpeg
  3/8 创建 Python venv 并安装依赖
  4/8 置备 FluidAudio CLI
  5/8 下载并预热模型
  6/8 写入本地配置（权限 600）
  7/8 生成并加载路径唯一的 launchd 服务
  8/8 编译并挂载 AirDrop Folder Action

未写入任何安装状态。
EOF
  exit 0
fi

step "2/8 系统依赖"
if command -v ffmpeg >/dev/null; then
  echo "ffmpeg 已安装，跳过"
else
  brew install ffmpeg || fail "Homebrew 安装 ffmpeg 失败"
fi

step "3/8 Python 环境"
if [[ ! -x "$BASE/venv/bin/python" ]]; then
  "$PYTHON" -m venv "$BASE/venv" || fail "创建 Python venv 失败"
fi
"$BASE/venv/bin/python" -m pip install -r "$BASE/requirements.txt" \
  || fail "安装 Python 依赖失败"

step "4/8 FluidAudio CLI"
"$BASE/scripts/provision_fluidaudio.sh" || fail "FluidAudio CLI 置备失败"

step "5/8 本地模型"
MEETINGNOTES_PYTHON="$BASE/venv/bin/python" "$BASE/scripts/provision_models.sh" \
  || fail "模型下载或预热失败"

step "6/8 本地配置"
CONFIG="$BASE/config.local.sh"
if [[ -f "$CONFIG" ]]; then
  chmod 600 "$CONFIG"
  echo "已有 config.local.sh，保留现有内容"
else
  if [[ "$NON_INTERACTIVE" == true ]]; then
    deepseek_key="${DEEPSEEK_API_KEY:-}"
    obsidian_dir="${OBSIDIAN_DIR:-}"
  else
    print -n -- "请输入 DeepSeek API Key（输入不回显）: "
    read -rs deepseek_key
    echo
    print -n -- "Obsidian 纪要目录（留空则不同步）: "
    read -r obsidian_dir
  fi
  [[ -n "$deepseek_key" ]] || fail "DeepSeek API Key 不能为空"
  umask 077
  config_tmp="$CONFIG.tmp.$$"
  trap 'rm -f "$config_tmp"' EXIT
  {
    printf 'export DEEPSEEK_API_KEY=%q\n' "$deepseek_key"
    printf 'export OBSIDIAN_DIR=%q\n' "$obsidian_dir"
  } > "$config_tmp"
  chmod 600 "$config_tmp"
  mv "$config_tmp" "$CONFIG"
  trap - EXIT
  echo "已写入 config.local.sh（权限 600）"
fi

mkdir -p "$BASE/inbox" "$BASE/output" "$BASE/done" "$BASE/logs"

step "7/8 launchd 后台服务"
path_hash="$(printf '%s' "$BASE" | shasum | cut -c1-8)"
label="com.meetingnotes.$path_hash"
launch_agents="$HOME/Library/LaunchAgents"
plist="$launch_agents/$label.plist"
mkdir -p "$launch_agents"
"$BASE/scripts/gen_launchd.sh" "$BASE" > "$plist" || fail "生成 launchd plist 失败"
plutil -lint "$plist" >/dev/null || fail "生成的 launchd plist 无效"
launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$plist" || fail "加载 launchd 服务失败"
echo "已加载 $label"

step "8/8 AirDrop Folder Action"
if "$BASE/scripts/attach_folder_action.sh"; then
  echo "AirDrop 自动入库已启用"
else
  echo "Folder Action 挂载失败；仍可把录音手动拖入 $BASE/inbox" >&2
fi

echo
echo "MeetingNotes 安装完成。把录音放入 $BASE/inbox 即可开始处理。"
