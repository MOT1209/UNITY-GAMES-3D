#!/usr/bin/env python3
"""Builds the KING FOOTBALL data pack `real_2026`, season 2026-27: Spain (LaLiga + Segunda), England (Premier League + Championship), Germany (Bundesliga +
2. Bundesliga).

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
    # Premier League 2026-27
    "Arsenal F.C.": ["eng_arsenal"], "Aston Villa F.C.": ["eng_aston_villa"], "AFC Bournemouth": ["eng_bournemouth"],
    "Brentford F.C.": ["eng_brentford"], "Brighton & Hove Albion F.C.": ["eng_brighton_hove_albion"],
    "Chelsea F.C.": ["eng_chelsea_fc"], "Coventry City F.C.": ["eng_coventry_city_fc"], "Crystal Palace F.C.": ["eng_crystal_palace"],
    "Everton F.C.": ["eng_everton"], "Fulham F.C.": ["eng_fulham"], "Hull City A.F.C.": ["eng_hull_city_afc"],
    "Ipswich Town F.C.": ["eng_ipswich_town_fc"], "Leeds United F.C.": ["eng_leeds_united"], "Liverpool F.C.": ["eng_liverpool"],
    "Manchester City F.C.": ["eng_manchester_city"], "Manchester United F.C.": ["eng_manchester_united"],
    "Newcastle United F.C.": ["eng_newcastle_united"], "Nottingham Forest F.C.": ["eng_nottingham_forest"],
    "Sunderland A.F.C.": ["eng_sunderland"], "Tottenham Hotspur F.C.": ["eng_tottenham_hotspur"],
    # EFL Championship 2026-27
    "Birmingham City F.C.": ["eng_birmingham_city_fc"], "Blackburn Rovers F.C.": ["eng_blackburn_rovers_fc"],
    "Bolton Wanderers F.C.": ["eng_bolton_wanderers_fc", "BOL", "ffffff", "1d2a5c"], "Bristol City F.C.": ["eng_bristol_city_fc"],
    "Burnley F.C.": ["eng_burnley"], "Cardiff City F.C.": ["eng_cardiff_city_fc", "CAR", "0070b5", "ffffff"],
    "Charlton Athletic F.C.": ["eng_charlton_athletic_fc"], "Derby County F.C.": ["eng_derby_county_fc"],
    "Lincoln City F.C.": ["eng_lincoln_city_fc", "LIN", "d71920", "ffffff"], "Norwich City F.C.": ["eng_norwich_city_fc"],
    "Middlesbrough F.C.": ["eng_middlesbrough_fc"], "Millwall F.C.": ["eng_millwall_fc"], "Portsmouth F.C.": ["eng_portsmouth_fc"],
    "Preston North End F.C.": ["eng_preston_north_end_fc"], "Queens Park Rangers F.C.": ["eng_queens_park_rangers_fc"],
    "Sheffield United F.C.": ["eng_sheffield_united_fc"], "Southampton F.C.": ["eng_southampton_fc"],
    "Stoke City F.C.": ["eng_stoke_city_fc"], "Swansea City A.F.C.": ["eng_swansea_city_afc"], "Watford F.C.": ["eng_watford_fc"],
    "West Bromwich Albion F.C.": ["eng_west_bromwich_albion_fc"], "West Ham United F.C.": ["eng_west_ham_united"],
    "Wolverhampton Wanderers F.C.": ["eng_wolverhampton_wanderers"], "Wrexham A.F.C.": ["eng_wrexham_afc"],
    # Bundesliga 2026-27
    "FC Augsburg": ["ger_fc_augsburg"], "1. FC Union Berlin": ["ger_union_berlin"], "SV Werder Bremen": ["ger_werder_bremen"],
    "Borussia Dortmund": ["ger_borussia_dortmund"], "SV Elversberg": ["ger_sv_07_elversberg"],
    "Eintracht Frankfurt": ["ger_eintracht_frankfurt"], "SC Freiburg": ["ger_sc_freiburg"],
    "Borussia Mönchengladbach": ["ger_borussia_m_gladbach"], "Hamburger SV": ["ger_hamburger_sv"],
    "TSG 1899 Hoffenheim": ["ger_tsg_1899_hoffenheim"], "1. FC Köln": ["ger_1_fc_koln"], "RB Leipzig": ["ger_rb_leipzig"],
    "Bayer 04 Leverkusen": ["ger_bayer_leverkusen"], "1. FSV Mainz 05": ["ger_1_fsv_mainz_05"],
    "FC Bayern Munich": ["ger_fc_bayern_munchen"], "SC Paderborn 07": ["ger_sc_paderborn_07"],
    "FC Schalke 04": ["ger_fc_schalke_04"], "VfB Stuttgart": ["ger_vfb_stuttgart"],
    # 2. Bundesliga 2026-27
    "Hertha BSC": ["ger_hertha_bsc"], "Arminia Bielefeld": ["ger_arminia_bielefeld"], "VfL Bochum": ["ger_vfl_bochum"],
    "Eintracht Braunschweig": ["ger_eintracht_braunschweig"],
    "FC Energie Cottbus": ["ger_fc_energie_cottbus", "FCE", "e2001a", "ffffff"],
    "SV Darmstadt 98": ["ger_sv_darmstadt_98"], "Dynamo Dresden": ["ger_dynamo_dresden"],
    "SpVgg Greuther Fürth": ["ger_spvgg_greuther_furth"], "Hannover 96": ["ger_hannover_96"],
    "1. FC Heidenheim": ["ger_heidenheim"], "1. FC Kaiserslautern": ["ger_1_fc_kaiserslautern"],
    "Karlsruher SC": ["ger_karlsruher_sc"], "Holstein Kiel": ["ger_holstein_kiel"], "1. FC Magdeburg": ["ger_1_fc_magdeburg"],
    "1. FC Nürnberg": ["ger_1_fc_nurnberg"], "VfL Osnabrück": ["ger_vfl_osnabruck", "OSN", "5c2d91", "ffffff"],
    "FC St. Pauli": ["ger_st_pauli"],
    "VFL Wolfsburg": ["ger_wolfsburg"],          # the season article links this spelling (redirect to VfL Wolfsburg)
}
# One entry per country, added one at a time (docs/REAL_DATA_PACK_2026.md "Adding a league").
# offset: rating offset of the market-value model (as real_2025: Premier League 0, LaLiga -1); fallback: rating
# for clubs with fewer than 5 valued players. `openfootball`: fixture file used to cross-check the top division.
COUNTRIES = {
    "spain": {
        "country": "Spain", "cup": {"id": "esp_cup", "name": "Copa del Rey"},
        "openfootball": "of_espana_2026-27_1-liga.txt",
        # Reserve side -> parent (a reserve team can never be promoted into its parent's division).
        "reserves": {"RC Celta Fortuna": "RC Celta de Vigo", "Real Sociedad B": "Real Sociedad"},
        "divisions": [
            {"id": "esp_d1", "name": "LaLiga", "tier": 1, "article": "2026–27 La Liga", "size": 20, "promote": 0,
             "relegate": 3, "offset": -1, "fallback": 72},
            {"id": "esp_d2", "name": "Segunda División", "tier": 2, "article": "2026–27 Segunda División", "size": 22,
             "promote": 2, "relegate": 0, "playoff": {"from": 3, "to": 6, "spots": 1}, "offset": -4, "fallback": 63},
        ],
    },
    "england": {
        "country": "England", "cup": {"id": "eng_cup", "name": "FA Cup"},
        "openfootball": "of_england_master_2026-27_1-premierleague.txt",
        "reserves": {},
        "divisions": [
            {"id": "eng_d1", "name": "Premier League", "tier": 1, "article": "2026–27 Premier League", "size": 20,
             "promote": 0, "relegate": 3, "offset": 0, "fallback": 74},
            {"id": "eng_d2", "name": "Championship", "tier": 2, "article": "2026–27 EFL Championship", "size": 24,
             "promote": 2, "relegate": 0, "playoff": {"from": 3, "to": 6, "spots": 1}, "offset": -3, "fallback": 66},
        ],
    },
    "germany": {
        "country": "Germany", "cup": {"id": "ger_cup", "name": "DFB-Pokal"},
        # players without an English article are verified on German Wikipedia (same rules: own footballer article,
        # date of birth, and an open-ended senior station at this club)
        "fallback_wiki": "de",
        "openfootball": "of_deutschland_master_2026-27_1-bundesliga.txt",
        "reserves": {},
        "divisions": [
            {"id": "ger_d1", "name": "Bundesliga", "tier": 1, "article": "2026–27 Bundesliga", "size": 18,
             "promote": 0, "relegate": 2, "offset": 0, "fallback": 73},
            # 2 up directly; 3rd plays the Bundesliga's 16th (relegation play-off), as in real_2025
            {"id": "ger_d2", "name": "2. Bundesliga", "tier": 2, "article": "2026–27 2. Bundesliga", "size": 18,
             "promote": 2, "relegate": 0, "playoff": {"from": 3, "to": 3, "spots": 1, "vs_upper": 16}, "offset": -4,
             "fallback": 64},
        ],
    },
}
RESERVES = {b: parent for c in COUNTRIES.values() for b, parent in c["reserves"].items()}
DIVISIONS = [dict(d, country_key=key) for key, c in COUNTRIES.items() for d in c["divisions"]]

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
    ("torwart", "GK"), ("innenverteidig", "CB"), ("linksverteidig", "LB"), ("linker verteidiger", "LB"),
    ("rechtsverteidig", "RB"), ("rechter verteidiger", "RB"), ("außenverteidig", "RB"), ("defensives mittelfeld", "CDM"),
    ("sechser", "CDM"), ("zentrales mittelfeld", "CM"), ("offensives mittelfeld", "CAM"), ("linksaußen", "LW"),
    ("rechtsaußen", "RW"), ("linkes mittelfeld", "LM"), ("rechtes mittelfeld", "RM"), ("flügelspieler", "RW"),
    ("mittelstürmer", "ST"), ("stürmer", "ST"), ("sturm", "ST"), ("mittelfeld", "CM"), ("abwehr", "CB"),
    ("verteidig", "CB"),
]
# FIFA codes used by the squad tables that data/countries.json does not list (filled after the first build).
EXTRA_NATIONS = {"ROM": "Romania", "NGR": "Nigeria", "KEN": "Kenya", "CUW": "Curaçao", "PHL": "Philippines",
                 "MTQ": "Martinique", "UAE": "United Arab Emirates", "AND": "Andorra", "QAT": "Qatar", "ISR": "Israel",
                 "SER": "Serbia", "LCA": "Saint Lucia", "BRB": "Barbados", "KAZ": "Kazakhstan", "SGP": "Singapore",
                 "NAM": "Namibia", "BAN": "Bangladesh", "AFG": "Afghanistan",
                 "SKN": "Saint Kitts and Nevis", "KVX": "Kosovo", "PHI": "Philippines", "DNK": "Denmark", "JAP": "Japan",
                 "MWI": "Malawi", "LBN": "Lebanon", "UGA": "Uganda", "TGO": "Togo", "PLE": "Palestine"}
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
    keys = {norm(a) for a in aliases}
    # English articles end in "F.C." / "A.F.C." but infoboxes often link the plain name ("Coventry City")
    suffix = r"\s+(a f c|f c|afc|fc|association football club|football club)$"
    keys |= {re.sub(suffix, "", k) for k in keys}
    t = re.sub(suffix, "", t)                 # "Nottingham Forest Football Club"
    for k in keys:
        if t == k or similar(t, k) >= 0.88:
            return True
        if t.startswith(k + " ") and (len(t) - len(k) <= 12 or re.search(r"\b(under|academy|reserves?)\b", t)):
            return True                 # reserve side: "Athletic Bilbao B", "Chelsea F.C. Under-21s and Academy"
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
    """The transfermarkt row with the same date of birth and the same player's name, or None.

    The same birth date and a shared surname are not enough (Iván Medina, Spain, matched Tobías Medina, Argentina).
    A row is accepted when the names are nearly identical, share two name parts, or the transfermarkt name is a
    one-word name / an abbreviation of the full name ("Anuar", "Fidel", "Álex Petxa" for Alexander Petxarroman)."""
    best, best_score = None, 0.0
    for r in by_dob.get(dob, []):
        cand = [r["name"], "%s %s" % (r["first_name"], r["last_name"])]
        sim = max(similar(a, b) for a in names if a for b in cand)
        shared = max(tokens_overlap(a, b) for a in names if a for b in cand)
        tm_tokens = norm(r["name"]).split()
        wiki_tokens = [t for a in names if a for t in norm(a).split()]
        abbreviation = bool(tm_tokens) and all(any(w.startswith(t) for w in wiki_tokens) for t in tm_tokens)
        same_player = sim >= 0.8 or shared >= 2 or abbreviation
        if same_player and sim > best_score:
            best, best_score = r, sim
    return best


def fallback_titles(row):
    """Titles to try in the fallback edition: the English link target, the shown name, and the usual
    disambiguation "(Fußballspieler)"."""
    out = [t for t in (row["article"], row["name"]) if t]
    out.append(row["name"] + " (Fußballspieler)")
    return list(dict.fromkeys(out))


def fallback_person(row, fb, fb_people, aliases):
    """The row's player from the fallback edition when his article is a footballer article with a date of birth and an
    open-ended senior station at this club; shaped like wiki_squads.person(). None otherwise."""
    lang, local_title = fb
    if lang != "de":
        return None
    names = set(aliases) | ({local_title} if local_title else set())
    for t in row.get("_cands", []):
        pde = wk.person_de(fb_people.get(lang, {}).get(t))
        if not pde or not pde["birth_date"]:
            continue
        for club in pde["current_clubs"]:
            club = club.split("#")[0]                       # "1. FC Magdeburg#Zweite Mannschaft" -> the club
            if club_matches(club, names):
                return {"article": pde["article"], "revision": pde["revision"], "full_name": pde["full_name"],
                        "birth_date": pde["birth_date"], "height_cm": pde["height_cm"], "position": pde["position"],
                        "current_club": "[[%s]]" % club, "club_number": ""}
    return None


def club_table_person(row, art, fb, club_text):
    """A player without any personal article, accepted when the club's own article in the fallback edition lists him in
    its current squad table with the same shirt number and a date of birth: two independent squad lists agree."""
    lang, local_title = fb
    if lang != "de" or not club_text or not row["no"]:
        return None
    for k in wk.kader_de(club_text):
        if k["no"] == row["no"] and k["birth_date"] and (norm(k["name"]) == norm(row["name"]) or similar(k["name"], row["name"]) >= 0.85):
            group = {"Tor": "Torwart", "Abwehr": "Abwehr", "Mittelfeld": "Mittelfeld", "Sturm": "Sturm"}.get(k["group"], "")
            return {"article": "de:%s#%s" % (local_title, k["name"]), "revision": "", "full_name": k["name"],
                    "birth_date": k["birth_date"], "height_cm": 0, "position": group,
                    "current_club": "[[%s]]" % art, "club_number": str(k["no"])}
    return None


def season_clubs(article, offline, size):
    """Clubs of a season article: the league-table template (`name_XXX = [[Club]]`), else the location map
    (LaLiga's article transcludes its table)."""
    _t, _ts, text = wk.wikitext(article, offline)
    table = []
    for m in re.finditer(r"\|\s*name_[A-Za-z0-9]+\s*=\s*([^\n|]*\[\[[^\]]+\]\][^\n]*)", text):
        link = wk.LINK.search(m.group(1))
        if link:
            table.append(link.group(1).strip())
    table = list(dict.fromkeys(table))
    if len(table) == size:
        return table
    labels = re.findall(r"[Ll]ocation map~[^\n]*?label=[^\n]*?\[\[([^\]|]+)", text)
    return [l for l in dict.fromkeys(x.strip() for x in labels) if l in CLUBS]


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
        arts = season_clubs(d["article"], offline, d["size"])
        if len(arts) != d["size"]:
            raise SystemExit("%s: expected %d clubs, found %d: %s" % (d["article"], d["size"], len(arts), arts))
        unknown = [a for a in arts if a not in CLUBS]
        if unknown:
            raise SystemExit("clubs missing from CLUBS: %s" % unknown)
        div_clubs[d["id"]] = arts
    # Cross-check every top division with openfootball's fixture file (independent source): each fixture-file club
    # must match exactly one Wikipedia club.
    report["openfootball_crosscheck"] = {}
    for c in COUNTRIES.values():
        top = c["divisions"][0]
        of_names = season_teams(os.path.join(CACHE, c["openfootball"]))
        pairs = {n: max(div_clubs[top["id"]], key=lambda a: (tokens_overlap(n, a), similar(n, a))) for n in of_names}
        if len(of_names) != top["size"] or len(set(pairs.values())) != top["size"]:
            raise SystemExit("openfootball %s list disagrees with Wikipedia: %s" % (top["name"], pairs))
        report["openfootball_crosscheck"][top["name"]] = "%d/%d clubs agree" % (top["size"], top["size"])

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
            if len(squads[art]["rows"]) < 18:      # a template variant the parser does not know: stop, never ship it
                raise SystemExit("%s: only %d squad rows parsed" % (title, len(squads[art]["rows"])))
    titles = sorted({r["article"] for s in squads.values() for r in s["rows"] if r["article"]})
    people = wk.people(titles, offline)
    fallback = {}           # club article -> (lang, its title in that language)
    fb_people = {}          # lang -> {candidate title: page}
    fb_clubs = {}           # club article -> text of its article in the fallback edition
    for d in DIVISIONS:
        lang = COUNTRIES[d["country_key"]].get("fallback_wiki")
        if not lang:
            continue
        local = wk.langlinks(div_clubs[d["id"]], lang, offline)
        club_pages = wk.people([t for t in local.values() if t], offline, lang)
        for art in div_clubs[d["id"]]:
            fallback[art] = (lang, local.get(art, ""))
            page = club_pages.get(local.get(art, ""))
            fb_clubs[art] = page["text"] if page and not page.get("missing") else ""
            squads[art]["fb_text"] = fb_clubs[art]
            cands = []
            for row in squads[art]["rows"]:
                if not (row["article"] and wk.person(people.get(row["article"]))):
                    row["_cands"] = fallback_titles(row)
                    cands += row["_cands"]
            fb_people.setdefault(lang, {}).update(wk.people(sorted(set(cands)), offline, lang))

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
                if pr is None and art in fallback:
                    pr = fallback_person(row, fallback[art], fb_people, aliases)
                if pr is None and art in fallback:
                    pr = club_table_person(row, art, fallback[art], fb_clubs.get(art, ""))
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
                # Over the squad limit (TransferMarket.MAX_SQUAD): drop the highest shirt numbers, but never a player
                # worth >= 3M EUR (dropping by number alone removed real first-team signings in England, where new
                # arrivals take high numbers).
                def value(rp):
                    tm = tm_match(by_dob, rp[1]["birth_date"], [rp[0]["name"], rp[1]["full_name"]])
                    return int(tm["market_value_in_eur"] or 0) if tm else 0
                vals = {id(rp): value(rp) for rp in kept}
                keepers = sorted((rp for rp in kept if rp[0]["pos"] == "GK"), key=lambda rp: -vals[id(rp)])[:2]
                # keep order: the two keepers, players worth >= 3M EUR (clearly first team, even with a new high
                # number), then everyone else by shirt number - the highest numbers (academy) are dropped first
                kept.sort(key=lambda rp: (rp not in keepers, vals[id(rp)] < 3_000_000, rp[0]["no"] or 999, -vals[id(rp)]))
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
        name = re.sub(r"\s+(F\.C\.|A\.F\.C\.)$", "", art)
        team = {"id": team_id, "name": name, "short_name": code, "category": "CLUB", "real": True,
                "country": COUNTRIES[d["country_key"]]["country"],
                "logo": "", "primary_color": primary, "secondary_color": secondary, "kits": bp.kits(primary, secondary),
                "stadium_id": "std_%s" % team_id}
    box = s["box"]
    squad_value = sum(p["transfer_value"] for p in players)
    full = wk.strip_markup(box.get("fullname", box.get("full_name", "")))
    team.update({
        "competitions": [d["id"], COUNTRIES[d["country_key"]]["cup"]["id"]],
        "budget": max(5_000_000, min(400_000_000, squad_value // 8)),
        "reputation": 0,
        "stadium_name": wk.strip_markup(box.get("ground", box.get("stadium", ""))),
        "stadium_capacity": capacity(wk.strip_markup(box.get("capacity", ""))),
        "manager_name": wk.strip_markup(box.get("manager", box.get("head coach", ""))),
    })
    if (not team["manager_name"] or not team["stadium_name"]) and s.get("fb_text"):
        de = wk.club_box_de(s["fb_text"])               # German infobox fills what the English one lacks
        team["manager_name"] = team["manager_name"] or de.get("manager", "")
        team["stadium_name"] = team["stadium_name"] or de.get("ground", "")
        team["stadium_capacity"] = team["stadium_capacity"] or capacity(de.get("capacity", ""))
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
    # age: the real age (the loader accepts 14-50)
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
    if tm and tm["contract_expiration_date"] and tm_club_id and tm["current_club_id"] == tm_club_id             and tm["contract_expiration_date"][:10] >= SEASON_START.isoformat():
        # same club as in the snapshot and not expired before the season starts (a contract ending 2026-06-30 in a
        # snapshot of 2026-07-06 was renewed or ended; the snapshot cannot tell which)
        contract_end = tm["contract_expiration_date"][:10]
    if contract_end:
        years = max(1, min(5, int(contract_end[:4]) - SEASON_START.year))
    else:
        years = 2
        unknown.append("contract")
    p = {"id": "tm_%s" % tm["player_id"] if tm else "wp_%s" % slug(pr["article"]), "name": row["name"],
         "age": max(14, min(50, age)), "birth_date": dob, "birth_year": int(dob[:4]), "nationality": nat,
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
    leagues = {}
    for key, c in COUNTRIES.items():
        league = {"country": c["country"], "name": c["country"], "season": SEASON, "cup": c["cup"], "divisions": [],
                  "reserves": {}}
        for d in c["divisions"]:
            div = {k: d[k] for k in ("id", "name", "tier", "promote", "relegate")}
            div["team_ids"] = sorted(CLUBS[a][0] for a in div_clubs[d["id"]])
            if "playoff" in d:
                div["playoff"] = d["playoff"]
            league["divisions"].append(div)
        for b, parent in c["reserves"].items():
            league["reserves"][CLUBS[b][0]] = CLUBS[parent][0]
        leagues[key] = league
    return leagues


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
    pack = {"id": PACK_ID, "name": "Real leagues %s (%s)" % (SEASON, ", ".join(c["country"] for c in COUNTRIES.values())),
            "version": 1, "season": SEASON,
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
