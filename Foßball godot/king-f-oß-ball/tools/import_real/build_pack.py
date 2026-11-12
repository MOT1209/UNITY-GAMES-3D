#!/usr/bin/env python3
"""Builds the optional KING FOOTBALL real-data pack (England + Spain, two tiers each).

    python3 tools/import_real/fetch.py        # downloads into tools/import_real/cache/
    python3 tools/import_real/build_pack.py   # writes data/packs/real_2025/

Division membership: openfootball season files (CC0).
First-tier squads: transfermarkt-datasets snapshot (players whose current club is the club and
whose last_season is the current season).
Second-tier squads: NOT in the snapshot (it covers first tiers only), so those clubs are real but
their players are GENERATED (fictional names) at a strength that fits the tier. Every club file
records which source its players came from (`players_source`).

Ratings: no open source of player ratings exists. Overall ratings are ESTIMATED from market value
(logarithmic: 1M EUR ~ 67, 10M ~ 77, 50M ~ 85, 200M ~ 91), age (young players' value is inflated by
potential, older players' deflated) and a small league offset; attributes are split from the overall
by position. Potential headroom uses the value percentile within the league. Everything is deterministic (seeded by ids), so re-running gives identical output.
"""
import datetime
import hashlib
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from realdata import match_clubs, read_gz_csv, season_teams, slug  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, "cache")
PACK_ID = "real_2025"
OUT = os.path.join(ROOT, "data", "packs", PACK_ID)
SEASON = "2025-26"
TM_SEASON = "2025"
SEASON_START = datetime.date(2025, 8, 1)
SNAPSHOT = "2026-07-06"

COUNTRIES = {
    "england": {
        "country": "England", "prefix": "eng", "name": "England",
        "cup": {"id": "eng_cup", "name": "FA Cup"},
        "divisions": [
            {"id": "eng_d1", "name": "Premier League", "tier": 1, "file": "of_england_master_2025-26_1-premierleague.txt",
             "tm": "GB1", "size": 20, "range": [58, 91], "promote": 0, "relegate": 3},
            {"id": "eng_d2", "name": "Championship", "tier": 2, "file": "of_england_master_2025-26_2-championship.txt",
             "tm": None, "size": 24, "strength": [64, 74], "promote": 2, "relegate": 0,
             "playoff": {"from": 3, "to": 6, "spots": 1}},
        ],
        "recently_relegated": ["Leicester City FC", "Ipswich Town FC", "Southampton FC"],
    },
    "spain": {
        "country": "Spain", "prefix": "esp", "name": "Spain",
        "cup": {"id": "esp_cup", "name": "Copa del Rey"},
        "divisions": [
            {"id": "esp_d1", "name": "LaLiga", "tier": 1, "file": "of_espana_master_2025-26_1-liga.txt",
             "tm": "ES1", "size": 20, "range": [57, 91], "promote": 0, "relegate": 3},
            {"id": "esp_d2", "name": "Segunda División", "tier": 2, "file": "of_espana_master_2025-26_2-liga2.txt",
             "tm": None, "size": 22, "strength": [60, 70], "promote": 2, "relegate": 0,
             "playoff": {"from": 3, "to": 6, "spots": 1}},
        ],
        "recently_relegated": ["CD Leganés", "Real Valladolid", "UD Las Palmas"],
        # A reserve team can never be promoted into its parent club's division.
        "reserves": {"Real Sociedad B": "Real Sociedad"},
    },
    "germany": {
        "country": "Germany", "prefix": "ger", "name": "Germany",
        "cup": {"id": "ger_cup", "name": "DFB-Pokal"},
        "divisions": [
            {"id": "ger_d1", "name": "Bundesliga", "tier": 1, "file": "of_deutschland_master_2025-26_1-bundesliga.txt",
             "tm": "L1", "size": 18, "range": [58, 91], "promote": 0, "relegate": 2},
            {"id": "ger_d2", "name": "2. Bundesliga", "tier": 2, "file": "of_deutschland_master_2025-26_2-bundesliga2.txt",
             "tm": None, "size": 18, "strength": [62, 72], "promote": 2, "relegate": 0,
             # 3rd place meets the Bundesliga's 16th in the relegation play-off
             "playoff": {"from": 3, "to": 3, "spots": 1, "vs_upper": 16}},
        ],
        "recently_relegated": ["Holstein Kiel", "VfL Bochum"],
    },
    "italy": {
        "country": "Italy", "prefix": "ita", "name": "Italy",
        "cup": {"id": "ita_cup", "name": "Coppa Italia"},
        "divisions": [
            {"id": "ita_d1", "name": "Serie A", "tier": 1, "file": "of_italy_master_2025-26_1-seriea.txt",
             "tm": "IT1", "size": 20, "range": [57, 91], "promote": 0, "relegate": 3},
            {"id": "ita_d2", "name": "Serie B", "tier": 2, "file": "of_italy_master_2025-26_2-serieb.txt",
             "tm": None, "size": 20, "strength": [60, 70], "promote": 2, "relegate": 0,
             "playoff": {"from": 3, "to": 8, "spots": 1}},
        ],
        "recently_relegated": ["Empoli FC", "Venezia FC", "AC Monza"],
    },
    "france": {
        "country": "France", "prefix": "fra", "name": "France",
        "cup": {"id": "fra_cup", "name": "Coupe de France"},
        "divisions": [
            {"id": "fra_d1", "name": "Ligue 1", "tier": 1, "file": "of_football.json_2025-26_fr.1.json",
             "tm": "FR1", "size": 18, "range": [57, 91], "promote": 0, "relegate": 2},
            {"id": "fra_d2", "name": "Ligue 2", "tier": 2, "file": "of_football.json_2025-26_fr.2.json",
             "tm": None, "size": 18, "strength": [58, 68], "promote": 2, "relegate": 0,
             # 3rd-5th play off; the winner meets Ligue 1's 16th
             "playoff": {"from": 3, "to": 5, "spots": 1, "vs_upper": 16}},
        ],
        "recently_relegated": ["Montpellier HSC", "AS Saint-Étienne", "Stade de Reims"],
    },
}

