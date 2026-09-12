# Scene Execution Gates & Live Dashboard (v3)

Proven in `~/auto-motion-episode1-v3` (2026-08-31): an ungated batch burned 34+ min per scene (model did 'font archaeology' — system font greps, fontTools installs; read deleted sibling dirs; never reached render) and produced user-rejected visuals. Same model with gates: reading contract files and writing HTML within 2 minutes.

## No burned-in captions (USER DECISION 2026-08-31, all future episodes)

The user explicitly chose: **no subtitle bar, no karaoke word-highlight captions, no verbatim narration text on screen.** Visuals are pure graphic storytelling (diagrams, data viz, icons, spotlight reveals); narration audio carries the language; only short conceptual Chinese labels are allowed as visual anchors, timed to word-level timestamps.

- Remove any `## Caption（卡拉OK字幕契约）` section injected into frame.md copies (gen-overlay.py emits it; strip it across all copies: run/, exampleFolder/, 9 scenes).
- Replace the prompt line `不需要把镜头文案逐字放进画面…` with an explicit ban:
  `禁止把镜头文案逐字放进画面；禁止出现字幕条、卡拉OK字幕或任何逐字展示口播的文字。画面只用图形、图标、数据可视化和少量概念性中文短标签表达含义。`
- Quality-gate item 3 becomes: `画面中不得出现字幕条、卡拉OK字幕或逐字口播文字；概念性标签应为短语而非整句；` — post-render acceptance extracts frames to verify no caption bar/verbatim text.
- caption-skin.html may remain in template but is not wired into prompts; final deliverable has no burned captions. Offer external `.srt` (transcription.srt already exists) if the user later wants switchable subtitles.

## Inject BEFORE executing any scene (use Python string replace, not bash heredoc — CJK corruption risk)

Anchor: replace the first occurrence of `阶段性汇报规则：` in every `run-claude-ai.sh` (or insert before the quality gate if already present). After injecting, dedupe: a repeated header `效率约束（最高优先级，违反即失败）：\n效率约束（最高优先级，违反即失败）：` appeared when injecting into already-gated scripts — check for `效率约束` first and skip.

### Efficiency gate (highest priority)

```text
效率约束（最高优先级，违反即失败）：
- 开工只读 scene-context.md（内含设计 tokens、词级时间、必守规则）；除命中的特效技能 SKILL.md 外，禁止浏览其他技能文档。
- 禁止联网搜索字体、素材或任何资料；「开始联网搜索」阶段消息照常输出，但不要真的发起 WebSearch。
- 字体方案完全按 frame.md 执行，不要检查系统字体、不要用 fontTools 分析字形、不要下载字体。
- 只允许读取当前镜头目录内的文件。
- 预算：理解与检查 ≤2 分钟，写代码 ≤8 分钟，npm run check 与抽帧自查 ≤3 分钟，单镜头 ≤15 分钟。
- npm run check 最多 3 轮：error 清零即可渲染，剩余 warning 记入交付说明，不许循环打磨。
- snapshot 用 --at 一次抽 3 帧（开头/中间/结尾），不要分 3 次调用。
- 超出任一预算立即停止优化，直接渲染交付当前版本。
- 不要创建 TODO 任务列表，直接干活。
```

### Quality gate

```text
质量自检门（必须在最终渲染前完成，逐条执行）：
- 写完代码后先运行 npm run check，所有 error 修复后才允许渲染；warning 逐条评估处理。
- 最终渲染前，必须用 npx hyperframes snapshot --at 抽取开头、中间、结尾至少 3 帧到 snapshots/ 自查。
- 自查清单（任一不满足，必须修改代码并重新抽帧，直到全部通过）：
  1) 任何装饰元素（点阵、圆环、网格、线条、图形）不得压在文字上；
  2) 主视觉不得严重偏侧，画面重心平衡；遵循 frame.md 的栅格：pad-x 5cqw，左上标签/字幕条共享同一左边距；
  3) 字幕标点不得进入高亮块内，字距均匀，无逐字异常空格；
  4) 中文必须正确渲染：中文用 Noto Sans SC，Space Grotesk 仅用于数字和拉丁字符；不得出现豆腐块或字体回退错误；
  5) 关键词/数字出现时间与 scene-timing.json 词级时间一致；
  6) 片尾无任何 EP 编号；
  7) 结尾收束完整：终帧必须是落定构图——无空占位节点、无悬空未连接的线条、所有出场元素全部落地；两条汇聚线必须合并到一个有内容的终点节点（v3 scene-002 教训：两个空圆收尾被判定叙事未闭环）；
  8) 转场呼吸（用户明确要求 2026-09-02："有些动画刚刚完成就马上转到下一个画面，用户没有看清楚"）：镜头结尾所有元素完成入场后至少停留 0.8 秒再结束；禁止动画刚完成就切镜头；文案读完后的剩余时间用于收尾停留，不得提前结束分配时长。
- 自查全部通过后，才允许最终渲染 MP4；最终渲染必须使用与 snapshot 相同的工程文件。
```

