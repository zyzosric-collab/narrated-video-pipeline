#!/usr/bin/env bash
# Phase 4+5+6 v3: 拆镜（Codex 只规划）→ SCENE_ID/契约护栏 → 注入效率+质量门 → 并行执行（独立日志）→ 质检门 → 拼接
# 用法: bash run-scenes-v3.sh <epDir>
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
MODE="${2:-all}"   # all = 全量（默认）| plan = 只拆镜不执行 | pilot = 只执行 scene-001
RUN="$EP/run"
LOGS="$EP/logs"

eval "$($PY "$PIPELINE/ep-env.py" "$EP")"
W="$WIDTH"; H="$HEIGHT"

mkdir -p "$RUN" "$LOGS" "$EP/frames"
REUSE=0
if [ "${REUSE_PLAN:-0}" = "1" ] && ls "$RUN"/scenes/scene-*/run-claude-ai.sh >/dev/null 2>&1; then
  REUSE=1
  printf '\033[1;36m[scenes]\033[0m REUSE_PLAN=1：复用现有拆镜，跳过工作区重组与 Codex 规划\n'
fi
if [ "$REUSE" != "1" ]; then
rm -rf "$RUN"/scenes "$RUN"/PROMPT.md "$RUN"/exampleFolder 2>/dev/null

# ---- Phase 4a: 工作区组装 ----
cp $AUTO_MOTION/PROMPT.md "$RUN/PROMPT.md"
cp -R $AUTO_MOTION/exampleFolder "$RUN/exampleFolder"
cp "$EP/transcription.srt" "$RUN/transcription.srt"
chmod +x "$RUN/exampleFolder/run-claude-ai.sh"
cp "$EP/voice-timing.json" "$RUN/voice-timing.json"

# 设计契约先于拆镜注入（v3 教训：frame.md 必须在镜头生成前存在）
PRESET="$( $PY -c "import yaml;print(yaml.safe_load(open('$EP/episode.yaml'))['preset'])" )"
PRESET_DIR="$AUTO_MOTION/exampleFolder/.claude/skills/hyperframes-design/frame-presets/$PRESET"
cp "$PRESET_DIR/FRAME.md" "$RUN/frame.md"
$PY "$PIPELINE/gen-overlay.py" "$EP" >> "$RUN/frame.md"
# 去除卡拉OK字幕契约（用户 2026-08-31 决定：无烧录字幕）
$PY - "$RUN/frame.md" <<'PYEOF'
import re, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
t2 = re.sub(r"## Caption（卡拉OK字幕契约）.*?(?=## |\Z)", "", t, flags=re.S)
open(p, "w", encoding="utf-8").write(t2)
print(f"caption stripped: {len(t)-len(t2)} chars")
PYEOF
cp "$RUN/frame.md" "$RUN/exampleFolder/frame.md"

# 配色规则随预设派生（episode-agnostic：禁止硬编码单集预设）
case "$PRESET" in
  broadside) REGISTER_RULE="本集允许 Broadside 官方双 register（ink-black/fire-orange），除此之外禁止自选配色与额外深色调" ;;
  *)         REGISTER_RULE="本集预设 ${PRESET} 为浅色系：禁止深色底、禁止自选配色与额外深色调；本集自带的应用界面截图作为内容图片（窗口卡片）呈现时不受此限" ;;
esac

# ---- Phase 4b: PROMPT 追加段（只规划不渲染 + 参数 + 契约）----
cat >> "$RUN/PROMPT.md" <<APPEOF

## 本轮模式：只规划，不执行（最高优先级）

只完成：读 SRT → 语义拆镜 → 创建全部 scenes/scene-NNN → 复制 exampleFolder → 填写所有 run-claude-ai.sh → 生成 scene-brief.md → 复核时长总和。
禁止调用 Claude，禁止 HyperFrames 渲染，禁止生成任何 MP4。全部任务文件就绪后立即退出。

## 本集执行参数（episode.yaml 派生，最高优先级）

- 画幅：${W}x${H}，${FPS}fps。模板中的 1080x1440 一律以本参数为准。
- Claude Code 使用当前用户配置的默认模型，禁止在命令行追加 --model 参数。
- 每个 SCENE_ID 必须等于镜头目录名。
- 每个镜头目录必须复制 frame.md、voice-timing.json 和完整 transcription.srt。
- 每个镜头 prompt 必须要求：先读 frame.md；色彩遵守 frame.md（dark-first 预设如 broadside 允许其官方 dark register，其余预设禁止深色底）；遵守 disney-animation-rule-skill；
  按语义至多点名 1 个特效技能；读取 scene-timing.json 并按词级时间落地关键词。
