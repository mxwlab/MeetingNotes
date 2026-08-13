"""构建独立的 MeetingNotes 菜单栏 macOS 应用。"""

from setuptools import setup


APP = ["ui/menubar.py"]
OPTIONS = {
    "argv_emulation": False,
    "packages": ["ui"],
    "plist": {
        "CFBundleDisplayName": "MeetingNotes",
        "CFBundleIdentifier": "com.moxiuwen.meetingnotes.menubar",
        "LSUIElement": True,
    },
}

setup(
    name="MeetingNotes",
    app=APP,
    options={"py2app": OPTIONS},
    setup_requires=["py2app"],
)
