#!/usr/bin/env python3
"""Builds the KING FOOTBALL data pack `real_2026`: Spain, season 2026-27 (LaLiga + Segunda División).

    python3 tools/import_real/fetch_2026.py            # transfermarkt snapshot + openfootball 2026-27 -> cache/2026/
    python3 tools/import_real/build_2026.py            # fetches Wikipedia (cached), writes data/packs/real_2026/
    python3 tools/import_real/build_2026.py --offline  # rebuild from the cache only (deterministic)

Sources, in order of authority (docs/REAL_DATA_PACK_2026.md has the full rules):

1. Division membership: the Wikipedia season articles "2026–27 La Liga" / "2026–27 Segunda División",
   cross-checked against openfootball's 2026-27 LaLiga fixture file (the build stops if they disagree).
2. Squad membership, shirt numbers, sporting nationality: the "Current squad" table of each club's Wikipedia
   article (maintained from the club's official website; its {{updated}} stamp is kept).
3. A squad row is accepted only if the player has his own Wikipedia footballer article whose infobox names this
   club (or its reserve side) as his current club. Rows that fail are excluded and listed in the report: this
   keeps vandalised or unconfirmed entries out.
4. Date of birth, height, listed positions: the player's own infobox.
5. Preferred foot, detailed position, market value, contract end: transfermarkt-datasets (snapshot 2026-07-06),
   matched by exact date of birth + name similarity. Contract end is used only when the player was already at
   the same club in the snapshot (otherwise it may predate a summer transfer). Fields that no source provides
   are listed per player in `unknown_fields` instead of being invented.
6. Ratings are ESTIMATES (no open source of ratings exists): the market-value model of build_pack.py.
   Players without a market value get their club's median minus 2 (`rating_basis: club_median`).
"""
import datetime
import difflib
import json
import math
import os
import re
import sys
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import build_pack as bp  # noqa: E402  (rating model, attribute split, kits)
import wiki_squads as wk  # noqa: E402
from realdata import read_gz_csv, season_teams, slug  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
CACHE = os.path.join(HERE, "cache", "2026")
PACK_ID = "real_2026"
OUT = os.path.join(ROOT, "data", "packs", PACK_ID)
OLD_PACK = os.path.join(ROOT, "data", "packs", "real_2025")
SEASON = "2026-27"
SEASON_START = datetime.date(2026, 8, 1)
TM_SNAPSHOT = "2026-07-06"
MAX_SQUAD = 30            # TransferMarket.MAX_SQUAD

