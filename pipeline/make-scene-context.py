#!/usr/bin/env python3
"""生成每镜头契约包 scene-context.md（性能优化①，2026-09-01 用户批准）。

用法: python3 make-scene-context.py <epDir>
- 在 Codex 拆镜完成后、Claude 执行前运行。
- 每个 lens 目录生成 scene-context.md（≤2KB）：
  frame.md 关键 tokens + 本镜头词级时间摘要 + 必守规则 + 命中特效技能要点。
- 同时改写该镜头 run-claude-ai.sh 的 prompt 头部：
  「第一件事读 scene-context.md，除命中的特效技能外无需浏览其他技能文档」。
"""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

ep = Path(sys.argv[1])
run = ep / "run"
scenes_dir = run / "scenes"
frame_path = run / "frame.md"

frame = frame_path.read_text(encoding="utf-8") if frame_path.exists() else ""

def extract_frame_tokens(frame_text: str) -> str:
    """从 FRAME.md frontmatter 提取 colors/typography/spacing 关键行。"""
    lines = []
    keep = False
    for ln in frame_text.splitlines():
        if re.match(r"^(colors|typography|spacing|radii):", ln):
            keep = True
            lines.append(ln)
            continue
        if keep:
            if re.match(r"^\S", ln):  # 新的顶层 key，停止
                keep = False
            else:
                lines.append(ln)
        if len(lines) > 60:
            break
    return "\n".join(lines[:60])

frame_tokens = extract_frame_tokens(frame)

RULES = """## 必守规则（违反即验收失败）
1. 色板/字体/间距/组件只能取自下方 tokens；禁止深色底、禁止自选配色。
2. 装饰元素（点阵/圆环/网格/线条）不得压在任何文字上。
3. 主视觉不得严重偏侧；遵循下方栅格；终帧必须是落定构图：无空占位节点、无悬空连线，汇聚线合并到有内容的终点节点。
4. 画面禁止出现字幕条、卡拉OK字幕、逐字口播文字；概念标签用短语不用整句。
5. 中文用 Noto Sans SC；Space Grotesk 仅用于数字和拉丁字符；禁止豆腐块。
6. 关键词/数字的出现时间必须对齐下方词级时间。
7. 片尾无任何 EP 编号。
8. 禁止 Date.now()、Math.random()、运行时网络请求；时间轴必须 paused + 可 seek。
9. 渲染完整时长，文案结束后的剩余时间保留为停顿/收尾。
10. 输出 mp4 必须放在当前镜头目录，文件名 = SCENE_ID.mp4。"""

def timing_summary(words: list[dict], max_words: int = 400) -> str:
    lines = ["## 本镜头词级时间（start=镜头内相对秒）"]
    for w in words[:max_words]:
        lines.append(f"{w['start']:.2f}-{w['end']:.2f} {w['word']}")
    return "\n".join(lines)

def skill_digest(skill_md: str, max_chars: int = 1200) -> str:
    """截取技能 SKILL.md 的实现要点（第一个 ## 之后的前 1200 字符）。"""
    m = re.search(r"^# .+?\n(.*)", skill_md, re.S)
    body = m.group(1) if m else skill_md
    body = re.sub(r"\n{3,}", "\n\n", body).strip()
    return body[:max_chars]

count = 0
for scene in sorted(scenes_dir.glob("scene-*")):
    if not scene.is_dir():
        continue
    st_path = scene / "scene-timing.json"
    words = []
    if st_path.exists():
        try:
            words = json.loads(st_path.read_text(encoding="utf-8")).get("words", [])
        except Exception:
            words = []

    # 命中的特效技能：从 run-claude-ai.sh 里 grep
    script = (scene / "run-claude-ai.sh").read_text(encoding="utf-8") if (scene / "run-claude-ai.sh").exists() else ""
    effect = None
    for m in re.finditer(r"(light-spotlight-render|svg-assembly-animator|pixel2motion|printed-curtain-render|threejs-earth-render|3d-chladni-render)", script):
        effect = m.group(1)
        break
    effect_block = ""
    if effect:
        sk = scene / ".claude" / "skills" / effect / "SKILL.md"
        if sk.exists():
            effect_block = f"\n## 特效技能要点：{effect}\n{skill_digest(sk.read_text(encoding='utf-8'))}\n"

    ctx = f"""# scene-context — {scene.name}
> 本文件是开工的唯一前置读物。除命中的特效技能外，无需再浏览其他技能文档。

## 设计 tokens（源自 frame.md，最高优先级）
{frame_tokens}

{RULES}

{timing_summary(words)}
{effect_block}
"""
    (scene / "scene-context.md").write_text(ctx, encoding="utf-8")

    # 改写 run-claude-ai.sh 的读取指令
    f = scene / "run-claude-ai.sh"
    t = f.read_text(encoding="utf-8")
    o = t
    t = t.replace(
        "第一件事先阅读 frame.md，再阅读",
        "第一件事先阅读 scene-context.md（内含 frame.md 全部关键 tokens、词级时间和必守规则），然后阅读",
    )
    t = t.replace(
        "第一件事先阅读 frame.md，",
        "第一件事先阅读 scene-context.md，",
    )
    if t != o:
        f.write_text(t, encoding="utf-8")
    count += 1

print(f"scene-context.md generated for {count} scenes")
