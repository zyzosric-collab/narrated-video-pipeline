#!/usr/bin/env bash
# ============================================================
# video-pipeline v2 — episode.sh
# 口播视频流水线（9 Phase）。用法：
#   bash episode.sh init <epDir> [aspect] [preset]     # Phase 0
#   bash episode.sh voice <epDir>                      # Phase 2（需先有 script 分段）
#   bash episode.sh design <epDir>                     # Phase 3
#   bash episode.sh scenes <epDir> [plan|pilot|rest|all]  # Phase 4+5+6（拆镜→并行执行→质检→拼接）
#   bash episode.sh audio <epDir>                      # Phase 7（BGM+SFX+混音）
#   bash episode.sh status <epDir>                     # 查看各 Phase 状态
# 配置真源：<epDir>/episode.yaml
# ============================================================
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"

say() { printf '\033[1;36m[episode]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[episode:FATAL]\033[0m %s\n' "$*" >&2; exit 1; }

yaml_get() { # yaml_get <epDir> <key>
  "$PY" - "$1" "$2" <<'PYEOF'
import sys, yaml
ep = yaml.safe_load(open(sys.argv[1] + "/episode.yaml"))
print(ep.get(sys.argv[2], ""))
PYEOF
}

# ---------------- Phase 0: init ----------------
do_init() {
  local ep="$1" aspect="${2:-16:9}" preset="${3:-auto}"
  mkdir -p "$ep"/{audio,logs,frames,assets}
  # 预设 auto = 按内容类型二选一（写作阶段人工确认时定，默认 blue-professional）
  [ "$preset" = "auto" ] && preset="blue-professional"
  case "$aspect" in
    16:9) W=1920; H=1080 ;;
    9:16) W=1080; H=1920 ;;
    3:4)  W=1080; H=1440 ;;
    *) die "aspect 必须是 16:9 | 9:16 | 3:4" ;;
  esac
  cat > "$ep/episode.yaml" <<YEOF
# Episode 配置真源（Phase 0 生成）
episode: "$(basename "$ep")"
aspect: "$aspect"
width: $W
height: $H
fps: 30
preset: "$preset"          # blue-professional | capsule
preset_dir: "$AUTO_MOTION/exampleFolder/.claude/skills/hyperframes-design/frame-presets/$preset"
bgm_volume: 0.25           # ducking 峰值；说话时自动降到 ~1/3
bgm_mood: ""               # 写作阶段填：如 "tech, inspiring, minimal"
speaker: "zh_male_dayi_uranus_bigtts"
speech_rate: 10
phases:
  script:  false
  voice:   false
  design:  false
  scenes:  false
  audio:   false
  delivered: false
YEOF
  say "Phase 0 完成: $ep/episode.yaml (aspect=$aspect ${W}x${H} preset=$preset)"
}

# ---------------- Phase 2: voice ----------------
do_voice() {
  local ep="$1"
  [ -f "$ep/episode.yaml" ] || die "先 init"
  "$PY" "$PIPELINE/build_narration_v2.py" "$ep"
  say "Phase 2 完成: $ep/narration.mp3 + voice-timing.json（词级）"
}

# ---------------- Phase 3: design ----------------
do_design() {
  local ep="$1"
  local run_dir="$ep/run"
  [ -f "$ep/episode.yaml" ] || die "先 init"
  [ -d "$run_dir" ] || die "先 scenes（设计契约在工作区就绪后注入）"
  bash "$PIPELINE/inject-design.sh" "$ep"
  say "Phase 3 完成: frame.md + caption 契约已注入各镜头"
}

# ---------------- Phase 4+5+6: scenes ----------------
do_scenes() {
  local ep="$1" mode="${2:-all}"
  # CURRENT executor (v3): plan | pilot | rest | all  (v2 is retired, see pipeline/legacy/)
  bash "$PIPELINE/run-scenes-v3.sh" "$ep" "$mode"
}

# ---------------- Phase 7: audio ----------------
do_audio() {
  local ep="$1"
  bash "$PIPELINE/build-audio.sh" "$ep"
}

# ---------------- status ----------------
do_status() {
  local ep="$1"
  "$PY" - "$ep" <<'PYEOF'
import sys, yaml, os
ep = sys.argv[1]
cfg = yaml.safe_load(open(f"{ep}/episode.yaml"))
checks = {
  "script (口播稿)": f"{ep}/script-segments.json",
  "voice (配音+SRT)": f"{ep}/narration.mp3",
  "design (frame.md)": f"{ep}/run/frame.md",
  "scenes (final.mp4)": f"{ep}/run/final.mp4",
  "audio (成片)": f"{ep}/final-with-voice.mp4",
}
print(f"episode: {cfg['episode']}  aspect: {cfg['aspect']} {cfg['width']}x{cfg['height']}  preset: {cfg['preset']}")
for name, path in checks.items():
    mark = "OK " if os.path.exists(path) and os.path.getsize(path) > 0 else "-- "
    print(f"  [{mark}] {name}")
PYEOF
}

case "${1:-}" in
  init)   do_init "$2" "${3:-16:9}" "${4:-auto}" ;;
  voice)  do_voice "$2" ;;
  design) do_design "$2" ;;
  scenes) do_scenes "$2" "${3:-all}" ;;
  audio)  do_audio "$2" ;;
  status) do_status "$2" ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
