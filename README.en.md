# narrated-video-pipeline — Chinese voice-over video pipeline

> Give it a topic; get a narrated, fully-composed short video you can publish.

Topic → research/script → Doubao TTS (word-level timestamps) → per-shot visuals → QC + concat → BGM ducking mix → publish kit.

The repo has two parts:

- **Skill package** — `SKILL.md` + `references/`: loaded by an agent (Hermes Agent / Claude Code / Codex) and defines the phases, hard rules and acceptance gates.
- **Executor** — `pipeline/`: bash/python scripts that run standalone (shot planning, TTS, render scheduling, QC, audio mix, live status dashboard).

## Pipeline at a glance

| Phase | Step | Artefact | Run by |
|---|---|---|---|
| P0 | init | `episode.yaml` (aspect / fps / preset / BGM level) | `episode.sh init` |
| P1 | Script | `script/*.md` (human-approved **before** TTS) | human + writing skills |
| P2 | Narration | `narration.mp3`, word-level JSON, `transcription.srt` | `build_narration_v2.py` → Doubao TTS (bundled) |
| P3 | Design contract | `frame.md` injected into the shot workspace | `inject-design.sh` |
| P4 | Shot planning | one `run-claude-ai.sh` + `PROMPT.md` per shot | Codex (**planning only, no rendering**) |
| P5 | Per-shot render | `scenes/scene-XXX/scene-XXX.mp4` | Claude Code + HyperFrames (concurrency 3) |
| P6 | QC + concat | `run/final.mp4` (`npm run check` + PSNR motion scan) | `run-scenes-v3.sh` |
| P7 | Audio layer | final cut with BGM ducking + cut-point SFX | `build-audio.sh` |
| P8 | Publish kit (optional) | `publish-kit.md` (per-platform titles/copy) | agent, after checking platform rules |

Division of labour: **Codex plans, Claude Code implements one shot at a time, the orchestrating agent owns QC and sign-off.**

## Quick start

```bash
# 1) clone + venv (PyYAML only)
git clone https://github.com/zyzosric-collab/narrated-video-pipeline ~/nvp
cd ~/nvp/pipeline && python3 -m venv .venv && .venv/bin/pip install pyyaml

# 2) point the bundled Doubao TTS at your own API key
cd ~/nvp/tools/volcengine-doubao-tts
cp .env.example .env.local && chmod 600 .env.local && $EDITOR .env.local  # VOLCENGINE_TTS_API_KEY
python3 tts.py --text 'config check.' --dry-run                          # no metered call

# 3) preflight everything at once
bash ~/nvp/pipeline/episode.sh doctor

# 4) create an episode (Phase 0)
bash ~/nvp/pipeline/episode.sh init ~/episodes/ep01 16:9 blue-professional
bash ~/nvp/pipeline/episode.sh status ~/episodes/ep01

# 5) script → human approval → narration (Phase 1-2)
bash ~/nvp/pipeline/episode.sh voice ~/episodes/ep01

# 6) design contract → shot plan → one-shot pilot → full batch (Phase 3-6)
bash ~/nvp/pipeline/episode.sh design ~/episodes/ep01
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 plan     # shot planning only
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 pilot    # render scene-001 only
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 rest     # rest + QC + concat
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 all      # full (finished shots skipped)

# 7) audio layer (Phase 7)
bash ~/nvp/pipeline/episode.sh audio ~/episodes/ep01 /path/to/bgm.mp3
```

The executor resolves its own location via `BASH_SOURCE`, so it can be invoked from any working directory; `doctor` reports every missing dependency together with the fix.

## Requirements

`ffmpeg`/`ffprobe`, `jq`, Node.js + `npx hyperframes`, Python 3.11+ with PyYAML, Codex CLI (planning, your own account/quota), Claude Code CLI (rendering, your own account/quota), the `auto-motion` render workspace (`github.com/zyzosric-collab/auto-motion`, cloned to `~/auto-motion`) — and **Doubao TTS, bundled here** at `tools/volcengine-doubao-tts/`, which needs nothing but your own `VOLCENGINE_TTS_API_KEY`.

Resolution order is `$TTS_CLI` → bundled `tools/volcengine-doubao-tts/tts.py` → legacy local path, so a fresh clone works with zero TTS configuration. Any implementation matching this contract can replace it:

```bash
python3 "$TTS_CLI" --text <text> --speaker <voice> --speech-rate <int> \
  --style <style> --instruction <hint> --output <mp3> --subtitle-json <word-json>
```

## Hard rules

