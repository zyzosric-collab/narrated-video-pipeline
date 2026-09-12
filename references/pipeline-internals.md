# Pipeline Internals (v2)

Machine-specific detail for `narrated-video-pipeline`. Paths are on the user's Mac.

## TTS 句首抢拍修复（2026-09-01，Episode2 验证有效）

大壹音色在 speech_rate=10 下句首会「抢拍」：首字被压短压轻（实测首字 110ms/-15.7dB，次字 170ms/-13.1dB），起播时前几字听不清。修复两步：

1. **发音指令加一句**（TTS 首次生成或重生成时必须带）：`开头第一个词咬字清晰、饱满有力，不要抢拍、不要吞字；句首适当留出呼吸感再开口。`
2. **重生成后必须重建下游**：段时长会变 → 重新 concat narration.mp3 → 用各段 words.json 重算全局 voice-timing.json（段间偏移累加）→ 同步到 run/。实测首字能量 -15.7→-8.5dB，全片时长 +0.53s。

原文件备份为 .bak；混音时成片开头垫 0.4s 静音（build-audio 内做），双保险。

## File map

```
$PIPELINE_DIR/（默认 `~/video-pipeline`）
  episode.sh              entry: init|voice|design|scenes|audio|status
  ep-env.py               episode.yaml -> shell eval lines (WIDTH/HEIGHT/FPS/PRESET/ASPECT/BGM_VOLUME)
  gen-overlay.py          frame.md Episode Overlay generator (aspect + CJK + caption rules);
                          preset map covers all 13 presets + .get fallback (KeyError'd on
                          broadside once -> overlay silently missing; verify with grep before
                          planning). Run with runner venv python ($PY, has yaml) not python3.
  build_narration_v2.py   P2: per-segment Doubao TTS + word timestamps -> narration.mp3,
                          transcription.srt, voice-timing.json
  inject-design.sh        P3: preset FRAME.md -> frame.md + overlay, distribute to scenes, caption-skin
  run-scenes-v3.sh        P4-6 CURRENT executor (approved 2026-09-01; MODE + overlay added
                          2026-09-03): workspace assembly, frame.md BEFORE planning, Codex
                          plan-only, SCENE_ID+contract guards, no --model override,
                          scene-context pack, gates injection (incl. 转场呼吸 item 8),
                          preset-derived color gates (REGISTER_RULE switches on episode.yaml
                          preset; broadside special-cased), prompt-overlay.md hook (episode
                          constraints appended to Codex PROMPT), screenshots distribution
                          (assets/screenshots -> run/screenshots + PROMPT usage section),
                          MODE arg: all (default) | plan (planning only, stops pre-render) |
                          pilot (scene-001 only, no concat), pure-bash concurrency-3 pool,
                          directory-filtered scene glob (Codex drops files into scenes/),
                          orphan recovery (hf-proj/hf-project/hf/loose), validation, concat
  make-scene-context.py   perf①: per-scene scene-context.md pack (frame tokens + word timing
                          + rules + effect-skill digest ≤2KB) so Claude reads ONE file instead
                          of 18-23 skill/file reads; also rewrites each prompt's read-first line
  make-scene-timing.py    per-scene scene-timing.json slices from voice-timing.json
  setup-shared-deps.py    perf③: one npm install at run/shared-deps + symlink into each scene
                          project (idempotent; handles hf-proj/hf-project/hf/loose variants) —
                          approved 2026-09-01, wire into executor before scene launch
  perf-audit-episode2.md  full timing audit + optimization decisions (user-approved)
  cut-points.py           scene cut timestamps from concat.txt (for SFX placement)
  build-audio.sh          P7: bgm prepare (loop/trim/fade) + sidechain ducking mix
  status-watcher.py       live dashboard: high-contrast standalone palette, pill badges,
                          progress bar; per-scene cards (stages/last tool/mp4/log size)
  render-presets.py       screenshots all 13 frame-presets for user preview
  V2-DESIGN.md            the design document the user approved

~/auto-motion/                    upstream repo - DO NOT edit tracked files
  exampleFolder/.claude/skills/    hyperframes* + motion-graphics + general-video + image-gen
                                   + 7 vibe-motion effect skills (untracked additions, sanctioned)
  frame-presets: exampleFolder/.claude/skills/hyperframes-design/frame-presets/
```

## Episode directory layout

```
<epDir>/
  episode.yaml          config source of truth (P0)
  script-segments.json  [{style, text}, ...] from P1
  narration.mp3         P2 concat output
  transcription.srt     sentence-level (consumed by auto-motion)
  voice-timing.json     sentence + word-level timestamps (consumed by captions)
  run/                  auto-motion workspace (PROMPT.md, exampleFolder copy, scenes/)
  run/frame.md          adopted design contract (P3)
  run/final.mp4         silent concat (native auto-motion deliverable)
  assets/bgm/ sfx/      audio sources
  frames/<scene>/       first/mid/last QC stills
  final-with-voice.mp4  final deliverable (P7)
```

## External commands — current machine facts

