#!/usr/bin/env bash
# Phase 3: design contract injection — adopt frame-preset as frame.md
# (with episode overlay: aspect adaptation + CJK pairing), distribute to
# run root + every scene dir (design-spec.md official mechanism).
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
EP="$1"

[ -f "$EP/episode.yaml" ] || { echo "FATAL: run init first" >&2; exit 1; }
[ -d "$EP/run" ] || { echo "FATAL: run workspace missing" >&2; exit 1; }

PRESET_DIR="$($PY -c "import yaml;print(yaml.safe_load(open('$EP/episode.yaml'))['preset_dir'])")"

# 1) FRAME.md -> frame.md (official: always lowercase) + episode overlay
cp "$PRESET_DIR/FRAME.md" "$EP/run/frame.md"
$PY "$PIPELINE/gen-overlay.py" "$EP" >> "$EP/run/frame.md"
echo "frame.md: $EP/run/frame.md"

# 2) distribute to every scene dir
COUNT=0
for d in "$EP"/run/scenes/scene-*; do
  [ -d "$d" ] || continue
  cp "$EP/run/frame.md" "$d/frame.md"
  COUNT=$((COUNT+1))
done
echo "distributed to $COUNT scenes"

# 3) caption skin (karaoke caption style source)
cp "$PRESET_DIR/caption-skin.html" "$EP/run/caption-skin.html"
echo "caption-skin: $EP/run/caption-skin.html"