# Wikipedia club article -> [team id] (+ [code, primary, secondary] for clubs that are new in this pack).
# Ids of clubs that exist in real_2025 are kept, and their colours/codes/city are taken from there.
CLUBS = {
    # LaLiga 2026-27
    "Athletic Bilbao": ["esp_athletic_club"], "Atlético Madrid": ["esp_atletico_de_madrid"],
    "FC Barcelona": ["esp_barcelona"], "CA Osasuna": ["esp_ca_osasuna"], "Deportivo Alavés": ["esp_deportivo_alaves"],
    "Elche CF": ["esp_elche_cf"], "Getafe CF": ["esp_getafe_cf"], "Levante UD": ["esp_levante_ud"],
    "Málaga CF": ["esp_malaga_cf"], "RC Celta de Vigo": ["esp_rc_celta"],
    "Deportivo de A Coruña": ["esp_deportivo_la_coruna"], "RCD Espanyol": ["esp_rcd_espanyol"],
    "Rayo Vallecano": ["esp_rayo_vallecano"], "Real Betis": ["esp_real_betis"], "Real Madrid CF": ["esp_real_madrid_c_f"],
    "Racing de Santander": ["esp_racing_santander"], "Real Sociedad": ["esp_real_sociedad"], "Sevilla FC": ["esp_sevilla"],
    "Valencia CF": ["esp_valencia_cf"], "Villarreal CF": ["esp_villarreal"],
    # Segunda División 2026-27
    "Albacete Balompié": ["esp_albacete"], "UD Almería": ["esp_ud_almeria"], "FC Andorra": ["esp_fc_andorra"],
    "Burgos CF": ["esp_burgos_cf"], "Cádiz CF": ["esp_cadiz_cf"], "CD Castellón": ["esp_cd_castellon"],
    "RC Celta Fortuna": ["esp_rc_celta_fortuna", "CEB", "8ac3ee", "ffffff"], "AD Ceuta FC": ["esp_ad_ceuta_fc"],
    "Córdoba CF": ["esp_cordoba_cf"], "SD Eibar": ["esp_sd_eibar"], "CD Eldense": ["esp_cd_eldense", "ELD", "1f3d99", "c8102e"],
    "Girona FC": ["esp_girona_fc"], "Granada CF": ["esp_granada_cf"], "UD Las Palmas": ["esp_ud_las_palmas"],
    "CD Leganés": ["esp_cd_leganes"], "RCD Mallorca": ["esp_rcd_mallorca"], "Real Oviedo": ["esp_real_oviedo"],
    "Real Sociedad B": ["esp_real_sociedad_b"], "CE Sabadell FC": ["esp_ce_sabadell", "SAB", "0055a4", "ffffff"],
    "Sporting de Gijón": ["esp_sporting_gijon"], "CD Tenerife": ["esp_cd_tenerife", "TEN", "ffffff", "003c7f"],
    "Real Valladolid": ["esp_real_valladolid"],
}
# Reserve side -> parent (a reserve team can never be promoted into its parent's division).
RESERVES = {"RC Celta Fortuna": "RC Celta de Vigo", "Real Sociedad B": "Real Sociedad"}
DIVISIONS = [
    {"id": "esp_d1", "name": "LaLiga", "tier": 1, "article": "2026–27 La Liga", "size": 20, "promote": 0, "relegate": 3,
     "offset": -1, "fallback": 72},
    {"id": "esp_d2", "name": "Segunda División", "tier": 2, "article": "2026–27 Segunda División", "size": 22,
     "promote": 2, "relegate": 0, "playoff": {"from": 3, "to": 6, "spots": 1}, "offset": -4, "fallback": 63},
]
CUP = {"id": "esp_cup", "name": "Copa del Rey"}

# Wikipedia squad position group -> fallback position
GROUP = {"GK": "GK", "DF": "CB", "MF": "CM", "FW": "ST"}
# Infobox position wording -> game position (first match per comma-separated chunk wins; specific phrases first)
POS_WORDS = [
    ("goalkeeper", "GK"), ("centre-back", "CB"), ("center-back", "CB"), ("centre back", "CB"), ("central defender", "CB"),
    ("left wing-back", "LB"), ("left-back", "LB"), ("left back", "LB"), ("right wing-back", "RB"), ("right-back", "RB"),
    ("right back", "RB"), ("full-back", "RB"), ("full back", "RB"), ("wing-back", "RB"), ("defensive midfielder", "CDM"),
    ("central midfielder", "CM"), ("attacking midfielder", "CAM"), ("left midfielder", "LM"), ("right midfielder", "RM"),
    ("left winger", "LW"), ("right winger", "RW"), ("winger", "RW"), ("centre-forward", "ST"), ("center-forward", "ST"),
    ("centre forward", "ST"), ("second striker", "ST"), ("striker", "ST"), ("forward", "ST"), ("midfielder", "CM"),
    ("defender", "CB"),
]
# FIFA codes used by the squad tables that data/countries.json does not list (filled after the first build).
EXTRA_NATIONS = {"ROM": "Romania", "NGR": "Nigeria", "KEN": "Kenya", "CUW": "Curaçao", "PHL": "Philippines",
                 "MTQ": "Martinique", "UAE": "United Arab Emirates", "AND": "Andorra", "QAT": "Qatar", "ISR": "Israel"}
# Nationalities left out of the game at the owner's request (same rule as build_pack.EXCLUDED_NATIONALITIES).
EXCLUDED_NATIONALITIES = set(bp.EXCLUDED_NATIONALITIES)


def norm(s):
    s = unicodedata.normalize("NFKD", s or "")
    s = "".join(c for c in s if not unicodedata.combining(c)).lower()
    return re.sub(r"[^a-z ]+", " ", s).strip()


def similar(a, b):
    return difflib.SequenceMatcher(None, norm(a), norm(b)).ratio()


