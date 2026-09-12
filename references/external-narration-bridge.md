# External Narration Bridge (user supplies script + voiceover)

Provenance: Episode5 (2026-09-05, CLIProxyAPI 本地号池, 16:9 blue-professional). User delivered the final script (`<user-private final script>`) AND the voiceover rendered from their own 豆包语音 settings (`CPA.mp3`（用户私有交付，未随仓库提供）, 111.72s, 24kHz mono 64kbps — same spec the pipeline's Doubao TTS outputs) and ordered: use as-is. Zero TTS calls, zero script edits this episode.

## When this mode applies

- User says the equivalent of 「配音和口播稿我都已经生成了，你不用再重新去做了」. The approval gates are satisfied by authorship: user wrote the script, user voiced it — no TTS approval gate applies, and the official-TTS-channel rule is moot because NO voice is generated.
- Never edit their script text, never call tts.py, never "fix" homophones/typos in what they sent. Copy files into the episode dir verbatim (`script.md` = copy; the original stays where it lives).

## Bridge pipeline (external mp3 → pipeline artifacts)

1. `episode.sh init <epDir> <aspect> <preset>` as usual.
2. `cp <user>.mp3 <epDir>/narration.mp3`; ffprobe duration/sample-rate first.
3. Sentence-split the user script into `<epDir>/script-segments.json` — one segment per sentence (19 in ep5); `style` labels are free-form here (TTS is not run, so style_map coverage does not matter in this mode).
4. Whisper word timestamps:
   ```bash
   whisper-cli -m ~/.cache/whisper-cpp/ggml-small.bin -f narration.mp3 -l zh --max-len 0 -ojf -of /tmp/<name>-whisper
   ```
   - **`-ojf` (full JSON) is required** — plain `-oj` emits only sentence-level text, no token offsets.
   - Model: `~/.cache/whisper-cpp/ggml-small.bin` (~466MB); ~10s for 112s audio on M2/Metal.
   - Filter special tokens in the JSON (text starting `[` or `_`, e.g. `[_BEG_]`).
5. Align: `python3 <epDir>/build-timing-from-whisper.py <epDir> <whisper.json> <audio_duration>` → emits `transcription.srt` + `voice-timing.json` in the standard schema (`{total, drift, word_count, sentences[{index,style,display,start,end,duration}], words[{sentence,word,start,end}]}`). That aligner was episode-local and is **not shipped here** — implement it against the output schema below (it only needs the whisper word list + the audio duration).
6. Then plan/pilot/rest/all + audio exactly as the normal pipeline (executor consumes SRT + voice-timing identically).

## Alignment algorithm requirements (why not exact matching)

Whisper homophone diffs vs a zh TTS script are NORMAL (observed in ep5: Claude Code→"Cloud,Code", 长→常, 上限→上线, 先在→现在, 留用→流用). The first exact-match implementation failed 19/19 sentences. Required design:

- Normalize both char streams: NFKC, strip punctuation/whitespace, casefold (so "CLIProxyAPI" vs "CLI Proxy API" equalize).
- **Per-sentence fuzzy anchor**: difflib ratio of sentence key vs candidate window; window length k±4 chars; search from the cursor up to +16 chars ahead; score = ratio − 0.001·(start−cursor) − 0.0005·(|wlen−k|); accept ≥0.6, else proportional fallback. Ep5: 19/19 anchored, zero fallback.
- **Opcode positional mapping** for word times: SequenceMatcher opcodes between the sentence key and the anchored whisper window map every whisper token to a fractional key position; word rows (CJK per char, latin per run) interpolate timestamps inside their covering token.
- Tile the timeline: clamp each sentence's end to the next sentence's start; last sentence ends at the audio duration; verify word-start monotonicity (ep5: 0 violations).
- SRT display text MUST come from the user script, never from whisper text — homophones would corrupt visible captions.

## Pitfalls

- **Streaming/pipe-concatenated MP3s can decode 0 samples in whisper-cli** ("Failed to find two consecutive MPEG audio frames" / empty transcription). User-downloaded Doubao files decode fine; if a streamed file comes back empty, re-wrap first (`ffmpeg -i in.mp3 -c copy out.mp3`) and retry.
- Whisper's own segment boundaries don't matter — anchoring runs over the char stream, not whisper sentences.
- `-l zh --max-len 0` both required for good token granularity.
- Drift check: voice-timing `total` must equal the ffprobe audio duration (±0.05s). Ep5: 111.72 = 111.72, drift 0.0.
