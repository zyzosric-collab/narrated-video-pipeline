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

# SFX 层（镜头切点）：从 concat.txt 取各镜头时长，在每个切点插一条 whoosh；
# 若 assets/sfx/chime.mp3 存在，再在结尾前 8s 补一记收束音（v2 配方）。
# 做法是先把 SFX 预混成一条「整片等长的等响底」sfx-bed.wav，再作为一路输入参与主混音：
# 这样主混音的输入数恒定、时长可控，不会因为切点数量变化而改变整轨归一化行为。
SFX_BED="$EP/assets/sfx-bed.wav"
SFX_INPUTS=()
SFX_CHAIN=""
UPTO=0
if [ -d "$SFX_DIR" ] && ls "$SFX_DIR"/*.mp3 >/dev/null 2>&1; then
  SFX="$(ls "$SFX_DIR"/*.mp3 | head -1)"
  # 切点 = 各镜头累计时长（不含最后），用独立 python 文件避免 heredoc 编码问题
  CUTS="$($PY "$PIPELINE/cut-points.py" "$EP")"
  for c in $CUTS; do
    MS="$($PY -c "print(int(float('$c')*1000))")"
    SFX_INPUTS+=(-i "$SFX")
    SFX_CHAIN="${SFX_CHAIN}[$UPTO:a]volume=0.16,adelay=${MS}|${MS}[w$UPTO];"
    UPTO=$((UPTO + 1))
  done
  if [ -s "$SFX_DIR/chime.mp3" ]; then
    CMS="$($PY -c "print(int(max(0, float('$VID_DUR') - 8.0)*1000))")"
    SFX_INPUTS+=(-i "$SFX_DIR/chime.mp3")
    SFX_CHAIN="${SFX_CHAIN}[$UPTO:a]volume=0.18,adelay=${CMS}|${CMS}[w$UPTO];"
    UPTO=$((UPTO + 1))
  fi
fi

if [ "$UPTO" -gt 0 ]; then
  SFX_MIX=""
  for i in $(seq 0 $((UPTO - 1))); do SFX_MIX="${SFX_MIX}[w$i]"; done
  ffmpeg -y -v error "${SFX_INPUTS[@]}" \
    -filter_complex "${SFX_CHAIN}${SFX_MIX}amix=inputs=$UPTO:duration=longest:normalize=0,apad,atrim=duration=$VID_DUR[sfxbed]" \
    -map "[sfxbed]" -t "$VID_DUR" -ar 48000 -ac 2 "$SFX_BED"
  SFX_SRC="[3:a]"
else
  # 没有 SFX 素材：铺一条等长静音底，保证主混音图恒为 4 路输入（时长行为一致）
  ffmpeg -y -v error -f lavfi -i "anullsrc=r=48000:cl=stereo" -t "$VID_DUR" "$SFX_BED"
  SFX_SRC="[3:a]"
fi

# 主混音：narration(loudnorm -16 LUFS) + bgm(被 narration 旁链压低) + sfx-bed
# sidechaincompress 的第一个输入是「被压缩的信号」，第二个是 key（旁链）：
#   [2:a][sc] = 压缩 BGM，用 narration 当 key → 说话时 BGM 自动降下来
# 配方取自本机已验证的 mix-final-v2.sh：ratio=8 / attack=100 / makeup=1（补回被压掉的整体电平），
# narration 先过 loudnorm=I=-16:TP=-1.5:LRA=7 保证交付响度稳定在平台区间。
# amix 显式 normalize=0（默认 normalize=1 会让整轨电平随输入个数漂移）；
# duration=longest + -t "$VID_DUR" 精确对齐，不用 -shortest（配音比画面短时会把画面截掉）。
# 开头留白：NARRATION_HEAD_PAD_MS（默认 0 = 不动时间轴）。
# 历史配方（E3）在混音里垫 0.4s 头静音；但那会整体后移配音，
# 与镜头规划（按词级时间戳切画面）必须一致才成立，因此做成显式开关而非默认。
PAD_MS="${NARRATION_HEAD_PAD_MS:-0}"
NAR_PAD=""
[ "$PAD_MS" -gt 0 ] 2>/dev/null && NAR_PAD="adelay=${PAD_MS}|${PAD_MS},"
DUCK="[1:a]asplit=2[nar][sc];[nar]${NAR_PAD}loudnorm=I=-16:TP=-1.5:LRA=7[norm];[2:a][sc]sidechaincompress=threshold=0.03:ratio=8:attack=100:release=600:makeup=1[bgmduck]"
MIX="[norm][bgmduck]${SFX_SRC}amix=inputs=3:weights=1.0 0.5 0.35:normalize=0:duration=longest,alimiter=limit=0.95[aout]"
ffmpeg -y -v error -i "$EP/run/final.mp4" -i "$EP/narration.mp3" -i "$EP/assets/bgm-prepared.wav" -i "$SFX_BED" \
  -filter_complex "${DUCK};${MIX}" \
  -map 0:v -map "[aout]" -c:v copy -c:a aac -b:a 160k -ar 48000 -ac 2 -t "$VID_DUR" "$EP/final-with-voice.mp4"

echo "=== 交付验收 ==="
ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
ffprobe -v error -select_streams a -show_entries stream=codec_name,channels -of default=noprint_wrappers=1 "$EP/final-with-voice.mp4"
echo "DONE: $EP/final-with-voice.mp4"
