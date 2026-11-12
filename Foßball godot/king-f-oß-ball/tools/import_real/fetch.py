#!/usr/bin/env python3
"""Downloads the importer's inputs into tools/import_real/cache/ (gitignored)."""
import os
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache")
OF = "https://raw.githubusercontent.com/openfootball/"
TM = "https://pub-e682421888d945d684bcae8890b0ec20.r2.dev/data/"
FILES = {
    "of_england_master_2025-26_1-premierleague.txt": OF + "england/master/2025-26/1-premierleague.txt",
    "of_england_master_2025-26_2-championship.txt": OF + "england/master/2025-26/2-championship.txt",
    "of_espana_master_2025-26_1-liga.txt": OF + "espana/master/2025-26/1-liga.txt",
    "of_espana_master_2025-26_2-liga2.txt": OF + "espana/master/2025-26/2-liga2.txt",
    "of_deutschland_master_2025-26_1-bundesliga.txt": OF + "deutschland/master/2025-26/1-bundesliga.txt",
    "of_deutschland_master_2025-26_2-bundesliga2.txt": OF + "deutschland/master/2025-26/2-bundesliga2.txt",
    "of_italy_master_2025-26_1-seriea.txt": OF + "italy/master/2025-26/1-seriea.txt",
    "of_italy_master_2025-26_2-serieb.txt": OF + "italy/master/2025-26/2-serieb.txt",
    # France has no 2025-26 .txt file; the football.json export has both divisions.
    "of_football.json_2025-26_fr.1.json": OF + "football.json/master/2025-26/fr.1.json",
    "of_football.json_2025-26_fr.2.json": OF + "football.json/master/2025-26/fr.2.json",
    "players.csv.gz": TM + "players.csv.gz",
    "clubs.csv.gz": TM + "clubs.csv.gz",
    "competitions.csv.gz": TM + "competitions.csv.gz",
}

if __name__ == "__main__":
    os.makedirs(CACHE, exist_ok=True)
    for name, url in FILES.items():
        dest = os.path.join(CACHE, name)
        urllib.request.urlretrieve(url, dest)
        print("%-50s %8d bytes" % (name, os.path.getsize(dest)))