POSITIONS = ["GK", "CB", "LB", "RB", "CDM", "CM", "CAM", "LM", "RM", "LW", "RW", "ST"]
# Mirrors PlayerData.OVERALL_WEIGHTS (scripts/data/player_data.gd) - same order, same floats.
WEIGHTS = {
    "GK": [("goalkeeping", 0.70), ("passing", 0.10), ("physical", 0.10), ("pace", 0.10)],
    "CB": [("defending", 0.50), ("physical", 0.25), ("passing", 0.10), ("pace", 0.10), ("dribbling", 0.05)],
    "LB": [("defending", 0.35), ("pace", 0.25), ("passing", 0.15), ("physical", 0.10), ("dribbling", 0.15)],
    "RB": [("defending", 0.35), ("pace", 0.25), ("passing", 0.15), ("physical", 0.10), ("dribbling", 0.15)],
    "CDM": [("defending", 0.35), ("passing", 0.25), ("physical", 0.20), ("dribbling", 0.10), ("pace", 0.10)],
    "CM": [("passing", 0.30), ("dribbling", 0.20), ("defending", 0.15), ("physical", 0.15), ("shooting", 0.10), ("pace", 0.10)],
    "CAM": [("passing", 0.30), ("dribbling", 0.30), ("shooting", 0.20), ("pace", 0.10), ("physical", 0.10)],
    "LM": [("pace", 0.25), ("dribbling", 0.30), ("passing", 0.25), ("shooting", 0.10), ("physical", 0.10)],
    "RM": [("pace", 0.25), ("dribbling", 0.30), ("passing", 0.25), ("shooting", 0.10), ("physical", 0.10)],
    "LW": [("pace", 0.30), ("dribbling", 0.30), ("shooting", 0.20), ("passing", 0.15), ("physical", 0.05)],
    "RW": [("pace", 0.30), ("dribbling", 0.30), ("shooting", 0.20), ("passing", 0.15), ("physical", 0.05)],
    "ST": [("shooting", 0.40), ("pace", 0.20), ("dribbling", 0.15), ("physical", 0.20), ("passing", 0.05)],
}
# Mirrors YouthGenerator.BIAS.
BIAS = {
    "CB": {"defending": 12, "physical": 10, "shooting": -14, "dribbling": -8},
    "LB": {"pace": 8, "defending": 7, "shooting": -10},
    "RB": {"pace": 8, "defending": 7, "shooting": -10},
    "CDM": {"defending": 9, "passing": 5, "shooting": -8},
    "CM": {"passing": 7, "dribbling": 4},
    "CAM": {"passing": 9, "dribbling": 9, "shooting": 4, "defending": -14},
    "LM": {"pace": 8, "dribbling": 7, "defending": -8},
    "RM": {"pace": 8, "dribbling": 7, "defending": -8},
    "LW": {"pace": 11, "dribbling": 11, "defending": -16},
    "RW": {"pace": 11, "dribbling": 11, "defending": -16},
    "ST": {"shooting": 13, "pace": 5, "physical": 5, "defending": -18},
}
OUTFIELD = ["pace", "shooting", "passing", "dribbling", "defending", "physical"]
SUB_POSITION = {
    "Goalkeeper": "GK", "Centre-Back": "CB", "Left-Back": "LB", "Right-Back": "RB",
    "Defensive Midfield": "CDM", "Central Midfield": "CM", "Attacking Midfield": "CAM",
    "Left Midfield": "LM", "Right Midfield": "RM", "Left Winger": "LW", "Right Winger": "RW",
    "Centre-Forward": "ST", "Second Striker": "ST",
}
POSITION_FALLBACK = {"Goalkeeper": "GK", "Defender": "CB", "Midfield": "CM", "Attack": "ST"}
# Same 23-slot layout as SquadGenerator (scripts/systems/teams/squad_generator.gd).
GEN_LAYOUT = ["GK", "GK", "CB", "CB", "CB", "CB", "LB", "RB", "CDM", "CDM", "CM", "CM", "CM", "CAM",
              "LW", "RW", "LW", "RW", "ST", "ST", "ST", "CB", "CM"]
