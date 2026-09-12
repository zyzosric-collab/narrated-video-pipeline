#!/usr/bin/env python3
"""Emit shell eval lines from episode.yaml (robust: no heredoc, no unicode-in-varname issues)."""
import sys

import yaml

ep = sys.argv[1]
c = yaml.safe_load(open(f"{ep}/episode.yaml"))
for key in ("width", "height", "fps", "preset", "aspect", "bgm_volume"):
    print(f'{key.upper()}={c[key]}')
