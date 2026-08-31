#!/bin/zsh
set -eu

BASE="${0:A:h:h}"
OUTPUT="${1:-$BASE/dist/MeetingNotes 安装器.app}"
APP_VERSION="${MEETINGNOTES_APP_VERSION:-0.2.0}"   # 发布时可传 MEETINGNOTES_APP_VERSION 对齐版本
CONTENTS="$OUTPUT/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

rm -rf "$OUTPUT"
mkdir -p "$MACOS" "$RESOURCES"
clang -fobjc-arc -O2 -framework Cocoa -framework UniformTypeIdentifiers \
  -mmacosx-version-min=14.0 \
  "$BASE/installer/MeetingNotesInstaller.m" \
  -o "$MACOS/MeetingNotes Installer"
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MeetingNotes Installer</string>
<key>CFBundleIdentifier</key><string>com.moxiuwen.meetingnotes.installer</string>
<key>CFBundleName</key><string>MeetingNotes 安装器</string>
<key>CFBundleDisplayName</key><string>MeetingNotes 安装器</string>
<key>CFBundleIconFile</key><string>MeetingNotes</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${APP_VERSION}</string>
<key>CFBundleVersion</key><string>${APP_VERSION}</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
chmod +x "$MACOS/MeetingNotes Installer"
cp "$BASE/assets/MeetingNotes.icns" "$RESOURCES/MeetingNotes.icns"
plutil -lint "$CONTENTS/Info.plist" >/dev/null
# clang 产物自带 linker ad-hoc signature，但它没有封装 bundle 资源。Chrome 下载后
# Gatekeeper 会把“签名与资源不一致”显示成 damaged；资源就位后重新签整个 app，
# 让本地双击与下载后的首次启动行为一致。
codesign --force --deep --sign - "$OUTPUT" >/dev/null
echo "$OUTPUT"
