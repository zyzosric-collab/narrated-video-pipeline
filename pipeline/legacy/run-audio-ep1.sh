#!/usr/bin/env bash
# Phase 7 实跑：Episode1-v2 音频层
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
EP=$AUTO_MOTION-episode1-v2
OLD=$HOME/Documents/Codex/2026-08-27/ce/work/episodes/openai-huggingface-incident-20260827/music
mkdir -p "$EP/assets/bgm" "$EP/assets/sfx"
# BGM：复用上一集 CC 许可曲目（Documentary 纪录片质感，主题气质匹配"AI 流水线纪实"）
cp "$OLD/router-v2/01-Music-For-Unknown-Documentary-Films.mp3" "$EP/assets/bgm/bgm-01.mp3"
# SFX：镜头切点 whoosh 用历史 QC 过的点击音效
cp "$OLD/sfx-router-v2/effect-FX---Retro-videogame---CLICK-MENU-OPTION.mp3" "$EP/assets/sfx/whoosh.mp3"
bash $PIPELINE/build-audio.sh "$EP"
