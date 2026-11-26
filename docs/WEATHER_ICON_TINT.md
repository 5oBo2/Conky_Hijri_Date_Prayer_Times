# Weather icons — source-faithful native Cairo vectors

## The design contract

**The original 20 `assets/weather/*.png` images are the source of truth.**
The current renderer reproduces their actual silhouette contours, not
procedurally drawn generic clouds/suns/moons. Preserve the original different
cloud shapes, including the TWO nested/overlapping clouds in `26.png`, their
occlusion boundaries, all sun/moon arcs and rays, and precipitation marks.

All conditions are rendered by `lib/Weather_Icons.lua` from generated native
Cairo fill paths in `lib/Weather_Icon_Paths.lua`. At runtime there is **no PNG
loading, painting, masking, filtering, Pillow or OpenCV**. No opaque wallpaper
color is painted behind clouds: the widgets remain transparent.

The source PNGs are kept unchanged for regeneration and reference. The old
`tint-neutral/`, `tint-celestial/` derived PNGs and their runtime masking path
are obsolete and removed. Do not reintroduce them.

## Original artwork and IDs

Exactly these 20 source IDs are traced:

`0, 5, 6, 9, 13, 14, 17, 20, 26, 29, 30, 31, 32, 33, 34, 37, 41, 45, 46, 47`.

- Sun-only: `32`; moon-only: `31`.
- Sun + clouds / precipitation: `30, 34, 37, 41`.
- Moon + clouds / precipitation: `29, 33, 45, 46, 47`.
- Neutral weather-only: all other IDs, including two-cloud `26`.

The WMO-to-icon mapping remains in `lib/Weather_Icons.lua`, unchanged.
Both `widgets/Weather.lua` and `widgets/Hijri_Date.lua` use the shared
`Weather_Icons.draw(cr, id, x, y, size)` entrypoint.

## Color policy

- Source-traced **sun and moon** paths use `appearance.next_prayer_color`,
  by default `#efb46f` (gold).
- Clouds, stars/snowflakes, rain, lightning, fog and temperature remain white.
- A different valid `#RRGGBB` (for example `#1296a5`) changes only the celestial
  paths in these icons; it also changes other deliberately shared prayer/Hijri
  accents elsewhere in the suite.
- Restart via `python3 restart.py` to load a new setting; no geometry or asset
  regeneration is required.

## How the paths preserve the assets

The offline authoring script `tools/trace_weather_png_to_cairo.py` reads the
original 256x256 PNG images. Their white-ink intensity (original alpha multiplied
by original white/gray pixel intensity) is traced at five brightness thresholds,
with subpixel contours and slight simplification. Cairo draws the nested
**even-odd filled contours**, from the soft outer bands to the opaque core.
The coordinates are corrected by half a pixel to match PNG pixel centers to
Cairo's pixel-edge coordinate system.

The celestial path regions come from the clear `31.png` moon and `32.png` sun
aligned onto each compound image using measured affine transforms in the
script's `CELESTIAL` table. Only **visible pixels already present in the
original art** are traced. That matters for cloud overlap: there are no
independent hidden sun/moon strokes to accidentally show through a cloud.

### Source-faithful cloud/celestial overlap order (2026-11-26 refinement)

Nine compound contact icons (`29`, `30`, `33`, `34`, `37`, `41`, `45`,
`46`, `47`) use a source-derived drawing order rather than a single global
color boundary. All nine are emitted as three contour groups: `n` (neutral
white), `c` (visible celestial stroke in `appearance.next_prayer_color`), and
`f` (foreground white cloud), rendered in that exact order.

There are two source-art overlap patterns:

- `29`, `33`, and `34` contain one cloud. That cloud is in front of the
  crescent/sun, so its white outline wins at both celestial contact points.
- `30`, `37`, `41`, `45`, `46`, and `47` contain a rear cloud and a separate
  foreground cloud. The celestial stroke wins over the rear cloud, while the
  foreground cloud wins wherever it crosses the celestial stroke. In
  `30`/`37`/`41`, the disconnected sun rays inside the rear cloud remain gold.

The foreground cloud mask is extracted from the enclosed cloud cavity in the
original source image. For the one-cloud icons it selects that sole cloud; for
the two-cloud icons it selects the lower-centroid cloud. No contour is moved,
redrawn, widened, or invented, and all three intensity layers recombine to
the same source ink. The other 11 icons retain their existing two-layer or
single-layer representation.

This source-derived layering supersedes the previous six-pixel contact
recovery experiment. Do not add per-icon pixel patches or globally weaken the
cloud guard: preserve the three-pass source overlap model instead. The
regression tests check source-ink conservation, the white/gold/white draw
order, deterministic path generation, and all 20 original silhouettes.
The production renderer remains native Cairo and performs no PNG/mask I/O at
runtime; the original PNGs remain authoring references only.

The pixel-fidelity regression measures the neutral + celestial outlines
combined as white against the actual source, not against a hand-designed
approximation. On the 20 source images, every icon's bright-core silhouette
has IoU >= 0.94, and mean per-pixel brightness difference < 2/255.
This is very close but **not exact byte/pixel reproduction**: the source has
subtle antialiasing and Cairo re-rasterizes the paths at the target scale.

## Regenerating paths (developer-only)

Regenerate only if the original source images change:

```bash
python3 -m pip install --user Pillow numpy opencv-python scikit-image pycairo
python3 tools/trace_weather_png_to_cairo.py
python3 -m unittest tests.test_weather_vector_fidelity -v
TZ=Africa/Cairo texlua tests/test_weather_icons.lua
```

No Python imaging libraries are needed for Conky runtime. The vector data is
autogenerated in `lib/Weather_Icon_Paths.lua` and checked into Git; **never
hand-edit the generated path arrays**. To replace an original icon, update its
source PNG and, if necessary, the matching `CELESTIAL` transform, then rerun
the generator and inspect the full 20-icon preview before committing.

## Future-agent guardrails

1. **Do not simplify all clouds into one reusable curve.** The source pack
   includes distinct single, layered, small and large clouds. Icon 26 is the
   user's explicit fidelity reference.
2. **Preserve overlap order.** In IDs `30`, `37`, `41`, `45`, `46`, and `47`,
   render `n` (rear white) -> `c` (gold celestial) -> `f` (foreground white).
   Do not collapse these layers into a single white/gold mask or change their
   order; the celestial stroke wins over the rear cloud, while the foreground
   cloud wins over the celestial stroke.
3. **Do not draw hidden celestial geometry.** Trace only source artwork pixels
   and keep the three layers' combined intensity equal to the original PNG.
4. Keep the current 256x256 source coordinate system, WMO mapping, target sizes,
   current/forecast handling and transparent backgrounds unchanged.
5. Keep runtime PNG I/O and runtime image-processing dependencies out of
   `lib/Weather_Icons.lua`.
6. Preserve the original PNG files for reference and regeneration, even though
   the renderer no longer uses them.
7. Run both Lua Weather/Date integration tests and Python vector-fidelity tests
   after any geometry or mask/transform change; do not claim live KDE quality
   until the user verifies the installed widget.
