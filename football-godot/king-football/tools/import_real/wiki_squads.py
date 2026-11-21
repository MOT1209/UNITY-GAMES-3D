#!/usr/bin/env python3
"""Current first-team squads from Wikipedia (season 2026-27).

    python3 tools/import_real/wiki_squads.py            # fetch into cache/2026/wiki/ and print a summary
    python3 tools/import_real/wiki_squads.py --offline  # parse the cached copies only

Why Wikipedia: no open dataset covers 2026-27 squads (transfermarkt-datasets stopped on 2026-07-06) and the
official LaLiga / club squad pages are rendered by JavaScript. The "Current squad" section of each club article
is maintained from the club's official website (editors may only add players and numbers once the club has
published them) and carries an `{{updated|<date>}}` stamp, which is kept with the data.

Licence: Wikipedia text is CC BY-SA 4.0. Only facts are taken (name, number, position group, nationality).
"""
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
CACHE = os.path.join(HERE, "cache", "2026", "wiki")
API = "https://en.wikipedia.org/w/api.php"
AGENT = "king-football-importer/1.0 (offline game data build; contact via repository)"

# openfootball club name -> English Wikipedia article
LALIGA_2026 = {
    "Athletic Club": "Athletic Bilbao",
    "CA Osasuna": "CA Osasuna",
    "Club Atlético de Madrid": "Atlético Madrid",
    "Deportivo Alavés": "Deportivo Alavés",
    "Elche CF": "Elche CF",
    "FC Barcelona": "FC Barcelona",
    "Getafe CF": "Getafe CF",
    "Levante UD": "Levante UD",
    "Málaga CF": "Málaga CF",
    "RC Celta de Vigo": "RC Celta de Vigo",
    "RC Deportivo La Coruña": "Deportivo de La Coruña",
    "RCD Espanyol de Barcelona": "RCD Espanyol",
    "Rayo Vallecano de Madrid": "Rayo Vallecano",
    "Real Betis Balompié": "Real Betis",
    "Real Madrid CF": "Real Madrid CF",
    "Real Racing Club de Santander": "Racing de Santander",
    "Real Sociedad de Fútbol": "Real Sociedad",
    "Sevilla FC": "Sevilla FC",
    "Valencia CF": "Valencia CF",
    "Villarreal CF": "Villarreal CF",
}


def api(params):
    params = dict(params, format="json", formatversion="2", maxlag="5")
    url = API + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": AGENT})
    for attempt in range(8):
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                data = json.loads(resp.read().decode("utf8"))
            if data.get("error", {}).get("code") == "maxlag":
                raise IOError("maxlag")
            return data
        except Exception as e:  # 429 / maxlag / transient network errors: wait (Retry-After if given) and retry
            if attempt == 7:
                raise
            wait = 5 * (attempt + 1)
            retry = getattr(e, "headers", None) and e.headers.get("Retry-After")
            if retry and str(retry).isdigit():
                wait = max(wait, int(retry))
            print("  wikipedia: %s, retrying in %ds" % (e, wait), file=sys.stderr)
            time.sleep(wait)


def cache_path(title):
    return os.path.join(CACHE, re.sub(r"[^\w\-]+", "_", title) + ".json")


def wikitext(title, offline=False):
    """(resolved title, revision timestamp, wikitext) of an article, cached on disk."""
    path = cache_path(title)
    batch = cache_path("p_" + title)
    if not os.path.exists(path) and os.path.exists(batch):
        with open(batch, encoding="utf8") as fh:
            d = json.load(fh)
        if not d.get("missing"):
            return d["title"], d["timestamp"], d["text"]
    if offline or os.path.exists(path):
        with open(path, encoding="utf8") as fh:
            d = json.load(fh)
        return d["title"], d["timestamp"], d["text"]
    r = api({"action": "query", "prop": "revisions", "rvprop": "content|timestamp", "rvslots": "main",
             "titles": title, "redirects": "1"})
    page = r["query"]["pages"][0]
    if page.get("missing"):
        raise SystemExit("Wikipedia article not found: %s" % title)
    rev = page["revisions"][0]
    d = {"title": page["title"], "timestamp": rev["timestamp"], "text": rev["slots"]["main"]["content"]}
    os.makedirs(CACHE, exist_ok=True)
    with open(path, "w", encoding="utf8") as fh:
        json.dump(d, fh, ensure_ascii=False)
    time.sleep(0.5)
    return d["title"], d["timestamp"], d["text"]


LINK = re.compile(r"\[\[([^\]|]+)(?:\|([^\]]+))?\]\]")