- Codex 0.151.0-alpha: `codex exec --dangerously-bypass-approvals-and-sandbox --skip-git-repo-check --json --output-last-message <file> - < PROMPT.md`. The old `--sandbox danger-full-access --ask-for-approval never` flags no longer exist. Shell execution goes through the code-mode-host binary (symlink `~/.local/bin/codex-code-mode-host -> /Applications/ChatGPT.app/Contents/Resources/codex-code-mode-host` — if missing, exec is fully broken; restore with `ln -sf`). MCP 401 noise at startup is harmless.
- Claude Code auth route is VOLATILE (observed in one week: opencode.ai/zen -> local cliproxy 127.0.0.1:8317 -> tokenrhythm; default model follows whatever the user last set). NEVER hardcode a model; scene scripts must not pass `--model`. Pre-flight per batch: read `~/.claude/settings.json` (read-only) + one `claude -p --output-format text "Reply exactly SMOKE"` smoke run in /tmp. `[claude-code:unrecognized_model]` stderr is benign; `API Error: 400 unknown provider` = report and wait for the user. Historical data points (stale-prone): glm-5.3-flash via opencode gateway 500'd/hung; qwen3.8-flash and deepseek-v4-pro worked there once; glm-5.3-flash[1M] via cliproxy smoked OK later.
- Doubao TTS wrapper: now bundled in this repo at `tools/volcengine-doubao-tts/tts.py` (the executor resolves it automatically after `$TTS_CLI`; the legacy `~/Documents/Codex/shared/volcengine-doubao-tts/tts.py` path is only a last-resort fallback). Key in `.env.local` as VOLCENGINE_TTS_API_KEY. Approved baseline: speaker `zh_male_dayi_uranus_bigtts` (大壹2.0), `--speech-rate 10` (~1.1x; config default 20 must be overridden). Word timestamps: `--subtitle-json <out>` returns `sentences[].words[]` with `word/startTime/endTime/confidence`. Pronunciation instruction: forbid digit-by-digit slow-down and exaggerated emphasis (user rejected that in an earlier episode); build_narration_v2.py PRONUNCIATION_INSTRUCTION now also carries the 句首咬字 line + clear standard English for model/tech names, natural CJK↔EN switching, decimals read as Chinese numbers (Episode3 script is dense with "Anthropic / Fable 5.1"). TTS-reading replacements like `AI->A I`, `HTML->H T M L` apply to the spoken text only, never the SRT display text.
- ffmpeg mix recipe (final.mp4 has NO audio stream; audio inputs are narration/bgm/sfx):
  1. Prepare BGM: `ffmpeg -stream_loop -1 -i bgm.mp3 -t <vid_dur> -af "volume=0.25,afade=t=out:st=<dur-2>:d=2" bgm-prepared.wav`
  2. Duck: `[1:a][2:a]sidechaincompress=threshold=0.03:ratio=6:attack=120:release=600[bgmduck]` (bgm main, narration sidechain)
  3. Mix: `[1:a][bgmduck]amix=inputs=2:weights=1.0 0.5:duration=first,alimiter=limit=0.95[aout]`; SFX layer delayed via `adelay=<ms>` at scene cut points from cut-points.py
  4. Mux: `-map 0:v -map [aout] -c:v copy -c:a aac -b:a 160k -shortest`

  Validated one-shot graph (Episode3, 2026-09-02 — pad + duck + mix + limit in one pass, video stream-copied):
  ```bash
  ffmpeg -y -i run/final.mp4 -i narration.mp3 -stream_loop -1 -i bgm.mp3 \
    -filter_complex "aevalsrc=0:d=0.4[sil];[sil][1:a]concat=n=2:v=0:a=1[voice];\
  [voice]asplit=2[vmix][vsc];[2:a]atrim=0:96,volume=0.25,afade=t=out:st=90:d=4[bg];\
  [bg][vsc]sidechaincompress=threshold=0.02:ratio=8:attack=120:release=500[bgd];\
  [vmix][bgd]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.891,aresample=48000[out]" \
    -map 0:v -map "[out]" -c:v copy -c:a aac -b:a 192k -ac 2 -movflags +faststart final-with-voice.mp4
  ```
  Traps learned here: `asplit` takes exactly ONE input — `[bg][voice]asplit=2[..][..]` fails with "More input link labels than inputs (2 > 1)"; split the voice itself (`[voice]asplit=2[vmix][vsc]`) so one copy feeds amix and the other drives the sidechain. `amix` needs `normalize=0` or it renormalizes both stems down (~-3dB each). Head pad is built INSIDE the graph via `aevalsrc=0:d=0.4` + concat (no separate pad step), and `-movflags +faststart` for platform upload preview.

## Design contract mechanics (from hyperframes-design/design-spec.md)