def tokens_overlap(a, b):
    return len(set(norm(a).split()) & set(norm(b).split()))


def age_on(iso):
    d = datetime.date.fromisoformat(iso)
    return SEASON_START.year - d.year - ((SEASON_START.month, SEASON_START.day) < (d.month, d.day))


def positions_from_text(text):
    out = []
    for chunk in re.split(r",|/|;| or | and |\n", (text or "").lower()):
        for word, pos in POS_WORDS:
            if word in chunk:
                if pos not in out:
                    out.append(pos)
                break
    return out


def club_link_target(raw):
    m = wk.LINK.search(raw or "")
    return m.group(1).strip() if m else wk.strip_markup(raw or "")


def club_matches(target, aliases):
    """True when an infobox club link names one of `aliases` (spelling variants and the club's reserve side allowed)."""
    t = norm(target)
    if not t:
        return False
    for k in {norm(a) for a in aliases}:
        if t == k or similar(t, k) >= 0.88:
            return True
        if t.startswith(k + " ") and len(t) - len(k) <= 12:     # "Athletic Bilbao B", "FC Barcelona Atletic"
            return True
    return False


def load_nations():
    data = json.load(open(os.path.join(ROOT, "data", "countries.json"), encoding="utf8"))["countries"]
    out = {c["country_code"]: c["country_name"] for c in data if c.get("region") != "Fictional"}
    # some squad tables write the full name ("nat=SPAIN") instead of the FIFA code
    out.update({c["country_name"].upper(): c["country_name"] for c in data if c.get("region") != "Fictional"})
    out.update({k: v for k, v in EXTRA_NATIONS.items() if k not in out})
    out.update({v.upper(): v for v in EXTRA_NATIONS.values()})
    return out


def tm_index():
    by_dob = {}
    for r in read_gz_csv(os.path.join(CACHE, "players.csv.gz")):
        dob = (r["date_of_birth"] or "")[:10]
        if dob:
            by_dob.setdefault(dob, []).append(r)
    clubs = {c["club_id"]: c for c in read_gz_csv(os.path.join(CACHE, "clubs.csv.gz"))}
    return by_dob, clubs


def tm_match(by_dob, dob, names):
    """The transfermarkt row with the same date of birth and a similar name, or None."""
    best, best_score = None, 0.0
    for r in by_dob.get(dob, []):
        cand = [r["name"], "%s %s" % (r["first_name"], r["last_name"])]
        score = max(similar(a, b) for a in names if a for b in cand)
        if any(tokens_overlap(a, b) for a in names if a for b in cand):
            score += 0.25
        if score > best_score:
            best, best_score = r, score
    return best if best_score >= 0.6 else None


def season_clubs(article, offline):
    _t, _ts, text = wk.wikitext(article, offline)
    labels = re.findall(r"Location map~[^\n]*?label=[^\n]*?\[\[([^\]|]+)", text)
    return list(dict.fromkeys(l.strip() for l in labels))


def old_team(team_id):
    path = os.path.join(OLD_PACK, "clubs", team_id + ".json")
    if os.path.exists(path):
        return json.load(open(path, encoding="utf8"))["team"]
    return None


def capacity(raw):
    digits = re.sub(r"[^\d]", "", (raw or "").split("(")[0].split("[")[0])
    return int(digits) if digits and int(digits) < 200000 else 0


