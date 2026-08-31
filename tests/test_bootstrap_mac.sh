#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_package() {
  local package_dir="$1"
  mkdir -p "$package_dir/scripts" "$package_dir/launchd" \
    "$package_dir/models" "$package_dir/inbox" "$package_dir/output" \
    "$package_dir/done" "$package_dir/logs" "$package_dir/venv"
  cp "$ROOT/scripts/bootstrap_mac.sh" "$package_dir/scripts/"
  cp "$ROOT/scripts/installer_progress.sh" "$package_dir/scripts/"
  cp "$ROOT/scripts/prompt_deepseek_key.applescript" "$package_dir/scripts/"
  touch "$package_dir/process.py" "$package_dir/watch_inbox.sh" \
    "$package_dir/watch_downloads.sh" "$package_dir/requirements.txt"
  echo secret-model > "$package_dir/models/should-not-copy"
  echo user-audio > "$package_dir/inbox/should-not-copy.m4a"
  echo old-note > "$package_dir/output/should-not-copy.md"
  echo log > "$package_dir/logs/should-not-copy.log"
  echo venv > "$package_dir/venv/should-not-copy"
  echo 'export DEEPSEEK_API_KEY=must-not-copy' > "$package_dir/config.local.sh"
  echo 'com.moxiuwen.meetingnotes.menubar.wrong-source' > "$package_dir/.menubar_label"

  for helper in fetch_python.sh fetch_ffmpeg.sh provision_models.sh provision_menubar.sh; do
    cat > "$package_dir/scripts/$helper" <<EOF
#!/bin/zsh
print -r -- "$helper" >> "\${MEETINGNOTES_TEST_CALLS:?}"
EOF
    chmod +x "$package_dir/scripts/$helper"
  done
  cat > "$package_dir/scripts/gen_launchd.sh" <<'EOF'
#!/bin/zsh
echo '<plist><dict></dict></plist>'
EOF
  cat > "$package_dir/scripts/attach_folder_action.sh" <<'EOF'
#!/bin/zsh
print -r -- "attach" >> "${MEETINGNOTES_TEST_CALLS:?}"
EOF
  chmod +x "$package_dir/scripts/gen_launchd.sh" \
    "$package_dir/scripts/attach_folder_action.sh"
  touch "$package_dir/launchd/com.meetingnotes.plist.template"
}

mock_bin="$tmp/mock-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/launchctl" <<'EOF'
#!/bin/zsh
exit 0
EOF
cat > "$mock_bin/plutil" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$mock_bin"/*

# 非 arm64 必须在创建安装目录前退出。
unsupported="$tmp/unsupported"
make_package "$unsupported"
if HOME="$tmp/home-unsupported" \
  MEETINGNOTES_UNAME_M=x86_64 MEETINGNOTES_UNAME_S=Darwin \
  MEETINGNOTES_INSTALL_DIR="$tmp/home-unsupported/MeetingNotes" \
  "$unsupported/scripts/bootstrap_mac.sh" >"$tmp/unsupported.log" 2>&1; then
  echo "FAIL unsupported architecture accepted"
  exit 1
fi
[[ ! -e "$tmp/home-unsupported/MeetingNotes" ]] \
  || { echo "FAIL unsupported architecture wrote state"; exit 1; }

package="$tmp/下载目录/MeetingNotes 安装包"
home="$tmp/home"
target="$home/MeetingNotes"
calls="$tmp/calls.log"
mkdir -p "$home/Library/LaunchAgents"
mkdir -p "$home/Desktop"
make_package "$package"

PATH="$mock_bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_UNAME_S=Darwin \
MEETINGNOTES_INSTALL_DIR="$target" \
MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
MEETINGNOTES_TEST_CALLS="$calls" \
DEEPSEEK_API_KEY="test-key-one" \
  "$package/scripts/bootstrap_mac.sh"

[[ -x "$target/scripts/bootstrap_mac.sh" ]] || { echo "FAIL settle"; exit 1; }
canonical_target="${target:A}"
[[ -L "$target/录音" && "$(readlink "$target/录音")" == "$canonical_target/inbox" ]] \
  || { echo "FAIL visible inbox"; exit 1; }
[[ -L "$target/纪要" && "$(readlink "$target/纪要")" == "$canonical_target/output" ]] \
  || { echo "FAIL visible output"; exit 1; }
