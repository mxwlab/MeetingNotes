"""MeetingNotes 主窗口：拖放/选择录音，并把文件送入后台队列。"""
import os
import shutil
import subprocess
import threading
import time
from pathlib import Path

import objc
from AppKit import (
    NSApp,
    NSApplication,
    NSApplicationActivationPolicyRegular,
    NSButton,
    NSColor,
    NSFont,
    NSImageView,
    NSMakeRect,
    NSOpenPanel,
    NSPasteboardTypeFileURL,
    NSTextField,
    NSView,
    NSWindow,
    NSWindowStyleMaskClosable,
    NSWindowStyleMaskTitled,
    NSWindowStyleMaskMiniaturizable,
    NSBackingStoreBuffered,
    NSModalResponseOK,
)
from Foundation import NSURL, NSObject

def resolve_base():
    override = os.environ.get("MEETINGNOTES_BASE")
    if override:
        return Path(override)
    marker = Path.home() / "Library" / "Application Support" / "MeetingNotes" / "base"
    if marker.is_file():
        value = marker.read_text(encoding="utf-8").strip()
        if value:
            return Path(value)
    return Path.home() / "MeetingNotes"


BASE = resolve_base()
INBOX = BASE / "inbox"


class DropView(NSView):
    controller = objc.ivar()
    hovering = objc.ivar()

    def initWithFrame_(self, frame):
        self = objc.super(DropView, self).initWithFrame_(frame)
        if self:
            self.hovering = False
            self.registerForDraggedTypes_([NSPasteboardTypeFileURL])
        return self

    def drawRect_(self, _):
        stroke = NSColor.controlAccentColor() if self.hovering else NSColor.separatorColor()
        stroke.setStroke()
        path = __import__("AppKit").NSBezierPath.bezierPathWithRoundedRect_xRadius_yRadius_(self.bounds(), 14, 14)
        path.setLineWidth_(2.0 if self.hovering else 1.0)
        path.setLineDash_count_phase_([7.0, 5.0], 2, 0)
        path.stroke()
        self.draw_text("拖入一段会议录音", 17, 150, 48, True)
        self.draw_text("松开后立即开始处理", 13, 157, 80, False)

    def draw_text(self, value, size, x, y, bold):
        attrs = {"NSFont": NSFont.systemFontOfSize_weight_(size, 0.6 if bold else 0.0), "NSForegroundColor": NSColor.labelColor() if bold else NSColor.secondaryLabelColor()}
        from Foundation import NSString
        NSString.stringWithString_(value).drawAtPoint_withAttributes_((x, y), attrs)

    def draggingEntered_(self, _):
        self.hovering = True
        self.setNeedsDisplay_(True)
        return 1

    def draggingExited_(self, _):
        self.hovering = False
        self.setNeedsDisplay_(True)

    def performDragOperation_(self, info):
        self.hovering = False
        self.setNeedsDisplay_(True)
        urls = info.draggingPasteboard().readObjectsForClasses_options_([NSURL], {"NSPasteboardURLReadingFileURLsOnlyKey": True})
        if urls:
            self.controller.enqueue_(Path(urls[0].path()))
            return True
        return False


