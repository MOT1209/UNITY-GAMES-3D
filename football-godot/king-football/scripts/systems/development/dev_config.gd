class_name DevConfig
extends RefCounted

## KING Player Development System: every balance number of the development ecosystem lives HERE (formulas in the other scripts only
## read these constants). Ratings of coaches use the same 1..20 scale as `StaffTeam` skills; players keep their 1..99 attributes.
## Nothing in this file is random: all randomness elsewhere is seeded (see DevelopmentEngine / CoachingStaff).

const STATE_VERSION := 1

# --- coaching departments --------------------------------------------------------------------------------------------
const DEPARTMENTS: Array[String] = ["attacking", "midfield", "defensive", "goalkeeping", "fitness", "tactical"]
## Player attributes (PlayerData.ATTRIBUTES) each department trains. The tactical coach has no attribute of his own: he adds a small
## bonus to everything (see TACTICAL_SHARE).
const DEPT_ATTRIBUTES := {
	"attacking": ["shooting", "dribbling", "pace"],
	"midfield": ["passing", "dribbling"],
	"defensive": ["defending", "physical"],
	"goalkeeping": ["goalkeeping"],
	"fitness": ["physical", "pace"],
	"tactical": ["passing", "defending"],
}
## Which department leads the training of an attribute (first match wins).
const ATTRIBUTE_LEAD := {"shooting": "attacking", "dribbling": "attacking", "pace": "fitness", "passing": "midfield",
		"defending": "defensive", "physical": "fitness", "goalkeeping": "goalkeeping"}
## Coach specialisations per department (text keys DEV_SPEC_<UPPER>), each tied to the attribute it favours.
const SPECIALISATIONS := {
	"attacking": {"finishing": "shooting", "wing_play": "dribbling", "movement": "pace"},
	"midfield": {"passing": "passing", "playmaking": "dribbling", "ball_control": "passing"},
	"defensive": {"tackling": "defending", "aerial": "physical", "marking": "defending"},
	"goalkeeping": {"shot_stopping": "goalkeeping", "distribution": "goalkeeping", "handling": "goalkeeping"},
	"fitness": {"conditioning": "physical", "speed": "pace", "recovery": "physical"},
	"tactical": {"positioning": "defending", "build_up": "passing", "pressing": "defending"},
}

# --- coach quality ---------------------------------------------------------------------------------------------------
const RATING_MIN := 1
const RATING_MAX := 20
## Star thresholds on the 1..20 overall (1: 1-4, 2: 5-8, 3: 9-12, 4: 13-16, 5: 17-20).
const STAR_STEP := 4
const STAR_KEYS: Array[String] = ["DEV_STAR_1", "DEV_STAR_2", "DEV_STAR_3", "DEV_STAR_4", "DEV_STAR_5"]
## Training multiplier of one coach: VACANT without a coach, MIN_COACH for a rating-1 coach .. MAX_COACH for a rating-20 coach.
const VACANT_MULT := 0.85
const MIN_COACH_MULT := 0.92
const MAX_COACH_MULT := 1.12
const SECOND_COACH_BONUS := 0.02             # each extra coach of the same department adds at most this
const DEPT_MULT_CAP := 1.15
const SPECIALISATION_BONUS := 0.02           # coach specialisation matches the trained attribute
const TACTICAL_SHARE := 0.25                 # share of the tactical coach's bonus/malus applied to every attribute
## Weights of the coach's ratings in his effective rating (sum 1.0); the last term is youth OR professional ability.
const W_OVERALL := 0.50
const W_TECHNICAL := 0.20
const W_TACTICAL := 0.10
const W_DEVELOPMENT := 0.20

# --- staff capacity, money ---------------------------------------------------------------------------------------------
const TOTAL_SLOTS_BASE := 6                  # + 1 per training facility level above 1
const DEPT_CAP_BASE := 1                     # coaches per department at facility level 1..2
const DEPT_CAP_LEVEL3 := 2                   # facility level 3..4
const DEPT_CAP_LEVEL5 := 3                   # facility level 5
const WAGE_BASE := 800
const WAGE_QUAD := 12                        # weekly wage demand = WAGE_BASE + overall^2 * WAGE_QUAD, scaled by reputation
const WAGE_REPUTATION_SCALE := 0.004         # +0.4 % per reputation point (reputation 0..100 -> up to +40 %)
const SIGNING_WEEKS := 4                     # signing bonus = this many weeks of the wage
const DISMISS_WEEKS_PER_YEAR := 8            # compensation weeks per remaining contract year
const DISMISS_WEEKS_MIN := 4
const DISMISS_WEEKS_MAX := 32
const CONTRACT_MIN_YEARS := 1
const CONTRACT_MAX_YEARS := 5
const MARKET_PER_DEPT := 3                   # candidates kept per department
const MARKET_REFRESH_WEEKS := 4
const MARKET_MAX_AGE_WEEKS := 20             # a candidate nobody hires leaves the market (finds another job)
const EXPIRY_WARNING_SEASONS := 1            # warn when this many seasons remain

