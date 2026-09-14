# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This package is **independent** of the umbrella workspace's `df_safer_dart` stack. It uses plain Flutter idioms (no `Option`/`Result`/`Resolvable`, no `_src.g.dart` barrels, no `_common.dart`, no `df_safer_dart_lints`). The parent workspace's `CLAUDE.md` describes patterns that do **not** apply here — defer to this file inside `packages/smil_animated_svg/` (the directory may still be named `animated_svg/` locally until renamed).

## What this package does

Renders SMIL-animated SVGs in Flutter with two widgets:

- **`SvgFrame`** — pure leaf renderer. Takes `position` (0..1), draws one frame. No ticker, no controller, no rebuild scheduling. Drop it in for a static SVG, or wrap it in an `AnimatedBuilder` to drive `position` yourself.
- **`AnimatedSvg`** — owns an `AnimationController` and plays the SVG. Same rendering knobs as `SvgFrame` plus `duration` / `curve` / `repeat` / `stopAt` and tween shortcuts (`colorTween`, `transformTween`, `opacityTween`).

Both share `buildSvgCustomPaint` (in `svg_frame.dart`) and the `AnimatedSvgPainter` (in `render/svg_painter.dart`).

Supported SVG subset: `<g>`, `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polygon>`, `<polyline>`, `<animate>`, `<animateTransform>`. Unknown elements are skipped silently; unknown attributes are kept verbatim. **No gradients, no `<use>`, no `<text>`, no `<image>`, no `<animateMotion>`, no CSS filter effects.**

## Architecture

Three layers, each in its own directory:

```
lib/
  smil_animated_svg.dart      # Public barrel (hand-written, not generated)
  src/
    animated_svg_widget.dart  # AnimatedSvg (StatefulWidget + TickerProviderStateMixin)
    svg_frame.dart            # SvgFrame + shared buildSvgCustomPaint()
    filters.dart              # AnimatedSvgFilters: grayscale, sepia, invert, tint, colorize
    color_swaps.dart          # SvgColorSwaps: normalised {Color: Color} lookup table
    recolor_svg.dart          # recolorSvg: parsed tree -> tree with paints replaced
    parse_cache.dart          # 64-entry LRU keyed by "asset:..." / "url:..." (+ "#palette")
    parser/
      svg_parser.dart         # XmlDocument -> SvgRoot
      svg_node.dart           # SvgRoot, SvgGroup, SvgPathShape, SvgRectShape, ...
      svg_animation.dart      # SvgAnimateAttribute, SvgAnimateTransform models
      transform_parser.dart   # `transform="..."` -> Matrix4
    render/
      evaluator.dart          # (time, node) -> {transform, live attributes}
      svg_painter.dart        # CustomPainter, consumes Animation via super(repaint:)
```

Data flow per frame: `AnimationController.value` → `super(repaint: animation)` on the painter → `paint()` → for each node, `evaluateNode(time, ...)` resolves SMIL → `_paintShape` walks live attributes → `path_drawing` builds geometry → `canvas.drawPath`. **No widget rebuilds during animation** — the painter listens to the `Animation` directly.

## Non-obvious behaviour — read before changing

