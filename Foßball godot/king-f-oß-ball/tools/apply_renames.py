#!/usr/bin/env python3
"""Applies the output of tools/dedupe_names to the pack files (same JSON formatting as the generators)."""
import glob
import json
import sys

renames = json.load(open(sys.argv[1], encoding="utf-8"))["renames"]
changed = 0
for pattern in ("data/packs/real_2025/clubs/*.json", "data/packs/real_2025/fictional/clubs/*.json"):
    for fn in glob.glob(pattern):
        d = json.load(open(fn, encoding="utf-8"))
        hit = False
        for p in d.get("players", []):
            if p["id"] in renames and p["id"].startswith("gen_"):
                p["name"] = renames[p["id"]]
                hit = True
                changed += 1
        if hit:
            open(fn, "w", encoding="utf-8").write(json.dumps(d, indent=1, sort_keys=True, ensure_ascii=False))
print("renamed", changed)
