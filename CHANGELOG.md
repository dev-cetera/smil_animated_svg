# CHANGELOG

## [0.2.0]

- `colorMap` on `SvgFrame` and `AnimatedSvg`: a `Map<Color, Color>` that replaces the SVG's own `fill` / `stroke` paints as it renders, so one asset can serve any number of palettes. Matching is on the parsed colour rather than the text in the file (`white`, `#fff` and `#ffffff` are one key) and ignores alpha; the source's alpha multiplies into the replacement's.
- The swap is applied to the parsed tree — keyframes included — and cached per palette. An SVG that animates its own `fill` therefore interpolates in the replacement palette instead of only matching where it lands on a keyframe, and the painter's per-frame cost is unchanged.
- `SvgNode` and `SvgShape` are now `sealed`. Breaking only for code outside this package that subclassed them (nothing did); in exchange, adding a shape can no longer silently skip a tree walk.
- Fixed: an interpolated `<animate>` colour lost its alpha channel on the way back into the live attribute map, so a fade between two `rgba()` keyframes rendered opaque.
- Parse cache raised from 32 to 64 entries, since a recoloured tree is held alongside the one it was derived from.

## [0.1.0]

- Initial release
