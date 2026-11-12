# Audio

`audio/match/` holds four sounds generated with Higgsfield (model `mirelo_text_to_audio`, 2026-11-12) from text prompts:
`crowd_ambience.mp3` (10 s loop), `crowd_cheer.mp3`, `crowd_groan.mp3` (5 s each) and `whistle.mp3` (2 s). They are original generated
sounds, not recordings of a real match. `MatchSounds` plays them from real match events; without the files the game falls back to
the synthesized `CrowdAudio`. Not included: club chants, commentary, music, menu sounds.
