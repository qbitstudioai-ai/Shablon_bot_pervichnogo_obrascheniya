#!/usr/bin/env python3
from __future__ import annotations

import base64
import gzip
import hashlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKPOINT = ROOT / "workflows" / "checkpoints" / "2026-10-03_v0.3"
OUT = ROOT / "workflows" / "Шаблон — мультиканальный бот и служебный Telegram — версия 0.3.json"
EXPECTED_SHA256 = "ca563ebb985be8d3b3f08d6525634b7d623abef7840a617bfbbaf9bdb36ef2f7"

parts = [CHECKPOINT / f"workflow_v0.3.json.gz.b64.part{i:02d}" for i in range(8)]
missing = [str(p) for p in parts if not p.exists()]
if missing:
    raise SystemExit("Missing checkpoint parts:\n" + "\n".join(missing))

encoded = "".join(p.read_text(encoding="utf-8").strip() for p in parts)
raw = gzip.decompress(base64.b64decode(encoded))
sha = hashlib.sha256(raw).hexdigest()
if sha != EXPECTED_SHA256:
    raise SystemExit(f"SHA-256 mismatch: expected {EXPECTED_SHA256}, got {sha}")

OUT.write_bytes(raw)
print(f"Restored: {OUT}")
print(f"SHA-256: {sha}")