# Fictional name pools for GENERATED second-tier players (random first+last combinations).
NAMES = {
    "England": {"first": ["Jack", "Harry", "Oliver", "George", "Charlie", "Alfie", "Jacob", "Thomas", "James", "Callum",
                          "Ryan", "Lewis", "Connor", "Kieran", "Joe", "Sam", "Liam", "Ben", "Josh", "Dan", "Tom", "Max"],
                "last": ["Walker", "Hughes", "Barnes", "Holt", "Pearce", "Whitfield", "Marsh", "Cartwright", "Doyle",
                         "Fletcher", "Haines", "Kirby", "Lowe", "Mercer", "Nolan", "Price", "Rowe", "Sutton", "Tate",
                         "Upton", "Vickers", "Webb", "Yates", "Bramley", "Ashworth", "Coulson"]},
    "Germany": {"first": ["Lukas", "Jonas", "Leon", "Felix", "Tim", "Niklas", "Moritz", "Paul", "Jan", "Fabian", "Tobias",
                          "Florian", "Maximilian", "Philipp", "Kevin", "Dennis", "Marcel", "Julian", "Simon", "Erik"],
                "last": ["Becker", "Schröder", "Neumann", "Krüger", "Hofmann", "Wolf", "Lange", "Brandt", "Zimmermann",
                         "Kraus", "Vogt", "Busch", "Seidel", "Engel", "Kühn", "Pohl", "Scholz", "Arnold", "Franke", "Ludwig"]},
    "Italy": {"first": ["Lorenzo", "Matteo", "Alessandro", "Davide", "Simone", "Federico", "Riccardo", "Andrea", "Luca",
                        "Gabriele", "Tommaso", "Nicolò", "Stefano", "Filippo", "Mattia", "Giacomo", "Pietro", "Daniele"],
              "last": ["Ferrara", "Galli", "Conti", "Marchetti", "Fontana", "Barbieri", "Rinaldi", "Caruso", "Mancini",
                       "Lombardi", "Moretti", "Testa", "Bellini", "Sartori", "Pellegrini", "Grasso", "Valentini", "Orlando"]},
    "France": {"first": ["Lucas", "Hugo", "Théo", "Mathis", "Nathan", "Enzo", "Louis", "Maxime", "Antoine", "Clément",
                         "Romain", "Baptiste", "Quentin", "Yanis", "Bastien", "Kylian", "Mehdi", "Adrien", "Julien"],
               "last": ["Lefèvre", "Moreau", "Girard", "Bonnet", "Dupont", "Lambert", "Fontaine", "Rousseau", "Vincent",
                        "Muller", "Faure", "André", "Mercier", "Blanc", "Guérin", "Boyer", "Garnier", "Chevalier", "Perrin"]},
    "Spain": {"first": ["Pablo", "Álvaro", "Javier", "Sergio", "Diego", "Adrián", "Rubén", "Iván", "Hugo", "Mario",
                        "Raúl", "Óscar", "Marcos", "Íker", "Unai", "Asier", "Jorge", "Dani", "Carlos", "Nacho"],
              "last": ["Moreno", "Navarro", "Iglesias", "Ortega", "Delgado", "Castro", "Vidal", "Serrano", "Molina",
                       "Gil", "Rubio", "Marín", "Soler", "Calvo", "Herrero", "Prieto", "Cano", "Vega", "Lozano",
                       "Pascual", "Arroyo", "Domínguez"]},
}


