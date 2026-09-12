#!/usr/bin/env bash
# Phase 4+5+6: 拆镜（Codex）→ SCENE_ID 护栏 → 并行执行 → 质检门（参数化验收+lint+抽帧）→ 拼接
# 用法: bash run-scenes-v2.sh <epDir>
set -uo pipefail
PIPELINE="${PIPELINE_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PY="${PIPELINE_PY:-$PIPELINE/.venv/bin/python}"
AUTO_MOTION="${AUTO_MOTION_DIR:-$HOME/auto-motion}"
TTS_CLI="${TTS_CLI:-$HOME/Documents/Codex/shared/volcengine-doubao-tts/tts.py}"
EP="$1"
RUN="$EP/run"
LOGS="$EP/logs"

eval "$($PY "$PIPELINE/ep-env.py" "$EP")"
W="$WIDTH"; H="$HEIGHT"

mkdir -p "$RUN" "$LOGS"
rm -rf "$RUN"/scenes "$RUN"/PROMPT.md 2>/dev/null

# ---- Phase 4a: 工作区组装（仓库原生模板 + 本集产物）----
cp $AUTO_MOTION/PROMPT.md "$RUN/PROMPT.md"
cp -R $AUTO_MOTION/exampleFolder "$RUN/exampleFolder"
cp "$EP/transcription.srt" "$RUN/transcription.srt"
chmod +x "$RUN/exampleFolder/run-claude-ai.sh"

# ---- Phase 4b: PROMPT 追加段（尺寸参数化 + 设计契约 + 防错三护栏 + 特效选型）----
cat >> "$RUN/PROMPT.md" <<APPEOF

## 本集执行参数（episode.yaml 派生，具有最高优先级）

- 画幅：**${W}×${H}（${FPS}fps）**。所有镜头、所有构图根节点 data-width="${W}" data-height="${H}"。
  模板中出现的 1080x1440 一律以本参数为准。

## 执行层模型要求（必须执行）

- 在为每个镜头填写并执行 run-claude-ai.sh 时，必须给 claude 命令追加 --model qwen3.8-flash 参数，
  即：claude -p --model qwen3.8-flash ...；不要回退到默认模型，不要修改或忽略本要求。

## 设计契约（必须执行）

- 工作区根部的 frame.md 是全片视觉唯一真源（blue-professional 预设 + 本集画幅适配 + 中文字体对）。
- 你在为每个镜头填写 run-claude-ai.sh 的 PROMPT 时，必须写入以下指令：
  「先读当前目录 frame.md；色板、字体、间距、组件只能取自该文件 frontmatter tokens；
  背景为暖奶油纸面，强调色仅用钴蓝 primary；禁止深色底、禁止自选配色。」
- 特效技能选型（.claude/skills/ 已预装）：disney-animation-rule-skill 每镜头必点名；
  light-spotlight / svg-assembly / pixel2motion / printed-curtain / threejs-earth / 3d-chladni
  按镜头文案语义至多点名 1 个；未命中不点名。特效与 frame.md 冲突时以 frame.md 为准。

## 防错护栏（违反任何一条即镜头失败）

1. SCENE_ID 必须等于镜头目录名（scene-00N），不得沿用模板默认值。
2. 禁止把渲染放到后台；claude 退出前必须完成渲染并把 mp4 转存到镜头目录（文件名=SCENE_ID.mp4）。
3. 每个镜头完成后输出阶段消息的规则不变（[[USER_MESSAGE]] 四条）。
APPEOF

# ---- Phase 4c: Codex 拆镜 + 填模板 ----
say() { printf '\033[1;36m[scenes]\033[0m %s\n' "$*"; }
say "Codex 拆镜启动（尺寸 ${W}x${H}）"
codex exec \
  --cd "$RUN" \
  --dangerously-bypass-approvals-and-sandbox \
  --skip-git-repo-check \
  --json \
  --output-last-message "$LOGS/codex-last-message.txt" \
  - <"$RUN/PROMPT.md" 2>&1 | tee "$LOGS/codex-events.jsonl" | grep -E '"type":"(item.completed|turn.completed|error)' | tail -200

# ---- Phase 5a: SCENE_ID 护栏（自动纠正副本里的漏改）----
say "SCENE_ID 护栏检查"
for d in "$RUN"/scenes/scene-*; do
  id="$(basename "$d")"
  f="$d/run-claude-ai.sh"
  [ -f "$f" ] || continue
  if ! grep -q "SCENE_ID=\"\${SCENE_ID:-$id}\"" "$f"; then
    sed -i '' "s/SCENE_ID=\"\${SCENE_ID:-[a-z0-9-]*}\"/SCENE_ID=\"\${SCENE_ID:-$id}\"/" "$f"
    say "  已纠正 $id 的 SCENE_ID"
  fi
