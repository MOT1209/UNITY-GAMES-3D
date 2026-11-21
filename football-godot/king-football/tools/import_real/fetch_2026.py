#!/usr/bin/env python3
"""Downloads the non-Wikipedia inputs of build_2026.py into tools/import_real/cache/2026/ (gitignored).

    python3 tools/import_real/fetch_2026.py
    python3 tools/import_real/build_2026.py      # fetches the Wikipedia articles itself (cached in cache/2026/wiki/)

transfermarkt-datasets stopped updating on 2026-07-06 (see its README), so its files give player facts that do not
change over a summer (date of birth, foot, height, market value) but NOT the 2026-27 squads; build_2026.py takes the
squads from Wikipedia and only matches players to these rows.
"""
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache", "2026")
OF = "https://raw.githubusercontent.com/openfootball/"
TM = "https://pub-e682421888d945d684bcae8890b0ec20.r2.dev/data/"
FILES = {
    "of_espana_2026-27_1-liga.txt": OF + "espana/master/2026-27/1-liga.txt",
    "of_england_master_2026-27_1-premierleague.txt": OF + "england/master/2026-27/1-premierleague.txt",
    "of_deutschland_master_2026-27_1-bundesliga.txt": OF + "deutschland/master/2026-27/1-bundesliga.txt",
    "of_italy_master_2026-27_1-seriea.txt": OF + "italy/master/2026-27/1-seriea.txt",
    "players.csv.gz": TM + "players.csv.gz",
    "clubs.csv.gz": TM + "clubs.csv.gz",
}

if __name__ == "__main__":
    os.makedirs(CACHE, exist_ok=True)
    for name, url in FILES.items():
        dest = os.path.join(CACHE, name)
        req = urllib.request.Request(url, headers={"User-Agent": "king-football-importer/1.0"})
        with urllib.request.urlopen(req, timeout=120) as resp, open(dest, "wb") as out:
            out.write(resp.read())
        print("%-40s %9d bytes" % (name, os.path.getsize(dest)))