def build(offline=False, write=True):
    nations = load_nations()
    by_dob, tm_clubs = tm_index()
    report = {"season": SEASON, "divisions": {}, "excluded": [], "duplicates": [], "trimmed": [], "missing_nations": [],
              "tm_matched": 0, "players": 0, "unknown_counts": {}, "squad_updated": {}}
    # --- 1. divisions -------------------------------------------------------------------------
    div_clubs = {}
    for d in DIVISIONS:
        arts = season_clubs(d["article"], offline)
        if len(arts) != d["size"]:
            raise SystemExit("%s: expected %d clubs, found %d: %s" % (d["article"], d["size"], len(arts), arts))
        unknown = [a for a in arts if a not in CLUBS]
        if unknown:
            raise SystemExit("clubs missing from CLUBS: %s" % unknown)
        div_clubs[d["id"]] = arts
    # Cross-check LaLiga with openfootball's fixture file (independent source): every fixture-file club must match
    # exactly one Wikipedia club.
    of_names = season_teams(os.path.join(CACHE, "of_espana_2026-27_1-liga.txt"))
    pairs = {}
    for n in of_names:
        best = max(div_clubs["esp_d1"], key=lambda a: (tokens_overlap(n, a), similar(n, a)))
        pairs[n] = best
    if len(of_names) != 20 or len(set(pairs.values())) != 20:
        raise SystemExit("openfootball LaLiga list disagrees with Wikipedia: %s" % pairs)
    report["openfootball_crosscheck"] = "20/20 clubs agree"

    # --- 2. squads ---------------------------------------------------------------------------
    squads = {}
    wk.people([a for arts in div_clubs.values() for a in arts], offline)     # batch-fetch the club articles
    for d in DIVISIONS:
        for art in div_clubs[d["id"]]:
            title, ts, text = wk.wikitext(art, offline)
            section = wk.current_squad_section(text)
            if section is None:
                raise SystemExit("%s: no current-squad section" % title)
            squads[art] = {"title": title, "revision": ts, "updated": wk.updated_stamp(section),
                           "rows": wk.parse_squad(section), "box": wk.infobox(text)}
    titles = sorted({r["article"] for s in squads.values() for r in s["rows"] if r["article"]})
    people = wk.people(titles, offline)

    # --- 3. players --------------------------------------------------------------------------
    seen = {}            # player article -> club article that kept him
    tm_club_ids = {}
    clubs_out = {}
    for d in DIVISIONS:
        league_rows = []
        for art in div_clubs[d["id"]]:
            s = squads[art]
            aliases = {s["title"], art}
            if art in RESERVES:
                aliases.add(RESERVES[art])
            kept = []
            for row in s["rows"]:
                pr = wk.person(people.get(row["article"])) if row["article"] else None
                why = ""
                if pr is None:
                    why = "no Wikipedia footballer article"
                elif not pr["birth_date"]:
                    why = "no date of birth in the infobox"
                elif not club_matches(club_link_target(pr["current_club"]), aliases):
                    why = "infobox current club is '%s'" % club_link_target(pr["current_club"])
                if not why:
                    nat = nations.get(row["nat"], row["nat"])
                    if nat in EXCLUDED_NATIONALITIES:
                        why = "nationality excluded by project rule (%s)" % nat
                if why:
                    report["excluded"].append({"club": art, "no": row["no"], "name": row["name"], "reason": why})
                    continue
                if pr["article"] in seen:
                    report["duplicates"].append({"name": row["name"], "kept": seen[pr["article"]], "dropped": art})
                    continue
                seen[pr["article"]] = art
                kept.append((row, pr))
            if len(kept) > MAX_SQUAD:
                # Over the squad limit: drop the highest shirt numbers (academy players) first.
                kept.sort(key=lambda rp: (rp[0]["no"] == 0, rp[0]["no"]))
                for row, pr in kept[MAX_SQUAD:]:
                    report["trimmed"].append({"club": art, "no": row["no"], "name": row["name"]})
                kept = kept[:MAX_SQUAD]
            league_rows.append((art, kept))
        # market-value percentile inside the division (potential headroom), as in build_pack.py
        values = []
        for art, kept in league_rows:
            for row, pr in kept:
                row["_tm"] = tm_match(by_dob, pr["birth_date"], [row["name"], pr["full_name"]])
                values.append((int(row["_tm"]["market_value_in_eur"] or 0) if row["_tm"] else 0, pr["article"]))
        values.sort()
        rank = {a: i / max(1, len(values) - 1) for i, (_v, a) in enumerate(values)}
        for art, kept in league_rows:
            ids = [row["_tm"]["current_club_id"] for row, _pr in kept if row["_tm"]]
            top = max(set(ids), key=ids.count) if ids else ""
            # the club's transfermarkt id: the current club of most of its matched players (>= 8 of them)
            tm_club_ids[art] = top if ids and ids.count(top) >= 8 else ""
        for art, kept in league_rows:
            clubs_out[art] = make_club(art, squads[art], d, kept, rank, nations, tm_club_ids.get(art, ""), report)
        report["divisions"][d["name"]] = len(div_clubs[d["id"]])

    report["tm_club_ids"] = tm_club_ids
    report["clubs"] = len(clubs_out)
    report["players"] = sum(len(c["players"]) for c in clubs_out.values())
    report["missing_nations"] = sorted(set(report["missing_nations"]))
    leagues = league_file(div_clubs)
    reputation(clubs_out, div_clubs)
    if write:
        write_pack(leagues, clubs_out, report)
    return leagues, clubs_out, report


