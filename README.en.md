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
| P2 | Narration | `narration.mp3`, word-level JSON, `subtitles.srt` | `build_narration_v2.py` → external TTS CLI |
| P3 | Design contract | `frame.md` injected into the shot workspace | `inject-design.sh` |
| P4 | Shot planning | one `run-claude-ai.sh` + `PROMPT.md` per shot | Codex (**planning only, no rendering**) |
| P5 | Per-shot render | `scenes/scene-XXX/scene-XXX.mp4` | Claude Code + HyperFrames (concurrency 3) |
| P6 | QC + concat | `run/final.mp4` (`npm run check` + PSNR motion scan) | `run-scenes-v3.sh` |
| P7 | Audio layer | final cut with BGM ducking + cut-point SFX | `build-audio.sh` |
| P8 | Publish kit (optional) | `publish-kit.md` (per-platform titles/copy) | agent, after checking platform rules |

Division of labour: **Codex plans, Claude Code implements one shot at a time, the orchestrating agent owns QC and sign-off.**

## Quick start

```bash
git clone <this-repo> ~/nvp
cd ~/nvp/pipeline && python3 -m venv .venv && .venv/bin/pip install pyyaml

bash ~/nvp/pipeline/episode.sh init ~/episodes/ep01 16:9 blue-professional
bash ~/nvp/pipeline/episode.sh voice ~/episodes/ep01     # after the script is approved
bash ~/nvp/pipeline/episode.sh design ~/episodes/ep01
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 plan    # plan shots only
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 pilot   # render scene-001 only
bash ~/nvp/pipeline/episode.sh scenes ~/episodes/ep01 rest    # rest + QC + concat
bash ~/nvp/pipeline/episode.sh audio ~/episodes/ep01 /path/to/bgm.mp3
```

The executor resolves its own location via `BASH_SOURCE`, so it can be invoked from any working directory.

## Requirements

`ffmpeg`/`ffprobe`, `jq`, Node.js + `npx hyperframes`, Python 3.11+ with PyYAML, Codex CLI (planning), Claude Code CLI (rendering), and an **external TTS CLI** (not bundled) matching:

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

No third-party voice service, model weights or API credentials are bundled — TTS, Codex and Claude Code are external dependencies under their own terms. MIT licensed.
