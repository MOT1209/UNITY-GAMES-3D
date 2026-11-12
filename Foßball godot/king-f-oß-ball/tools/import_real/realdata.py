"""Shared helpers for the KING FOOTBALL real-data importer (stdlib only).

Sources (see SOURCES.md written next to the pack):
  * openfootball (CC0 1.0, public domain) - which clubs play in which division.
  * transfermarkt-datasets (snapshot up to 2026-07-06) - real first-tier squads.
"""
import csv
import gzip
import re
import unicodedata

LINE = re.compile(r"^\s+(?:\d{1,2}[:.]\d\d\s+)?(?P<a>[^\s(].*?)\s{2,}(?:v|\d+-\d+(?:\s*\(\d+-\d+\))?(?:\s*(?:a\.e\.t\.|pen\.).*?)?)\s{2,}(?P<b>[^(].*?)\s*$")
LINE_V = re.compile(r"^\s+(?:\d{1,2}[:.]\d\d\s+)?(?P<a>[A-Za-z\u00C0-\u024F].*?)\s+v\s+(?P<b>[A-Za-z\u00C0-\u024F].*?)(?:\s{2,}.*)?\s*$")
STOP = {"fc", "afc", "cf", "sd", "cd", "ud", "rcd", "rc", "ca", "sad", "club", "de", "the", "balompie", "sc"}


def season_teams(path):
    """Club names appearing as home/away in an openfootball season .txt file."""
    teams = set()
    with open(path, encoding="utf8") as fh:
        for line in fh:
            if line.lstrip().startswith(("(", "#", "=", "▪")):
                continue
            m = LINE_V.match(line) or LINE.match(line)
            if m:
                teams.add(m.group("a").strip())
                teams.add(m.group("b").strip())
    return sorted(teams)


def strip_accents(s):
    return "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))


def norm(name):
    s = strip_accents(name).lower().replace("&", " and ")
    s = re.sub(r"[^a-z0-9 ]+", " ", s)
    return " ".join(w for w in s.split() if w not in STOP)


def slug(name):
    return re.sub(r"[^a-z0-9]+", "_", strip_accents(name).lower()).strip("_")


def read_gz_csv(path):
    with gzip.open(path, "rt", encoding="utf8") as fh:
        return list(csv.DictReader(fh))


def match_clubs(of_names, tm_clubs, aliases):
    """Maps every openfootball name to a transfermarkt club row. Returns (mapping, unmatched)."""
    by_norm = {norm(c["name"]): c for c in tm_clubs}
    mapping, unmatched = {}, []
    for name in of_names:
        target = aliases.get(name)
        if target:
            hit = next((c for c in tm_clubs if c["name"] == target), None)
        else:
            n = norm(name)
            hit = by_norm.get(n)
            if hit is None:
                cands = [c for k, c in by_norm.items() if n and (n in k or k in n)]
                hit = cands[0] if len(cands) == 1 else None
        if hit is None:
            unmatched.append(name)
        else:
            mapping[name] = hit
    return mapping, unmatched