### Diagnosing 'ugly' output

vision_analyze a mid-frame PNG. v3 review of a rejected frame: contract compliance ~85% (cream bg, cobalt accent fine) but hard defects — decorative dot grid overlapping badge text, left-heavy composition with dead right half, uneven caption letter-spacing, punctuation inside highlight blocks. The checklist above maps 1:1 to those defects.

## Visibility & quota rules (user complained twice)

- One Hermes background terminal PER scene — never a single xargs/parent shell; the parent pattern hid all per-scene progress.
- `run-claude-ai.sh` redirects Claude stdout into `claude-<scene>.stream.jsonl` and filters `[[USER_MESSAGE]]` lines into `claude-<scene>.user.log`, so tabs are quiet by design. Explain this instead of treating quiet tabs as a hang.
- Concurrency default 3 (user order 2026-09-02 "以后默认并发就是并发3"); refill completed slots manually. Mid-batch upgrade: kill only the xargs scheduler pid (running claude processes survive), then relaunch remaining scenes under a new -P3 scheduler.

## Preset-aware color gates (Episode3, broadside)

The blanket 禁止深色底 conflicts with dark-first presets the user may explicitly name (broadside = ink-black/fire-orange two-register, no cream/paper register). Executor gate text is now preset-aware: the named preset's official dark register is allowed verbatim from its tokens; extra dark tints stay banned. After a preset switch: patch every scene prompt, verify old text is gone (grep), clean partials, relaunch — running scenes never see edited prompts.

## Executor robustness (Episode3 hotfixes, all applied to run-scenes-v3.sh)

- Codex can drop FILES into run/scenes/ (a stray scene-plan.md once FATALed the executor: "scene-plan.md 缺 run-claude-ai.sh"). All scene loops use `[ -d "$d" ] || continue`; the launcher uses `find ... -type d`.
- After design injection assert `grep -c 'Episode Overlay' run/frame.md` == 1 before Codex planning (a silent gen-overlay KeyError lost the overlay once).
- Executor print text must match actual flags (said "并发 2" while running -P 3 — confusing during live monitoring).
- Live dashboard: `python3 $PIPELINE_DIR/status-watcher.py` (background, silent) rewrites `status.html` every 10s; open with desktop_preview. Parses each scene's `.user.log` (stage messages), tail of `.stream.jsonl` (last tool_use; mtime <90s = 运行中, older = 疑似停顿), MP4 presence/size.
- Progress read-out: count tool_use events per scene from stream.jsonl, print last 5 (name + 60-char hint of command/file_path/query) — distinguishes 'stuck in WebSearch 30min' from 'reading own contract files'.

### Transient provider 503s (tokenrhythm) — retry pattern, not a route failure

Distinguish from the fatal `400 unknown provider`: `API Error: 503 auth_unavailable: no auth available (providers=openai-compatible-tokenrhythm, model=...)` is a transient server-side gateway fault. Observed mid-run: a scene died after 12 min (12k events) while a sibling scene on the same model kept running with zero errors — the gateway randomly rejects some requests under load.

Response: do NOT stop the batch or bother the user. Free the dead scene's slot, clean its partial logs (`*.stream.jsonl *.user.log *.stderr.log *.launch.log`; keep `node_modules` — reinstalling wastes minutes), and relaunch with backoff (first retry ~5 min via `sleep 300;` prefix, then 10–15 min if it keeps failing). Success on retry is expected.

## Post-run cleanup trap

