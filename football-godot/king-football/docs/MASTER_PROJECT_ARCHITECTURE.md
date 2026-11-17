# Master project architecture

The logical modules of the master prompt are mapped to the real folders. No files are moved.

| Logical module | Real location |
|---|---|
| Core | `scripts/core` (Loc, GameManager, TeamDB, SaveManager, ErrorText), `scripts/ui/app_hub.gd` (AppHub) |
| MatchEngine | `scripts/systems/match`, `scripts/ball`, `scripts/player`, `scripts/gameplay` |
| FootballAI | `systems/match/{player_ai,team_ai,manager_ai,ai_intent}.gd`, `scripts/teams/team_goalkeeper.gd` |
| Tactics | `scripts/teams` (formations, presets) |
| Players | `scripts/data`, `scripts/players` |
| Teams | `scripts/systems/teams`, `scripts/systems/squads` |
| Career / YouthAcademy / Transfers / Finance | `scripts/systems/{career,academy,scouting,promotion,transfers,finance,training}` |
| Competitions / WorldSimulation | `scripts/systems/competitions` (`league_pyramid`, `match_simulator`) |
| Stadium | `scripts/environment` |
| Presentation | `scripts/ui`, `scripts/camera` |
| Tests | `tests/` |

## Rules kept
- `PlayerData` is the single source of truth; cards, profiles, squads and stats read it by stable player id. No create-player feature.
- Matches play on copies (`MatchSetup.duplicate_for_match`), so career data changes only through the finished-match report.
- `MatchState` owns `MatchStats`; `MatchManager` wires gameplay signals into it; results are processed once.
- Saves are versioned and validated; club kit colours are never replaced by KING colours.

## Target gaps
An `EventBus` autoload does not exist (signals are used directly); introduce one only if a real coupling problem appears.
