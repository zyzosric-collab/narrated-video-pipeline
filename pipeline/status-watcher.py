#!/usr/bin/env python3
"""Episode 渲染状态面板 v2 — 高对比度、独立配色（不依赖主题变量，避免灰底灰字）。

每 10s 重写 status.html；页面自身每 10s 自动刷新。
状态判定：完成 > 运行中(日志<300s) > 疑似停顿 > 排队中。
"""
from __future__ import annotations
import html
import json
import os
import time
from pathlib import Path
import sys

RUN = Path(sys.argv[1]).expanduser().resolve() if len(sys.argv) > 1 else Path.cwd()
OUT_HTML = Path(__file__).resolve().parent / "status.html"
_scenes = sorted(p.name for p in RUN.glob("scene-*")) if RUN.exists() else []
SCENES = _scenes or [f"scene-{i:03d}" for i in range(1, 13)]
MAX_SECONDS = 6 * 3600
START = time.time()

# 高对比配色（面板自带浅底，深色文字）
C_BG = "#f6f4ec"        # 面板底（暖纸）
C_CARD = "#ffffff"
C_TEXT = "#1a1a1a"
C_MUTED = "#6f6f6f"
C_BORDER = "#d8d4c8"
C_DONE = "#0a7d43"      # 绿
C_DONE_BG = "#e3f5ec"
C_RUN = "#1d4ed8"       # 蓝
C_RUN_BG = "#e8eefe"
C_WARN = "#b91c1c"      # 红
C_WARN_BG = "#fdeaea"
C_QUEUE = "#8a8574"     # 灰褐
C_QUEUE_BG = "#efede4"

STATUS_META = {
    "完成": (C_DONE, C_DONE_BG, "✓"),
    "运行中": (C_RUN, C_RUN_BG, "▶"),
    "疑似停顿": (C_WARN, C_WARN_BG, "⚠"),
    "排队中": (C_QUEUE, C_QUEUE_BG, "…"),
}


def read_tail(path: Path, nbytes: int = 262144) -> str:
    try:
        with open(path, "rb") as f:
            f.seek(0, 2)
            size = f.tell()
            f.seek(max(0, size - nbytes))
            return f.read().decode("utf-8", errors="ignore")
    except OSError:
        return ""


def last_tool(scene_dir: Path) -> str:
    text = read_tail(scene_dir / f"claude-{scene_dir.name}.stream.jsonl")
    last = ""
    for line in text.splitlines():
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("type") == "assistant":
            for c in e.get("message", {}).get("content", []):
                if c.get("type") == "tool_use":
                    name = c.get("name", "")
                    inp = c.get("input", {}) or {}
                    hint = inp.get("file_path") or inp.get("command") or inp.get("query") or ""
                    hint = str(hint)[:64].replace("<", "&lt;")
                    last = f"{name} · {hint}" if hint else name
    return last


def scene_state(name: str) -> dict:
    d = RUN / name
    mp4 = d / f"{name}.mp4"
    user_log = d / f"claude-{name}.user.log"
    stream = d / f"claude-{name}.stream.jsonl"
    state = {"id": name, "status": "排队中", "stages": [], "last_tool": "", "mp4": "", "log_size": "0 KB"}
    if not d.exists():
        return state
    if mp4.exists() and mp4.stat().st_size > 0:
        state["status"] = "完成"
        state["mp4"] = f"{mp4.stat().st_size / 1e6:.1f} MB"
    if user_log.exists():
        lines = [l.strip() for l in user_log.read_text(encoding="utf-8", errors="ignore").splitlines() if l.strip()]
        state["stages"] = lines[-6:]
    if stream.exists():
        size = stream.stat().st_size
        state["log_size"] = f"{size / 1e6:.1f} MB" if size > 1e6 else f"{size / 1e3:.0f} KB"
        age = time.time() - stream.stat().st_mtime
        if not (mp4.exists() and mp4.stat().st_size > 0):
            state["status"] = "运行中" if age < 300 else "疑似停顿"
        state["last_tool"] = last_tool(d)
    return state