- 禁止任何 EP 编号；无烧录字幕；禁止把镜头文案逐字放进画面。

## 设计契约（必须执行）

- frame.md 是全片视觉唯一真源。每个镜头 prompt 必须写入：
  「先读当前目录 frame.md；色板、字体、间距、组件只能取自该文件；${REGISTER_RULE}。」
APPEOF

# Episode 专属覆盖（存在则追加；保持工具 episode 无关）
[ -f "$EP/prompt-overlay.md" ] && cat "$EP/prompt-overlay.md" >> "$RUN/PROMPT.md"

# 截图素材（混合画面路线）：入库工作区，供 Codex 拆镜时查看与分配
if ls "$EP/assets/screenshots"/*.png >/dev/null 2>&1; then
  mkdir -p "$RUN/screenshots"
  cp "$EP/assets/screenshots"/*.png "$RUN/screenshots/"
  cat >> "$RUN/PROMPT.md" <<SSHEOF

## 真实界面截图素材（混合画面路线）

- screenshots/ 目录下有本应用的真实截图（文件名即语义：my-skills-overview 总览、add-skills-install 安装来路、tools-management 工具管理、updates-page 定时更新）。
- 涉及功能演示的镜头（安装来路、工具管理、批量管理、定时更新）必须把对应截图作为「应用窗口卡片」编入画面：带窗口边框与阴影、入场动效（推近或上浮），按叙事需要用高亮框或放大圈注关键区域。
- 窗口卡片之外的背景、装饰、图表仍用 frame.md 的图形语言；截图不得拉伸变形，圆角阴影用 CSS 实现。
- 没有对应截图的镜头保持纯动画。具体分配由你按语义在拆镜时决定。
SSHEOF
fi

fi
# ---- Phase 4c: Codex 拆镜（只规划）----
say() { printf '\033[1;36m[scenes]\033[0m %s\n' "$*"; }
if [ "$REUSE" = "1" ]; then
  :
else
say "Codex 规划启动（${W}x${H}，只规划不渲染）"
codex exec \
  --cd "$RUN" \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --output-last-message "$LOGS/codex-last-message.txt" \
  - < "$RUN/PROMPT.md" > "$LOGS/codex-events.jsonl" 2>&1

[ -d "$RUN/scenes" ] || { say "FATAL: Codex 未生成 scenes"; exit 1; }
fi

# ---- Phase 5a: SCENE_ID + 契约护栏 ----
say "护栏检查与门注入"
for d in "$RUN"/scenes/scene-*; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"
  f="$d/run-claude-ai.sh"
  [ -f "$f" ] || { say "FATAL: $id 缺 run-claude-ai.sh"; exit 1; }
  # SCENE_ID 纠正
  if ! grep -q "SCENE_ID=\"\${SCENE_ID:-$id}\"" "$f"; then
    sed -i '' "s/SCENE_ID=\"\${SCENE_ID:-[a-z0-9-]*}\"/SCENE_ID=\"\${SCENE_ID:-$id}\"/" "$f"
    say "  已纠正 $id 的 SCENE_ID"
  fi
  # 移除任何 --model 覆盖（用户规则：用当前配置）
  sed -i '' 's/ *--model [a-zA-Z0-9._-]*//g' "$f"
  # 复制契约文件
  cp "$RUN/frame.md" "$d/frame.md"
  cp "$RUN/voice-timing.json" "$d/voice-timing.json" 2>/dev/null || true
done

# 词级时间切片到每镜头
$PY "$PIPELINE/make-scene-timing.py" "$EP" || say "WARN: make-scene-timing 未完全命中（Codex brief 命名差异），词级文件已尽力注入"

# ---- 契约包生成（性能优化①：一次 Read 取代 18-23 次翻文件）----
$PY "$PIPELINE/make-scene-context.py" "$EP" || say "WARN: scene-context 生成失败，Claude 将退回读原技能文档"

