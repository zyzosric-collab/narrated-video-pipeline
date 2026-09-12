---
name: narrated-video-pipeline
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [macos]
description: Produce narrated MG videos via the local episode pipeline.
metadata:
  hermes:
    tags: [video, auto-motion, tts, pipeline, mg-animation, hyperframes]
    related_skills: [codex, claude-code]
---

# Narrated Video Pipeline (v2)

Turns a topic into a finished narrated motion-graphics video: research → 影视飓风-style script (mediastorm-copywriter) → Doubao TTS narration with word-level timestamps → auto-motion scene rendering (Codex director, Claude Code using the user's current configured model, HyperFrames) → BGM/SFX ducking mix.

## Script writing style bar (hard-won across Episodes 1-2)

The script is the most-iterated artifact — user rejected MANY drafts. Rules that now govern P1:

- **Never reuse the previous episode's skeleton** for a same-adjacent topic: same opening move, same data contrast, same 升华 direction = user calls it a reskin ("和之前那个测试稿几乎一样"). Style template ≠ content-template: hooks/data/升华 must be rebuilt fresh each episode.
- **Opening 3 seconds must be a concrete instant** (user-selected via checklist): time + action + anomaly ("昨天下午三点，我敲了一行字，然后去泡了杯咖啡"). No abstract questions ("你有没有想过…有多麻烦？" was rejected), no topical buildup — start IN the moment.
- **Show don't rate**: never exaggerate speed ("一小时出好几条" was rejected); convey advantage via the concrete complexity of manual work (磨脚本/配音两难/学软件劝退/对齐到秒).
- **种草/工具推荐 episodes (Episode4 pattern, user-approved 2026-09-03)**: open on the tool's PAYOFF as a concrete instant ("刚保存，另一个工具里就已经是新版了"), then flashback to the manual-pain contrast (上周复制三份、版本角标错位). Give every technical mechanism ONE life analogy (软链接→"把U盘拷文件换成了同步盘"). One selling point per segment; compress caveats/warnings to ≤2 short segments placed AFTER the value props. v1 that catalogs features with a mild-annoyance hook got "文案写的不是很吸引人"; v2 with this structure got "还凑合吧" = approval, stop iterating.
- **Script/voice previews must use the pipeline's real TTS** — never a generic built-in TTS provider (Episode4: an edge-voice preview drew "配音没有按照我的要求来"; the approved 豆包大壹 voice + 咬字 pronunciation instructions ARE part of the deliverable). Since build_narration_v2.py caches per-segment audio, running real P2 right after script approval IS both the preview and the final narration — changed segments re-synthesize, the rest is reused.
- **去 AI 味 in the voiceover body**: no 破折号, no 冒号列举句, no 引号强调, no "不是A是B"对仗收尾 (max 1, plain-language only), no "你会发现/从来/真正"升华腔. oil-tone lint + a symbol/pattern counter script; short spoken sentences, one point per sentence.
- **Naming**: never "流水线" in the script body — call it skill / 技能包 (user-set).
- **CTA must match the deliverable**: if the video already IS the demo, "想看现场跑一遍" is contradictory (user rejected). Use 关注/联系 paths.
- When text-only polish stalls (3+ rejections), switch narrative STRUCTURE (offer full alternative skeletons: 先看结果/倒叙拆解/报价反差/身份反差) rather than rewording; or ask the user to check which dimension is off (网感/开场瞬间/真实细节/节奏) — do not keep guessing.
- When stuck on subjective quality, let the FRAME carry half the attraction (voiceover becomes narration over strong visuals).
- **Hot-topic episodes** (news reactions, model releases): build a research.md FIRST from official pages + ≥3 independent sources; every number spoken must carry its comparison (vs previous version or rival — bare numbers are meaningless aloud); prefer one overlooked detail as the mid-video turn (e.g. hidden watermarks in the Fable 5.1 release); hot window is 48-72h; script completeness beats a length target (user: "不要刻意压时长").

- **Runner**: `$PIPELINE_DIR`（默认 `~/video-pipeline`）— entry `episode.sh`, subcommands `init|voice|design|scenes|audio|status`
- **Upstream repo**: `~/auto-motion` (vibe-motion/auto-motion). Its tracked files must stay pristine — the runner works on copies in `<epDir>/run/`.
- Full internals, pitfalls, and recipes: `references/pipeline-internals.md`
- External narration bridge (user-supplied script + voice): `references/external-narration-bridge.md`
- Scene efficiency/quality gate text + live status dashboard: `references/scene-quality-gates.md`
- **Platform publish rules (MUST read before writing any publish kit)**: `references/platform-publish-rules.md` — per-platform title-length/tag-count/description limits; writing a publish kit without checking these got Episode2's v1 rejected (视频号标题超16字、标签超限).

## Audio and delivery policy

Use the `audio-asset-sourcing` skill for BGM/SFX discovery, licensing records, sound-plan generation, auditioning, ducking, and final audio validation. Prefer Pixabay for both music and SFX when accessible; if blocked, use a documented fallback and never mislabel the source. Keep the silent auto-motion master separate from the mixed derivative. Do not add episode-number markers such as `EP.01` to end cards; use a plain closing label such as `感谢观看` unless the user explicitly requests a series marker.

## When to Use

- User gives a topic and wants a narrated short video made
- User provides a `transcription.srt` for the auto-motion flow
- User supplies BOTH the finished script and the finished voiceover mp3 (their own 豆包语音 output): external narration mode — skip P1/P2 entirely, never call TTS, never edit their text; bridge their audio to word-level timestamps via whisper (see `references/external-narration-bridge.md`, validated Episode5)
- Resuming/patching an existing episode directory (e.g. re-run one scene, swap BGM)

Don't use for: one-off clips not part of this pipeline (use the hyperframes skills directly), or non-narrated animation requests.

## Before You Build — decisions to ask (never skip)

1. **Aspect ratio**: 9:16 (1080×1920) / 16:9 (1920×1080, default) / 3:4 (1080×1440). All three are supported via episode.yaml; validation reads expected W×H from it.
2. **Visual preset — MUST ask every episode (user order 2026-09-02)**: never default-carry the previous episode's preset. Present a recommendation with reasoning (热点/知识类 → blue-professional; 传播/吸引类 → capsule), name the alternative, and offer `render-presets.py` previews. User decides.
3. **BGM mood keywords** (infer from topic, confirm with user).
4. **Visual mode for tool-demo/product episodes** (Episode4, 2026-09-03): pure animation vs hybrid — animation backbone + the user's REAL UI screenshots as window-cards inside feature segments (user chose hybrid). Check the user's Desktop for their OWN screenshots first ("我桌面上有截图") before downloading official assets; episode assets live only under `<epDir>/assets/`. Lock the real numbers visible in those screenshots into `<epDir>/prompt-overlay.md` so scenes cannot invent data.

If the user wants to discuss design first, produce a design doc and wait — do not implement while design is under discussion.

## Workflow

**New-order pipeline (user-approved 2026-09-01 — BGM audition BEFORE rendering)**:

```text
1. user confirms script
2. TTS voice (narration + word timestamps)  — fix includes 句首咬字 instruction
3. BGM audition as AUDIO ONLY: narration.mp3 + each candidate track -> audition-<id>.mp3 (seconds each, no video)
4. user picks BGM  ← last decision point
5. render scenes + concat + single mix -> final-with-voice.mp4 (head 0.4s silence pad)
6. publish kit (read references/platform-publish-rules.md first)
```

**Delivery**: present the final cut as `MEDIA:<path>` AND open it via `desktop_preview` — Episode4: handing over only a path got "视频在哪里？我没看到".

Never build full-video audition versions per BGM candidate — that triples rendering for a music decision (Episode2 did this; user corrected). The silent master (run/final.mp4) may exist before BGM selection if scenes finished rendering, but scene rendering is scheduled AFTER BGM pick when starting from script.

```bash
bash episode.sh init <epDir> 16:9 blue-professional   # P0: writes episode.yaml
# P1: research + write script with mediastorm-copywriter skill (human reviews)
#     then emit <epDir>/script-segments.json: [{"style":..., "text":...}, ...]
bash episode.sh voice <epDir>                          # P2: Doubao TTS per segment -> narration.mp3,
                                                       #     transcription.srt + voice-timing.json (word-level)
bash episode.sh scenes <epDir>                         # P4-6: Codex fills run-claude-ai.sh per scene ->
                                                       #     SCENE_ID guard -> per-scene terminals (-P3) with efficiency+quality gates ->
                                                       #     orphan re-render -> per-scene validation -> concat
bash episode.sh design <epDir>                         # P3: adopt preset FRAME.md as frame.md + episode
                                                       #     overlay (aspect/CJK/caption rules) -> distribute to scenes
bash episode.sh audio <epDir> [bgm.mp3] [sfxDir]       # P7: ducking mix -> final-with-voice.mp4
bash episode.sh status <epDir>                         # phase checklist
```

The scene executor `run-scenes-v3.sh` (invoked directly, or via `episode.sh scenes <epDir> [plan|pilot|rest|all]` — the subcommand now dispatches to v3) takes a MODE arg: `all` (default full run), `plan` (Codex planning only, stops before rendering — the pilot-first entry point), `pilot` (renders scene-001 only, skips concat), `rest` (batch everything EXCEPT scene-001 at concurrency 3 — the post-pilot entry point, added 2026-09-05). Set `REUSE_PLAN=1` whenever the plan already exists: it skips workspace re-assembly AND Codex re-planning — without it every invocation re-runs the full Codex planning burn (~10-20min quota) and the plan can drift from what the user actually reviewed. Guards/contract files/timing slices/gate re-injection still run (idempotent). The scheduler is a pure-bash concurrency-3 pool (xargs retired, see scene-quality-gates.md). Episode-specific constraints go in `<epDir>/prompt-overlay.md` — the executor appends it to the Codex PROMPT and auto-distributes `assets/screenshots/*.png` into `run/screenshots/` with window-card usage rules.

P1 (writing) is human-in-the-loop: load `mediastorm-copywriter`, draft with its required structure and self-checks, show the user, iterate before voicing. Style bar: see "Script writing style bar" above — it overrides generic skill defaults where they conflict.

**Approval gate is non-collapsible (episode4 lesson, 2026-09-03 — user formally complained):** after ANY rejection, the rewritten draft goes back to the user for approval FIRST; never batch "rewrite + TTS" and present script+voice together for combined review. The fix-then-show lint loop covers lint findings only and is never a substitute for the approval gate. Also: all voice previews/auditions must use the pipeline's official TTS channel (tts.py with the episode's configured speaker), never an ad-hoc platform TTS — treating a preview as a throwaway artifact does not excuse the wrong engine.

