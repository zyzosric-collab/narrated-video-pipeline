#!/usr/bin/env python3
"""Extract the user's numbered segment draft from script.md without rewriting text."""
from __future__ import annotations
import json
import re
import sys
from pathlib import Path

src = Path(sys.argv[1])
out = Path(sys.argv[2])
text = src.read_text(encoding="utf-8")
start = text.find("【分段稿")
first_rule = text.find("--------------------------------------------------------------------------------", start)
end = text.find("--------------------------------------------------------------------------------", first_rule + 1)
if start < 0 or first_rule < 0 or end < 0:
    raise SystemExit("分段稿区块不存在")
section = text[first_rule + len("--------------------------------------------------------------------------------"):end]
style_map = {
    "hook": "counterintuitive_hook",
    "setup": "tech_explainer",
    "point1": "evidence_explainer",
    "point2": "evidence_explainer",
    "pain": "tech_explainer",
    "turn": "tech_explainer",
    "reveal": "counterintuitive_hook",
    "point": "evidence_explainer",
    "sublime": "conclusion",
    "cta": "conclusion",
}
segments = []
for m in re.finditer(r"^\s*(\d+)\.\s*\[([^]]+)\]\s*(.*?)(?=^\s*\d+\.\s*\[|\Z)", section, re.M | re.S):
    idx = int(m.group(1))
    raw_style = m.group(2).strip()
    style = style_map.get(raw_style, raw_style)
    body = re.sub(r"\s+", "", m.group(3))
    if body:
        segments.append({"index": idx, "style": style, "text": body})
if not segments:
    raise SystemExit("没有解析到分段")
indices = [s["index"] for s in segments]
if indices != list(range(1, len(indices) + 1)):
    raise SystemExit(f"分段编号不连续: {indices}")
out.write_text(json.dumps(segments, ensure_ascii=False, indent=2), encoding="utf-8")
print(json.dumps({"segments": len(segments), "indices": indices}, ensure_ascii=False))