# ---- Phase 5b: 注入效率门 + 质量门（Python，避免 heredoc CJK 损坏）----
$PY - "$RUN/scenes" <<'PYEOF'
import sys
from pathlib import Path
run = Path(sys.argv[1])
eff = """效率约束（最高优先级，违反即失败）：
- 禁止联网搜索字体、素材或任何资料；「开始联网搜索」阶段消息照常输出，但不要真的发起 WebSearch。
- 字体方案完全按 frame.md 执行，不要检查系统字体、不要用 fontTools 分析字形、不要下载字体。
- 只允许读取当前镜头目录内的文件。
- 预算：理解与检查 ≤2 分钟，写代码 ≤8 分钟，npm run check 与抽帧自查 ≤3 分钟，单镜头 ≤15 分钟。
- 超出任一预算立即停止优化，直接渲染交付当前版本。
- 不要创建 TODO 任务列表，直接干活。

"""
gate = """质量自检门（必须在最终渲染前完成，逐条执行）：
- 写完代码后先运行 npm run check，所有 error 修复后才允许渲染。
- 最终渲染前，必须用 npx hyperframes snapshot --at 抽开头/中间/结尾至少 3 帧到 snapshots/ 自查。
- 自查清单（任一不满足必须改完重抽）：
  1) 装饰元素不得压在文字上；
  2) 主视觉不得严重偏侧，遵循 frame.md 栅格；
  3) 画面中不得出现字幕条、卡拉OK字幕或逐字口播文字；概念性标签应为短语而非整句；
  4) 中文用 Noto Sans SC，Space Grotesk 仅用于数字和拉丁字符，不得出现豆腐块；
  5) 关键词/数字出现时间与 scene-timing.json 词级时间一致；
  6) 片尾无任何 EP 编号；
  7) 结尾收束完整：终帧必须是落定构图，无空占位节点、无悬空连线；汇聚线必须合并到有内容的终点节点；
  8) 转场呼吸：镜头结尾所有元素完成入场后至少停留 0.8 秒再结束，禁止动画刚完成就切镜头；文案读完后的剩余时间用于收尾停留，不得提前结束。
- 自查全部通过后，才允许最终渲染；最终渲染必须使用与 snapshot 相同的工程文件。

"""
n = 0
for f in sorted(run.glob("scene-*/run-claude-ai.sh")):
    t = f.read_text(encoding="utf-8")
    o = t
    if "效率约束" not in t:
        t = t.replace("阶段性汇报规则：", "阶段性汇报规则：", 1)  # keep anchor
        if "阶段性汇报规则：" in t:
            t = t.replace("阶段性汇报规则：", eff + gate + "阶段性汇报规则：", 1)
        else:
            t = eff + gate + t
    # 无字幕约束替换
    t = t.replace("不需要把镜头文案逐字放进画面；可使用图形、图标、概念性文字或少量中文标签表达含义。",
                  "禁止把镜头文案逐字放进画面；禁止出现字幕条、卡拉OK字幕或任何逐字展示口播的文字。画面只用图形、图标、数据可视化和少量概念性中文短标签表达含义。")
    if t != o:
        f.write_text(t, encoding="utf-8")
        n += 1
print(f"gates injected into {n} scenes")
PYEOF

# ---- Phase 5c: 并行执行（plan=只拆镜不执行 / pilot=仅001 / all=全量，并发3）----
if [ "$MODE" = "plan" ]; then
  say "plan 模式：拆镜产物已就绪，跳过执行（试点/批量由后续调用决定）"
  say "PLAN-ONLY-DONE: $(ls -d "$RUN"/scenes/scene-* 2>/dev/null | wc -l | tr -d ' ') scenes planned"
  exit 0
fi
REST_EXCLUDE=""
if [ "$MODE" = "pilot" ]; then
  say "试点执行（仅 scene-001，验收通过后再批量）"
  SCENE_GLOB="scene-001"
elif [ "$MODE" = "rest" ]; then
  say "批量执行剩余镜头（跳过已验收的 scene-001，并发 3）"
  SCENE_GLOB="scene-*"
  REST_EXCLUDE="scene-001"
else
  say "并行执行镜头（并发 3）"
  SCENE_GLOB="scene-*"
fi
SCENES_TO_RUN="$(find "$RUN"/scenes -maxdepth 1 -type d -name "$SCENE_GLOB" ${REST_EXCLUDE:+! -name "$REST_EXCLUDE"} | sort)"
for d in $SCENES_TO_RUN; do
  (
    id="$(basename "$d")"
    echo "[$id] start $(date +%H:%M:%S)"
    cd "$d" || exit 127
    bash run-claude-ai.sh > "$id.launch.log" 2>&1
    echo "[$id] exit=$? $(date +%H:%M:%S)"
  ) &
  while [ "$(jobs -rp | wc -l | tr -d ' ')" -ge 3 ]; do sleep 5; done
done
wait

