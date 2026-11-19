# Youth academy system

## Structure
`Academy` (roster, extended pathway, quality, budget), `AcademyConfig` (age groups U15 / U17 / U19, over-age rules), `TrainingSystem` (weekly academy training), `YouthDevelopment` (league, cups, loans, mentors, knowledge, staff), `PromotionSystem`, `ScoutingSystem`.

## Training and development
* Academy prospects get a development plan like first-team players (`DevelopmentPlans`, detailed targets). `TrainingSystem.focus_for` order: individual focus, the player's plan, the age group's focus.
* Group coaching: `group_bonus` makes a coach assigned to one age group help only that group (tested for U15, U17 and U19).
* **Youth league matches** (`YouthDevelopment._grow`): with the career hooks (`DevelopmentEngine.youth_hooks`) a match trains the attribute of the prospect's plan, boosted by the best of the academy coach and the specialist coach of his age group. Without hooks the older random-attribute behaviour remains (used by direct callers and old tests). Status: implemented + tested.
* Catch-up of long calendar jumps: queued, exactly once (see PLAYER_DEVELOPMENT_ARCHITECTURE.md).

## Rules checked by tests
* Each age-group lineup has only players of its ages (an U15 never plays the U19 league), at most one goalkeeper and one whenever an eligible one exists, never the same player twice, never an injured or suspended player.
* Loan options and accepted loans never go to the prospect's own club.
* Promotion keeps the prospect's attributes and detailed attributes; a promoted player leaves the roster and becomes a first-team player; unknown or already promoted players are rejected.
* A prospect's detailed development and the academy roster survive a save / load.

## Not covered / limits
Youth scouting and recruitment were not re-audited in this pass (only the catch-up of their weeks was fixed and tested); release of over-age prospects exists (`PromotionSystem.release_youth`, confirmed action in the academy screen) but was not re-verified here; loans and mentors are not boosted by the specialist coach; the youth hub screens were not re-audited node by node.
