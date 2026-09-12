#!/usr/bin/env python3
"""Phase 2 (v2): 豆包TTS逐段配音 + 词级时间戳。

输入: <epDir>/script-segments.json  [{"style": ..., "text": ...}, ...]
      <epDir>/episode.yaml
输出: <epDir>/narration.mp3
      <epDir>/transcription.srt     (句级，供 auto-motion 拆镜)
      <epDir>/voice-timing.json     (句级+词级，供卡拉OK字幕/镜头对时)
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

PIPELINE = Path(__file__).resolve().parent  # pipeline root = this script's dir
def _default_tts_cli() -> str:
    """TTS CLI 解析顺序：$TTS_CLI > 仓库内 tools/volcengine-doubao-tts/tts.py > 本机旧路径。"""
    vendored = PIPELINE.parent / "tools" / "volcengine-doubao-tts" / "tts.py"
    if vendored.exists():
        return str(vendored)
    return str(Path.home() / "Documents/Codex/shared/volcengine-doubao-tts/tts.py")


TTS_CLI = Path(os.environ.get("TTS_CLI") or _default_tts_cli())

REPLACEMENTS = [("AI", "A I"), ("HTML", "H T M L")]

PRONUNCIATION_INSTRUCTION = (
    "开头第一个词咬字清晰、饱满有力，不要抢拍、不要吞字；句首适当留出呼吸感再开口。"
    "英文模型名和专业词使用清晰、标准的英文发音；单独写开的英文字母逐个读；"
    "中英文切换自然，不要把英文强行中文音译；小数按中文数字准确读出；"
    "保持知识型科技解说的自然连贯感，不要吞字、漏字或擅自改写。"
)


def tts_text(display: str) -> str:
    r = display
    for s, t in REPLACEMENTS:
        r = r.replace(s, t)
    return r


def duration(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(path)],
        check=True, capture_output=True, text=True).stdout.strip()
    return float(out)


def srt_time(seconds: float) -> str:
    ms = round(seconds * 1000)
    h, ms = divmod(ms, 3_600_000)
    m, ms = divmod(ms, 60_000)
    s, ms = divmod(ms, 1_000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def main() -> None:
    ep = Path(sys.argv[1])
    cfg = ep / "episode.yaml"
    import yaml
    conf = yaml.safe_load(open(cfg))

    segs = json.load(open(ep / "script-segments.json"))
    audio_dir = ep / "audio"
    audio_dir.mkdir(exist_ok=True)

    import yaml as _yaml  # noqa: F401  (配置读取已在上方)

    records = []
    for i, seg in enumerate(segs, start=1):
        mp3 = audio_dir / f"segment-{i:03d}.mp3"
        wordjson = audio_dir / f"segment-{i:03d}.words.json"
        spoken = tts_text(seg["text"])
        if not mp3.exists() or mp3.stat().st_size < 1000:
            print(f"[{i:02d}/{len(segs)}] synthesizing", flush=True)
            cmd = ["python3", str(TTS_CLI), "--text", spoken,
                   "--speaker", conf["speaker"], "--speech-rate", str(conf["speech_rate"]),
                   "--style", seg.get("style", "tech_explainer"),
                   "--instruction", PRONUNCIATION_INSTRUCTION,
                   "--output", str(mp3),
                   "--subtitle-json", str(wordjson)]
            subprocess.run(cmd, check=True)
        else:
            print(f"[{i:02d}/{len(segs)}] reusing", flush=True)

        words = []
        if wordjson.exists():
            wdata = json.loads(wordjson.read_text())
            # 火山 sentence.words: [{word, start, end, ...}] 相对段内
            for sent in wdata.get("sentences", []):
                words.extend(sent.get("words", []))
        records.append({
            "index": i, "style": seg.get("style", ""),
            "display": seg["text"], "tts": spoken,
            "audio": str(mp3), "duration": duration(mp3),
            "words": words,
        })

    # concat → narration.mp3
    concat = audio_dir / "concat.txt"
    concat.write_text("".join(f"file '{r['audio']}'\n" for r in records))
    narration = ep / "narration.mp3"
    subprocess.run(["ffmpeg", "-y", "-v", "error", "-f", "concat", "-safe", "0",
                    "-i", str(concat), "-c:a", "libmp3lame", "-b:a", "160k",
                    "-ar", "24000", str(narration)], check=True)

    # 句级时间轴（ffprobe 实测累计）+ 词级全局时间
    cursor, srt_blocks, timing = 0.0, [], []
    for r in records:
        start = cursor
        cursor += r["duration"]
        r["start"], r["end"] = start, cursor
        srt_blocks.append(f"{r['index']}\n{srt_time(start)} --> {srt_time(cursor)}\n{r['display']}\n")
        for w in r["words"]:
            w_start = float(w.get("startTime", w.get("start", 0)))
            w_end = float(w.get("endTime", w.get("end", 0)))
            timing.append({
                "sentence": r["index"],
                "word": w.get("word", ""),
                "start": round(start + w_start, 3),
                "end": round(start + w_end, 3),
            })

    final_dur = duration(narration)
    drift = final_dur - cursor
    if abs(drift) > 0.5:
        raise RuntimeError(f"时长漂移过大: segments={cursor:.3f} final={final_dur:.3f}")

    (ep / "transcription.srt").write_text("\n".join(srt_blocks), encoding="utf-8")
    (ep / "voice-timing.json").write_text(json.dumps({
        "total": final_dur, "drift": round(drift, 3),
        "word_count": len(timing),
        "sentences": [{k: r[k] for k in ("index", "style", "display", "start", "end", "duration")} for r in records],
        "words": timing,
    }, ensure_ascii=False, indent=1), encoding="utf-8")
    print(json.dumps({"status": "success", "segments": len(records),
                      "duration": final_dur, "drift": round(drift, 3),
                      "words": len(timing)}, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
