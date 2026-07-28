#!/bin/zsh
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Unsupported architecture must stop before producing any state.
if MEETINGNOTES_UNAME_M=x86_64 "$ROOT/install.sh" --dry-run >"$tmp/nonarm.log" 2>&1; then
  echo "FAIL non-arm64 accepted"
  exit 1
fi
grep -q "Apple Silicon" "$tmp/nonarm.log" || { echo "FAIL non-arm64 message"; exit 1; }

# Build a fully isolated project and HOME, with external tools replaced by
# deterministic local fakes. No real package, launchd, or Folder Action state
# is touched.
project="$tmp/project"
home="$tmp/home"
mock_bin="$tmp/mock-bin"
mkdir -p "$project/scripts" "$project/launchd" "$home/Downloads" "$mock_bin"
cp "$ROOT/install.sh" "$project/"
cp "$ROOT/requirements.txt" "$project/"
cp "$ROOT/watch_inbox.sh" "$ROOT/watch_downloads.sh" "$project/"
touch "$project/launchd/com.meetingnotes.plist.template"

for helper in provision_fluidaudio.sh provision_models.sh attach_folder_action.sh; do
  cat > "$project/scripts/$helper" <<EOF
#!/bin/zsh
touch "$tmp/$helper.called"
EOF
  chmod +x "$project/scripts/$helper"
done
cat > "$project/scripts/gen_launchd.sh" <<'EOF'
#!/bin/zsh
cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>Label</key><string>com.meetingnotes.test</string>
</dict></plist>
PLIST
EOF
chmod +x "$project/scripts/gen_launchd.sh"

cat > "$mock_bin/python3" <<'EOF'
#!/bin/zsh
set -eu
if [[ "$1" == "-c" ]]; then
  echo "3.10"
  exit 0
fi
if [[ "$1" == "-m" && "$2" == "venv" ]]; then
  target="$3"
  mkdir -p "$target/bin"
  cat > "$target/bin/python" <<'PY'
#!/bin/zsh
exit 0
PY
  chmod +x "$target/bin/python"
  exit 0
fi
exit 2
EOF
cat > "$mock_bin/brew" <<EOF
#!/bin/zsh
print -r -- "\$*" >> "$tmp/brew.log"
EOF
cat > "$mock_bin/xcode-select" <<'EOF'
#!/bin/zsh
[[ "$1" == "-p" ]] && { echo /Library/Developer/CommandLineTools; exit 0; }
exit 1
EOF
cat > "$mock_bin/launchctl" <<EOF
#!/bin/zsh
print -r -- "\$*" >> "$tmp/launchctl.log"
exit 0
EOF
chmod +x "$mock_bin"/*

HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
MEETINGNOTES_UNAME_S=Darwin MEETINGNOTES_UNAME_M=arm64 \
MEETINGNOTES_PYTHON="$mock_bin/python3" \
DEEPSEEK_API_KEY="test-key" OBSIDIAN_DIR="" \
  "$project/install.sh" --non-interactive

[[ -x "$project/venv/bin/python" ]] || { echo "FAIL venv"; exit 1; }
[[ -f "$tmp/provision_fluidaudio.sh.called" ]] || { echo "FAIL FluidAudio step"; exit 1; }
[[ -f "$tmp/provision_models.sh.called" ]] || { echo "FAIL model step"; exit 1; }
[[ -f "$tmp/attach_folder_action.sh.called" ]] || { echo "FAIL Folder Action step"; exit 1; }
[[ -f "$project/config.local.sh" ]] || { echo "FAIL config"; exit 1; }
[[ "$(stat -f '%Lp' "$project/config.local.sh")" == 600 ]] || { echo "FAIL config mode"; exit 1; }
grep -q "test-key" "$project/config.local.sh" || { echo "FAIL config key"; exit 1; }
plist=("$home/Library/LaunchAgents"/com.meetingnotes.*.plist(N))
[[ ${#plist} == 1 ]] || { echo "FAIL launchd plist"; exit 1; }
grep -q "bootstrap" "$tmp/launchctl.log" || { echo "FAIL launchctl bootstrap"; exit 1; }

echo "PASS"