- **Spec deviation: all transforms compose multiplicatively.** SMIL's default `additive="replace"` would mean a second `<animateTransform>` discards the first, but we always sum (`evaluator.dart` lines around the `NOTE on additive` block). Existing assets in `example/assets/` rely on this; switching to spec-strict would silently break them.
- **Load-race protection.** Both `SvgFrame` and `AnimatedSvg` bump a `_loadGeneration` token on every `_loadIfNeeded` entry. Async loads compare their captured token before calling `setState`, so a load started for a previous source can't clobber a newer result. Preserve this when touching the load path — and **also** bump the generation on a sync cache hit in `didUpdateWidget` (otherwise an in-flight load for the prior source can still commit).
- **`TickerProviderStateMixin`, not `SingleTicker...`** in `_AnimatedSvgState`. Asset-source changes dispose and re-create the controller, and `Single...` refuses to vend a second ticker even after the first is disposed.
- **`AnimatedSvg.position != null` freezes the controller.** While `position` is set, the internal controller is `stop()`ped — same cost as a `SvgFrame`. Tweens still evaluate at the fixed `position` (the painter's `_liveT` falls back to `position` when `animation` is null). **Don't null out tweens when `useAnimation` is false** — there's a regression test for this in `widget_smoke_test.dart`.
- **Minimum duration clamp = 1 ms.** Caller can pass `Duration.zero` or negatives; without the clamp `AnimationController.repeat()` would spin the simulation infinitely fast and pin the raster thread. There's a regression test for this too.
- **Canvas state is balanced with `try/finally`.** A malformed `d=` attribute in `path_drawing.parseSvgPathData` will throw; if the `canvas.restore()` is skipped, every subsequent paint on the same canvas is corrupted. Keep the painter's `paint()` and `_paintNode` wrapped in try/finally on any edit.
- **Parse cache is global static state, cleared by `reassemble`.** Hot reload invalidates automatically. Tests should call `SvgFrame.clearCache()` (or `AnimatedSvg.clearCache()`) if they care about cold-load behaviour.
- **`SvgShape.resolvePath` caches by a string key.** Shapes whose geometry isn't animated keep the same key across frames and skip `path_drawing` re-parsing. Don't break the cache by changing what `pathCacheKey` includes without updating the corresponding `buildPath`.
- **Non-finite filtering matters.** `transform_parser.dart` and `svg_painter.dart` filter NaN/±Inf out of numeric inputs. A NaN in a `Matrix4` entry silently produces empty Skia draws downstream — the worst kind of failure. Keep the filters in place.
- **`colorMap` is applied to the parsed tree, not at paint time.** `recolor_svg.dart` rebuilds the node tree with every matching `fill` / `stroke` replaced — attribute values *and* `<animate>` keyframe values — and caches the result under `"<source>#<palette>"`. Two reasons it lives there rather than in `_paintShape`: an interpolated colour matches no key, so a paint-time swap could only recolour the instants that land exactly on a keyframe; and re-matching the evaluator's own output would apply a two-entry swap (A→B, B→A) twice and cancel it. The painter and evaluator know nothing about colour replacement, and the per-frame cost is unchanged.
- **`SvgNode` / `SvgShape` are `sealed`** so the `switch` in `recolor_svg.dart` is exhaustive — a new shape type is a compile error there rather than an element silently dropped from recoloured trees.
- **`formatSvgColor` is the inverse of `parseSvgColor`** and emits `#RRGGBBAA` when a colour carries alpha. Don't "simplify" it back to six digits: the evaluator round-trips interpolated colours through it, and dropping alpha turned a fade between two `rgba()` keyframes opaque.
- **SVG `opacity` is non-inheriting.** The group painter pulls `opacity` off the merged attribute map before recursing into children; the group's own opacity is applied via `saveLayer`. Don't "fix" this to inherit.

## Linting

Uses **Flutter** lints (`include: package:flutter_lints/recommended.yaml`), not the umbrella workspace's strict Dart config. `custom_lint` plugin is declared but no `df_safer_dart_lints` dependency exists here, so it's effectively a no-op. Key knobs:

- `strict-casts`, `strict-inference`, `strict-raw-types` all on.
- `prefer_relative_imports: error` — never use `package:smil_animated_svg/...` inside `lib/`.
- `require_trailing_commas: true`, `prefer_single_quotes: true`, `omit_local_variable_types: true`.
- `formatter.trailing_commas: preserve`.

Every Dart file starts with the `▓▓▓` license banner — preserve it on edits.

## Common commands

Run inside the package directory (currently `packages/animated_svg/` on disk; will become `packages/smil_animated_svg/` once you rename the workspace folder):

```sh
flutter pub get
dart analyze
dart format .
dart fix --apply
flutter test                                     # full suite
flutter test test/widget_smoke_test.dart         # one file
flutter test --plain-name "swaps sources"        # one test
dart pub publish --dry-run
```

The example app:

```sh
cd example
flutter pub get
flutter run -d macos       # or chrome, etc.
```

**Tests must be run from the package root** — `parser_test.dart` reads `example/assets/compledo_logo_sway.svg` via a relative path.

## Release flow

This package does **not** use the umbrella workspace's `+message` / `++message` commit-prefix scheme. It ships via a `prod` branch:

1. Edit version in `pubspec.yaml` and update `CHANGELOG.md` manually if you want a specific bump; otherwise let CI auto-bump (see `.github/workflows/prod.yml`: `feat`/`feat(...)` → minor, `breaking`/`BREAKING CHANGE` → major, else patch).
2. Run `./deploy.sh` — fast-forwards `prod` to `main`, pushes, switches back to `main`.
3. `prod.yml` runs tests, bumps the version (if not already bumped), commits `ci: ...`, tags `vX.Y.Z`.
4. `publish.yml` triggers on the tag and pushes to pub.dev.

`publish.yml` runs `dart pub publish --force` directly — it does **not** strip `publish_to` from `pubspec.yaml`. The `publish_to: none` guard is therefore load-bearing right now: it blocks accidental publication until the first manual sanity-check via `dart pub publish --dry-run` clears. To enable real publishing, drop `publish_to: none` from `pubspec.yaml` or have CI strip it before `dart pub publish` runs.
