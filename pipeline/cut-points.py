#!/usr/bin/env python3
"""Emit scene cut-point timestamps (seconds, cumulative, excluding the last scene)."""
import re
import subprocess
import sys
from pathlib import Path

ep = sys.argv[1]
concat = Path(ep) / "run" / "concat.txt"
durs = []
for line in concat.read_text().splitlines():
    m = re.search(r"file '([^']+)'", line)
    if not m:
        continue
    f = m.group(1)
    d = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", f],
        capture_output=True, text=True).stdout.strip()
    durs.append(float(d))
t, cuts = 0.0, []
for d in durs[:-1]:
    t += d
    cuts.append(round(t, 3))
print(" ".join(str(c) for c in cuts))
