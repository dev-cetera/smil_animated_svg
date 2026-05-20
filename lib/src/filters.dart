import 'dart:ui';

/// Common [ColorFilter] recipes for SVG rendering.
///
/// Tradeoff overview:
///   * `color: Colors.red, colorBlendMode: BlendMode.srcIn` — every coloured
///     pixel becomes red (silhouette). Matches `Image.color`.
///   * `color: Colors.red, colorBlendMode: BlendMode.modulate` — multiplies
///     SVG colours by red (tint that preserves relative shading).
///   * `colorFilter: AnimatedSvgFilters.grayscale` — luminance-preserving
///     desaturate. The SVG retains its shading, drained of colour.
///   * `colorFilter: AnimatedSvgFilters.colorize(Colors.red)` — replaces
///     the hue with the given colour while preserving luminance.
abstract final class AnimatedSvgFilters {
  /// Luminance-preserving greyscale. Pixels retain their relative brightness.
  static const ColorFilter grayscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0.0, 0.0,
    0.2126, 0.7152, 0.0722, 0.0, 0.0,
    0.2126, 0.7152, 0.0722, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ]);

  /// Classic sepia tint.
  static const ColorFilter sepia = ColorFilter.matrix(<double>[
    0.393, 0.769, 0.189, 0.0, 0.0,
    0.349, 0.686, 0.168, 0.0, 0.0,
    0.272, 0.534, 0.131, 0.0, 0.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ]);

  /// Inverts all colour channels (alpha preserved).
  static const ColorFilter invert = ColorFilter.matrix(<double>[
    -1.0, 0.0, 0.0, 0.0, 255.0,
    0.0, -1.0, 0.0, 0.0, 255.0,
    0.0, 0.0, -1.0, 0.0, 255.0,
    0.0, 0.0, 0.0, 1.0, 0.0,
  ]);

  /// Multiplicative tint that preserves the SVG's shading. Equivalent to
  /// `ColorFilter.mode(tint, BlendMode.modulate)` but exposed here for
  /// discoverability.
  static ColorFilter tint(Color tint) =>
      ColorFilter.mode(tint, BlendMode.modulate);

  /// Replaces the SVG's hue with [tint] while preserving its luminance.
  /// Good for "colorize this icon red but keep its shading."
  static ColorFilter colorize(Color tint) {
    final r = tint.r;
    final g = tint.g;
    final b = tint.b;
    // Luminance weights times the target colour: each output channel is the
    // input luminance scaled by the channel of the target colour.
    return ColorFilter.matrix(<double>[
      0.2126 * r, 0.7152 * r, 0.0722 * r, 0.0, 0.0,
      0.2126 * g, 0.7152 * g, 0.0722 * g, 0.0, 0.0,
      0.2126 * b, 0.7152 * b, 0.0722 * b, 0.0, 0.0,
      0.0, 0.0, 0.0, 1.0, 0.0,
    ]);
  }
}
