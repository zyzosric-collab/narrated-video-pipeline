#!/usr/bin/env bash
# ============================================================
# narrated-video-pipeline — episode.sh（执行器入口）
# 口播视频流水线。用法：
#   bash episode.sh doctor                             # 环境自检（推荐第一步）
#   bash episode.sh init <epDir> [aspect] [preset]      # Phase 0
#   bash episode.sh voice <epDir>                       # Phase 2（需先有 script-segments.json）
#   bash episode.sh design <epDir>                      # Phase 3
#   bash episode.sh scenes <epDir> [plan|pilot|rest|all]  # Phase 4+5+6（拆镜→并行执行→质检→拼接）
#   bash episode.sh audio <epDir> [bgm.mp3]             # Phase 7（BGM+SFX+混音）
#   bash episode.sh status <epDir>                      # 查看各 Phase 状态
# 配置真源：<epDir>/episode.yaml
# 环境变量：PIPELINE_DIR / PIPELINE_PY / AUTO_MOTION_DIR / TTS_CLI（都有默认值，可不设）
# ============================================================
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"

say() { printf '\033[1;36m[episode]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[episode:FATAL]\033[0m %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

# ---------------- 依赖解析（宁可早失败，也不要「假成功」）----------------
# 解释器：$PIPELINE_PY > <pipeline>/.venv/bin/python > 系统 python3（需已装 PyYAML）
if [ -n "${PIPELINE_PY:-}" ]; then
  PY="$PIPELINE_PY"
elif [ -x "$PIPELINE/.venv/bin/python" ]; then
  PY="$PIPELINE/.venv/bin/python"
elif have python3 && python3 -c 'import yaml' >/dev/null 2>&1; then
  PY="python3"
else
  die "找不到可用 Python 解释器（需要 PyYAML）。先建虚拟环境：
    cd \"${PIPELINE}\" && python3 -m venv .venv && .venv/bin/pip install pyyaml"

fi
[ -x "$PY" ] || [ "$PY" = "python3" ] || die "解释器不可执行: ${PY}（检查 PIPELINE_PY，或删掉它用默认值）"

# TTS CLI：$TTS_CLI > 仓库内 tools/volcengine-doubao-tts/tts.py > 本机旧路径
if [ -z "${TTS_CLI:-}" ]; then
  if [ -f "$PIPELINE/../tools/volcengine-doubao-tts/tts.py" ]; then
    TTS_CLI="$(cd "$PIPELINE/../tools/volcengine-doubao-tts" && pwd)/tts.py"
  else
    TTS_CLI="$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py"
  fi
fi

yaml_get() { # yaml_get <epDir> <key>
  "$PY" - "$1" "$2" <<'PYEOF'
import sys, yaml
ep = yaml.safe_load(open(sys.argv[1] + "/episode.yaml"))
print(ep.get(sys.argv[2], ""))
PYEOF
}

# ---------------- 环境自检 ----------------
do_doctor() {
  local ok=0
  check() { # check <名称> <修复提示> <判定命令…>
    local name="$1" hint="$2"
    shift 2
    if "$@" >/dev/null 2>&1; then
      printf '  [OK  ] %s\n' "$name"
    else
      printf '  [MISS] %s\n         ↳ %s\n' "$name" "$hint"
      ok=1
    fi
  }
  echo "执行器  : $PIPELINE"
  echo "工作区  : $AUTO_MOTION"
  echo "解释器  : $PY"
  echo "TTS CLI : $TTS_CLI"
  echo
  check "ffmpeg"  "brew install ffmpeg"    have ffmpeg
  check "ffprobe" "brew install ffmpeg"    have ffprobe
  check "jq"      "brew install jq"        have jq
  check "node"    "brew install node"      have node
  check "npx"     "brew install node"      have npx
  check "claude (Claude Code CLI)" "npm i -g @anthropic-ai/claude-code，然后登录（P5 逐镜头渲染用）" have claude
  check "codex (Codex CLI)"        "安装并登录 Codex CLI（P4 拆镜规划用）"                        have codex
  check "Python 解释器 + PyYAML"   "cd \"${PIPELINE}\" && python3 -m venv .venv && .venv/bin/pip install pyyaml" "$PY" -c "import yaml"
  check "TTS CLI"                  "见 tools/volcengine-doubao-tts/README.md"      test -f "${TTS_CLI}"
  check "auto-motion 渲染工作区"   "git clone https://github.com/zyzosric-collab/auto-motion ~/auto-motion（或设 AUTO_MOTION_DIR 指向别处）" test -d "${AUTO_MOTION}"
  echo
  if [ -f "$TTS_CLI" ]; then
    local tts_dir; tts_dir="$(cd "$(dirname "$TTS_CLI")" && pwd)"
    if [ -f "$tts_dir/.env.local" ] || [ -n "${VOLCENGINE_TTS_API_KEY:-}" ]; then
      echo "  [OK  ] 火山引擎 TTS 密钥（.env.local 或环境变量）"
    else
      echo "  [MISS] 火山引擎 TTS 密钥"
      echo "         ↳ cp \"${tts_dir}/.env.example\" \"${tts_dir}/.env.local\" 并填入 VOLCENGINE_TTS_API_KEY"
      echo "           自检：python3 \"${TTS_CLI}\" --text '配置检查。' --dry-run"
      ok=1
    fi
  fi
  echo
  if [ "$ok" = 0 ]; then
    say "自检通过。下一步：bash episode.sh init <epDir> 16:9 <preset>"
  else
    printf '\033[1;31m[episode] 自检未通过：先补齐上面 [MISS] 的项\033[0m\n' >&2
    return 1
  fi
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
  [ -f "$ep/script-segments.json" ] || die "缺少 $ep/script-segments.json（Phase 1 拆段产物：数组，元素形如 {\"style\": \"tech_explainer\", \"text\": \"…\"}）"
  [ -f "$TTS_CLI" ] || die "找不到 TTS CLI: ${TTS_CLI}（配置方法见 tools/volcengine-doubao-tts/README.md）"
  "$PY" "$PIPELINE/build_narration_v2.py" "$ep" || die "Phase 2 失败（原因见上方输出）"
  say "Phase 2 完成: $ep/narration.mp3 + transcription.srt + voice-timing.json（词级）"
}

# ---------------- Phase 3: design ----------------
do_design() {
  local ep="$1"
  [ -f "$ep/episode.yaml" ] || die "先 init"
  mkdir -p "$ep/run"   # 设计契约可在拆镜前注入；拆镜后重跑则再分发到各镜头
  bash "$PIPELINE/inject-design.sh" "$ep" || die "Phase 3 失败（原因见上方输出）"
  say "Phase 3 完成: frame.md + caption 契约已注入各镜头"
}

# ---------------- Phase 4+5+6: scenes ----------------
do_scenes() {
  local ep="$1" mode="${2:-all}"
  [ -f "$ep/episode.yaml" ] || die "先 init"
  [ -d "$AUTO_MOTION" ] || die "找不到渲染工作区 ${AUTO_MOTION}（clone github.com/zyzosric-collab/auto-motion，或设 AUTO_MOTION_DIR）"
  # 当前执行器（v3）：plan | pilot | rest | all（v2 已退役，见 pipeline/legacy/）
  bash "$PIPELINE/run-scenes-v3.sh" "$ep" "$mode" || die "Phase 4-6 失败（原因见上方输出）"
}

# ---------------- Phase 7: audio ----------------
do_audio() {
  local ep="$1" bgm="${2:-}"
  [ -f "$ep/episode.yaml" ] || die "先 init"
  if [ -n "$bgm" ]; then
    bash "$PIPELINE/build-audio.sh" "$ep" "$bgm" || die "Phase 7 失败（原因见上方输出）"
  else
    bash "$PIPELINE/build-audio.sh" "$ep" || die "Phase 7 失败（原因见上方输出）"
  fi
}

# ---------------- status ----------------
do_status() {
  local ep="$1"
  [ -f "$ep/episode.yaml" ] || die "找不到 $ep/episode.yaml"
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
  doctor) do_doctor ;;
  init)   do_init "$2" "${3:-16:9}" "${4:-auto}" ;;
  voice)  do_voice "$2" ;;
  design) do_design "$2" ;;
  scenes) do_scenes "$2" "${3:-all}" ;;
  audio)  do_audio "$2" "${3:-}" ;;
  status) do_status "$2" ;;
  *) sed -n '2,14p' "$0"; exit 1 ;;
esac