[[ -L "$home/Desktop/MeetingNotes 录音" ]] || { echo "FAIL desktop entry"; exit 1; }
[[ ! -e "$target/models/should-not-copy" ]] || { echo "FAIL copied models"; exit 1; }
[[ ! -e "$target/inbox/should-not-copy.m4a" ]] || { echo "FAIL copied inbox"; exit 1; }
[[ ! -e "$target/output/should-not-copy.md" ]] || { echo "FAIL copied output"; exit 1; }
[[ ! -e "$target/venv/should-not-copy" ]] || { echo "FAIL copied venv"; exit 1; }
[[ ! -e "$target/.menubar_label" ]] || { echo "FAIL copied path-bound menu bar label"; exit 1; }
grep -q "test-key-one" "$target/config.local.sh" || { echo "FAIL config"; exit 1; }
[[ "$(stat -f '%Lp' "$target/config.local.sh")" == 600 ]] || { echo "FAIL config mode"; exit 1; }
for expected in fetch_python.sh fetch_ffmpeg.sh provision_models.sh provision_menubar.sh attach; do
  grep -q "$expected" "$calls" || { echo "FAIL missing $expected"; exit 1; }
done

# 再次运行保留配置；不会重新向用户索取或覆盖 key。
PATH="$mock_bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_UNAME_S=Darwin \
MEETINGNOTES_INSTALL_DIR="$target" \
MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
MEETINGNOTES_TEST_CALLS="$calls" \
DEEPSEEK_API_KEY="must-not-replace" \
  "$target/scripts/bootstrap_mac.sh"
grep -q "test-key-one" "$target/config.local.sh" || { echo "FAIL config overwritten"; exit 1; }
! grep -q "must-not-replace" "$target/config.local.sh" \
  || { echo "FAIL new key replaced existing config"; exit 1; }
! grep -q "test-key-one" "$target/logs/bootstrap.log" \
  || { echo "FAIL key leaked to log"; exit 1; }
grep -Fq 'MEETINGNOTES_INSTALLER_KEY' "$target/scripts/bootstrap_mac.sh" \
  || { echo "FAIL native installer key handoff missing"; exit 1; }
grep -Fq 'MEETINGNOTES_INSTALLER_BASE_URL' "$target/scripts/bootstrap_mac.sh" \
  || { echo "FAIL custom provider handoff missing"; exit 1; }

# 中途失败后重跑应保留已写配置，并从幂等步骤继续完成。
retry_package="$tmp/retry-package"
retry_home="$tmp/retry-home"
retry_target="$retry_home/MeetingNotes"
retry_marker="$tmp/fail-once.marker"
retry_calls="$tmp/retry-calls.log"
mkdir -p "$retry_home/Library/LaunchAgents"
mkdir -p "$retry_home/Desktop"
make_package "$retry_package"
cat > "$retry_package/scripts/fetch_ffmpeg.sh" <<'EOF'
#!/bin/zsh
if [[ ! -e "${MEETINGNOTES_TEST_FAIL_ONCE:?}" ]]; then
  : > "$MEETINGNOTES_TEST_FAIL_ONCE"
  exit 1
fi
print -r -- "fetch_ffmpeg.sh" >> "${MEETINGNOTES_TEST_CALLS:?}"
EOF
chmod +x "$retry_package/scripts/fetch_ffmpeg.sh"
if PATH="$mock_bin:/usr/bin:/bin" HOME="$retry_home" \
  MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_UNAME_S=Darwin \
  MEETINGNOTES_INSTALL_DIR="$retry_target" \
  MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
  MEETINGNOTES_TEST_CALLS="$retry_calls" \
  MEETINGNOTES_TEST_FAIL_ONCE="$retry_marker" \
  DEEPSEEK_API_KEY="retry-key" \
    "$retry_package/scripts/bootstrap_mac.sh" >"$tmp/retry-first.log" 2>&1; then
  echo "FAIL injected failure was ignored"
  exit 1
fi
grep -q "retry-key" "$retry_target/config.local.sh" || { echo "FAIL retry config missing"; exit 1; }
PATH="$mock_bin:/usr/bin:/bin" HOME="$retry_home" \
  MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_UNAME_S=Darwin \
  MEETINGNOTES_INSTALL_DIR="$retry_target" \
  MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
  MEETINGNOTES_TEST_CALLS="$retry_calls" \
  MEETINGNOTES_TEST_FAIL_ONCE="$retry_marker" \
  DEEPSEEK_API_KEY="must-not-replace-retry" \
    "$retry_target/scripts/bootstrap_mac.sh" >/dev/null
grep -q "retry-key" "$retry_target/config.local.sh" || { echo "FAIL retry overwrote config"; exit 1; }
grep -q "attach" "$retry_calls" || { echo "FAIL retry did not complete"; exit 1; }

echo "PASS"
