# Database management tools (database phase 7)

One logic layer, two front ends: `DatabaseTools` (`scripts/systems/tools/database_tools.gd`) is used by the in-game **Database tools** screen (`scripts/ui/screens/database_tools_screen.gd`, navigation entry "Database tools") and by the command line (`tools/db_cli.tscn`). Everything changes or reads the live database; nothing is a mock-up.

## Screen (4 tabs)
- **Clubs (Club Manager)**: search by name/id, filter by country and type (real / fictional / custom), list with crests, club profile (identity, city, founding year, reputation and rating, squad composition and average, finance and status, stadium, crest and its type, rivals), edit supported metadata (`full_name, nickname, city, region, founding_year, description, stadium_name, stadium_capacity, stadium_level, manager_id`; validated, the old value is restored on error; ids, reputation and finances are not editable here), squad list that opens the player.
- **Players (Player Manager)**: search by name or exact id, filter by position, profile (identity, age, nationality, type, position, overall/potential, height/weight marked as estimate when not stored, the 18 detailed attributes, appearance metadata, development history), link to the full player profile.
- **Crests (Crest Manager)**: browse, preview each crest on the home kit and on a player card, assign an alternative crest of the club, create a new alternative design, import a custom image (validated, resized), crest report (count, missing files, problems).
- **Database**: validate (critical errors and warnings), statistics, export a snapshot, import a package (dry-run checkbox, default on), generate fictional clubs into a package file.

## Command line
`godot --headless --path . res://tools/db_cli.tscn -- <command> [world=default|real_2025]`
`validate` (exit 1 on critical errors) · `stats` · `search-club <text>` · `search-player <text>` · `export <file>` · `import <file> [dry]` (exit 1 when refused) · `generate <seed> <per_country> <file>`. Unknown commands exit 2.

## Packages
Snapshot / package format: `{"format": "king_database_snapshot", "version": 1, "teams": [...], "players": [...]}` with the same team and player dictionaries the game saves. Export is deterministic (sorted, no timestamps). Import is all-or-nothing: every record is validated and checked for duplicate or existing ids, squads and clubs must resolve; nothing is added when anything is wrong; a package from a newer version or another format is refused. Generated packages hold fictional clubs outside any league until the user places them.

## Tests
`tests/db_tools_validation.tscn` (85 checks): statistics, validation of the real world and of planted errors, search and filters, profiles, metadata editing, export/import round trip (identical), refusal cases, generation + import, the screen end to end (clubs, players, crests, database tab including real import/export/generate files) and the CLI as a separate process.
