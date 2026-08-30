#!/bin/zsh
set -eu
ROOT="${0:A:h:h}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
app="$tmp/MeetingNotes 安装器.app"
"$ROOT/scripts/build_installer_app.sh" "$app" >/dev/null
[[ -x "$app/Contents/MacOS/MeetingNotes Installer" ]] || { echo "FAIL executable"; exit 1; }
plutil -lint "$app/Contents/Info.plist" >/dev/null || { echo "FAIL plist"; exit 1; }
[[ -s "$app/Contents/Resources/MeetingNotes.icns" ]] || { echo "FAIL app icon"; exit 1; }
[[ "$(plutil -extract CFBundleIconFile raw "$app/Contents/Info.plist")" == MeetingNotes ]] \
  || { echo "FAIL icon plist"; exit 1; }
file "$app/Contents/MacOS/MeetingNotes Installer" | grep -q 'arm64' || { echo "FAIL arm64"; exit 1; }
strings "$app/Contents/MacOS/MeetingNotes Installer" | grep -q '@@MEETINGNOTES@@' || { echo "FAIL protocol"; exit 1; }
grep -Fq '请先填写 DeepSeek API Key' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL key validation"; exit 1; }
grep -Fq 'DeepSeek\n推荐 · 开箱即用' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recommended provider"; exit 1; }
grep -Fq '其他服务\nOpenAI 兼容' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL custom provider option"; exit 1; }
grep -Fq 'providerCard:@"DeepSeek' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL DeepSeek card"; exit 1; }
grep -Fq 'providerCard:@"其他服务' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL custom provider card"; exit 1; }
grep -Fq 'bezelColor=self.customProviderSelected' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL selected card highlight"; exit 1; }
grep -Fq 'x:40 y:246 w:120 h:20' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL service title position"; exit 1; }
grep -Fq 'x:40 y:164 w:260 h:52' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL service card spacing"; exit 1; }
# 选择/拖入只是暂存待确认，不立即处理；点“开始解析”才真正入队
grep -Fq '[self selectRecording:panel.URL]' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL chooser should stage, not enqueue"; exit 1; }
grep -Fq '[self.controller selectRecording:url]' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL drop should stage, not enqueue"; exit 1; }
grep -Fq '@"开始解析" action:@selector(startParsing:)' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL missing 开始解析 button"; exit 1; }
grep -Fq '[self enqueueRecording:url]' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL 开始解析 does not enqueue"; exit 1; }
# 待确认态：用 ✕ 删除已选文件、去掉“重选”按钮（不抢主视觉）
grep -Fq '@"✕" target:self action:@selector(reselectRecording:)' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL missing ✕ clear button"; exit 1; }
grep -Fq '@"重选"' "$ROOT/installer/MeetingNotesInstaller.m" && { echo "FAIL 重选 button should be removed"; exit 1; }
# 拖放区下方队列状态区：读 .pet_state（正在处理）+ 数 inbox（等待计数），与桌面小猫联动
grep -Fq 'updateStatus' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL missing queue status area"; exit 1; }
grep -Fq '@".pet_state"' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL status must read .pet_state"; exit 1; }
grep -Fq 'inboxAudioCount' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL waiting count must derive from inbox"; exit 1; }
grep -Fq '个排队等待' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL missing waiting-count text"; exit 1; }
# 不再写死“已加入…正在等待”那行（处理完不消失的 bug）
grep -Fq '正在等待小猫处理' "$ROOT/installer/MeetingNotesInstaller.m" && { echo "FAIL stale one-shot status must be removed"; exit 1; }
# 完成页不再有“完成”按钮（关窗走标题栏红点）
grep -Fq '@"完成" action:@selector(cancel:)' "$ROOT/installer/MeetingNotesInstaller.m" && { echo "FAIL 完成 button should be removed"; exit 1; }
grep -Fq 'applicationShouldTerminateAfterLastWindowClosed' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL should quit on window close"; exit 1; }
grep -Fq 'copyItemAtURL:sourceURL' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recording is not copied safely"; exit 1; }
grep -Fq 'registerForDraggedTypes:@[NSPasteboardTypeFileURL]' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recording drop target"; exit 1; }
grep -Fq 'stringByAppendingPathComponent:@"inbox"' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recording queue path"; exit 1; }
grep -Fq 'kick.arguments=@[script]' "$ROOT/installer/MeetingNotesInstaller.m" || { echo "FAIL recording processing kick"; exit 1; }
echo PASS