def seeded(*parts):
    h = hashlib.sha256("|".join(str(p) for p in parts).encode("utf8")).hexdigest()
    return random.Random(int(h[:16], 16))


def gd_round(x):
    """GDScript roundi(): half away from zero."""
    return int(math.floor(x + 0.5)) if x >= 0 else -int(math.floor(-x + 0.5))


def overall(attrs, pos):
    total = 0.0
    for attr, w in WEIGHTS[pos]:
        total += float(attrs[attr]) * float(w)
    return max(1, min(99, gd_round(total)))


def build_attributes(target, pos, rng):
    """Six outfield attributes + goalkeeping whose PlayerData overall equals `target`."""
    a = {}
    for attr in OUTFIELD:
        a[attr] = target + BIAS.get(pos, {}).get(attr, 0) + rng.randint(-4, 4)
    if pos == "GK":
        a["goalkeeping"] = target + rng.randint(-1, 1)
        for attr in OUTFIELD:
            a[attr] = target - 22 + rng.randint(-6, 6)
        a["passing"] = target - 18 + rng.randint(-5, 5)
        a["physical"] = target - 10 + rng.randint(-5, 5)
        a["pace"] = target - 16 + rng.randint(-5, 5)
    else:
        a["goalkeeping"] = rng.randint(5, 15)
    for k in a:
        a[k] = max(1, min(99, a[k]))
    for _ in range(12):
        delta = target - overall(a, pos)
        if delta == 0:
            break
        for attr, _w in WEIGHTS[pos]:
            a[attr] = max(1, min(99, a[attr] + (1 if delta > 0 else -1)))
    # fine-tune one attribute at a time (some may sit at the 1/99 bounds)
    for _ in range(300):
        delta = target - overall(a, pos)
        if delta == 0:
            break
        step = 1 if delta > 0 else -1
        movable = [(w, attr) for attr, w in WEIGHTS[pos] if 1 <= a[attr] + step <= 99]
        if not movable:
            break
        _w, attr = max(movable)
        a[attr] += step
    if pos == "GK":
        a["shooting"] = min(a["shooting"], 35)
        a["dribbling"] = min(a["dribbling"], 40)
    return a


def potential_for(age, ovr, rng, headroom):
    if age <= 20:
        gain = rng.randint(8, 15)
    elif age <= 23:
        gain = rng.randint(4, 9)
    elif age <= 26:
        gain = rng.randint(1, 4)
    else:
        gain = rng.randint(0, 1)
    return max(ovr, min(95, ovr + int(round(gain * headroom))))


def age_on(dob):
    try:
        d = datetime.date.fromisoformat(dob[:10])
    except ValueError:
        return 25
    return SEASON_START.year - d.year - ((SEASON_START.month, SEASON_START.day) < (d.month, d.day))


def kits(primary, secondary):
    """Same structure as KitEditor.default_kits."""
    def kit(main, sec, accent):
        return {"main": main, "secondary": sec, "accent": accent, "shorts": sec, "socks": main,
                "number": accent, "pattern": "solid"}
    return {"home": kit(primary, secondary, "ffffff"), "away": kit("ffffff", primary, secondary),
            "third": kit(secondary, primary, "ffffff"), "goalkeeper": kit("2ecc71", "1b1b1b", "ffffff")}


