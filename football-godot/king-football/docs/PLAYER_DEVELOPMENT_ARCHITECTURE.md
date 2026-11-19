# Player development architecture

Status words: **implemented + tested** (a suite checks it), **implemented, not tested** (code exists, no dedicated check), **not implemented**.

## Layers
| Layer | Files | Status |
|---|---|---|
| Broad attributes (7) - the only inputs of the match engine and `get_overall` | `scripts/data/player_data.gd` | implemented + tested |
| Detailed attributes (40, stored lazily, one broad parent each) | `scripts/data/detailed_attributes.gd` | implemented + tested (`detailed_attributes_validation`, 47 checks) |
| Weekly engine (plans, match experience, sessions, fatigue, injuries, season caps) | `scripts/systems/development/development_engine.gd` | implemented + tested (`player_development_validation`) |
| Plans (templates, roles, custom, balanced, conversion, long term) | `development_plans.gd` | implemented + tested |
| Coaching staff | `coaching_staff.gd` (see COACHING_STAFF_SYSTEM.md) | implemented + tested |
| Academy training / matches | `training_system.gd`, `youth_development.gd` (see YOUTH_ACADEMY_SYSTEM.md) | implemented + tested |
| Calendar catch-up | `sync` functions of the engine, `TrainingSystem`, `YouthDevelopment`, `ScoutingSystem` | implemented + tested |
| Screens | `dev_hub_screen`, `dev_analytics_screen`, `training_center_screen`, `coaching_staff_screen`, `coach_recruitment_screen`, `youth_hub_screen` | partly tested (see below) |

## Detailed attributes and the match engine
The match engine keeps reading the seven broad attributes. Every detailed attribute has exactly one broad parent (`DetailedAttributes.CATALOG`; `positioning` follows the player's position), so a point is never counted twice.
* **Lazy storage.** `PlayerData.detail` is empty until a detailed attribute is first trained or a plan is assigned (`DetailedAttributes.ensure`). An untouched player reports derived values (broad value + a stable per-player offset of at most 6), so existing players, data packs and saves need no migration and the overall rating never changes when details are created.
* **Detail -> broad.** Training a detailed attribute adds 1 to it and 1/Z of a point to its parent (Z = number of details sharing that parent), i.e. the broad attribute follows the average of its details. A point that would push the overall past potential is refused (progress parked at 0.99).
* **Broad -> detail.** A change of a broad attribute by any other route (legacy broad training, yearly ageing, lifecycle, academy) moves every detail under it by the same amount, through the `PlayerData` setters.
* **Goalkeeping details** exist for goalkeepers only; outfield players never show or train them.
* **Load safety.** Unknown names are dropped, values are clamped to 1..99, missing names are completed with derived values (`sanitize`, `complete`, `validate`).

## Weekly development of a first-team player (`DevelopmentEngine._first_team_week`)
1. Plan clock and consistency; weights per target (detailed names, or broad names in plans from old saves).
2. Points per target = `ProgressionModel.weekly_points` x coaching multiplier (`CoachingStaff.attribute_multiplier`) x consistency x focus spread x weight x `DevConfig.ENGINE_SCALE`.
3. Match experience: only if minutes were played since the last processed week; scaled by rating, age and headroom.
4. Scheduled sessions: extra points per session, fatigue per session, overload injury risk.
5. Plan intensity moves fitness; training-caused injury risk is added on top of the baseline.
6. Season gain caps per attribute and age band; notifications and plan cycles.

## Calendar catch-up
`DevelopmentEngine.sync`, `TrainingSystem.sync_to_calendar`, `YouthDevelopment.sync` and `ScoutingSystem.sync_to_calendar` advance their persisted "last processed week" one week at a time, only over weeks really processed. `DevConfig.CATCH_UP_BATCH_WEEKS` (60) bounds one call; the remainder stays queued (`pending_weeks`) and is resumed by the next call, also after a save / load. Nothing is dropped and no week is processed twice (tested for 10 / 60 / 100 / 200-week jumps and a save in the middle of a queue).

## Persistence
`DevConfig.STATE_VERSION` = 2 (1 = broad plans). Old states load, keep their week pointer, sessions, plan clocks and the legacy `skipped` counter; plans upgrade on first use (`DevelopmentPlans._upgrade`), players when their details are first needed. Tested with a version-1 state.

## Known limits
* The parent split of the detailed attributes is a fixed design choice, not tuned on real football data.
* The academy training screen still offers the seven broad categories (the engine accepts detailed focuses).
* Loan and mentor growth in the academy are not boosted by the specialist coach.
