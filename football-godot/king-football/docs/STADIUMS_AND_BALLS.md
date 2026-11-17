# Stadiums and match balls

## Stadiums
`StadiumCatalog` (`scripts/environment/stadium_catalog.gd`) lists five grounds:

| id | name | look |
|---|---|---|
| `arena` | King Arena | the original Blender stadium (`stadium.glb`) |
| `crescent_bowl` | Crescent Bowl | open two-tier bowl, teal / white sections, LED ribbon, light crown ring |
| `old_fortress` | Old Fortress | four separate two-tier stands with roofs, open corners, red brick, corner floodlight pylons |
| `riverside_park` | Riverside Park | small community ground: covered main stand, open terrace, grass banks behind the goals |
| `desert_dome` | Desert Dome | closed two-tier ring, sand facade, amber LED ribbon, roof ring with an open centre |

The four new grounds are **shells**: `tools/stadium_gen/build_stadiums.py` (plain Python, no dependencies) writes
`assets/models/stadium/shells/<id>.glb`. `StadiumArena.shell` loads the base `stadium.glb`, removes its stands, roof,
facade and screens (`SHELL_REPLACES`) and adds the shell. Pitch, goals, ad boards, dugouts, tunnel, plaza, ground
and every `COL_` / `TRIGGER_` / `SPAWN_` helper come from the base, so **gameplay is identical** in every stadium.

Rules the shapes follow (checked by `tests/stadiums_validation`): nothing solid or visible in the broadcast camera's
sightline on the +x side, a sloped `COL_Shell_Stands` surface the crowd is placed on, no spectator on the pitch.

Selection: match setup screen ("Home team's stadium" or any stadium). League / cup fixtures use `"home"`: a club's
`stadium_id` when it names a catalogue stadium, otherwise a stable pick from the club id.

Rebuild after changing a design:

    python3 tools/stadium_gen/build_stadiums.py
    godot --headless --path . --import
    xvfb-run godot --path . --rendering-driver opengl3 res://tools/stadium_gen/stadium_shots.tscn -- /tmp/shots

## Match balls
`BallCatalog` (`scripts/ball/ball_catalog.gd`), cosmetic only (same physics): classic, gold, winter (orange),
retro leather, street, night glow. `BallVisual.apply_style()` changes colours, panel size and glow of the procedural
pattern. Chosen on the match setup screen; saved with the match (`MatchSetup.ball_id`, old saves -> classic).