def assign_numbers(players):
    used = set()
    gk_numbers = [1, 13, 31, 41]
    for p in players:
        if p["position"] == "GK":
            n = next(x for x in gk_numbers + list(range(2, 100)) if x not in used)
        else:
            n = next(x for x in range(2, 100) if x not in used and x not in (13, 31, 41))
        used.add(n)
        p["shirt_number"] = n


def real_squad(club_rows, league_rank, lo, hi, team_id):
    """Real players of one club. `league_rank` maps player_id -> value percentile (0..1)."""
    rows = sorted(club_rows, key=lambda r: (-int(r["market_value_in_eur"] or 0), r["player_id"]))
    gks = [r for r in rows if r["position"] == "Goalkeeper"]
    keep = rows[:30]
    for g in gks:
        if sum(1 for r in keep if r["position"] == "Goalkeeper") >= 2:
            break
        if g not in keep:
            keep[-1] = g
    out = []
    for r in keep:
        rng = seeded("tm", r["player_id"])
        pos = SUB_POSITION.get(r["sub_position"]) or POSITION_FALLBACK.get(r["position"], "CM")
        age = age_on(r["date_of_birth"])
        value = int(r["market_value_in_eur"] or 0)
        # log-value model: 1M EUR -> 67, 10M -> 77, 50M -> 84.7, 200M -> 91 (league offset `lo` - 58)
        target = 67.0 + 10.4 * (math.log10(max(value, 50_000)) - 6.0) + (lo - 58) + rng.uniform(-1.0, 1.0)
        pct = league_rank.get(r["player_id"], 0.0)
        if age <= 21:
            target -= (22 - age) * 1.5          # value is inflated by youth: current ability is lower
        elif age >= 31:
            target += (age - 30) * 1.0          # and deflated by age
        target = max(45, min(hi + 2, gd_round(target)))
        attrs = build_attributes(target, pos, rng)
        ovr = overall(attrs, pos)
        exp_year = (r["contract_expiration_date"] or "")[:4]
        years = max(1, min(5, int(exp_year) - SEASON_START.year)) if exp_year.isdigit() else 2
        p = {"id": "tm_%s" % r["player_id"], "name": r["name"], "age": max(16, min(45, age)),
             "nationality": r["country_of_citizenship"] or "Unknown", "position": pos,
             "foot": {"right": "RIGHT", "left": "LEFT", "both": "BOTH"}.get(r["foot"], "RIGHT"),
             "potential": potential_for(age, ovr, rng, 0.6 + 0.4 * pct),
             "experience": max(0, (age - 17) * 30 + int(r["international_caps"] or 0) * 5),
             "fitness": 100, "stamina": 100, "morale": 70, "contract_years": years,
             "salary": ovr * ovr // 4, "transfer_value": max(value, ovr * ovr * 100), "status": "ACTIVE"}
        p.update(attrs)
        out.append(p)
    pos_order = {k: i for i, k in enumerate(POSITIONS)}
    out.sort(key=lambda p: (pos_order[p["position"]], -p["transfer_value"], p["id"]))
    assign_numbers(out)
    return out


def generated_squad(team_id, country, strength):
    rng = seeded("gen", team_id)
    pool = NAMES[country]
    used = set()
    out = []
    for i, pos in enumerate(GEN_LAYOUT):
        age = rng.randint(19, 35)
        target = gd_round(38.0 + strength * 0.42 + rng.uniform(-7.0, 7.0) - (6.0 if i >= 11 else 0.0))
        attrs = build_attributes(max(40, min(85, target)), pos, rng)
        ovr = overall(attrs, pos)
        for _ in range(40):
            nm = "%s %s" % (rng.choice(pool["first"]), rng.choice(pool["last"]))
            if nm not in used:
                break
        used.add(nm)
        p = {"id": "gen_%s_%02d" % (team_id, i + 1), "name": nm, "age": age, "nationality": country,
             "position": pos, "foot": rng.choice(["RIGHT", "RIGHT", "LEFT", "BOTH"]),
             "potential": potential_for(age, ovr, rng, 0.8), "experience": max(0, (age - 17) * 25),
             "fitness": 100, "stamina": 100, "morale": 70, "contract_years": rng.randint(1, 4),
             "salary": ovr * ovr // 4, "transfer_value": ovr * ovr * 400, "status": "ACTIVE"}
        p.update(attrs)
        out.append(p)
    assign_numbers(out)
    return out


def build(cache=CACHE, out_dir=OUT, write=True):
    meta = json.load(open(os.path.join(HERE, "club_meta.json"), encoding="utf8"))
    tm_clubs = read_gz_csv(os.path.join(cache, "clubs.csv.gz"))
    tm_players = read_gz_csv(os.path.join(cache, "players.csv.gz"))
    report = {"season": SEASON, "countries": {}, "unmatched": [], "missing_meta": []}
    leagues, clubs = {}, {}
    for key, c in COUNTRIES.items():
        prefix = c["prefix"]
        league = {"country": c["country"], "name": c["name"], "season": SEASON, "divisions": [], "cup": c["cup"],
                  "reserves": {}}
        name_to_id = {}
        for d in c["divisions"]:
            names = season_teams(os.path.join(cache, d["file"]))
            if len(names) != d["size"]:
                raise SystemExit("%s: expected %d teams, found %d" % (d["file"], d["size"], len(names)))
            team_ids = []
            if d["tm"]:
                current = [r for r in tm_clubs if r["domestic_competition_id"] == d["tm"] and r["last_season"] == TM_SEASON]
                mapping, unmatched = match_clubs(names, current, json.load(open(os.path.join(HERE, "club_aliases.json"), encoding="utf8")))
                report["unmatched"] += unmatched
                club_ids = {mapping[n]["club_id"]: n for n in mapping}
                league_rows = [r for r in tm_players if r["last_season"] == TM_SEASON and r["current_club_id"] in club_ids]
                ranked = sorted(league_rows, key=lambda r: (int(r["market_value_in_eur"] or 0), int(r["highest_market_value_in_eur"] or 0)))
                rank = {r["player_id"]: (i / max(1, len(ranked) - 1)) for i, r in enumerate(ranked)}
            for n in names:
                if n not in meta:
                    report["missing_meta"].append(n)
                    continue
                code, primary, secondary = meta[n][:3]
                display_override = meta[n][3] if len(meta[n]) > 3 else ""
                team_id = "%s_%s" % (prefix, slug(n))
                name_to_id[n] = team_id
                team_ids.append(team_id)
                if d["tm"] and n in mapping:
                    tm_row = mapping[n]
                    rows = [r for r in league_rows if r["current_club_id"] == tm_row["club_id"]]
                    players = real_squad(rows, rank, d["range"][0], d["range"][1], team_id)
                    if len(players) < 18:
                        raise SystemExit("%s has only %d real players" % (n, len(players)))
                    source = "transfermarkt-datasets"
                    display = display_override or tm_row["name"]
                    squad_value = sum(int(r["market_value_in_eur"] or 0) for r in rows)
                    stadium = tm_row["stadium_name"]
                else:
                    srng = seeded("strength", team_id)
                    lo, hi = d["strength"]
                    strength = srng.randint(lo, hi - 3) + (3 if n in c.get("recently_relegated", []) else 0)
                    players = generated_squad(team_id, c["country"], strength)
                    source = "generated"
                    display = display_override or n
                    squad_value = sum(p["transfer_value"] for p in players)
                    stadium = ""
                clubs[team_id] = {"team": {
                    "id": team_id, "name": display, "short_name": code, "category": "CLUB", "real": True,
                    "country": c["country"], "logo": "", "primary_color": primary, "secondary_color": secondary,
                    "kits": kits(primary, secondary), "stadium_id": "std_%s" % team_id,
                    "reputation": 0, "budget": max(5_000_000, min(400_000_000, squad_value // 8)),
                    "competitions": [d["id"], c["cup"]["id"]]},
                    "players": players, "players_source": source, "stadium_name": stadium,
                    "_value": squad_value, "_tier": d["tier"]}
            div = {k: d[k] for k in ("id", "name", "tier", "promote", "relegate")}
            div["team_ids"] = sorted(team_ids)
            if "playoff" in d:
                div["playoff"] = d["playoff"]
            league["divisions"].append(div)
        for b, parent in c.get("reserves", {}).items():
            if b in name_to_id and parent in name_to_id:
                league["reserves"][name_to_id[b]] = name_to_id[parent]
        # reputation: tier 1 -> 70..95, tier 2 -> 50..70, by squad value rank inside the division
        for div in league["divisions"]:
            ids = sorted(div["team_ids"], key=lambda t: clubs[t]["_value"])
            lo, hi = (70, 95) if div["tier"] == 1 else (50, 70)
            for i, t in enumerate(ids):
                clubs[t]["team"]["reputation"] = lo + (hi - lo) * i // max(1, len(ids) - 1)
        leagues[key] = league
        report["countries"][key] = {d["name"]: len(d["team_ids"]) for d in league["divisions"]}
    if report["unmatched"] or report["missing_meta"]:
        raise SystemExit("unmatched clubs %s / clubs without colours %s" % (report["unmatched"], report["missing_meta"]))
    report["clubs"] = len(clubs)
    report["players"] = sum(len(c["players"]) for c in clubs.values())
    report["real_players"] = sum(len(c["players"]) for c in clubs.values() if c["players_source"] != "generated")
    if write:
        write_pack(out_dir, leagues, clubs, report)
    return leagues, clubs, report


def write_pack(out_dir, leagues, clubs, report):
    os.makedirs(os.path.join(out_dir, "leagues"), exist_ok=True)
    os.makedirs(os.path.join(out_dir, "clubs"), exist_ok=True)
    for f in os.listdir(os.path.join(out_dir, "clubs")):
        os.remove(os.path.join(out_dir, "clubs", f))
    for key, league in leagues.items():
        with open(os.path.join(out_dir, "leagues", key + ".json"), "w", encoding="utf8") as fh:
            json.dump(league, fh, ensure_ascii=False, indent=1, sort_keys=True)
    for team_id, c in clubs.items():
        data = {k: v for k, v in c.items() if not k.startswith("_")}
        with open(os.path.join(out_dir, "clubs", team_id + ".json"), "w", encoding="utf8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1, sort_keys=True)
    pack = {"id": PACK_ID, "name": "Real leagues 2025-26 (England, Spain, Germany, Italy, France)", "version": 1, "season": SEASON,
            "snapshot": SNAPSHOT, "countries": sorted(leagues.keys()),
            "sources": [
                {"name": "openfootball", "url": "https://github.com/openfootball", "license": "CC0 1.0 (public domain)",
                 "used_for": "leagues, divisions, clubs (England, Spain, Germany, Italy as .txt; France via football.json)"},
                {"name": "transfermarkt-datasets", "url": "https://github.com/dcaribou/transfermarkt-datasets",
                 "license": "dataset published by its author; data originates from Transfermarkt",
                 "used_for": "first-tier squads (names, positions, ages, nationality, market value)"}],
            "rating_note": "Ratings are estimates derived from market value, age and league strength - not official ratings.",
            "generated_note": "Second-tier players are generated with fictional names (the snapshot covers first tiers only).",
            "report": report}
    with open(os.path.join(out_dir, "pack.json"), "w", encoding="utf8") as fh:
        json.dump(pack, fh, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(out_dir, "SOURCES.md"), "w", encoding="utf8") as fh:
        fh.write("# Sources of this data pack\n\n"
                 "- Leagues, divisions, clubs: openfootball (CC0 1.0, public domain), season %s.\n"
                 "- First-tier squads: transfermarkt-datasets (github.com/dcaribou/transfermarkt-datasets), snapshot %s;\n"
                 "  the data originates from Transfermarkt. Development / personal use; legal review needed before\n"
                 "  any public or commercial release.\n"
                 "- Second-tier players: generated, fictional names.\n"
                 "- Ratings: ESTIMATES from market value, age and league (see docs/REAL_DATA_PACK.md).\n"
                 "- No club badges, kit artwork or player photos are included.\n" % (SEASON, SNAPSHOT))


if __name__ == "__main__":
    _l, _c, rep = build()
    print(json.dumps(rep, ensure_ascii=False, indent=1))