def make_club(art, s, d, kept, rank, nations, tm_club_id, report):
    cfg = CLUBS[art]
    team_id = cfg[0]
    report["squad_updated"][art] = s["updated"] or s["revision"][:10]
    players = [make_player(row, pr, d, rank, nations, tm_club_id) for row, pr in kept]
    # Players without a market value: their club's median rating - 2 (>= 5 valued players), else the division default.
    valued = sorted(p["_ovr"] for p in players if p["rating_basis"] == "market_value")
    base = valued[len(valued) // 2] - 2 if len(valued) >= 5 else d["fallback"]
    for p in players:
        if p["rating_basis"] != "market_value":
            rng = bp.seeded("wp2026", p["id"])
            target = base + rng.uniform(-2.0, 2.0)
            if p["age"] <= 21:
                target -= (22 - p["age"]) * 1.5
            finish(p, max(45, min(88, bp.gd_round(target))), rng, 0.5)
            p["transfer_value"] = p["_ovr"] * p["_ovr"] * 400
    # Shirt numbers: the official ones from the squad table. Missing or clashing ones get a free number (flagged).
    used = set()
    for p in players:
        if p["shirt_number"] <= 0 or p["shirt_number"] in used:
            p["shirt_number"] = 0
        else:
            used.add(p["shirt_number"])
    for p in players:
        if p["shirt_number"] == 0:
            p["shirt_number"] = next(x for x in range(2, 100) if x not in used and x not in (13, 31, 41))
            used.add(p["shirt_number"])
            p["unknown_fields"].append("shirt_number")
    order = {k: i for i, k in enumerate(bp.POSITIONS)}
    players.sort(key=lambda p: (order[p["position"]], p["shirt_number"]))
    for p in players:
        for f in p["unknown_fields"]:
            report["unknown_counts"][f] = report["unknown_counts"].get(f, 0) + 1
        if p["tm_id"]:
            report["tm_matched"] += 1
        p.pop("_ovr", None)

    old = old_team(team_id)
    if old:
        team = {k: v for k, v in old.items() if k not in ("competitions", "budget", "reputation")}
    else:
        code, primary, secondary = cfg[1], cfg[2], cfg[3]
        team = {"id": team_id, "name": art, "short_name": code, "category": "CLUB", "real": True, "country": "Spain",
                "logo": "", "primary_color": primary, "secondary_color": secondary, "kits": bp.kits(primary, secondary),
                "stadium_id": "std_%s" % team_id}
    box = s["box"]
    squad_value = sum(p["transfer_value"] for p in players)
    full = wk.strip_markup(box.get("fullname", box.get("full_name", "")))
    team.update({
        "competitions": [d["id"], CUP["id"]],
        "budget": max(5_000_000, min(400_000_000, squad_value // 8)),
        "reputation": 0,
        "stadium_name": wk.strip_markup(box.get("ground", box.get("stadium", ""))),
        "stadium_capacity": capacity(wk.strip_markup(box.get("capacity", ""))),
        "manager_name": wk.strip_markup(box.get("manager", box.get("head coach", ""))),
    })
    if full and len(full) <= 80:                 # TeamData.validate: full_name <= 80 characters
        team["full_name"] = full
    return {"team": team, "players": players, "players_source": "wikipedia+transfermarkt-datasets",
            "squad_source": {"article": s["title"], "revision": s["revision"], "updated": s["updated"],
                             "url": "https://en.wikipedia.org/wiki/" + s["title"].replace(" ", "_")},
            "_value": squad_value, "_tier": d["tier"]}


def finish(p, target, rng, headroom):
    attrs = bp.build_attributes(target, p["position"], rng)
    p.update(attrs)
    p["_ovr"] = bp.overall(attrs, p["position"])
    p["potential"] = bp.potential_for(p["age"], p["_ovr"], rng, headroom)
    p["salary"] = p["_ovr"] * p["_ovr"] // 4


def make_player(row, pr, d, rank, nations, tm_club_id):
    tm = row.get("_tm")
    unknown = []
    dob = pr["birth_date"]
    age = age_on(dob)
    listed = positions_from_text(pr["position"])
    tm_pos = bp.SUB_POSITION.get(tm["sub_position"]) if tm else None
    if row["pos"] == "GK" or (listed and listed[0] == "GK"):
        pos = "GK"
    else:
        pos = tm_pos or (listed[0] if listed else None) or GROUP.get(row["pos"], "CM")
        if pos == "GK":
            pos = GROUP.get(row["pos"], "CM")
    secondary = [x for x in listed if x not in (pos, "GK")][:3]
    nat = nations.get(row["nat"]) or EXTRA_NATIONS.get(row["nat"]) or ""
    if not nat:
        nat = row["nat"]
        unknown.append("nationality_name")
    foot = {"right": "RIGHT", "left": "LEFT", "both": "BOTH"}.get((tm or {}).get("foot", ""), "")
    if not foot:
        foot = "RIGHT"                       # the game needs a value; flagged as unknown
        unknown.append("foot")
    height = pr["height_cm"] or (int(float(tm["height_in_cm"])) if tm and tm["height_in_cm"] else 0)
    if not height:
        unknown.append("height_cm")
    contract_end = ""
    if tm and tm["contract_expiration_date"] and tm_club_id and tm["current_club_id"] == tm_club_id:
        contract_end = tm["contract_expiration_date"][:10]      # same club as in the snapshot: contract still valid
    if contract_end:
        years = max(1, min(5, int(contract_end[:4]) - SEASON_START.year))
    else:
        years = 2
        unknown.append("contract")
    p = {"id": "tm_%s" % tm["player_id"] if tm else "wp_%s" % slug(pr["article"]), "name": row["name"],
         "age": max(16, min(45, age)), "birth_date": dob, "birth_year": int(dob[:4]), "nationality": nat,
         "position": pos, "secondary_positions": secondary, "foot": foot, "height_cm": height,
         "shirt_number": row["no"], "fitness": 100, "stamina": 100, "morale": 70,
         "experience": max(0, (age - 17) * 30 + (int(tm["international_caps"] or 0) * 5 if tm else 0)),
         "contract_years": years, "contract_end": contract_end, "status": "ACTIVE", "player_type": "REAL",
         "tm_id": tm["player_id"] if tm else "", "wiki": pr["article"], "unknown_fields": unknown}
    if tm and tm["last_name"]:
        p["first_name"], p["last_name"] = tm["first_name"], tm["last_name"]
    value = int(tm["market_value_in_eur"] or 0) if tm else 0
    if value > 0:
        rng = bp.seeded("tm", tm["player_id"])
        target = 67.0 + 10.4 * (math.log10(max(value, 50_000)) - 6.0) + d["offset"] + rng.uniform(-1.0, 1.0)
        if age <= 21:
            target -= (22 - age) * 1.5          # value is inflated by youth: current ability is lower
        elif age >= 31:
            target += (age - 30) * 1.0          # and deflated by age
        finish(p, max(45, min(93, bp.gd_round(target))), rng, 0.6 + 0.4 * rank.get(pr["article"], 0.0))
        p["transfer_value"] = max(value, p["_ovr"] * p["_ovr"] * 100)
        p["market_value_eur"] = value
        p["rating_basis"] = "market_value"
    else:
        p["rating_basis"] = "club_median"
        unknown.append("market_value")
    return p


def league_file(div_clubs):
    league = {"country": "Spain", "name": "Spain", "season": SEASON, "cup": CUP, "divisions": [], "reserves": {}}
    for d in DIVISIONS:
        div = {k: d[k] for k in ("id", "name", "tier", "promote", "relegate")}
        div["team_ids"] = sorted(CLUBS[a][0] for a in div_clubs[d["id"]])
        if "playoff" in d:
            div["playoff"] = d["playoff"]
        league["divisions"].append(div)
    for b, parent in RESERVES.items():
        league["reserves"][CLUBS[b][0]] = CLUBS[parent][0]
    return {"spain": league}


def reputation(clubs, div_clubs):
    """Tier 1 -> 70..95, tier 2 -> 50..70, by squad value rank inside the division (as in build_pack.py)."""
    for d in DIVISIONS:
        arts = sorted(div_clubs[d["id"]], key=lambda a: clubs[a]["_value"])
        lo, hi = (70, 95) if d["tier"] == 1 else (50, 70)
        for i, a in enumerate(arts):
            clubs[a]["team"]["reputation"] = lo + (hi - lo) * i // max(1, len(arts) - 1)


def write_pack(leagues, clubs, report):
    os.makedirs(os.path.join(OUT, "leagues"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "clubs"), exist_ok=True)
    for f in os.listdir(os.path.join(OUT, "clubs")):
        os.remove(os.path.join(OUT, "clubs", f))
    for key, league in leagues.items():
        with open(os.path.join(OUT, "leagues", key + ".json"), "w", encoding="utf8") as fh:
            json.dump(league, fh, ensure_ascii=False, indent=1, sort_keys=True)
    for c in clubs.values():
        data = {k: v for k, v in c.items() if not k.startswith("_")}
        with open(os.path.join(OUT, "clubs", c["team"]["id"] + ".json"), "w", encoding="utf8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1, sort_keys=True)
    pack = {"id": PACK_ID, "name": "LaLiga 2026-27 (Spain)", "version": 1, "season": SEASON,
            "snapshot": max(c["squad_source"]["revision"][:10] for c in clubs.values()),
            "countries": sorted(leagues.keys()),
            "sources": [
                {"name": "Wikipedia (English)", "url": "https://en.wikipedia.org", "license": "CC BY-SA 4.0 (facts only)",
                 "used_for": "2026-27 divisions, current squads, shirt numbers, nationality, date of birth, height, "
                             "positions, managers, stadiums"},
                {"name": "openfootball", "url": "https://github.com/openfootball", "license": "CC0 1.0 (public domain)",
                 "used_for": "cross-check of the 2026-27 LaLiga club list"},
                {"name": "transfermarkt-datasets", "url": "https://github.com/dcaribou/transfermarkt-datasets",
                 "license": "dataset published by its author; data originates from Transfermarkt",
                 "used_for": "preferred foot, detailed position, market value (rating estimate), contract end; snapshot "
                             + TM_SNAPSHOT}],
            "rating_note": "Ratings are estimates derived from market value, age and league strength - not official ratings.",
            "report": report}
    with open(os.path.join(OUT, "pack.json"), "w", encoding="utf8") as fh:
        json.dump(pack, fh, ensure_ascii=False, indent=1, sort_keys=True)
    with open(os.path.join(OUT, "SOURCES.md"), "w", encoding="utf8") as fh:
        fh.write("# Sources of this data pack (season %s)\n\n"
                 "- Divisions, squads, shirt numbers, nationality, date of birth, height, positions, managers, stadiums:\n"
                 "  English Wikipedia (CC BY-SA 4.0): each club's \"Current squad\" table and each player's article.\n"
                 "  Every club file records the article revision it was built from (`squad_source`).\n"
                 "- LaLiga club list cross-checked with openfootball (CC0).\n"
                 "- Preferred foot, detailed position, market value, contract end: transfermarkt-datasets, snapshot %s.\n"
                 "- Ratings: ESTIMATES (see docs/REAL_DATA_PACK_2026.md).\n"
                 "- No club badges, kit artwork or player photos are included.\n" % (SEASON, TM_SNAPSHOT))


if __name__ == "__main__":
    _l, _c, rep = build(offline="--offline" in sys.argv)
    short = {k: v for k, v in rep.items() if k not in ("excluded", "duplicates", "trimmed", "squad_updated")}
    for k in ("excluded", "duplicates", "trimmed"):
        short[k] = len(rep[k])
    print(json.dumps(short, ensure_ascii=False, indent=1))
