#!/usr/bin/env python3
"""桌面小猫：处理录音时出现在右下角，转录时显示真实进度条，干完等用户点击关闭。
由 process.py 启动，通过状态文件 ~/MeetingNotes/.pet_state 驱动，与转录/纪要逻辑解耦。
状态文件三行：状态(transcribe/summarize/done/fail) / 录音名 / 进度百分比(转录时用)。"""
import os
import tkinter as tk

STATE_FILE = os.path.expanduser("~/MeetingNotes/.pet_state")

WIN_W, WIN_H, MARGIN_X, MARGIN_Y, RADIUS = 214, 116, 24, 164, 20
CARD = "#23252b"
EDGE = "#3a3d45"
BAR_LEN = 10

# 状态：猫脸、状态文案、模式(progress/busy/static)、是否终态(等用户点击关闭)
STATES = {
    "transcribe": ("🐱", "🎧 听录音中", "progress", False),
    "summarize":  ("🐱", "✍️ 整理纪要中", "busy", False),
    "done":       ("😸", "🎉 纪要好了！", "static", True),
    "fail":       ("😿", "⚠️ 出错了，看日志", "static", True),
}
DOTS = ["", "·", "··", "···"]


class Pet:
    def __init__(self):
        self.root = tk.Tk()
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.resizable(False, False)
        try:
            self.root.wm_attributes("-transparent", True)   # macOS 透明背景 → 圆角
            bg = "systemTransparent"
        except tk.TclError:
            bg = CARD
        self.root.configure(bg=bg)

        sw, sh = self.root.winfo_screenwidth(), self.root.winfo_screenheight()
        x, y = sw - WIN_W - MARGIN_X, sh - WIN_H - MARGIN_Y
        self.root.geometry(f"{WIN_W}x{WIN_H}+{x}+{y}")

        self.canvas = tk.Canvas(self.root, width=WIN_W, height=WIN_H,
                                bg=bg, highlightthickness=0, bd=0)
        self.canvas.pack()
        self._round_rect(1, 1, WIN_W - 1, WIN_H - 1, RADIUS, fill=CARD, outline=EDGE)

        box = tk.Frame(self.canvas, bg=CARD)
        self.face = tk.Label(box, text="🐱", font=("Apple Color Emoji", 40), bg=CARD)
        self.face.pack()
        # 状态行：文案 + 接在后面的定宽后缀(百分比/动态点)，定宽 → 不抖动
        row = tk.Frame(box, bg=CARD)
        row.pack(pady=(2, 1))
        self.status = tk.Label(row, text="", font=("PingFang SC", 13), fg="#f0f0f0", bg=CARD)
        self.status.pack(side="left")
        self.suffix = tk.Label(row, text="", font=("Menlo", 12), anchor="w", fg="#8ab4f8", bg=CARD)
        self.suffix.pack(side="left")
        # 进度条单独一行，在弹窗里居中
        self.detail = tk.Label(box, text="", font=("Menlo", 12),
                               anchor="center", justify="center", fg="#9aa0aa", bg=CARD)
        self.detail.pack()
        self.canvas.create_window(WIN_W // 2, WIN_H // 2, window=box, anchor="center")
        self._box = box

        self.tick = 0
        self.closing = False
        self.terminal = False
        self._state = None
        self._dragged = False
        for w in (self.root, self.canvas, self._box, self.face, self.status, self.suffix, self.detail):
            w.bind("<ButtonPress-1>", self._start_move)
            w.bind("<B1-Motion>", self._on_move)
            w.bind("<ButtonRelease-1>", self._end_move)
        self.root.after(0, self.update)

    def _round_rect(self, x1, y1, x2, y2, r, **kw):
        pts = [x1+r, y1, x2-r, y1, x2, y1, x2, y1+r, x2, y2-r, x2, y2,
               x2-r, y2, x1+r, y2, x1, y2, x1, y2-r, x1, y1+r, x1, y1]
        return self.canvas.create_polygon(pts, smooth=True, **kw)

    def _start_move(self, e):
        self._ox, self._oy = e.x_root, e.y_root
        self._wx, self._wy = self.root.winfo_x(), self.root.winfo_y()
        self._dragged = False

    def _on_move(self, e):
        dx, dy = e.x_root - self._ox, e.y_root - self._oy
        if abs(dx) > 2 or abs(dy) > 2:
            self._dragged = True
        self.root.geometry(f"+{self._wx + dx}+{self._wy + dy}")

    def _end_move(self, e):
        if self.terminal and not self._dragged:
            self.close()

    def close(self, event=None):
        self.root.destroy()

    def read_state(self):
        try:
            with open(STATE_FILE, encoding="utf-8") as f:
                lines = f.read().splitlines()
            state = lines[0].strip() if lines else ""
            name = lines[1].strip() if len(lines) > 1 else ""
            extra = lines[2].strip() if len(lines) > 2 else ""
            return state, name, extra
        except FileNotFoundError:
            return None, "", ""
        except Exception:
            return "", "", ""

    def update(self):
        if self.closing:
            return
        state, name, extra = self.read_state()
        if state is None:                       # 状态文件消失 → 谢幕
            self.root.destroy()
            return

        info = STATES.get(state)
        if info:
            face, stext, mode, terminal = info
            if state != self._state:            # 状态变了才改猫脸/文案，避免每帧重绘
                self.face.config(text=face)
                self.status.config(text=stext)
                self._state = state
                if terminal:
                    self.suffix.config(text="", width=0)
                    self.detail.config(text="点此关闭 · 可拖动", fg="#c8ccd4")
                    self.terminal = True
                    self.closing = True
                    return
            if mode == "progress":
                try:
                    pct = max(0, min(100, int(extra)))
                except ValueError:
                    pct = 0
                filled = round(pct / 100 * BAR_LEN)
                bar = "█" * filled + "░" * (BAR_LEN - filled)
                self.suffix.config(text=f" {pct:>3}%", width=5, fg="#8ab4f8")   # 百分比接在"听录音中"后面
                self.detail.config(text=bar, fg="#8ab4f8")                        # 进度条单独一行、居中
            elif mode == "busy":
                self.suffix.config(text=DOTS[self.tick % len(DOTS)], width=4, fg="#9aa0aa")
                self.detail.config(text="")

        self.tick += 1
        self.root.after(300, self.update)

    def run(self):
        try:
            self.root.mainloop()
        except Exception:
            pass


if __name__ == "__main__":
    Pet().run()
