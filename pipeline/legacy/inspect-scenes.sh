#!/usr/bin/env bash
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
# 巡检 v2 拆镜质量
R=$AUTO_MOTION-episode1-v2/run
echo "=== SCENE_ID 护栏 ==="
for i in 01 02 03 04 05 06 07 08 09 10; do
  f="$R/scenes/scene-$i/run-claude-ai.sh"
  [ -f "$f" ] || continue
  sid="$(grep -m1 'SCENE_ID=' "$f" | sed 's/.*:-\([a-z0-9-]*\).*/\1/')"
  dim="$(grep -coE 'data-width=.1920.|1920.?x.?.?1080|1920×1080' "$f")"
  fm="$(grep -c 'frame.md' "$f")"
  echo "scene-$i: SCENE_ID=$sid 画幅引用=$dim frame.md引用=$fm"
done
echo "=== 特效选型 ==="
grep -hoE 'light-spotlight-render|svg-assembly-animator|pixel2motion|printed-curtain-render|threejs-earth-render|3d-chladni-render' "$R"/scenes/*/run-claude-ai.sh 2>/dev/null | sort | uniq -c
echo "=== disney 覆盖 ==="
grep -l 'disney' "$R"/scenes/*/run-claude-ai.sh 2>/dev/null | wc -l
