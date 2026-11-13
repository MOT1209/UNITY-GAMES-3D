#!/usr/bin/env python3
"""Adds city and founding year to the real clubs of the pack from openfootball/clubs (CC0 / public domain).

  python3 tools/import_real/club_facts.py            # fetch (cached), match, write the pack files
  python3 tools/import_real/club_facts.py --report   # only print what would change

Only facts the source states are written: a club whose entry has no year keeps founding_year = 0, a club with no
matching entry keeps both empty. Nothing is estimated. Finances have no public-domain source and stay untouched.
Pack files keep the generator formatting (indent 1, sorted keys).
"""
import glob
import json
import os
import re
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from realdata import norm  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, "cache")
BASE = "https://raw.githubusercontent.com/openfootball/clubs/master/europe/"
FILES = {"eng": "england/eng.clubs.txt", "esp": "spain/es.clubs.txt", "ger": "germany/de.clubs.txt",
         "ita": "italy/it.clubs.txt", "fra": "france/fr.clubs.txt"}
SOURCE = "openfootball/clubs (CC0 1.0)"


def fetch(cc):
    os.makedirs(CACHE, exist_ok=True)
    dest = os.path.join(CACHE, "of_clubs_%s.txt" % cc)
    if not os.path.exists(dest):
        req = urllib.request.Request(BASE + FILES[cc], headers={"User-Agent": "king-football-importer/1.0"})
        with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as out:
            out.write(r.read())
    return dest


def parse(path):
    """-> list of {names: [...], year: int|0, city: str} (reserve teams 'ii)' are skipped)."""
    out, cur = [], None
    for raw in open(path, encoding="utf8"):
        line = raw.rstrip("\n")
        s = line.strip()
        if not s or s.startswith(("=", "#", "▪")):
            continue
        if s.startswith("|"):
            if cur is not None:
                body = s.split("##")[0].split("#")[0]
                for a in body.split("|"):
                    a = re.sub(r"\[[a-z]+\]", "", a).strip()
                    if a:
                        cur["names"].append(a)
            continue
        if re.match(r"^[ivx]+\)", s):                      # ii) Real Madrid B: a reserve team
            cur = None
            continue
        body = re.split(r"\s##|\s#", s)[0].strip()
        parts = [p.strip() for p in body.split(",")]
        name = parts[0]
        year = 0
        city = ""
        rest = parts[1:]
        if rest and re.fullmatch(r"\d{4}", rest[0]):
            year = int(rest[0])
            rest = rest[1:]
        rest = [p for p in rest if not p.startswith("@")]   # '@ Stadium' parts
        if rest:
            city = rest[-1]
        city = re.sub(r"\(.*?\)", "", city).split("›")[0].strip()
        cur = {"names": [name], "year": year, "city": city}
        out.append(cur)
    return out


def main():
    report_only = "--report" in sys.argv
    changed = matched = 0
    unmatched = []
    for cc in FILES:
        index = {}
        for rec in parse(fetch(cc)):
            for n in rec["names"]:
                index.setdefault(norm(n), []).append(rec)
        for fn in sorted(glob.glob(os.path.join(ROOT, "data/packs/real_2025/clubs/%s_*.json" % cc))):
            d = json.load(open(fn, encoding="utf-8"))
            team = d["team"]
            cands = {id(r): r for r in index.get(norm(team["name"]), [])}
            if len(cands) != 1:
                unmatched.append((team["id"], team["name"], len(cands)))
                continue
            rec = next(iter(cands.values()))
            matched += 1
            new = dict(team)
            if rec["city"]:
                new["city"] = rec["city"]
            if rec["year"]:
                new["founding_year"] = rec["year"]
            if new != team:
                changed += 1
                if not report_only:
                    d["team"] = new
                    open(fn, "w", encoding="utf-8").write(json.dumps(d, indent=1, sort_keys=True, ensure_ascii=False))
    print("matched %d, files changed %d, unmatched %d" % (matched, changed, len(unmatched)))
    for u in unmatched:
        print("  unmatched:", u)


if __name__ == "__main__":
    main()
