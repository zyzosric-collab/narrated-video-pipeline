#!/usr/bin/env python3
"""Generate the Episode Overlay section for frame.md (avoids bash heredoc UTF-8 issues)."""
import sys

import yaml

ep = sys.argv[1]
c = yaml.safe_load(open(f"{ep}/episode.yaml"))
aspect, w, h, preset = c["aspect"], c["width"], c["height"], c["preset"]
preset_name = {
    "blue-professional": "Blue Professional",
    "capsule": "Capsule",
    "broadside": "Broadside",
    "coral": "Coral",
    "daisy-days": "Daisy Days",
    "cartesian": "Cartesian",
    "cobalt-grid": "Cobalt Grid",
    "bold-poster": "Bold Poster",
    "blockframe": "Blockframe",
    "biennale-yellow": "Biennale Yellow",
    "editorial-forest": "Editorial Forest",
    "claude": "Claude",
    "creative-mode": "Creative Mode",
}.get(preset, preset.replace("-", " ").title())

overlay = f"""

---

# Episode Overlay（本集适配，优先级高于上方模板 prose）

## Canvas

- 本集画幅：**{aspect}（{w}×{h}）**。上方模板以 1920×1080 为主尺度书写的几何值，
  按 cqw 单位等比生效；绝对 px 值按短边等比换算。
- 画幅适配：display 区与索引区按 Aspect-Ratio Behavior 表的 {aspect} 列排布；
  对角面板在竖屏时转为上下横带。
- 每个构图根节点必须声明 data-width="{w}" data-height="{h}"。

## Typography for CJK（中文配对，预设官方方案）

- 中文标题：Noto Sans SC 700（承接 display 角色）
- 中文正文：Noto Serif SC 400 / Hiragino Sans GB fallback（承接 body 角色）
- 数字保持 Latin 阿拉伯数字，中西文之间留 0.15em 间距
- eyebrow 的 uppercase+tracking 信号在 CJK 弱化，一律加 accent-line（4px primary 短线）补足

## Caption（卡拉OK字幕契约）

- 字幕皮肤：{preset_name} caption-skin（当前词 primary chip / 已读墨色 / 未读灰）
- 词级时间：voice-timing.json 的 words[]（豆包 TTS 实测 startTime/endTime）
- 位置：底部 band，不与 display 区冲突；band 内安全边距 = pad-x

## Hard Rules（镜头级硬约束，违反即验收失败）

- 色板/字体/间距只能取自本文件 frontmatter tokens，禁止自选配色，尤其禁止深色底
- 背景必须为暖奶油纸面（colors.canvas），文字用 text 阶梯，强调只用 primary
- 零散元素对齐到预设 spacing 网格，禁止随手 px
"""
sys.stdout.write(overlay)
