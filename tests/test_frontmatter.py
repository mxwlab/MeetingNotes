import importlib, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))


def load():
    sys.modules.pop("process", None)
    return importlib.import_module("process")


NOTES = """# 会议纪要
## TL;DR
一句话。
## 参会人
张主任、清源、王某（前端）、其他
## 按参会人归纳
### 张主任
- 汇报
## 关键实体 / 术语
- **InfluxDB**：时序数据库
- 联通
- 飞客码（Figma）
## 未明确归属的要点
无
"""


def test_extract_participants():
    process = load()
    ppl = process._section_items(NOTES, "参会人")
    assert "张主任" in ppl and "清源" in ppl and "王某" in ppl
    assert all("（" not in p for p in ppl)  # 去掉括号注释


def test_extract_participants_skips_disclaimer_blockquote():
    process = load()
    notes = ("# 会议纪要\n## 参会人\n> 注：人名由语音识别推断，可能有误。\n\n"
             "郭总、张清源\n## 关键实体 / 术语\n无\n")
    ppl = process._section_items(notes, "参会人")
    assert "郭总" in ppl and "张清源" in ppl
    assert "注" not in ppl and "可能有误。" not in ppl  # 免责声明不进 frontmatter


def test_extract_entities():
    process = load()
    ents = process._section_items(NOTES, "关键实体")
    assert "InfluxDB" in ents and "联通" in ents and "飞客码" in ents


def test_missing_section_returns_empty():
    process = load()
    assert process._section_items(NOTES, "不存在的节") == []


def test_obsidian_appends_transcript():
    import tempfile, os
    from unittest import mock
    process = load()
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "vault"))
        process.OBSIDIAN_DIR = os.path.join(d, "vault", "会议纪要")
        with mock.patch.object(process, "log"):
            ok = process.save_to_obsidian("测试", NOTES, "a.m4a",
                                          transcript_md="## 话题一\n整理后的可读全文")
        assert ok
        files = [f for f in os.listdir(process.OBSIDIAN_DIR) if f.endswith(".md")]
        content = open(os.path.join(process.OBSIDIAN_DIR, files[0]), encoding="utf-8").read()
        assert "## 会议整理稿" in content          # 整理稿被接进来
        assert "整理后的可读全文" in content
        assert "participants:" in content         # frontmatter 仍在
        assert content.index("# 会议纪要") < content.index("## 会议整理稿")  # 纪要在上


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    failed = 0
    for fn in fns:
        try:
            fn(); print("PASS", fn.__name__)
        except Exception as e:
            failed += 1; print("FAIL", fn.__name__, "->", repr(e))
    print("DONE failures=", failed)
    sys.exit(1 if failed else 0)
