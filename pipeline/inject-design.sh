#!/usr/bin/env bash
# Phase 3: design contract injection — adopt frame-preset as frame.md
# (with episode overlay: aspect adaptation + CJK pairing), distribute to
# run root + every scene dir (design-spec.md official mechanism).
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
# 解释器：$PIPELINE_PY > <pipeline>/.venv/bin/python > 系统 python3（需 PyYAML）
if [ -n "${PIPELINE_PY:-}" ]; then
  PY="$PIPELINE_PY"
elif [ -x "$PIPELINE/.venv/bin/python" ]; then
  PY="$PIPELINE/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1; then
  PY="python3"
else
  echo "FATAL: 找不到可用 Python 解释器（需要 PyYAML）。先执行: cd \"$PIPELINE\" && python3 -m venv .venv && .venv/bin/pip install pyyaml" >&2
  exit 1
fi
[ -x "$PY" ] || [ "$PY" = "python3" ] || { echo "FATAL: 解释器不可执行: ${PY}（检查 PIPELINE_PY，或删掉它用默认值）" >&2; exit 1; }
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
# TTS CLI 解析顺序：$TTS_CLI > 仓库内 tools/volcengine-doubao-tts/tts.py > 本机旧路径
if [ -z "${TTS_CLI:-}" ]; then
  if [ -f "$PIPELINE/../tools/volcengine-doubao-tts/tts.py" ]; then
    TTS_CLI="$(cd "$PIPELINE/../tools/volcengine-doubao-tts" && pwd)/tts.py"
  else
    TTS_CLI="$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py"
  fi
fi
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