- Spec precedence: `frame.md` -> `design.md` -> `DESIGN.md` (always adopt lowercase frame.md; presets ship uppercase FRAME.md templates).
- Frontmatter (colors/typography/spacing/components) is normative brand truth; prose is context.
- blue-professional CJK pairing (official): Noto Sans SC 700 display / Noto Serif SC 400 body; eyebrow uppercase-tracking signal weakens in CJK -> compensate with a 4px primary accent-line; numerals stay Latin Arabic.
- caption-skin.html: karaoke caption contract — `.caption-group`/`.caption-word` with `.is-active`/`.is-spoken` states driven by word timestamps; states set via `gsap.set` on seek (never `tl.call` callbacks — they don't fire on render seek). Token contract: `--cap-ink --cap-canvas --cap-accent --font-display --cap-band-top --cap-band-height`.
- Each FRAME.md documents Aspect-Ratio Behavior for 16:9 / 9:16 / 1:1 (e.g. diagonal panel becomes top/bottom band on 9:16) — cite the right column in the overlay.

## Sourcing BGM/SFX

Executor status 2026-09-02 (Episode3): the executor ran end-to-end unattended after this session's hotfixes — xargs -P3, directory-filtered scene glob, preset-aware color gates, gen-overlay map extension, 转场呼吸 gate item. Remaining manual/TODO: 503 auto-backoff relaunch, resident-browser gate reuse, shared-deps wiring into run-scenes-v3.sh (setup-shared-deps.py is still invoked by hand).

- Openverse API works headlessly: `https://api.openverse.org/v1/audio/?q=<kw>&license=cc0,by` (audio endpoints; ~30s timeouts observed — retry). Pixabay pages are Cloudflare-gated for curl; Jamendo API requires a client_id (demo id rejected).
- Reusable CC-licensed tracks + QC'd SFX from a previous episode: a local `music/{router-v2,sfx-router-v2}/` asset dir from a previous episode.

## Episode 4 additions (2026-09-03, Skills Hub 种草)

- **Runner path resolution**: the executor resolves its own dir via `BASH_SOURCE` and the interpreter as `$PY` = `PIPELINE_PY` ?? `$PIPELINE_DIR/.venv/bin/python`, so it works from any cwd. Historical trap: an older version resolved `.venv/bin/python` relative to cwd and, from a wrong cwd, printed "[episode] Phase 2 完成" while voice never ran. Regardless of the fix, **verify the phase artifact (`assets/narration.mp3` etc.) exists before trusting a completion line**.
- **GitHub file verification route**: raw.githubusercontent.com curl timed out (180s); `https://cdn.jsdelivr.net/gh/<org>/<repo>@main/<path>` returned in seconds. Use jsdelivr first for README/source verification.
- **Local BGM inventory (license-verified — audit BEFORE hitting the network)**:
  - `~/auto-motion-episode2/assets/bgm/candidate-{a,b,c}.mp3` (also in ep3 assets/bgm/) — Pixabay: a=《Technology》Verclub_Music, b=《Technology Future Innovation Pulse》alex-morgan, c=《Investigate》; titles/sources in ep2 audio-assets.json.
  - a local `music/candidates/{close-up,cyberpunk-city,sci-fi-score}.mp3` set from a previous episode — Mixkit, records in that dir's MUSIC-AUDITION-REPORT.md.
  - Episode4 pick: D = close-up.mp3 (Michael Ramir C., Mixkit), sha256 a7f05a29d07a84d38072ccd2b35204bca812db86e75b2a837e71cc144d3e739b, copied to `<epDir>/assets/bgm/close-up.mp3`.
- **Batch audition recipe** (one loop: narration first 30s × each track's 30s excerpt from 20s offset, identical mix settings):
  ```bash
  ffmpeg -y -v error -i narration.mp3 -i <track>.mp3 -filter_complex \
    "[0:a]atrim=0:30,asetpts=N/SR/TB[nar];[1:a]atrim=20:50,asetpts=N/SR/TB,volume=0.25,afade=t=in:d=1.5,afade=t=out:st=28:d=2[bg];\
  [bg][nar]sidechaincompress=threshold=0.06:ratio=6:attack=120:release=500[duck];\
  [nar][duck]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.891[aout]" \
    -map "[aout]" -b:a 160k auditions/audition-<id>.mp3
  ```
- **prompt-overlay.md mechanism**: per-episode constraint file (real instance numbers read from the user's own screenshots, naming rules, no-EP rule); executor appends it to the Codex PROMPT and copies `assets/screenshots/*.png` into `run/screenshots/` with a window-card usage section. Episode4 overlay locks 93/47/11/87/失败0/3s + "截图内容不得改动，高亮圈注可以".
- **Hybrid visual mode**: feature scenes embed the user's real UI screenshots as window-cards (border+shadow+entrance move+highlight zoom); non-feature scenes stay pure animation; screenshot content must never be altered or stretched.

## Episode 1 (v1->v2) evidence

- v1 (3:4, dark, sentence timing): `~/auto-motion-episode1/final-with-voice.mp4`
- v2 (16:9, blue-professional, word timing, BGM): `~/auto-motion-episode1-v2/final-with-voice.mp4` — 8 scenes, all 1920×1080, durations within 0.03s of expected, total 82.0s vs 81.888s SRT (frame rounding).
- The 464-word timing sample: first sentence words at 0.365/0.455/0.575...s — caption chips can hit word boundaries.
- Runtime: P2 ~4min (13 segments), P4-6 ~40min for 8 scenes at concurrency 3 (Codex fill ~35min + parallel render ~22min), P7 <1min.
