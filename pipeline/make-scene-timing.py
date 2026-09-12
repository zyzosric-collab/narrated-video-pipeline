#!/usr/bin/env python3
"""Copy frame/timing context into each scene and emit scene-relative word timing."""
from __future__ import annotations
import json
import shutil
import sys
from pathlib import Path

from yaml import safe_load

ep = Path(sys.argv[1])
run = ep / "run"
full = json.loads((ep / "voice-timing.json").read_text())
for scene in sorted((run / "scenes").glob("scene-*")):
    brief = scene / "scene-brief.md"
    timing = {"scene": scene.name, "words": []}
    # Use scene plan if available; otherwise derive by matching segment sentence indexes.
    text = brief.read_text(encoding="utf-8") if brief.exists() else ""
    import re
    nums = [int(x) for x in re.findall(r"(?:段|sentence|segment)\D{0,8}(\d+)", text, re.I)]
    if not nums:
        nums = [int(x) for x in re.findall(r"\b(\d+)\b", text)]
    allowed = set(nums)
    for w in full.get("words", []):
        if not allowed or w.get("sentence") in allowed:
            timing["words"].append(w)
    (scene / "scene-timing.json").write_text(json.dumps(timing, ensure_ascii=False, indent=2), encoding="utf-8")
    for name in ("frame.md", "voice-timing.json", "transcription.srt"):
        src = run / name
        if src.exists():
            shutil.copy2(src, scene / name)
print("scene timing context prepared")
