# QA strategy

- Every suite is `tests/<name>_validation.tscn`; `tests/run_all.sh <godot>` runs all of them and fails if a suite is not listed.
- Rule: a feature is "IMPLEMENTED" only after its code is inspected and a test passes; otherwise NEEDS_VERIFICATION.
- End-to-end: `phase7_end_to_end_validation` uses real input actions and the real match scene, from kick-off to save and reload.
- Rendering checks (portraits, screenshots) need `xvfb` and `--rendering-driver opengl3`; headless runs skip them.
- Importer: `python3 -m unittest discover -s tools/import_real/tests`.
- Performance: `tools/profile_match.tscn`; numbers from a software renderer must not be quoted as GPU results.
- Each new mechanic gets its own regression test before merge; merge only with the whole suite green.

## Run time
`tests/run_all.sh` now takes about 13 minutes: `career_longevity_validation` (12 simulated seasons) alone needs about 6 minutes, so
`SUITE_TIMEOUT` defaults to 600 s per suite. Run single suites while developing:
`godot --headless --path . res://tests/<name>.tscn`.

## Suites added after Phase 7
match_rules (33), match_restarts (27), phase8_tactics (20), phase9_manager (25), phase10_finance (22), phase11_world (30),
phase12_awards (29), phase13_presentation (40).