def strip_markup(s):
    s = re.sub(r"<!--.*?-->", "", s, flags=re.S)
    s = re.sub(r"<br\s*/?>", " ", s, flags=re.I)
    s = re.sub(r"<ref[^>]*/>", "", s)
    s = re.sub(r"<ref[^>]*>.*?</ref>", "", s, flags=re.S)
    s = re.sub(r"\{\{(?:sortname)\|([^|}]+)\|([^|}]+)[^}]*\}\}", r"\1 \2", s, flags=re.I)
    s = LINK.sub(lambda m: m.group(2) or m.group(1), s)
    s = re.sub(r"\{\{[^}]*\}\}", "", s)
    s = re.sub(r"'{2,}", "", s)
    s = re.sub(r"</?[a-z][^>]*>", "", s, flags=re.I)          # remaining HTML tags (<small>, <span>...)
    return re.sub(r"\s+", " ", s).strip()


def template_params(body):
    """Splits `a=1|b=[[x|y]]` on top-level pipes only."""
    out, depth, cur = [], 0, ""
    i = 0
    while i < len(body):
        two = body[i:i + 2]
        if two in ("[[", "{{"):
            depth += 1
            cur += two
            i += 2
            continue
        if two in ("]]", "}}"):
            depth -= 1
            cur += two
            i += 2
            continue
        if body[i] == "|" and depth == 0:
            out.append(cur)
            cur = ""
        else:
            cur += body[i]
        i += 1
    out.append(cur)
    params = {}
    for p in out:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip().lower()] = v.strip()
    return params


def templates(text, name_re):
    """Yields the parameter strings of every `{{name ...}}` call (balanced braces)."""
    for m in re.finditer(r"\{\{\s*(" + name_re + r")\s*\|", text, flags=re.I):
        depth, j = 2, m.end()
        while j < len(text) and depth > 0:
            if text.startswith("{{", j):
                depth += 2
                j += 2
            elif text.startswith("}}", j):
                depth -= 2
                j += 2
            else:
                j += 1
        yield m.start(), text[m.end():j - 2]


def current_squad_section(text):
    """Text from the 'Current squad' heading up to the first `{{Fs end}}` after it."""
    m = re.search(r"^=+\s*(?:Current|First[- ]team)\s+squad\s*=+\s*$", text, flags=re.I | re.M)
    if not m:
        m = re.search(r"^=+\s*Players\s*=+\s*$", text, flags=re.I | re.M)
    if not m:
        return None
    end = re.search(r"\{\{\s*Fs end\s*(?:\|[^}]*)?\}\}", text[m.end():], flags=re.I)
    return text[m.end(): m.end() + end.end()] if end else None


def parse_squad(section):
    players = []
    for _pos, body in templates(section, r"Fs player"):
        p = template_params(body)
        raw = p.get("name", "")
        link = LINK.search(raw)
        article = link.group(1).strip() if link else ""
        name = strip_markup(raw)
        if not name:
            continue
        no = re.sub(r"\D", "", p.get("no", ""))
        players.append({"no": int(no) if no else 0, "pos": p.get("pos", "").upper(), "nat": p.get("nat", "").upper(),
                        "name": name, "article": article, "other": strip_markup(p.get("other", ""))})
    return players


def updated_stamp(section):
    m = re.search(r"\{\{\s*updated\s*\|([^}]+)\}\}", section, flags=re.I)
    return m.group(1).split("|")[0].strip() if m else ""


def infobox(text):
    """Selected fields of an article's football infobox (club or person)."""
    for _pos, body in templates(text, r"Infobox (?:football biography|football club)"):
        return {k: v for k, v in template_params(body).items()}
    return {}


def club_squad(of_name, offline=False):
    title, ts, text = wikitext(LALIGA_2026[of_name], offline)
    section = current_squad_section(text)
    if section is None:
        raise SystemExit("%s: no current-squad section" % title)
    # Some clubs keep the squad on a transcluded page ({{:Page}} or a template).
    if not re.search(r"Fs player", section, flags=re.I):
        raise SystemExit("%s: squad section has no Fs player rows" % title)
    box = infobox(text)
    return {"club": of_name, "article": title, "revision": ts, "updated": updated_stamp(section),
            "manager": strip_markup(box.get("manager", box.get("head coach", ""))),
            "ground": strip_markup(box.get("ground", box.get("stadium", ""))),
            "capacity": strip_markup(box.get("capacity", "")),
            "players": parse_squad(section)}


