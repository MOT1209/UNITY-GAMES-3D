#!/usr/bin/env python3
"""Stores the output of tools/export_kit_repairs in the pack files (same JSON formatting as the generators)."""
import glob
import json
import sys

kits = json.load(open(sys.argv[1], encoding="utf-8"))["kits"]
changed = 0
for pattern in ("data/packs/real_2025/clubs/*.json", "data/packs/real_2025/fictional/clubs/*.json"):
    for fn in glob.glob(pattern):
        d = json.load(open(fn, encoding="utf-8"))
        tid = d["team"]["id"]
        if tid in kits and d["team"].get("kits") != kits[tid]:
            d["team"]["kits"] = kits[tid]
            open(fn, "w", encoding="utf-8").write(json.dumps(d, indent=1, sort_keys=True, ensure_ascii=False))
            changed += 1
print("clubs updated", changed)
