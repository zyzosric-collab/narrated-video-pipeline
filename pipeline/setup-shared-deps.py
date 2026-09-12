#!/usr/bin/env python3
"""Episode-level dependency install + per-scene node_modules symlink (approved 2026-09-01).

Usage: python3 setup-shared-deps.py <epDir>
- Installs deps once in <epDir>/run/shared-deps (one hyperframes project scaffold).
- For each scene project dir (hf-proj | hf-project | hf | scene root with package.json),
  replaces any existing node_modules with a symlink to the shared one.
- Idempotent: safe to re-run before relaunching scenes.
"""
from __future__ import annotations
import json
import shutil
import subprocess
import sys
from pathlib import Path

RUN = Path(sys.argv[1]).expanduser().resolve() / "run"
SHARED = RUN / "shared-deps"
VARIANTS = ("hf-proj", "hf-project", "hf")

if not SHARED.exists():
    SHARED.mkdir(parents=True)
    subprocess.run(
        ["npx", "--yes", "hyperframes@latest", "init", "shared-deps", "--non-interactive", "--example", "blank"],
        cwd=RUN, check=False, capture_output=True,
    )
    # init may create RUN/shared-deps/shared-deps depending on CLI version; normalize
    nested = SHARED / "shared-deps"
    if nested.exists():
        for child in nested.iterdir():
            shutil.move(str(child), str(SHARED / child.name))
        nested.rmdir()
if not (SHARED / "package.json").exists():
    raise SystemExit("shared-deps scaffold failed; no package.json")

print("installing shared deps once ...")
subprocess.run(["npm", "install", "--no-audit", "--no-fund", "--silent"], cwd=SHARED, check=False)

linked = 0
scenes = sorted(p for p in (RUN / "scenes").glob("scene-*") if p.is_dir()) if (RUN / "scenes").exists() else []
for scene in scenes:
    targets = [scene / v for v in VARIANTS if (scene / v / "package.json").exists()]
    if (scene / "package.json").exists():
        targets.append(scene)  # loose project at scene root
    for proj in targets:
        nm = proj / "node_modules"
        if nm.is_symlink() and nm.resolve() == SHARED.resolve():
            linked += 1
            continue
        if nm.exists() and not nm.is_symlink():
            shutil.rmtree(nm)
        nm.symlink_to(SHARED / "node_modules")
        linked += 1
        print(f"linked {proj.relative_to(RUN)}/node_modules -> shared")
print(f"done: {linked} project(s) sharing one node_modules")