# --- development plans & weekly calculation ------------------------------------------------------------------------------
const PLAN_SWITCH_ADAPTATION_WEEKS := 3      # after a plan change the first weeks are less effective ...
const PLAN_SWITCH_ADAPTATION := 0.60         # ... by this factor (changing plans is never free)
const CONSISTENCY_FULL_WEEKS := 10           # weeks on one plan for the full consistency bonus
const CONSISTENCY_MIN := 0.92
const CONSISTENCY_MAX := 1.06
const FOCUS_SPREAD := 0.12                   # extra total points per additional target attribute (small: spreading is not free)
const FOCUS_SPREAD_CAP := 1.35
const CONVERSION_WEEKS := 16                 # position conversion plan length
const LONG_TERM_RATE := 0.85                 # long-term plan: slower now ...
const LONG_TERM_FATIGUE := 0.75              # ... gentler on the body ...
const LONG_TERM_BONUS_WEEKS := 26            # ... and a bonus once it has run this long
const LONG_TERM_BONUS := 1.10
const INTENSITY_DEFAULT := 0.6
const SEASON_ATTR_CAP_YOUNG := 6             # max attribute points gained per attribute and season through the weekly engine (age <= 21)
const SEASON_ATTR_CAP_PRIME := 3             # age 22..29
const SEASON_ATTR_CAP_OLD := 1               # age >= 30
const OLD_AGE := 30
const SEASON_WEEKS := 46
const ENGINE_SCALE := 0.6                    # global damping of the weekly engine (the yearly PlayerLifecycle growth still exists)

# --- match experience -------------------------------------------------------------------------------------------------
const MATCH_POINTS := 0.10                   # attribute points a full appearance adds to the plan attributes (before age / headroom)
const MATCH_RATING_BASE := 6.5
const MATCH_RATING_SCALE := 0.15             # +15 % per rating point above the base (capped)
const MATCH_RATING_CAP := 1.3
const BENCH_UNUSED_FACTOR := 0.0             # no appearance, no match experience
const LOW_PLAYTIME_WEEKS := 8                # warn about a young player (<= 21) without a game for this many weeks

# --- workload, fatigue, injuries ----------------------------------------------------------------------------------------
const FITNESS_SWING := 4.0                   # fitness points per week an individual plan intensity moves fitness: (0.5 - intensity) * swing
const FATIGUE_WARN_FITNESS := 55
const FATIGUE_EXCESS_FITNESS := 40           # below this training stops helping at all
## Training-caused injury risk ON TOP of the match / weekly baseline of `Availability` (a moderate plan adds nothing).
const INJURY_OVERLOAD_START := 0.6           # plan intensity above this adds risk
const INJURY_OVERLOAD_SLOPE := 0.03          # weekly chance added at intensity 1.0 per unit above the start (0.4 * 0.03 = 1.2 %)
const INJURY_FATIGUE_SLOPE := 0.0008         # added weekly chance per fitness point below FATIGUE_WARN_FITNESS
const INJURY_MAX_WEEKLY := 0.05
const INJURY_MIN_WEEKS := 1
const INJURY_MAX_WEEKS := 6

# --- youth ---------------------------------------------------------------------------------------------------------------
const YOUTH_CATCH_UP_MAX_WEEKS := 60         # weeks of youth / academy development processed in one calendar jump (safety cap)
const READY_OVERALL_MARGIN := 4              # a prospect is "ready for promotion" within this many points of the squad's weakest regular
const SNAPSHOT_EVERY_WEEKS := 4
const HISTORY_MAX := 60
const NOTIFY_MAX := 80
const ACTIVITY_MAX := 60


static func stars(overall: int) -> int:
	return clampi(1 + (clampi(overall, RATING_MIN, RATING_MAX) - 1) / STAR_STEP, 1, 5)


static func star_key(overall: int) -> String:
	return STAR_KEYS[stars(overall) - 1]


static func dept_cap(training_level: int) -> int:
	if training_level >= 5:
		return DEPT_CAP_LEVEL5
	if training_level >= 3:
		return DEPT_CAP_LEVEL3
	return DEPT_CAP_BASE


static func total_slots(training_level: int) -> int:
	return TOTAL_SLOTS_BASE + maxi(training_level - 1, 0)


static func season_attr_cap(age: int) -> int:
	if age >= OLD_AGE:
		return SEASON_ATTR_CAP_OLD
	if age >= 22:
		return SEASON_ATTR_CAP_PRIME
	return SEASON_ATTR_CAP_YOUNG


static func stars_text(overall: int) -> String:
	return "★".repeat(stars(overall)) + "☆".repeat(5 - stars(overall))