Killing a scene mid-run also leaves orphan PROCESSES: per-scene `hyperframes preview --foreground` servers and their chrome-headless-shell children. After pausing/killing scenes run `pkill -f 'claude -p'; pkill -f 'hyperframes/dist/cli.js preview'` and verify with pgrep — stale preview servers keep consuming resources and can hold file locks. (The 2026-08-27 `lingjing` project's own render process is unrelated — never pkill by bare 'hyperframes'.) Also, the live status-watcher process dies with session restarts; relaunch it silently when resuming.

Deleting scene artifacts with a glob (`rm -rf "$d/hf-project" "$d"/*.stream.jsonl ...`) silently LEAVES a renamed project dir (`hf/`) and stray files the model created at the scene root (`caption-skin.html`, `gsap.min.js`, `vendor/`, `renders/`, `snapshots/`, `index.html`, `hyperframes.json`). After cleanup, `ls` the scene dir and remove leftovers individually — stale `index.html`/`renders/` would be picked up by orphan-render recovery and produce wrong videos.

## Independent visual QC under service failures (Episode3, 2026-09-02)

vision_analyze can 504 intermittently; one scene's frames failed 4 straight attempts even after shrinking the PNG 1600→720→560→480px. Pattern: at most 3 attempts (with one size reduction between), then STOP retrying — mark that scene as `⏳ 视觉服务未复核` in the acceptance report, proceed with concat/mix so the pipeline isn't blocked, and explicitly name the un-reviewed scene + its time range in the delivery message so the user eyeballs it. Never present a batch as fully QC'd when one scene was skipped.

## Per-scene duration check (gap found in Episode3)

Total duration matching narration (+0.16s) MASKED a per-scene defect: scene-001 rendered 3.0s vs its 3.888s narration segment — its speech tail played over scene-002's visuals. After concat, verify EACH scene mp4 duration ≥ its scene-timing.json word window (last word endTime minus scene start offset, plus the 0.8s settle) within ±0.3s; a short scene must be re-rendered, not absorbed by the total. scene-timing.json is `{scene, words}` — derive expected duration from the words, don't expect a duration field.

0. **Mechanical scene timeout (approved 2026-09-01)**: the 15-min prompt budget is soft — models ignore it (v3 scene-001 ran 44min). The executor MUST enforce a hard kill: `timeout`-style watch at 25 min per scene (kill the `claude -p` process group, not the terminal), then auto-relaunch that scene ONCE with a fresh log. A scene that times out twice = suspected model-capability problem, not a network problem — report to the user, don't retry a third time.
0b. **Resident browser for gates (approved 2026-09-01)**: every `npm run check` / `hyperframes snapshot` call cold-starts a headless Chrome instance (10-20s each; measured 74s/100s/33s per snapshot, 20-49s per check in scene-002). The executor should start ONE persistent browser session per scene project before gates run and reuse it, saving 2-3 min per scene. Implementation note: check current HyperFrames CLI for a persistent-preview or daemon flag (`hyperframes preview --background` exists) and route check/snapshot through it; fall back gracefully to cold-start if unavailable.
1. Read `~/.claude/settings.json` env (READ-ONLY): base URL + default sonnet/opus model.
2. `cd /tmp && claude -p --output-format text "Reply exactly SMOKE"` (background, ~60s wait).
3. `[claude-code:unrecognized_model]` stderr = benign. Non-zero exit with `API Error: 400 unknown provider for model X` = route broken → stop, report, wait for the user (they change the model, not you).
4. Only after SMOKE passes, start the batch (2 terminals), then verify real progress within ~3min via stream.jsonl tool_use tail — a dead route fails within seconds; a live one accumulates events.

## Template-reuse across scenes (REJECTED 2026-09-01)

Proposal to let similar-structure scenes copy prior scenes' projects was REJECTED by the user: it risks duplicated-looking visuals, which conflicts with the product promise "每个镜头都是现写代码，画面不重复". Do NOT implement scene-to-scene template reuse. Per-scene fresh authoring stays mandatory. If scene production time must drop further, the sanctioned levers are: resident browser (above), scene-context pack, check budget, concurrency, and executor-model choice.

## BGM audition order (user-approved 2026-09-01)

Audition BGM as AUDIO ONLY (narration.mp3 + candidate track, one ffmpeg audio mix each — seconds, no video re-render), BEFORE any video rendering. Only after the user picks a track, render scenes / assemble video and mix once into final-with-voice.mp4. Never build three full video auditions — that triples rendering work for a music decision. Deliverables: three audition-<id>.mp3 files + audio-assets.json entries (source/artist/license), then a single final mix after selection.

## Model-capability escalation rule (approved 2026-09-01)

Quality ceiling is set by the executor model, not by gate text. If the pilot scene fails user acceptance twice after gate-compliant retries, STOP burning quota: report to the user that the bottleneck is the model's front-end/animation ability, and let them choose a stronger model. Never silently keep regenerating on a model the user has effectively rejected (gpt-5.6-sol was user-rejected once already). The gate guarantees the floor (contract compliance, no defects); it cannot guarantee taste — the pilot-approval step is where taste is calibrated.

## Executor consolidation TODO (approved 2026-09-01)

`run-scenes-v3.sh` had the right shape (plan → preflight → parallel → normalize → concat) but shipped with bugs and v3 ended up manually driven. Before the next episode: fix it into the single trusted executor — hard scene timeout (above), 503 auto-backoff relaunch, shared node_modules install + symlink (see SKILL.md pitfalls), orphan-render recovery for all project-dir variants, and per-scene acceptance hooks that call back with frame paths for vision_analyze. Target: `bash run-scenes-v3.sh <epDir>` runs unattended; Hermes only does visual acceptance and slot refills.

Shared-deps helper is now implemented: `python3 $PIPELINE_DIR/setup-shared-deps.py <epDir>` — run after scene scaffolding, before executing scenes. It installs once into `run/shared-deps` and symlinks every scene project's `node_modules` to it (handles `hf-proj`/`hf-project`/`hf`/loose-root variants, idempotent).