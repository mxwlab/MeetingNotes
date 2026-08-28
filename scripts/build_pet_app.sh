#!/bin/zsh
# 构建原生桌面进度小猫 MeetingNotesPet.app（accessory，不占 Dock）。
# 由 process.py 在处理录音时启动，读 .pet_state 显示白底原生进度卡片。
set -eu
BASE="${0:A:h:h}"
OUTPUT="${1:-$BASE/dist/MeetingNotesPet.app}"
APP_VERSION="${MEETINGNOTES_APP_VERSION:-0.2.0}"
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
rm -rf "$OUTPUT"
mkdir -p "$MACOS" "$RESOURCES"
clang -fobjc-arc -O2 -framework Cocoa \
  -mmacosx-version-min=14.0 "$BASE/installer/MeetingNotesPet.m" \
  -o "$MACOS/MeetingNotesPet"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MeetingNotesPet</string>
<key>CFBundleIdentifier</key><string>com.moxiuwen.meetingnotes.pet</string>
<key>CFBundleName</key><string>MeetingNotesPet</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
<key>CFBundleVersion</key><string>${APP_VERSION}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
chmod +x "$MACOS/MeetingNotesPet"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
echo "$OUTPUT"
