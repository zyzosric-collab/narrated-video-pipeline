#!/usr/bin/env bash
# Phase 7: 音频层 —— BGM(ducking) + SFX(镜头切点) 混音
# 用法: bash build-audio.sh <epDir> [bgm.mp3] [sfx-dir]
# bgm 不给则从 assets/bgm/ 里找第一个 mp3；sfx 不给则跳过音效层。
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

# SFX 层（镜头切点）：从 concat.txt 取各镜头时长，在第一个切点插一条 whoosh
SFX_INPUTS=()
SFX_CHAIN=""
MIXIN=""
if [ -d "$SFX_DIR" ] && ls "$SFX_DIR"/*.mp3 >/dev/null 2>&1; then
  SFX="$(ls "$SFX_DIR"/*.mp3 | head -1)"
  SFX_INPUTS=(-i "$SFX")
  # 切点 = 各镜头累计时长（不含最后），用独立 python 文件避免 heredoc 编码问题
  CUTS="$($PY "$PIPELINE/cut-points.py" "$EP")"
  # v2.0: 单条 whoosh 延迟到第一个镜头切点（多切点 v2.1 迭代）
  FIRST_CUT="${CUTS%% *}"
  MS="$($PY -c "print(int(float('$FIRST_CUT')*1000))")"
  SFX_CHAIN="[3:a]volume=0.5,adelay=${MS}|${MS}[sfxout];"
  MIXIN="[sfxout]"
fi

# 主混音：narration 100% + bgm sidechain-duck + sfx
# sidechaincompress 的第一个输入是「被压缩的信号」，第二个是 key（旁链）：
#   [2:a][1:a] = 压缩 BGM，用 narration 当 key → 说话时 BGM 自动降下来
# amix 用 duration=longest：bgm-prepared 恰好等于成片时长，narration 偏短时由 BGM 补足，
#   最后以 -t "$VID_DUR" 精确对齐；不用 -shortest（配音比画面短时会把画面截掉）。
DUCK="[2:a][1:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck]"
if [ -n "$MIXIN" ]; then
  ffmpeg -y -v error -i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav" "${SFX_INPUTS[@]}" \
    -filter_complex "${DUCK};${SFX_CHAIN}[1:a][bgmduck][sfxout]amix=inputs=3:weights=1.0 0.5 0.5:normalize=0:duration=longest,alimiter=limit=0.95[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -t "$VID_DUR" "$EP/final-with-voice.mp4" \
    || { echo "WARN: 带 SFX 的混音失败，回退到无 SFX 混音" >&2; MIXIN=""; }
fi
if [ -z "$MIXIN" ]; then
  ffmpeg -y -v error -i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav" \
    -filter_complex "${DUCK};[1:a][bgmduck]amix=inputs=2:weights=1.0 0.5:normalize=0:duration=longest,alimiter=limit=0.95[aout]" \
    -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -t "$VID_DUR" "$EP/final-with-voice.mp4"
fi

echo "=== 交付验收 ==="
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
echo "DONE: $EP/final-with-voice.mp4"
