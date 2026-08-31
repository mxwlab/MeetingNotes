"""构建独立的 MeetingNotes 菜单栏 macOS 应用。"""

import os
import re

from setuptools import setup


APP = ["ui/menubar.py"]
BUNDLE_IDENTIFIER = os.environ.get(
    "MEETINGNOTES_MENUBAR_BUNDLE_ID", "com.moxiuwen.meetingnotes.menubar"
)
if not re.fullmatch(r"[A-Za-z0-9.-]+", BUNDLE_IDENTIFIER):
    raise SystemExit(f"invalid menu bar bundle identifier: {BUNDLE_IDENTIFIER}")
OPTIONS = {
    "argv_emulation": False,
    "packages": ["ui"],
    "plist": {
        "CFBundleDisplayName": "MeetingNotes",
        "CFBundleIdentifier": BUNDLE_IDENTIFIER,
        "LSUIElement": True,
    },
}

setup(
    name="MeetingNotes 菜单栏",
    app=APP,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
