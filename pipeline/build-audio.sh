#!/usr/bin/env bash
# Phase 7: 音频层 —— BGM(ducking) + SFX(镜头切点) 混音
# 用法: bash build-audio.sh <epDir> [bgm.mp3] [sfx-dir]
# bgm 不给则从 assets/bgm/ 里找第一个 mp3；sfx 不给则跳过音效层。
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
EP="$1"
BGM="${2:-}"
SFX_DIR="${3:-$EP/assets/sfx}"

BGV="$($PY -c "import yaml;print(yaml.safe_load(open('$EP/episode.yaml')).get('bgm_volume',0.25))")"

[ -f "$EP/narration.mp3" ] || { echo "FATAL: 无 narration.mp3（先 voice）" >&2; exit 1; }
[ -f "$EP/run/final.mp4" ] || { echo "FATAL: 无 run/final.mp4（先 scenes）" >&2; exit 1; }

# BGM 定位
if [ -z "$BGM" ]; then
  BGM="$(ls "$EP"/assets/bgm/*.mp3 2>/dev/null | head -1 || true)"
fi
[ -n "$BGM" ] && [ -f "$BGM" ] || { echo "FATAL: 未提供 BGM（$EP/assets/bgm/ 下也没有）" >&2; exit 1; }
echo "BGM: $BGM (峰值音量 $BGV)"

# BGM 循环/截断到视频时长 + 末尾淡出
VID_DUR="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$EP/run/final.mp4")"
FADE_START="$("$PY" -c "print(max(0, float('$VID_DUR') - 2.0))")"
ffmpeg -y -v error -stream_loop -1 -i "$BGM" -t "$VID_DUR" \
  -af "volume=${BGV},afade=t=out:st=${FADE_START}:d=2" "$EP/assets/bgm-prepared.wav"

# SFX 拼接层（镜头切点）：从 concat.txt 取各镜头时长，逐切点插一个 whoosh
FILTER=""
INPUTS=(-i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav")
NIN=3
if [ -d "$SFX_DIR" ] && ls "$SFX_DIR"/*.mp3 >/dev/null 2>&1; then
  SFX="$(ls "$SFX_DIR"/*.mp3 | head -1)"
  INPUTS+=(-i "$SFX")
  SFXIDX=3
  # 切点 = 各镜头累计时长（不含最后），用独立 python 文件避免 heredoc 编码问题
  CUTS="$($PY "$PIPELINE/cut-points.py" "$EP")"
  FILTER=""
  # v2.0: 单条 whoosh 延迟到第一个镜头切点（多切点 v2.1 迭代）
  FIRST_CUT="${CUTS%% *}"
  MS="$($PY -c "print(int(float('$FIRST_CUT')*1000))")"
  FILTER="[${SFXIDX}:a]volume=0.5,adelay=${MS}|${MS}[sfxout];"
  MIXIN="[sfxout]"
else
  MIXIN=""
fi

# 主混音：narration 100% + bgm sidechain-duck + sfx
# 注意：final.mp4 无音轨，所以混音只发生在音频输入之间（narration=输入1, bgm=输入2, sfx=输入3）
# ffmpeg 全局 stream 索引：1:narration 2:bgm 3:sfx；视频用 0:v
if [ -n "$MIXIN" ]; then
  ffmpeg -y -v error "${INPUTS[@]}" -filter_complex "[1:a][2:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck];[2:a][1:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck2];${FILTER}[bgmduck][1:a][3:a]amix=inputs=3:weights=1.0 0.35 0.5:duration=first,alimiter=limit=0.95[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -shortest "$EP/final-with-voice.mp4" 2>/dev/null || \
  ffmpeg -y -v error -i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav" -filter_complex "[1:a][2:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck];[1:a][bgmduck]amix=inputs=2:weights=1.0 0.5:duration=first,alimiter=limit=0.95[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -shortest "$EP/final-with-voice.mp4"
else
  ffmpeg -y -v error -i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav" -filter_complex "[1:a][2:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck];[1:a][bgmduck]amix=inputs=2:weights=1.0 0.5:duration=first,alimiter=limit=0.95[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -shortest "$EP/final-with-voice.mp4"
fi

echo "=== 交付验收 ==="
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
echo "DONE: $EP/final-with-voice.mp4"
