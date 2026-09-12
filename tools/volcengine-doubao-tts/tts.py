#!/usr/bin/env python3
"""Volcengine Doubao Seed-TTS 2.0 client for video narration.

Uses the official V3 HTTP SSE endpoint and X-Api-Key authentication.
Secrets are loaded from the process environment or .env.local only.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request
import uuid
from pathlib import Path
from typing import Any, Optional


ROOT = Path(__file__).resolve().parent
CONFIG_PATH = ROOT / "config.json"
STYLES_PATH = ROOT / "styles.json"
PRONUNCIATIONS_PATH = ROOT / "pronunciations.json"
ENV_PATH = ROOT / ".env.local"


def load_json(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def load_local_env(path: Path = ENV_PATH) -> None:
    if not path.exists():
        return
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip().strip("\"'"))


def prepare_pronunciation(text: str, mapping: dict[str, str]) -> str:
    """Expand ASCII abbreviations without touching longer ASCII words."""
    for source in sorted(mapping, key=len, reverse=True):
        replacement = mapping[source]
        pattern = rf"(?<![A-Za-z]){re.escape(source)}(?![A-Za-z])"
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)
    return text


def build_request(
    text: str,
    config: dict[str, Any],
    context_texts: list[str],
    enable_subtitle: bool = False,
) -> tuple[dict[str, str], dict[str, Any]]:
    api_key = os.getenv("VOLCENGINE_TTS_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError(
            "缺少 VOLCENGINE_TTS_API_KEY；请在 .env.local 中配置，勿写入源码。"
        )

    additions = {
        "post_process": {"pitch": config["pitch"]},
        "disable_markdown_filter": not bool(config.get("filter_markdown", True)),
        "enable_latex_tn": False,
    }
    headers = {
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
        "X-Api-Key": api_key,
        "X-Api-Resource-Id": config["resource_id"],
        "X-Api-Request-Id": str(uuid.uuid4()),
        "X-Control-Require-Usage-Tokens-Return": "*",
    }
    audio_params = {
        "format": config["format"],
        "bit_rate": config["bit_rate"],
        "speech_rate": config["speech_rate"],
        "loudness_rate": config["loudness_rate"],
    }
    if enable_subtitle:
        audio_params["enable_subtitle"] = True
    body = {
        "user": {"uid": "lingjing_video_tts"},
        "req_params": {
            "text": text,
            "speaker": config["speaker"],
            "sample_rate": config["sample_rate"],
            "audio_params": audio_params,
            "context_texts": context_texts,
            "additions": json.dumps(additions, ensure_ascii=False),
        },
    }
    return headers, body


def synthesize(
    endpoint: str,
    headers: dict[str, str],
    body: dict[str, Any],
    output_path: Path,
    timeout: float,
    subtitle_path: Optional[Path] = None,
) -> dict[str, Any]:
    request = urllib.request.Request(
        endpoint,
        data=json.dumps(body, ensure_ascii=False).encode("utf-8"),
        headers=headers,
        method="POST",
    )
    audio_chunks: list[bytes] = []
    subtitle_sentences: list[dict[str, Any]] = []
    usage: dict[str, Any] = {}
    request_id = headers["X-Api-Request-Id"]

    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            for raw_line in response:
                line = raw_line.decode("utf-8", errors="replace").strip()
                if not line.startswith("data:"):
                    continue
                payload_text = line[5:].strip()
                if not payload_text or payload_text == "[DONE]":
                    continue
                payload = json.loads(payload_text)
                code = payload.get("code", 0)
                if code not in (0, 20000000):
                    raise RuntimeError(
                        f"火山引擎业务错误 code={code}: {payload.get('message', '')}"
                    )
                audio_data = payload.get("data")
                if isinstance(audio_data, str) and audio_data:
                    audio_chunks.append(base64.b64decode(audio_data))
                sentence = payload.get("sentence")
                if (
                    isinstance(sentence, dict)
                    and isinstance(sentence.get("words"), list)
                    and sentence["words"]
                ):
                    subtitle_sentences.append(sentence)
                if isinstance(payload.get("usage"), dict):
                    usage.update(payload["usage"])
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:1000]
        raise RuntimeError(f"HTTP {exc.code}: {detail}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"网络请求失败: {exc.reason}") from exc

    if not audio_chunks:
        raise RuntimeError("接口未返回音频数据。")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_bytes(b"".join(audio_chunks))
    if subtitle_path is not None:
        if not subtitle_sentences:
            raise RuntimeError("已请求字幕时间戳，但接口未返回 sentence.words。")
        subtitle_path.parent.mkdir(parents=True, exist_ok=True)
        subtitle_path.write_text(
            json.dumps(
                {
                    "schema_version": "1.0.0",
                    "request_id": request_id,
                    "sentences": subtitle_sentences,
                },
                ensure_ascii=False,
                indent=2,
            )
            + "\n",
            encoding="utf-8",
        )
    return {
        "status": "success",
        "output": str(output_path.resolve()),
        "bytes": output_path.stat().st_size,
        "request_id": request_id,
        "usage": usage,
        "subtitle": str(subtitle_path.resolve()) if subtitle_path else None,
        "subtitle_sentences": len(subtitle_sentences),
        "subtitle_words": sum(len(item["words"]) for item in subtitle_sentences),
    }


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="火山引擎豆包语音合成 2.0")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--text", help="要合成的文本")
    source.add_argument("--file", type=Path, help="UTF-8 文本文件")
    parser.add_argument("--output", "-o", type=Path, help="输出音频路径")
    parser.add_argument("--speaker", help="覆盖 speaker ID")
    parser.add_argument("--speech-rate", type=int, help="[-50,100]；20 约为 1.2 倍")
    parser.add_argument("--pitch", type=int, help="[-12,12]")
    parser.add_argument("--style", help="styles.json 中的语气预设")
    parser.add_argument("--instruction", action="append", default=[], help="追加自然语言语气指令")
    parser.add_argument(
        "--subtitle-json",
        type=Path,
        help="请求火山引擎原生字词时间戳，并把 sentence.words 保存为 JSON",
    )
    parser.add_argument("--no-pronunciation-fix", action="store_true", help="关闭英文缩写发音预处理")
    parser.add_argument("--dry-run", action="store_true", help="只校验配置，不调用接口")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    load_local_env()
    config = load_json(CONFIG_PATH)
    styles = load_json(STYLES_PATH)

    if args.speaker:
        config["speaker"] = args.speaker
    if args.speech_rate is not None:
        config["speech_rate"] = args.speech_rate
    if args.pitch is not None:
        config["pitch"] = args.pitch
    style_name = args.style or config["style_preset"]
    if style_name not in styles:
        raise RuntimeError(f"未知语气预设: {style_name}")
    if not -50 <= int(config["speech_rate"]) <= 100:
        raise RuntimeError("speech_rate 必须在 [-50,100] 内")
    if not -12 <= int(config["pitch"]) <= 12:
        raise RuntimeError("pitch 必须在 [-12,12] 内")

    text = args.text if args.text is not None else args.file.read_text(encoding="utf-8")
    text = text.strip()
    if not text:
        raise RuntimeError("输入文本为空")
    if not args.no_pronunciation_fix:
        text = prepare_pronunciation(text, load_json(PRONUNCIATIONS_PATH))

    context_texts = [*styles[style_name], *args.instruction]
    headers, body = build_request(
        text,
        config,
        context_texts,
        enable_subtitle=args.subtitle_json is not None,
    )
    output = args.output or (ROOT / "outputs" / f"tts.{config['format']}")

    if args.dry_run:
        safe_headers = {**headers, "X-Api-Key": "***REDACTED***"}
        print(json.dumps({
            "status": "dry-run",
            "endpoint": config["endpoint"],
            "headers": safe_headers,
            "request": body,
            "output": str(output.resolve()),
        }, ensure_ascii=False, indent=2))
        return 0

    result = synthesize(
        config["endpoint"],
        headers,
        body,
        output,
        float(config["timeout_seconds"]),
        subtitle_path=args.subtitle_json,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(json.dumps({"status": "error", "error": str(exc)}, ensure_ascii=False), file=sys.stderr)
        raise SystemExit(1)