### TTS notes (Episode2-verified)

- The parse-script style_map must map EVERY user segment tag to a styles.json preset; unknown tags (e.g. `pain`, `reveal`) crash TTS mid-batch. Extend the map whenever the user's script uses new tags.
- **首字抢拍 fix** (see `references/pipeline-internals.md` for full recipe): add 「开头第一个词咬字清晰、饱满有力，不要抢拍、不要吞字；句首适当留出呼吸感再开口」 to the pronunciation instruction; after regenerating ANY segment, re-concat narration.mp3 AND rebuild global voice-timing.json (offsets accumulate per segment), then re-sync to run/.

### Tone lint (mandatory, user-approved 2026-09-01 — fix-then-show)

`oil-tone` (creative/) is installed as a CHECKER ONLY — never as the script writer for this pipeline (its philosophy bans the 升华/金句/CTA endings that mediastorm requires; writer stays mediastorm-copywriter).

**Fix loop (user-approved 2026-09-01): the agent fixes its own draft's lint findings — the user never line-edits agent-drafted text.** Loop: draft → run lint → fix all FAILs myself → judge each WARN with documented reasoning (口播设问/排比是 mediastorm 特性, not bugs) → re-run until clean → only then show the script to the user. The user's role is content-level approval (viewpoint, facts, taste), not proofreading. This differs from the script-recovery gate: that rule protects USER-authored/approved scripts from agent edits; this rule applies to agent-drafted drafts before first approval.