def people(titles, offline=False):
    """Article title -> {"title", "timestamp", "text"} for many articles (50 per request, cached)."""
    out, todo = {}, []
    for t in titles:
        path = cache_path("p_" + t)
        if os.path.exists(path):
            with open(path, encoding="utf8") as fh:
                out[t] = json.load(fh)
        elif not offline:
            todo.append(t)
    for i in range(0, len(todo), 50):
        chunk = todo[i:i + 50]
        r = api({"action": "query", "prop": "revisions", "rvprop": "content|timestamp", "rvslots": "main",
                 "titles": "|".join(chunk), "redirects": "1"})
        q = r["query"]
        back = {}
        for n in q.get("normalized", []):
            back[n["to"]] = n["from"]
        for rd in q.get("redirects", []):
            back[rd["to"]] = back.get(rd["from"], rd["from"])
        for page in q["pages"]:
            src = back.get(page["title"], page["title"])
            d = {"title": page["title"], "missing": bool(page.get("missing")), "timestamp": "", "text": ""}
            if not d["missing"]:
                rev = page["revisions"][0]
                d["timestamp"], d["text"] = rev["timestamp"], rev["slots"]["main"]["content"]
            out[src] = d
            with open(cache_path("p_" + src), "w", encoding="utf8") as fh:
                json.dump(d, fh, ensure_ascii=False)
        time.sleep(1.0)
    return out


MONTHS = {m: i + 1 for i, m in enumerate(["january", "february", "march", "april", "may", "june", "july", "august",
                                           "september", "october", "november", "december"])}


def birth_date(raw):
    """ISO date from `{{birth date and age|2003|5|3}}` (any argument order variant) or plain text."""
    m = re.search(r"\{\{\s*birth[ _]date(?: and age)?2?\s*\|([^}]*)\}\}", raw, flags=re.I)
    if m:
        parts = [x.strip() for x in m.group(1).split("|") if x.strip() and "=" not in x]
        vals = []
        for x in parts[:3]:
            if x.isdigit():
                vals.append(int(x))
            elif x.lower() in MONTHS:
                vals.append(MONTHS[x.lower()])
        if len(vals) == 3 and vals[0] > 1000:
            return "%04d-%02d-%02d" % (vals[0], vals[1], vals[2])
    m = re.search(r"(\d{1,2}) (\w+) (\d{4})", strip_markup(raw))
    if m and m.group(2).lower() in MONTHS:
        return "%s-%02d-%02d" % (m.group(3), MONTHS[m.group(2).lower()], int(m.group(1)))
    m = re.search(r"(\w+) (\d{1,2}), (\d{4})", strip_markup(raw))
    if m and m.group(1).lower() in MONTHS:
        return "%s-%02d-%02d" % (m.group(3), MONTHS[m.group(1).lower()], int(m.group(2)))
    return ""


def height_cm(raw):
    m = re.search(r"\{\{\s*(?:height|convert)\s*\|\s*(?:m\s*=\s*)?([12][.,]\d{1,2})", raw, flags=re.I)
    if m:
        return int(round(float(m.group(1).replace(",", ".")) * 100))
    m = re.search(r"([12][.,]\d{2})\s*m\b", strip_markup(raw))
    if m:
        return int(round(float(m.group(1).replace(",", ".")) * 100))
    m = re.search(r"\b(1[5-9]\d|20\d)\s*cm\b", strip_markup(raw))
    return int(m.group(1)) if m else 0


def person(d):
    """Facts from a footballer's infobox, or None when the article is missing / not a footballer."""
    if not d or d.get("missing"):
        return None
    box = {}
    for _pos, body in templates(d["text"], r"Infobox football biography"):
        box = template_params(body)
        break
    if not box:
        return None
    return {"article": d["title"], "revision": d["timestamp"],
            "full_name": strip_markup(box.get("full_name", box.get("fullname", ""))),
            "birth_date": birth_date(box.get("birth_date", "")),
            "height_cm": height_cm(box.get("height", "")),
            "position": strip_markup(box.get("position", "")),
            "current_club": box.get("currentclub", box.get("current_club", "")),
            "club_number": re.sub(r"\D", "", strip_markup(box.get("clubnumber", box.get("club_number", ""))))}


def all_squads(offline=False):
    return {n: club_squad(n, offline) for n in sorted(LALIGA_2026)}


if __name__ == "__main__":
    off = "--offline" in sys.argv
    squads = all_squads(off)
    total = 0
    for n, s in squads.items():
        total += len(s["players"])
        numbered = sum(1 for p in s["players"] if p["no"])
        print("%-30s %2d players (%2d numbered) updated=%-18s rev=%s manager=%s | %s" % (
            n, len(s["players"]), numbered, s["updated"], s["revision"][:10], s["manager"], s["ground"]))
    print("total", total)
