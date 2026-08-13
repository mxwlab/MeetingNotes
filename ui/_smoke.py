import rumps

class Smoke(rumps.App):
    def __init__(self):
        super().__init__("MeetingNotesSmoke", title="🐱 冒烟")
        self.menu = ["点我测试 Window", "点我测试 alert"]

    @rumps.clicked("点我测试 Window")
    def w(self, _):
        r = rumps.Window("输入点东西", "Window 测试", default_text="hi",
                         ok="确定", cancel="取消", secure=False).run()
        rumps.alert("你输入了", f"clicked={r.clicked} text={r.text!r}")

    @rumps.clicked("点我测试 alert")
    def a(self, _):
        n = rumps.alert("三按钮", "选一个", ok="重试", cancel="取消", other="跳过并保存")
        rumps.alert("结果", f"返回码={n}")

if __name__ == "__main__":
    Smoke().run()
