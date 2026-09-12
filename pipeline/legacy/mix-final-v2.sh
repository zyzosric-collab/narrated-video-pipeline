#!/usr/bin/env bash
# Mix final video audio: narration + ducked BGM + timed SFX.
# Usage: mix-final-v2.sh <episode-dir>
set -euo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
EP="$1"
VIDEO="$EP/run/final.mp4"
NARR="$EP/narration.mp3"
BGM="$EP/assets/bgm/bgm-01.mp3"
SFX_DIR="$EP/assets/sfx"
OUT="$EP/final-with-voice.mp4"

[ -s "$VIDEO" ] || { echo "missing video: $VIDEO" >&2; exit 1; }
[ -s "$NARR" ] || { echo "missing narration: $NARR" >&2; exit 1; }
[ -s "$BGM" ] || { echo "missing bgm: $BGM" >&2; exit 1; }

DUR="$(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$VIDEO")"
FADE="$("$PY" -c "print(max(0,float('$DUR')-2.0))")"
ffmpeg -y -v error -stream_loop -1 -i "$BGM" -t "$DUR" \
  -af "volume=0.25,afade=t=out:st=$FADE:d=2" "$EP/assets/bgm-prepared.wav"

# Build a sparse SFX bed. Use a soft click at scene cuts and a confirmation chime near the end.
# All SFX are low-gain and are not allowed to compete with speech.
WHOOSH="$SFX_DIR/whoosh.mp3"
CHIME="$SFX_DIR/chime.mp3"
SFX_BED="$EP/assets/sfx-bed.wav"
CUT1="$("$PY" $PIPELINE/cut-points.py "$EP" | awk '{print $1}')"
CUT2="$("$PY" $PIPELINE/cut-points.py "$EP" | awk '{print $2}')"
CHIME_AT="$("$PY" -c "print(max(0,float('$DUR')-8.0))")"
WHOOSH_MS1="$("$PY" -c "print(int(float('$CUT1')*1000))")"
WHOOSH_MS2="$("$PY" -c "print(int(float('$CUT2')*1000))")"
CHIME_MS="$("$PY" -c "print(int(float('$CHIME_AT')*1000))")"

if [ -s "$WHOOSH" ] && [ -s "$CHIME" ]; then
  ffmpeg -y -v error -i "$WHOOSH" -i "$WHOOSH" -i "$CHIME" -filter_complex \
    "[0:a]volume=0.16,adelay=${WHOOSH_MS1}|${WHOOSH_MS1}[w1];[1:a]volume=0.12,adelay=${WHOOSH_MS2}|${WHOOSH_MS2}[w2];[2:a]volume=0.18,adelay=${CHIME_MS}|${CHIME_MS}[c];[w1][w2][c]amix=inputs=3:duration=longest:normalize=0,apad,atrim=duration=$DUR[sfx]" \
    -map "[sfx]" -t "$DUR" -ar 48000 -ac 2 "$SFX_BED"
else
  ffmpeg -y -v error -f lavfi -i anullsrc=r=48000:cl=stereo -t "$DUR" "$SFX_BED"
fi

# Narration drives the sidechain compressor on BGM. No video re-encode.
ffmpeg -y -v error -i "$VIDEO" -i "$NARR" -i "$EP/assets/bgm-prepared.wav" -i "$SFX_BED" \
  -filter_complex \
  "[1:a]asplit=2[nar][sc];[nar]loudnorm=I=-16:TP=-1.5:LRA=7[norm];[2:a][sc]sidechaincompress=threshold=0.03:ratio=8:attack=100:release=600:makeup=1[duck];[norm][duck]amix=inputs=2:weights=1.0 0.5:duration=first[voicebg];[voicebg][3:a]amix=inputs=2:weights=1.0 0.35:duration=first,alimiter=limit=0.95[out]" \
  -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 160k -ar 48000 -ac 2 -shortest "$OUT"

ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of default=noprint_wrappers=1 "$OUT"
ffprobe -v error -select_streams a -show_entries stream=codec_name,sample_rate,channels -of default=noprint_wrappers=1 "$OUT"
echo "DONE: $OUT"