# ---- Phase 5d: 孤儿渲染补渲 ----
say "孤儿渲染检测"
for d in "$RUN"/scenes/$SCENE_GLOB; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"
  if [ ! -s "$d/$id.mp4" ]; then
    proj=""
    for v in hf-proj hf-project hf; do
      [ -f "$d/$v/index.html" ] && proj="$d/$v" && break
    done
    [ -z "$proj" ] && [ -f "$d/index.html" ] && proj="$d"
    if [ -n "$proj" ]; then
      say "  $id 缺 mp4，工程在 $proj → 补渲染"
      (cd "$proj" && npx hyperframes render --output "$id.mp4" >/dev/null 2>&1 \
        && [ -f "$proj/$id.mp4" ] && cp "$proj/$id.mp4" "$d/$id.mp4" && say "  $id 补渲染完成") || say "  $id 补渲染失败"
    fi
  fi
done

# ---- Phase 5e: 质检门 ----
say "质检门（${W}x${H} @${FPS}fps）"
FAIL=0; EXP_SUM=0; ACT_SUM=0
for d in "$RUN"/scenes/$SCENE_GLOB; do
  [ -d "$d" ] || continue
  id="$(basename "$d")"; mp4="$d/$id.mp4"
  exp="$(grep -m1 'SCENE_DURATION_SECONDS=' "$d/run-claude-ai.sh" | sed 's/.*:-\([0-9.]*\).*/\1/')"
  [ -s "$mp4" ] || { echo "FAIL $id: mp4 missing"; FAIL=1; continue; }
  encj="$(ffprobe -v error -select_streams v:0 -show_entries stream=profile,level,pix_fmt -of json "$mp4")"
  prof="$(jq -r '.streams[0].profile' <<<"$encj")"; lvl="$(jq -r '.streams[0].level' <<<"$encj")"; pix="$(jq -r '.streams[0].pix_fmt' <<<"$encj")"
  if [ "$prof" != "High" ] || [ "$lvl" != "40" ] || [ "$pix" != "yuv420p" ]; then
    say "  $id 编码 $prof@$lvl/$pix → 规范化"
    ffmpeg -y -v error -i "$mp4" -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p -crf 18 -r "$FPS" "$d/.norm.mp4" \
      && mv "$d/.norm.mp4" "$mp4" || { echo "FAIL $id: 规范化失败"; FAIL=1; continue; }
  fi
  json="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height,avg_frame_rate -show_entries format=duration -of json "$mp4")"
  w="$(jq -r '.streams[0].width' <<<"$json")"; h="$(jq -r '.streams[0].height' <<<"$json")"
  dur="$(jq -r '.format.duration' <<<"$json")"
  audio="$(ffprobe -v error -select_streams a -show_entries stream=index -of csv=p=0 "$mp4" | grep -c . || true)"
  ok="OK"
  [ "$w" = "$W" ] && [ "$h" = "$H" ] || ok="SPEC"
  awk -v a="$dur" -v b="$exp" 'BEGIN{if((a-b)<-0.3||(a-b)>0.3) exit 1}' || ok="DUR"
  [ "$audio" != "0" ] && ok="AUDIO"
  [ "$ok" != "OK" ] && FAIL=1
  EXP_SUM="$(awk -v a="$EXP_SUM" -v b="$exp" 'BEGIN{printf "%.3f",a+b}')"
  ACT_SUM="$(awk -v a="$ACT_SUM" -v b="$dur" 'BEGIN{printf "%.3f",a+b}')"
  echo "$id: ${w}x${h} dur=${dur}s exp=${exp}s [$ok]"
  mkdir -p "$EP/frames/$id"
  ffmpeg -y -v error -ss 0.1 -i "$mp4" -frames:v 1 "$EP/frames/$id/first.png"
  ffmpeg -y -v error -ss "$(awk -v d="$dur" 'BEGIN{print d*0.5}')" -i "$mp4" -frames:v 1 "$EP/frames/$id/mid.png"
  ffmpeg -y -v error -ss "$(awk -v d="$dur" 'BEGIN{print d-0.15}')" -i "$mp4" -frames:v 1 "$EP/frames/$id/last.png"
done
echo "时长合计: 实际=${ACT_SUM}s 期望=${EXP_SUM}s"

# ---- Phase 6: 拼接（试点模式不拼接）----
if [ "$FAIL" = "0" ] && [ "$MODE" != "pilot" ]; then
  say "拼接 final.mp4"
  LIST="$RUN/concat.txt"; : > "$LIST"
  for d in "$RUN"/scenes/scene-*; do
  [ -d "$d" ] || continue
    id="$(basename "$d")"; echo "file '$d/$id.mp4'" >> "$LIST"
  done
  ffmpeg -y -v error -f concat -safe 0 -i "$LIST" -c copy "$RUN/final.mp4"
  say "ALL-PASS: $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$RUN/final.mp4")s"
else
  say "HAS-FAILURES"; exit 1
fi
