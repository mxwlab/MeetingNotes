#!/bin/zsh
set -eu

ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
package="$tmp/新版 安装包"
home="$tmp/旧用户"
target="$home/MeetingNotes"
calls="$tmp/calls"
mkdir -p "$package/scripts" "$package/launchd" "$home/Desktop" \
  "$home/Library/LaunchAgents" "$target/inbox" "$target/output" "$target/done" \
  "$tmp/mock-bin"

cp "$ROOT/scripts/bootstrap_mac.sh" "$package/scripts/"
cp "$ROOT/scripts/prompt_deepseek_key.applescript" "$package/scripts/"
touch "$package/process.py" "$package/watch_inbox.sh" "$package/watch_downloads.sh" \
  "$package/requirements.txt"
echo old-audio > "$target/inbox/保留录音.m4a"
echo old-note > "$target/output/保留纪要.md"
echo done-audio > "$target/done/已完成.m4a"
printf 'export DEEPSEEK_API_KEY=old-key\nexport OBSIDIAN_DIR=/old/vault\n' > "$target/config.local.sh"
chmod 600 "$target/config.local.sh"

for helper in fetch_python.sh fetch_ffmpeg.sh provision_models.sh provision_menubar.sh; do
  cat > "$package/scripts/$helper" <<EOF
#!/bin/zsh
print -r -- "$helper" >> "\${MEETINGNOTES_TEST_CALLS:?}"
EOF
  chmod +x "$package/scripts/$helper"
done
cat > "$package/scripts/gen_launchd.sh" <<'EOF'
#!/bin/zsh
echo '<plist><dict></dict></plist>'
EOF
cat > "$package/scripts/attach_folder_action.sh" <<'EOF'
#!/bin/zsh
print -r -- attach >> "${MEETINGNOTES_TEST_CALLS:?}"
EOF
chmod +x "$package/scripts/gen_launchd.sh" "$package/scripts/attach_folder_action.sh"

cat > "$tmp/mock-bin/launchctl" <<'EOF'
#!/bin/zsh
print -r -- "$*" >> "${MEETINGNOTES_TEST_CALLS:?}"
exit 0
EOF
cat > "$tmp/mock-bin/plutil" <<'EOF'
#!/bin/zsh
exit 0
EOF
chmod +x "$tmp/mock-bin/"*

PATH="$tmp/mock-bin:/usr/bin:/bin" HOME="$home" \
MEETINGNOTES_UNAME_S=Darwin MEETINGNOTES_UNAME_M=arm64 MEETINGNOTES_MACOS_MAJOR=14 \
MEETINGNOTES_INSTALL_DIR="$target" MEETINGNOTES_BOOTSTRAP_TEST_MODE=true \
MEETINGNOTES_TEST_CALLS="$calls" DEEPSEEK_API_KEY=must-not-replace \
  "$package/scripts/bootstrap_mac.sh" >/dev/null

grep -Fq old-key "$target/config.local.sh" || { echo "FAIL key replaced"; exit 1; }
grep -Fq '/old/vault' "$target/config.local.sh" || { echo "FAIL Obsidian path lost"; exit 1; }
grep -Fq old-audio "$target/inbox/保留录音.m4a" || { echo "FAIL inbox lost"; exit 1; }
grep -Fq old-note "$target/output/保留纪要.md" || { echo "FAIL output lost"; exit 1; }
grep -Fq done-audio "$target/done/已完成.m4a" || { echo "FAIL done lost"; exit 1; }
grep -Fq provision_menubar.sh "$calls" || { echo "FAIL menu bar not added"; exit 1; }
[[ "$(grep -c '^bootstrap ' "$calls")" == 1 ]] \
  || { echo "FAIL duplicate background bootstrap"; exit 1; }

echo PASS
