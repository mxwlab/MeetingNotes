"""构建用户双击的 MeetingNotes 主窗口应用。"""
from setuptools import setup

APP = ["ui/main.py"]
OPTIONS = {
    "argv_emulation": False,
    "packages": ["ui"],
    "plist": {
        "CFBundleDisplayName": "MeetingNotes",
        "CFBundleIdentifier": "com.moxiuwen.meetingnotes",
        "LSUIElement": False,
    },
}
setup(name="MeetingNotes", app=APP, options={"py2app": OPTIONS}, setup_requires=["py2app"])
