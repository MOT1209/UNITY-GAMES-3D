# QA strategy

- Every suite is `tests/<name>_validation.tscn`; `tests/run_all.sh <godot>` runs all of them and fails if a suite is not listed.
- Rule: a feature is "IMPLEMENTED" only after its code is inspected and a test passes; otherwise NEEDS_VERIFICATION.
- End-to-end: `phase7_end_to_end_validation` uses real input actions and the real match scene, from kick-off to save and reload.
- Rendering checks (portraits, screenshots) need `xvfb` and `--rendering-driver opengl3`; headless runs skip them.
- Importer: `python3 -m unittest discover -s tools/import_real/tests`.
- Performance: `tools/profile_match.tscn`; numbers from a software renderer must not be quoted as GPU results.
- Each new mechanic gets its own regression test before merge; merge only with the whole suite green.