class MainDelegate(NSObject):
    window = objc.ivar()
    status = objc.ivar()

    def applicationDidFinishLaunching_(self, _):
        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(NSMakeRect(0, 0, 680, 540), NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable, NSBackingStoreBuffered, False)
        self.window.setTitle_("MeetingNotes")
        self.window.center()
        content = self.window.contentView()
        icon = NSImageView.alloc().initWithFrame_(NSMakeRect(36, 472, 32, 32))
        icon.setImage_(NSApp.applicationIconImage())
        content.addSubview_(icon)
        self.draw_label(content, "MeetingNotes", 78, 478, 15, True)
        self.draw_label(content, "把录音变成清晰、可搜索的会议纪要", 48, 416, 28, True)
        self.draw_label(content, "支持两种方式：拖入录音，或直接从手机 AirDrop 到这台 Mac。", 48, 382, 15, False)
        drop = DropView.alloc().initWithFrame_(NSMakeRect(48, 184, 584, 166))
        drop.controller = self
        content.addSubview_(drop)
        self.draw_label(content, "AirDrop 收到的录音会自动进入队列，不需要一直打开这个窗口。", 48, 152, 13, False)
        choose = NSButton.alloc().initWithFrame_(NSMakeRect(48, 94, 180, 38))
        choose.setTitle_("选择录音文件")
        choose.setBezelStyle_(1)
        choose.setTarget_(self)
        choose.setAction_("choose:")
        content.addSubview_(choose)
        open_folder = NSButton.alloc().initWithFrame_(NSMakeRect(242, 94, 180, 38))
        open_folder.setTitle_("打开录音文件夹")
        open_folder.setBezelStyle_(1)
        open_folder.setTarget_(self)
        open_folder.setAction_("openFolder:")
        content.addSubview_(open_folder)
        self.status = self.draw_label(content, "等待加入第一段录音", 48, 48, 13, False)
        self.window.makeKeyAndOrderFront_(None)
        NSApp.activateIgnoringOtherApps_(True)

    def draw_label(self, parent, text, x, y, size, bold):
        field = NSTextField.alloc().initWithFrame_(NSMakeRect(x, y, 590, 28))
        field.setStringValue_(text)
        field.setFont_(NSFont.systemFontOfSize_weight_(size, 0.6 if bold else 0.0))
        field.setTextColor_(NSColor.labelColor() if bold else NSColor.secondaryLabelColor())
        field.setBezeled_(False)
        field.setDrawsBackground_(False)
        field.setEditable_(False)
        field.setSelectable_(False)
        parent.addSubview_(field)
        return field

    def choose_(self, _):
        panel = NSOpenPanel.openPanel()
        panel.setTitle_("选择会议录音")
        panel.setPrompt_("开始处理")
        panel.setCanChooseFiles_(True)
        panel.setCanChooseDirectories_(False)
        if panel.runModal() == NSModalResponseOK and panel.URL():
            self.enqueue_(Path(panel.URL().path()))

    def openFolder_(self, _):
        INBOX.mkdir(parents=True, exist_ok=True)
        subprocess.run(["open", str(INBOX)], check=False)

    def enqueue_(self, source):
        """把录音复制进 inbox。复制可能耗时（大文件），放后台线程做，避免卡住界面。"""
        try:
            INBOX.mkdir(parents=True, exist_ok=True)
            target = INBOX / source.name
            if target.exists():
                target = INBOX / f"{source.stem}-{int(time.time())}{source.suffix}"
        except OSError as exc:
            self.status.setStringValue_(f"加入失败：{exc}")
            return
        self.status.setStringValue_(f"正在复制：{source.name}…")
        threading.Thread(target=self._copy_worker, args=(source, target), daemon=True).start()

    def _copy_worker(self, source, target):
        # 后台线程不能碰 AppKit UI，完成后切回主线程更新状态并触发 watcher
        try:
            shutil.copy2(source, target)
            self.performSelectorOnMainThread_withObject_waitUntilDone_(
                "enqueueDone:", f"已加入：{source.name}，正在等待处理…", False)
        except OSError as exc:
            self.performSelectorOnMainThread_withObject_waitUntilDone_(
                "enqueueDone:", f"加入失败：{exc}", False)

    def enqueueDone_(self, message):
        self.status.setStringValue_(message)
        if not message.startswith("加入失败"):
            watcher = BASE / "watch_inbox.sh"
            if watcher.exists():
                subprocess.Popen(["/bin/zsh", str(watcher)],
                                 stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    app = NSApplication.sharedApplication()
    app.setActivationPolicy_(NSApplicationActivationPolicyRegular)
    delegate = MainDelegate.alloc().init()
    app.setDelegate_(delegate)
    app.run()
