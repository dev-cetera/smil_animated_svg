import 'dart:ui';

/// A normalised colour-replacement table: "wherever this SVG paints colour A,
/// paint colour B instead."
///
/// Built from the `colorMap` passed to [SvgFrame] / [AnimatedSvg]. Callers
/// never see this type — they hand over a plain `Map<Color, Color>` and this
/// class turns it into something cheap to look up and cheap to compare.
///
/// **Matching ignores alpha.** Both the key and the colour found in the file
/// are reduced to their RGB triple before comparison. That is what lets one
/// key match every spelling of the same colour: the file's paint is parsed
/// into a [Color] first, so `white`, `#fff`, `#ffffff` and `rgb(255,255,255)`
/// are all the same key, and a `#ffffff80` fill still matches an opaque
/// `Colors.white` key.
///
/// **The two alphas multiply on the way out.** A fully opaque paint swapped
/// for a half-transparent replacement comes out half-transparent, and a paint
/// that was already half-transparent stays half-transparent when swapped for
/// an opaque replacement. So a swap can fade a colour, but it can never
/// silently make a translucent part of the artwork solid.
class SvgColorSwaps {
  const SvgColorSwaps._(this._byRgb, this.cacheKey);

  factory SvgColorSwaps(Map<Color, Color> colorMap) {
    final byRgb = <int, Color>{};
    for (final entry in colorMap.entries) {
      byRgb[_rgbOf(entry.key)] = entry.value;
    }
    // Sorted so two maps built in a different insertion order share one key.
    final rgbKeys = byRgb.keys.toList()..sort();
    final cacheKey = rgbKeys
        .map(
          (rgb) => '${rgb.toRadixString(16)}>'
              '${byRgb[rgb]!.toARGB32().toRadixString(16)}',
        )
        .join(',');
    return SvgColorSwaps._(byRgb, cacheKey);
  }

  /// Replacements keyed by the 24-bit RGB of the colour being replaced.
  final Map<int, Color> _byRgb;

  /// Stable identity of this table. Composed into the parse-cache key so the
  /// recoloured tree for one palette is reused across widgets, and compared
  /// in `didUpdateWidget` to decide whether a recolour is needed at all.
  final String cacheKey;

  /// Null when there is nothing to replace, so every downstream check is a
  /// plain null check rather than a null-or-empty one.
  static SvgColorSwaps? maybe(Map<Color, Color>? colorMap) {
    if (colorMap == null || colorMap.isEmpty) return null;
    return SvgColorSwaps(colorMap);
  }

  bool get isEmpty => _byRgb.isEmpty;

  /// The replacement for [color], or [color] itself when nothing matches.
  Color apply(Color color) {
    final replacement = _byRgb[_rgbOf(color)];
    if (replacement == null) return color;
    return replacement.withValues(alpha: color.a * replacement.a);
  }

  static int _rgbOf(Color color) => color.toARGB32() & 0xffffff;

  @override
  bool operator ==(Object other) =>
      other is SvgColorSwaps && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