```bash
python3 ~/.hermes/skills/creative/oil-tone/scripts/tone_lint.py <epDir>/script.md
```

### Script revision and recovery gate

- Treat the user-approved script as the single source of truth for all downstream artifacts. A script change invalidates narration, word timestamps, SRT, scene boundaries, scene visuals, SFX timing, BGM automation, and the final mix.
- When the user asks to restore an original script, do not reconstruct it from memory or from a derivative `script.md`. Search for an independent source artifact first: the original writing-project script, the first TTS display text, the first SRT, or the earliest approved session artifact. Show the discovered source and provenance before overwriting anything.
- If the exact original cannot be proven, do not claim restoration. Preserve the current file, save a clearly named recovery candidate separately, and ask the user to confirm which version is authoritative.
- Never silently rewrite a user script to fix factual or technical wording. Offer corrections separately; the user edits and approves the script before any TTS or visual regeneration.
- After approval, regenerate the entire dependency chain in order; never mix old narration or scenes with a revised script.

## Hard rules (user-set — violating these got corrected in-session)

- **Script approval gate BEFORE TTS (user order 2026-09-03, Episode4 复盘)**: after drafting or revising a script, deliver the TEXT ALONE for user review first and wait for explicit approval; never bundle "finished script + generated voiceover" into one review delivery. Any TTS run before script approval is a violation — efficiency arguments (segment-reuse skips, preview convenience) are never a justification. The user must be able to judge the script as pure text, before a generated voice anchors their review.
- **Official TTS channel for ALL voice output, auditions included (user order 2026-09-03)**: every voice preview, audition, or interim sample MUST go through the pipeline's official Doubao TTS (`tts.py`, `zh_male_dayi_uranus_bigtts` + pronunciation instruction). Never use platform built-in TTS (e.g. Hermes edge voice) as a stand-in — a wrong voice color contaminates the user's first judgment of the script itself.
- **Pure upstream**: never edit tracked files in `~/auto-motion` (untracked additions only, e.g. preset folders); never source skills from `~/.claude/skills` or `~/.codex/skills` modified copies — user explicitly rejected that.
- **Palette authority = the user's named preset**: user rejects dark/oppressive DEFAULTS and any self-chosen palette, but an explicitly user-named preset overrides (Episode3: user ordered broadside, a dark-first two-register preset, after blue-professional had already started). Color gates must therefore be PRESET-AWARE, not blanket 禁止深色底: dark register allowed only from the named preset's official tokens (no extra dark tints/vignettes/grain); light presets keep the ban. After ANY preset switch mid-episode, re-inject every scene prompt and verify no old text remains (`grep -l '禁止深色底' <epDir>/run/scenes/scene-*/run-claude-ai.sh` must be empty) before relaunching.
- **Episode-agnostic tooling**: any per-episode helper (status-watcher.py, run-scenes-v3.sh paths) MUST take the episode dir as a parameter/argument — hardcoded episode paths silently break after an episode is cleaned up (status-watcher pointed at deleted episode1-v3 and reported all scenes as 排队中 while episode2 was actually rendering; user caught it). status-watcher.py now reads `RUN = sys.argv[1]` if edited again — verify the dashboard path matches the ACTIVE episode before showing it to the user.
- **Executor model**: never change or override the user's Claude Code model configuration. Scene scripts must invoke `claude -p` without a `--model` flag unless the user explicitly specifies one for this run; Claude Code then selects the model from its current configuration. Read-only inspect the effective route before execution; never edit settings or infer a model from an old run. Routes change often (opencode.ai/zen -> local cliproxy 127.0.0.1:8317 -> tokenrhythm, observed within one week). Pre-flight per batch: one `claude -p --output-format text "Reply exactly SMOKE"` smoke run in /tmp; a `[claude-code:unrecognized_model]` stderr line is benign, but `API Error: 400 unknown provider` means stop and wait for the user — never pick substitute models yourself. Transient `503 auth_unavailable` from the provider is NOT a route failure — retry with backoff (see `references/scene-quality-gates.md`).
- **Scene hard timeout + capability escalation**: enforce a mechanical 25-min kill per scene (prompt budgets are soft; one scene ran 44min). If the pilot scene fails user acceptance twice after gate-compliant retries, stop and tell the user the bottleneck is the model — let them choose a stronger one (gpt-5.6-sol was user-rejected once). Full protocol: `references/scene-quality-gates.md`.
- **No burned-in captions**: the user removed karaoke/verbatim on-screen narration text (2026-08-31). Scene prompts must explicitly forbid caption bars and verbatim script text; visuals are graphic storytelling + short conceptual labels only. Strip the `## Caption` contract from frame.md copies injected by gen-overlay.py.
- **Parallel scene execution is sanctioned** (executor concurrency 3; pure-bash pool since 2026-09-05, xargs retired) even though auto-motion's PROMPT.md says serial — user approved the deviation. Split orchestration into two explicit phases: Codex planning only, then the external executor runs the prepared scene scripts; never let Codex render and then render the same scenes again in parallel.
- **Scene tasks must be visible & quota-bounded**: one Hermes background terminal PER scene — never hide scenes inside one xargs/parent shell (user complained twice about lost visibility). The script redirects Claude output into `claude-<scene>.stream.jsonl`/`.user.log`, so tabs look quiet by design — give the user the live status dashboard (`video-pipeline/status-watcher.py` -> `status.html`, open via preview; per-scene cards, 10s refresh). **Default concurrency 3 (user order 2026-09-02 "以后默认并发就是并发3", overriding the old default of 2)**; per-scene hard timeout 25 min and circuit-breaker stay in force.
- **Scene efficiency + quality gates are mandatory**: inject both into every `run-claude-ai.sh` BEFORE executing (full text: `references/scene-quality-gates.md`). Efficiency: no web/font searches, no reading outside the scene's own directory, time budgets (~15min scene total), no TODO scaffolding. Quality: `npm run check` clean -> `hyperframes snapshot` >=3 frames -> checklist (no decoration over text, balanced composition, NO caption bars / karaoke / verbatim narration text — captions removed by user 2026-08-31, Noto Sans SC for CJK, keywords hitting scene-timing.json, no EP numbering) -> only then final render. One ungated run burned 34min/scene on 'font archaeology' and produced user-rejected visuals.
- **Ask the aspect ratio up front** — user requested this explicitly.
- **Pilot-scene-first is the default**: render scene-001 (or the shortest scene) alone, run full acceptance (spec + stage messages + frame sampling via vision_analyze), get explicit user approval of the standard, THEN batch the rest at concurrency 3. Never start the full batch ungated — one ungated batch produced user-rejected visuals across 3 scenes (2026-08-31). If a mid-batch scene fails acceptance, stop new launches, fix the gate text, re-run the failed scene before refilling slots.
- **Pilot fixes are surgical, not generative (2026-09-05)**: when the user accepts the pilot's standard with small notes (label size, spacing, line endpoints), do NOT re-run the scene model. Edit the accepted scene's `index.html` CSS directly (compute geometry first — e.g. a rotated connector div's horizontal reach = left + width·cos|θ|), re-render locally `cd <sceneDir> && npx hyperframes render --output <id>.mp4` (~8s, zero model quota), re-verify (ffprobe + fresh first/mid/last frames). Inject the user's fixes as a `用户验收修正（最高优先级）` block into every NOT-YET-RUN scene's run-claude-ai.sh BEFORE launching the batch (Python injector anchored on `效率约束`; running scenes never see prompt edits). Validated rules + recipe: `references/scene-quality-gates.md` § Acceptance-derived visual rules.
- **Read the full docs before proposing designs** — shallow reading of auto-motion/hyperframes produced wrong recommendations once; design proposals must come after a complete pass over the mechanism files.

## Pitfalls

- **Runner path resolution**: the executor resolves its own dir via `BASH_SOURCE` and the interpreter as `$PY` = `PIPELINE_PY` ?? `$PIPELINE_DIR/.venv/bin/python`, so it runs from any cwd. Historical trap: an older version resolved `.venv/bin/python` relative to cwd and, from a wrong cwd, printed "[episode] Phase 2 完成" while voice never ran — a silent success lie (Episode4). Regardless of the fix, **verify the phase artifact (`assets/narration.mp3` etc.) exists before trusting a completion line**.
- **Model self-check is necessary but not sufficient**: a model can pass its own snapshot self-check while the composition still has narrative defects (v3 scene-002 ended on two empty circles — the converge action had no payoff). Hermes MUST independently vision_analyze at least a mid frame + the final frame of the pilot scene, and ≥2 frames (mid + end) of every batch scene. Ending-frame check: composition must be a settled state with no placeholder nodes or dangling connectors (gate item 7 in scene-quality-gates.md).
- **gen-overlay.py preset map**: was hardcoded to two presets and KeyError'd on broadside — and the executor KEPT GOING, so frame.md silently lost its Episode Overlay and Codex planned without aspect/CJK/hard-rule sections. Map now covers all 13 presets with a .get() fallback, but ALWAYS verify `grep -c 'Episode Overlay' <epDir>/run/frame.md` returns 1 before starting Codex planning. Run it with the runner venv python ($PY — has PyYAML); system python3 lacks yaml.
- **Prompt/gate edits never reach running scenes**: changing run-claude-ai.sh mid-batch only affects not-yet-started scenes. To fix gate text mid-batch: kill the executor AND `pkill -f 'claude -p'`, clean each touched scene's partials (stream.jsonl/launch.log/mp4/hf-* project dirs), relaunch the whole batch. Mid-batch concurrency change = kill ONLY the scheduler (the `run-scenes-v3.sh` process), keep running `claude` processes alive, then relaunch over the remaining scenes — a temporary over-provisioned transition is expected.
- **bash heredocs containing Chinese text + `${VAR}` interpolation** corrupt variable names with stray bytes (`W×H` -> `W<bad>:`) -> unbound-variable failures. Generate prompt overlays with small Python scripts reading episode.yaml (see `gen-overlay.py`, `ep-env.py`), never bash heredocs.
- **Codex template slips**: may leave `SCENE_ID="${SCENE_ID:-scene-001}"` in every scene (outputs then land as scene-001.mp4 in each dir) -> validate the generated script and output name against the directory before running. Do not require or inject a model flag; verify that no unintended `--model` override is present when the user asked to keep current configuration.
- **Orphan renders**: Claude may start `hyperframes render` in the background then exit; the mp4 never lands. If `<scene>.mp4` is missing but `hf-proj/index.html` exists, `cd hf-proj && npx hyperframes render --output <id>.mp4` recovers in ~20s. Note the project dir name varies (`hf-proj`, `hf-project`, `hf`, or project files loose at the scene root) — check all variants when hunting orphans, and make sure leftover `index.html`/`renders/` from a cancelled run are cleaned before relaunching a scene.
- **Doubao word timestamps** use `startTime`/`endTime` field names (not start/end) inside `sentences[].words[]`; requested via `tts.py --subtitle-json <out.json>`.
- **final.mp4 has no audio stream** — mixing filtergraphs must reference only the audio inputs (narration/bgm/sfx); `[0:a]` matches nothing and fails.
- **sidechaincompress** signature: `[main][sidechain]sidechaincompress=...` — first input gets compressed, second drives it. BGM is main, narration is sidechain.
- **BGM sourcing**: Openverse API (`api.openverse.org/v1/audio/?q=...&license=cc0,by`) is the reliable route; Pixabay web is Cloudflare-walled for curl; Jamendo needs a client_id. Previously downloaded CC tracks live under a local per-episode `music/` asset dir.
- **node_modules duplication**: each scene's Claude runs its own `npm install` inside its scene dir (hundreds of MB per copy; v3 accumulated 2 full copies before cleanup). Optimization for future runs: install once at the episode level (shared `package.json` in `run/`), then symlink `node_modules` into each scene project before executing — cuts install time per scene to near zero and disk to one copy. Note Claude sometimes scaffolds loose files (`index.html` at scene root) instead of a `hf-project/` dir; the shared-install symlink must target wherever the project actually lands (check all variants: `hf-proj`, `hf-project`, `hf`, scene root).
- **Workspace lifecycle**: a failed/paused batch leaves behind a large scene tree (v3 reached 1.2GB before the user deleted the whole episode dir). On cleanup, distinguish: deliverable MP4s + narration/SRT/voice-timing (keep or archive per user choice) vs node_modules/logs/snapshots (safe to delete). If the user says "不要了" about an episode dir, confirm scope before `rm -rf` — the v3 deletion was user-approved in full after they explicitly chose to abandon the episode.
- 30fps encoding rounds scene durations up to whole frames, so concat total runs ~0.1s long over an 80s SRT — expected, not a bug.

## Verification

- `episode.sh status <epDir>` shows phase artifacts
- Per-scene: ffprobe W×H/fps/duration vs episode.yaml + scene expected duration (±0.3s), zero audio streams. Duration check is PER SCENE, not just total: sum can mask one short scene whose speech tail then bleeds into the next scene's visuals (Episode3 scene-001: 3.0s rendered vs 3.9s narration segment, hidden by a matching 95.5s total). Compare each scene mp4 against its scene-timing.json word window.
- Frame sampling: first/mid/last PNG per scene into `<epDir>/frames/` — check palette/register and layout before accepting. If vision_analyze 504s: max 3 attempts with one size reduction, then fall back to (a) a mid+last contact sheet (`frames/contact-sheet.png`) shown to the user, and (b) a DOM geometry audit (below). Mark uncovered scenes 未复核 in the delivery message.
- **Geometry audit for 错位/重叠 (user-requested, Episode4)**: scenes are HTML — audit the DOM instead of eyeballing. `episode4-skills-hub/logs/dom_audit.py` seeks the gsap timeline (`tl` inline var; scenes often leave `window.__timelines` unset) or CSS `document.getAnimations()`, then measures rect intersections: text-overlap (>20%), deco-over-text (>35%, svg layers judged by child union-box not full-canvas bbox), out-of-frame. Run with the Hermes kernel venv python (has aiohttp); `browser_exec` is blocked by the local SOCKS proxy (python-socks missing — do NOT pip install per user rule). Verify suspicions with computed-style probes + PIL pixel counts before editing; filter through opacity (parent-hidden children still report rects = false positives).
- Final: duration ≈ narration duration (±0.5s), AAC audio present, spot-listen ducking (BGM dips under speech). A/V streams must be equal length: align via `[0:v]tpad=stop_mode=clone` + `-t`; audio out via `aformat=sample_rates=48000:channel_layouts=stereo`.
- **Mix = the audition the user approved, exactly**: bake BGM at the auditioned gain (0.25 direct — `amix weights` re-halving silently halfs it; use `normalize=0`), same sidechain params; ffmpeg traps: `adelay=delays=400:all=1` (positional form fails on some builds), a filtergraph label is consumable exactly once (`asplit=2` for sidechain+mix paths).