done

# ---- Phase 5b: 并行执行（B 方案）----
say "并行执行镜头（并发 3）"
ls -d "$RUN"/scenes/scene-* | sort | xargs -P 3 -I{} bash -c '
  d="{}"; id="$(basename "$d")"
  cd "$d" || exit 127
  echo "[$id] start $(date +%H:%M:%S)"
  bash run-claude-ai.sh > "$id.launch.log" 2>&1
  echo "[$id] exit=$? $(date +%H:%M:%S)"
'

# ---- Phase 5c: 孤儿渲染补渲 ----
say "孤儿渲染检测"
for d in "$RUN"/scenes/scene-*; do
  id="$(basename "$d")"
  if [ ! -s "$d/$id.mp4" ] && [ -f "$d/hf-proj/index.html" ]; then
    say "  $id 缺 mp4 但 hf-proj 完整 → 补渲染"
    (cd "$d/hf-proj" && npx hyperframes render --output "$id.mp4" >/dev/null 2>&1 \
      && cp "$id.mp4" "$d/$id.mp4" && say "  $id 补渲染完成") || say "  $id 补渲染失败"
  fi
done

# ---- Phase 5d: 质检门（参数化验收 + 编码规范化 + 抽帧）----
say "质检门（${W}x${H} @${FPS}fps）"
FAIL=0; EXP_SUM=0; ACT_SUM=0
for d in "$RUN"/scenes/scene-*; do
  id="$(basename "$d")"; mp4="$d/$id.mp4"
  exp="$(grep -m1 'SCENE_DURATION_SECONDS=' "$d/run-claude-ai.sh" | sed 's/.*:-\([0-9.]*\).*/\1/')"
  [ -s "$mp4" ] || { echo "FAIL $id: mp4 missing"; FAIL=1; continue; }
  # 编码规范化：QuickTime 对 H.264 level>4.0 / 非 yuv420p 会渲染空白（Episode1-v2 实测教训）。
  # 统一强制 High@4.0 + yuv420p，与 PROMPT.md「规格不一致先转码规范化再拼接」同源。
  encj="$(ffprobe -v error -select_streams v:0 -show_entries stream=profile,level,pix_fmt -of json "$mp4")"
  prof="$(jq -r '.streams[0].profile' <<<"$encj")"; lvl="$(jq -r '.streams[0].level' <<<"$encj")"; pix="$(jq -r '.streams[0].pix_fmt' <<<"$encj")"
  if [ "$prof" != "High" ] || [ "$lvl" != "40" ] || [ "$pix" != "yuv420p" ]; then
    say "  $id 编码 $prof@$lvl/$pix 不合规 → 规范化重编码"
    ffmpeg -y -v error -i "$mp4" -c:v libx264 -profile:v high -level:v 4.0 -pix_fmt yuv420p -crf 18 -r "$FPS" "$d/.norm.mp4" \
      && mv "$d/.norm.mp4" "$mp4" && say "  $id 规范化完成" \
      || { echo "FAIL $id: 规范化重编码失败"; FAIL=1; continue; }
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
  # 抽帧（首/中/尾）
  mkdir -p "$EP/frames/$id"
  ffmpeg -y -v error -ss 0.1 -i "$mp4" -frames:v 1 "$EP/frames/$id/first.png"
  ffmpeg -y -v error -ss "$(awk -v d="$dur" 'BEGIN{print d*0.5}')" -i "$mp4" -frames:v 1 "$EP/frames/$id/mid.png"
  ffmpeg -y -v error -ss "$(awk -v d="$dur" 'BEGIN{print d-0.15}')" -i "$mp4" -frames:v 1 "$EP/frames/$id/last.png"
done
echo "时长合计: 实际=${ACT_SUM}s 期望=${EXP_SUM}s"

# ---- Phase 6: 拼接 ----
say "拼接 final.mp4"
LIST="$RUN/concat.txt"; : > "$LIST"
for d in "$RUN"/scenes/scene-*; do
  id="$(basename "$d")"; echo "file '$d/$id.mp4'" >> "$LIST"
done
ffmpeg -y -v error -f concat -safe 0 -i "$LIST" -c copy "$RUN/final.mp4" || FAIL=1

if [ "$FAIL" = "0" ]; then
  say "ALL-PASS: $(ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$RUN/final.mp4")s"
else
  say "HAS-FAILURES"; exit 1
fi
