# Crests of the fictional clubs

`fictional/<club id>.png` - eight original emblems (512 x 512, transparent outside the shield) for the eight fictional clubs of the default world.
Generated with Higgsfield (model `z_image`, 2026-11-12) from text prompts that describe a made-up emblem in each club's colours
(no real club, name or logo was referenced); the background was removed locally. Each club's `logo` field in `data/clubs/<id>.json` points at its file,
so `LogoService.resolve()` shows the artwork, and the crest registry of the database branch uses the club's own logo first.
A contact sheet is in `docs/qa/fictional_crests.png`.

Known limits: the artwork is raster, so very small sizes (< 40 px) lose detail; the edge of some emblems keeps a faint soft shadow from the source image;
the 198 clubs of the real data pack still use the procedural crests (generating them with an image model would need about 30 credits and would risk
resembling real clubs).
Regenerating: the same prompts with the same model will not give identical images.