def esc(s: str) -> str:
    return html.escape(str(s), quote=False)


def render(states: list[dict]) -> str:
    done = sum(1 for s in states if s["status"] == "完成")
    running = sum(1 for s in states if s["status"] == "运行中")
    warn = sum(1 for s in states if s["status"] == "疑似停顿")
    pct = int(done / len(states) * 100)
    now = time.strftime("%H:%M:%S")

    cards = []
    for s in states:
        color, bg, icon = STATUS_META[s["status"]]
        stages = "".join(
            f'<div style="font-size:12px;color:{C_DONE};margin-top:3px">✓ {esc(st)}</div>'
            for st in s["stages"]
        )
        tool = (
            f'<div style="font-size:12px;color:{C_TEXT};margin-top:8px;background:{C_BG};'
            f'border-radius:6px;padding:4px 8px;font-family:ui-monospace,Menlo,monospace">▸ {esc(s["last_tool"])}</div>'
            if s["last_tool"] else ""
        )
        mp4line = (
            f'<div style="font-size:12px;color:{C_DONE};font-weight:700;margin-top:8px">MP4 已生成 · {esc(s["mp4"])}</div>'
            if s["mp4"] else ""
        )
        cards.append(f"""
<div style="background:{C_CARD};border:1.5px solid {C_BORDER};border-left:5px solid {color};border-radius:12px;padding:12px 14px;min-width:250px;flex:1;box-shadow:0 1px 3px rgba(0,0,0,0.06)">
  <div style="display:flex;justify-content:space-between;align-items:center">
    <b style="font-size:15px;color:{C_TEXT}">{s['id']}</b>
    <span style="font-size:12px;font-weight:700;color:{color};background:{bg};padding:2px 10px;border-radius:99px">{icon} {s['status']}</span>
  </div>
  {stages}{tool}{mp4line}
  <div style="font-size:11px;color:{C_MUTED};margin-top:8px">日志 {esc(s['log_size'])}</div>
</div>""")

    bar = f"""
<div style="margin-top:10px;background:#e8e5da;border-radius:99px;height:10px;overflow:hidden">
  <div style="width:{pct}%;height:100%;background:linear-gradient(90deg,{C_RUN},{C_DONE});border-radius:99px;transition:width .4s"></div>
</div>"""

    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><meta http-equiv="refresh" content="10"></head>
<body style="margin:0;background:{C_BG};font-family:-apple-system,'PingFang SC','Noto Sans SC',sans-serif">
<div style="padding:16px 18px">
  <div style="display:flex;align-items:baseline;gap:12px;flex-wrap:wrap">
    <b style="font-size:18px;color:{C_TEXT}">{RUN.parent.name or 'episode'} · 镜头渲染状态</b>
    <span style="font-size:12px;color:{C_MUTED}">{RUN} · 每10秒自动刷新 · {now}</span>
  </div>
  <div style="margin-top:8px;font-size:14px;color:{C_TEXT};display:flex;gap:16px;flex-wrap:wrap">
    <span>完成 <b style="color:{C_DONE};font-size:16px">{done}</b>/{len(states)}</span>
    <span>运行中 <b style="color:{C_RUN};font-size:16px">{running}</b></span>
    <span>停顿 <b style="color:{C_WARN};font-size:16px">{warn}</b></span>
  </div>
  {bar}
  <div style="margin-top:12px;display:flex;flex-wrap:wrap;gap:10px">{''.join(cards)}</div>
</div>
</body></html>"""


def main() -> None:
    while time.time() - START < MAX_SECONDS:
        states = [scene_state(n) for n in SCENES]
        OUT_HTML.write_text(render(states), encoding="utf-8")
        time.sleep(10)


if __name__ == "__main__":
    main()
