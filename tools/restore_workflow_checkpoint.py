#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import gzip
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CHECKPOINTS = {
    "2026-10-04_v0.4_KB-01A": {
        "parts": 10,
        "prefix": "workflow_v0.4_KB-01A.json.gz.b64.part",
        "sha256": "4bc5efda58a36634f7931618e22c4ebdacba8d6510357a2d53ad689664c5f959",
        "output": "Шаблон — мультиканальный бот и служебный Telegram — версия 0.4 KB-01A.json",
    },
    "2026-10-03_v0.3": {
        "parts": 8,
        "prefix": "workflow_v0.3.json.gz.b64.part",
        "sha256": "ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7",
        "output": "Шаблон — мультиканальный бот и служебный Telegram — версия 0.3.json",
    },
}

parser = argparse.ArgumentParser(description="Restore a saved n8n workflow checkpoint")
parser.add_argument(
    "--checkpoint",
    choices=CHECKPOINTS,
    default="2026-10-04_v0.4_KB-01A",
    help="Checkpoint to restore (default: latest KB-01A)",
)
args = parser.parse_args()

cfg = CHECKPOINTS[args.checkpoint]
checkpoint = ROOT / "workflows" / "checkpoints" / args.checkpoint
parts = [checkpoint / f"{cfg['prefix']}{i:02d}" for i in range(cfg["parts"])]
missing = [str(p) for p in parts if not p.exists()]
if missing:
    raise SystemExit("Missing checkpoint parts:\n" + "\n".join(missing))

encoded = "".join(p.read_text(encoding="utf-8").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(encoded))
sha = hashlib.sha256(raw).hexdigest()
if sha != cfg["sha256"]:
    raise SystemExit(f"SHA-256 mismatch: expected {cfg['sha256']}, got {sha}")

out = ROOT / "workflows" / cfg["output"]
out.write_bytes(raw)
print(f"Restored: {out}")
print(f"SHA-256: {sha}")
