#!/bin/zsh
set -eu

BASE="${0:A:h}"
VERSION="${1:-0.2.0-beta.1}"
OUTPUT_DIR="${2:-$BASE/dist}"
[[ "$VERSION" =~ '^[A-Za-z0-9._-]+$' ]] || {
  echo "版本号只能包含字母、数字、点、下划线和连字符" >&2
  exit 2
}
BUILD_PYTHON="${MEETINGNOTES_BUILD_PYTHON:-$(command -v python3 || true)}"
[[ -n "$BUILD_PYTHON" && -x "$BUILD_PYTHON" ]] || {
  echo "制作发布包需要 python3（仅制作方需要）" >&2
  exit 1
}

archive_name="MeetingNotes-mac-$VERSION.zip"
archive="$OUTPUT_DIR/$archive_name"
manifest="$OUTPUT_DIR/MeetingNotes-mac-$VERSION.manifest.txt"
checksum="$archive.sha256"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
package="$stage/MeetingNotes"

files=(
  "开始使用.command"
  "assets/MeetingNotes.icns"
  "assets/meetingnotes-icon.png"
  "README.md"
  "NOTICE"
  "config.example.sh"
  "requirements.txt"
  "requirements-ui.txt"
  "setup_ui.py"
  "installer/MeetingNotesInstaller.m"
  "process.py"
  "pet.py"
  "watch_inbox.sh"
  "watch_downloads.sh"
  "uninstall.sh"
  "docs/新手安装图文教程.md"
  "launchd/com.meetingnotes.plist.template"
  "launchd/com.moxiuwen.meetingnotes.menubar.plist.template"
  "folder-action/airdrop-to-inbox.applescript"
  "folder-action/attach-folder-action.applescript"
  "folder-action/detach-folder-action.applescript"
  "licenses/FFmpeg-COPYING.GPLv2"
  "tests/fixtures/tiny.wav"
  "scripts/attach_folder_action.sh"
  "scripts/bootstrap_mac.sh"
  "scripts/fetch_ffmpeg.sh"
  "scripts/fetch_python.sh"
  "scripts/gen_launchd.sh"
  "scripts/prompt_deepseek_key.applescript"
  "scripts/provision_models.sh"
  "scripts/provision_menubar.sh"
  "scripts/build_main_app.sh"
  "scripts/install_menubar_autostart.sh"
  "scripts/installer_progress.sh"
  "ui/__init__.py"
  "ui/menubar.py"
  "ui/main.py"
  "ui/pet_status.py"
  "ui/provider_config.py"
)

for relative_path in "${files[@]}"; do
  source_path="$BASE/$relative_path"
  [[ -f "$source_path" ]] || {
    echo "发布白名单文件缺失：$relative_path" >&2
    exit 1
  }
  mkdir -p "$package/${relative_path:h}"
  cp -p "$source_path" "$package/$relative_path"
done

# 制作方预编译原生安装器；朋友运行发布包时不需要 Xcode 或编译工具。
# 版本号与本次发布对齐，避免安装器里的 CFBundleShortVersionString 落后。
MEETINGNOTES_APP_VERSION="$VERSION" \
  "$BASE/scripts/build_installer_app.sh" "$package/MeetingNotes 安装器.app" >/dev/null

# 固定时间戳并禁止 macOS 扩展属性，确保同一源码重复构建得到相同 zip。
find "$package" -exec touch -h -t 202001010000 {} +
xattr -cr "$package" 2>/dev/null || true
mkdir -p "$OUTPUT_DIR"
rm -f "$archive" "$manifest" "$checksum"

"$BUILD_PYTHON" - "$package" "$archive" <<'PY'
import os
import stat
import sys
import zipfile

package, archive = sys.argv[1:3]
root_name = os.path.basename(package)
paths = []
for dirpath, _, filenames in os.walk(package):
    for filename in filenames:
        paths.append(os.path.join(dirpath, filename))

with zipfile.ZipFile(
    archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
) as output:
    for path in sorted(paths):
        relative = os.path.relpath(path, package)
        archive_path = root_name + "/" + relative.replace(os.sep, "/")
        info = zipfile.ZipInfo(archive_path, date_time=(2020, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        mode = stat.S_IMODE(os.stat(path).st_mode)
        # Include the Unix regular-file type bit. macOS Archive Utility/ditto
        # otherwise treats the entry type as unknown and drops executable bits.
        info.external_attr = ((stat.S_IFREG | mode) & 0xFFFF) << 16
        info.create_system = 3
        with open(path, "rb") as source:
            output.writestr(info, source.read(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
PY

(
  cd "$package"
  for packaged_file in ${(f)"$(find . -type f -print | LC_ALL=C sort)"}; do
    file_sha="$(shasum -a 256 "$packaged_file" | awk '{print $1}')"
    printf '%s  %s\n' "$file_sha" "${packaged_file#./}"
  done
) > "$manifest"

archive_sha="$(shasum -a 256 "$archive" | awk '{print $1}')"
printf '%s  %s\n' "$archive_sha" "$archive_name" > "$checksum"

echo "发布包已生成：$archive"
echo "SHA-256：$archive_sha"
echo "清单：$manifest"
