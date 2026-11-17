"""Importer tests (stdlib unittest). Run: python3 -m unittest discover -s tools/import_real/tests"""
import json
import os
import random
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import build_pack as bp  # noqa: E402
from realdata import match_clubs, norm, season_teams, slug  # noqa: E402

CACHE = bp.CACHE
HAS_CACHE = os.path.exists(os.path.join(CACHE, "players.csv.gz"))


class Helpers(unittest.TestCase):
    def test_norm_and_slug(self):
        self.assertEqual(norm("Brighton & Hove Albion"), "brighton and hove albion")
        self.assertEqual(norm("Atlético de Madrid"), "atletico madrid")
        self.assertEqual(norm("Real Betis Balompié"), norm("Real Betis"))
        self.assertEqual(slug("Córdoba CF"), "cordoba_cf")

    def test_match_clubs_exact_contains_alias_and_unmatched(self):
        tm = [{"name": "Liverpool FC"}, {"name": "Celta de Vigo"}, {"name": "Athletic Bilbao"}]
        m, u = match_clubs(["Liverpool", "RC Celta", "Athletic Club", "Nowhere"], tm, {"Athletic Club": "Athletic Bilbao"})
        self.assertEqual(m["Liverpool"]["name"], "Liverpool FC")
        self.assertEqual(m["RC Celta"]["name"], "Celta de Vigo")
        self.assertEqual(m["Athletic Club"]["name"], "Athletic Bilbao")
        self.assertEqual(u, ["Nowhere"])

    def test_season_teams_both_formats(self):
        txt = ("= League\n▪ Matchday 1\n  Fri Aug 8 2025\n"
               "    20:00  Birmingham City FC      v Ipswich Town FC          1-1 (0-0)\n"
               "  19:00   Liverpool  4-2 (1-0)  Bournemouth   \n"
               "                  (Hugo EKITIKE 37')\n")
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False, encoding="utf8") as fh:
            fh.write(txt)
        try:
            self.assertEqual(season_teams(fh.name), ["Birmingham City FC", "Bournemouth", "Ipswich Town FC", "Liverpool"])
        finally:
            os.remove(fh.name)

    def test_overall_matches_gdscript_rounding(self):
        self.assertEqual(bp.gd_round(2.5), 3)
        self.assertEqual(bp.gd_round(-2.5), -3)
        a = {"pace": 70, "shooting": 80, "passing": 60, "dribbling": 75, "defending": 30, "physical": 70, "goalkeeping": 10}
        self.assertEqual(bp.overall(a, "ST"), bp.gd_round(80 * .4 + 70 * .2 + 75 * .15 + 70 * .2 + 60 * .05))

    def test_attributes_hit_target_and_are_deterministic(self):
        for pos in bp.POSITIONS:
            for target in (50, 70, 88):
                a1 = bp.build_attributes(target, pos, random.Random(7))
                a2 = bp.build_attributes(target, pos, random.Random(7))
                self.assertEqual(a1, a2)
                self.assertEqual(bp.overall(a1, pos), target, (pos, target))
                self.assertTrue(all(1 <= v <= 99 for v in a1.values()))

    def test_potential_never_below_overall(self):
        rng = random.Random(1)
        for age in range(16, 40):
            for ovr in (50, 75, 94):
                self.assertGreaterEqual(bp.potential_for(age, ovr, rng, 1.0), ovr)

    def test_generated_squad_rules(self):
        s = bp.generated_squad("eng_test", "England", 68)
        self.assertEqual(s, bp.generated_squad("eng_test", "England", 68))
        self.assertGreaterEqual(sum(1 for p in s if p["position"] == "GK"), 2)
        self.assertEqual(len({p["name"] for p in s}), len(s))
        self.assertEqual(len({p["shirt_number"] for p in s}), len(s))


@unittest.skipUnless(HAS_CACHE, "run fetch.py first")
class FullBuild(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.leagues, cls.clubs, cls.report = bp.build(write=False)

    def test_division_sizes_and_membership(self):
        sizes = {d["id"]: len(d["team_ids"]) for lg in self.leagues.values() for d in lg["divisions"]}
        self.assertEqual(sizes, {"eng_d1": 20, "eng_d2": 24, "esp_d1": 20, "esp_d2": 22, "ger_d1": 18, "ger_d2": 18,
                                 "ita_d1": 20, "ita_d2": 20, "fra_d1": 18, "fra_d2": 18})
        all_ids = [t for lg in self.leagues.values() for d in lg["divisions"] for t in d["team_ids"]]
        self.assertEqual(len(all_ids), len(set(all_ids)))
        self.assertEqual(set(all_ids), set(self.clubs))

    def test_squads_valid(self):
        ids = set()
        for team_id, c in self.clubs.items():
            ps = c["players"]
            self.assertTrue(18 <= len(ps) <= 30, team_id)
            self.assertGreaterEqual(sum(1 for p in ps if p["position"] == "GK"), 2, team_id)
            self.assertEqual(len({p["shirt_number"] for p in ps}), len(ps), team_id)
            self.assertLessEqual(len(c["team"]["short_name"]), 5)
            for p in ps:
                self.assertNotIn(p["id"], ids)
                ids.add(p["id"])
                self.assertTrue(14 <= p["age"] <= 50)
                self.assertGreaterEqual(p["potential"], bp.overall(p, p["position"]), p["id"])

    def test_first_tier_is_real_second_tier_generated(self):
        for c in self.clubs.values():
            tier1 = c["team"]["competitions"][0].endswith("_d1")
            self.assertEqual(c["players_source"], "transfermarkt-datasets" if tier1 else "generated")

    def test_more_valuable_means_higher_rated(self):
        real = [p for c in self.clubs.values() if c["players_source"] != "generated" for p in c["players"]
                if 24 <= p["age"] <= 30]
        hi = [bp.overall(p, p["position"]) for p in real if p["transfer_value"] >= 60_000_000]
        lo = [bp.overall(p, p["position"]) for p in real if p["transfer_value"] <= 3_000_000]
        self.assertGreater(min(hi), max(lo) - 5)
        self.assertGreater(sum(hi) / len(hi), sum(lo) / len(lo) + 10)

    def test_relegation_playoffs_defined(self):
        for key in ("germany", "france"):
            d2 = self.leagues[key]["divisions"][1]
            self.assertEqual(d2["playoff"]["vs_upper"], 16, key)
            self.assertEqual(self.leagues[key]["divisions"][0]["relegate"], 2, key)
        self.assertEqual(self.leagues["italy"]["divisions"][1]["playoff"], {"from": 3, "to": 8, "spots": 1})

    def test_reserve_team_rule_recorded(self):
        self.assertEqual(self.leagues["spain"]["reserves"], {"esp_real_sociedad_b": "esp_real_sociedad"})

    def test_build_is_deterministic(self):
        _l, clubs2, _r = bp.build(write=False)
        self.assertEqual(json.dumps(self.clubs, sort_keys=True), json.dumps(clubs2, sort_keys=True))


if __name__ == "__main__":
    unittest.main()