1. No burned-in subtitles (no caption bars, no karaoke highlight, no on-screen script text) — ship an external `.srt` instead.
2. The script must be human-approved before TTS runs; never bundle a new script and its generated voice-over into one review.
3. Aspect ratio and visual preset are asked per episode; default 16:9 @ 1920×1080 / 30fps.
4. BGM is chosen from an **audio-only** preview before any video is rendered.
5. Shot rendering concurrency is fixed at 3; always run a one-shot pilot before the full batch.
6. Shot QC = read the **full** `npm run check` output + run a **PSNR motion scan** (catches “animation never moves”). Tailing the log is not a pass.
7. Legibility floor: eyebrow/label type ≥ 1.1cqw; connector lines stop ≥ 8px outside card edges.
8. Do not modify the global config of external CLIs or force a model on the command line.

## Verification status

- 5 episodes produced with this pipeline (7–9 shots each, 30–115 s).
- Latest episode: expected 111.5 s vs actual 111.6 s (A/V equal length), QC gate and frame spot-checks passed.
- Aspect ratios 16:9 / 9:16 / 3:4; 13 visual presets via `auto-motion`'s `hyperframes-design/frame-presets/`.
- Verified on macOS (Apple Silicon). Bash + POSIX tools, so Linux should work, but it is untested there.

## Docs

[`docs/install.md`](docs/install.md) · [`docs/architecture.md`](docs/architecture.md) · [`docs/usage.md`](docs/usage.md) · [`docs/troubleshooting.md`](docs/troubleshooting.md)

## Credits & third-party components

Nothing third-party is **bundled here**. Every external component is used via runtime `npx`, a separate clone, or an official API contract — no upstream source is copied into this repo.

| Component | Role | Source | License | How it is used |
|---|---|---|---|---|
| **HyperFrames** | P5 render engine (HTML → MP4) | [heygen-com/hyperframes](https://github.com/heygen-com/hyperframes) (npm `hyperframes`) | Apache-2.0 | invoked as `npx hyperframes`; no code copied |
| **Auto-Motion** | Render-workspace template + bundled HyperFrames skill pack (where the 13 visual presets live) | [vibe-motion/auto-motion](https://github.com/vibe-motion/auto-motion); the clone URL in the docs points at its fork [zyzosric-collab/auto-motion](https://github.com/zyzosric-collab/auto-motion) | **upstream declares no license** (no LICENSE file) | cloned separately to `~/auto-motion`; no files from it live here |
| **FFmpeg / ffprobe** | mixing, frame extraction, duration & loudness checks | [ffmpeg.org](https://ffmpeg.org) | LGPL-2.1+ / GPL (Homebrew build is `--enable-gpl`, x264/x265) | separate processes, not linked or redistributed |
| **jq** | JSON processing | [jqlang.github.io/jq](https://jqlang.github.io/jq) | MIT | installed by the user |
| **Node.js / npm** | running HyperFrames and `npm run check` | [nodejs.org](https://nodejs.org) | MIT | installed by the user |
| **Python + PyYAML** | executor scripts | [python.org](https://python.org) / [pyyaml.org](https://pyyaml.org) | PSF-2.0 / MIT | installed by the user (`pipeline/.venv`) |
| **Codex CLI** | P4 shot planning | [openai/codex](https://github.com/openai/codex) | Apache-2.0 | user-supplied CLI |
| **Claude Code** | P5 per-shot implementation | Anthropic | proprietary (Anthropic terms) | user-supplied CLI |
| **Doubao speech synthesis 2.0 (`seed-tts-2.0`)** | P2 narration + word timestamps | Volcengine | commercial service terms | HTTP API only; the client in `tools/volcengine-doubao-tts/` is original code (stdlib only, no SDK) |
| **Google Fonts** (Noto Sans SC / Space Grotesk, etc.) | on-screen type | [fonts.google.com](https://fonts.google.com) | SIL OFL 1.1 | loaded at render time; no font binaries in the repo |

This repo's own code and docs (`SKILL.md`, `references/`, `pipeline/`) are original and MIT-licensed; the components above are governed solely by their own terms. If you redistribute **videos produced by** this pipeline, apply the table above — note in particular that **upstream Auto-Motion declares no license**, so its redistributable scope depends on the upstream repo and your local law; ask upstream before commercial use.

No API credentials, model weights or third-party assets are bundled — the Doubao TTS client under `tools/` is stdlib-only source, the speech service is Volcengine's, and Codex / Claude Code are external dependencies under their own terms. Keep `.env.local` on your machine (it is gitignored). MIT licensed.
