#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

release_dir="$tmp/release"
extract_dir="$tmp/朋友 收到的安装包"
home="$tmp/测试 用户"
target="$home/MeetingNotes"
calls="$tmp/mock-network.calls"
mock_bin="$tmp/mock-bin"

"$ROOT/build_release.sh" "zip-orchestration-test" "$release_dir" >/dev/null
archive="$release_dir/MeetingNotes-mac-zip-orchestration-test.zip"

mkdir -p "$extract_dir" "$home/Desktop" "$home/Library/LaunchAgents" "$mock_bin"
python3 - "$archive" "$extract_dir" <<'PY'
import os
import stat
import sys
import zipfile

archive, destination = sys.argv[1:3]
with zipfile.ZipFile(archive) as source:
    for info in source.infolist():
        source.extract(info, destination)
        path = os.path.join(destination, info.filename)
        mode = info.external_attr >> 16
        if mode:
            os.chmod(path, stat.S_IMODE(mode))
PY

package="$extract_dir/MeetingNotes"
[[ -x "$package/开始使用.command" ]] || {
  echo "FAIL zip did not preserve launcher executable mode"
  exit 1
}
[[ -x "$package/scripts/bootstrap_mac.sh" ]] || {
  echo "FAIL zip did not preserve bootstrap executable mode"
  exit 1
}

# Replace only external/system boundaries. The bootstrap being exercised is the
# exact file extracted from the release zip.
for helper in fetch_python.sh fetch_ffmpeg.sh provision_models.sh; do
  cat > "$package/scripts/$helper" <<EOF
#!/bin/zsh
print -r -- "$helper" >> "\${MEETINGNOTES_TEST_CALLS:?}"
EOF
  chmod +x "$package/scripts/$helper"
done
cat > "$package/scripts/attach_folder_action.sh" <<'EOF'
#!/bin/zsh
print -r -- "attach-folder-action" >> "${MEETINGNOTES_TEST_CALLS:?}"
EOF
chmod +x "$package/scripts/attach_folder_action.sh"

cat > "$mock_bin/launchctl" <<'EOF'
#!/bin/zsh
exit 0
EOF
cat > "$mock_bin/plutil" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$mock_bin/launchctl" "$mock_bin/plutil"

run_bootstrap() {
  PATH="$mock_bin:/usr/bin:/bin" HOME="$home" \
  MEETINGNOTES_UNAME_S=Darwin MEETINGNOTES_UNAME_M=arm64 \
  MEETINGNOTES_MACOS_MAJOR=14 \
  MEETINGNOTES_INSTALL_DIR="$target" \
  MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
  MEETINGNOTES_TEST_CALLS="$calls" \
  DEEPSEEK_API_KEY="$1" \
    "$2/scripts/bootstrap_mac.sh"
}

run_bootstrap "zip-test-key" "$package" >/dev/null

[[ -x "$target/scripts/bootstrap_mac.sh" ]] || {
  echo "FAIL extracted package was not settled"
  exit 1
}
[[ "$(stat -f '%Lp' "$target/config.local.sh")" == 600 ]] || {
  echo "FAIL config mode"
  exit 1
}
grep -Fq "zip-test-key" "$target/config.local.sh" || {
  echo "FAIL config missing"
  exit 1
}
! grep -Fq "zip-test-key" "$target/logs/bootstrap.log" || {
  echo "FAIL key leaked to log"
  exit 1
}
[[ -L "$home/Desktop/MeetingNotes 录音" ]] || {
  echo "FAIL desktop entry missing"
  exit 1
}
for expected in fetch_python.sh fetch_ffmpeg.sh \
  provision_models.sh attach-folder-action; do
  grep -Fq "$expected" "$calls" || {
    echo "FAIL missing orchestration call: $expected"
    exit 1
  }
done

# A second run must retain the original configuration and complete again.
run_bootstrap "must-not-replace" "$target" >/dev/null
grep -Fq "zip-test-key" "$target/config.local.sh" || {
  echo "FAIL second run overwrote config"
  exit 1
}
! grep -Fq "must-not-replace" "$target/config.local.sh" || {
  echo "FAIL second run accepted replacement key"
  exit 1
}

echo "PASS"
