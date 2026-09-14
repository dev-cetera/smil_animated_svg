import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../parser/svg_animation.dart';
import '../parser/transform_parser.dart';

/// Resolve all animations on a node at time [t] (seconds since the document
/// timeline started).
///
/// Returns the composed transform (base × accumulated animateTransform) and
/// the merged attribute map (base attributes overridden by any active
/// `<animate>` evaluations).
class NodeEvaluation {
  const NodeEvaluation({
    required this.transform,
    required this.attributes,
  });

  final Matrix4 transform;
  final Map<String, String> attributes;
}

NodeEvaluation evaluateNode({
  required double timeSeconds,
  required Matrix4 baseTransform,
  required Map<String, String> baseAttributes,
  required List<SvgAnimation> animations,
}) {
  // NOTE on `additive`: SMIL's spec default is `replace`, which means a
  // second `<animateTransform>` on the same element discards the first.
  // We always multiplicatively compose (effectively `additive="sum"` for
  // everything). This matches what most SVG authors intend — and what
  // existing assets in this repo rely on — even when they omit the
  // attribute. Switching to spec-strict would silently break those.

  // Fast path: nothing to evaluate. Skips the Matrix4.clone() that otherwise
  // happens per static node per frame, which is the bulk of nodes in any
  // realistic SVG (only a handful actually animate).
  if (animations.isEmpty) {
    return NodeEvaluation(
      transform: baseTransform,
      attributes: baseAttributes,
    );
  }

  // Clone the base once; further composition is in place to avoid allocating
  // a fresh Matrix4 per animation per frame.
  Matrix4? composedTransform;
  Map<String, String>? liveAttributes;

  for (final animation in animations) {
    if (animation is SvgAnimateTransform) {
      final values = _evaluateTransform(animation, timeSeconds);
      if (values == null) continue;
      final matrix = buildAnimatedTransform(animation.type.name, values);
      composedTransform ??= baseTransform.clone();
      composedTransform.multiply(matrix);
    } else if (animation is SvgAnimateAttribute) {
      final value = _evaluateAttribute(animation, timeSeconds);
      if (value == null) continue;
      liveAttributes ??= Map<String, String>.of(baseAttributes);
      liveAttributes[animation.attributeName] = value;
    }
  }

  return NodeEvaluation(
    transform: composedTransform ?? baseTransform,
    attributes: liveAttributes ?? baseAttributes,
  );
}

/// Where are we inside the animation's timeline at [timeSeconds]?
/// Returns a fraction in [0, 1] across the current cycle, or null if the
/// animation has not started yet or has already finished.
double? _progress(SvgAnimation animation, double timeSeconds) {
  final beginSeconds = animation.begin.inMicroseconds / 1e6;
  final local = timeSeconds - beginSeconds;
  if (local < 0.0) return null;

  final cycle = animation.duration.inMicroseconds / 1e6;
  if (cycle <= 0.0) return null;

  if (animation.repeatCount.isFinite) {
    final totalDuration = cycle * animation.repeatCount;
    if (local >= totalDuration) {
      // SMIL "freeze" vs "remove" fill mode would matter here. Default to
      // freezing on the final value, which feels right for UI animations.
      return 1.0;
    }
  }

  final cyclePosition = local % cycle;
  return cyclePosition / cycle;
}

List<double>? _evaluateTransform(
  SvgAnimateTransform animation,
  double timeSeconds,
) {
  final progress = _progress(animation, timeSeconds);
  if (progress == null) return null;

  final (lowerIndex, upperIndex, blend) =
      _findKeyframeWindow(animation.keyTimes, progress);
  final eased = _applyEasing(animation, lowerIndex, blend);
  final lower = animation.values[lowerIndex];
  final upper = animation.values[upperIndex];

  final length = lower.length < upper.length ? lower.length : upper.length;
  final out = List<double>.filled(length, 0.0);
  for (var i = 0; i < length; i++) {
    out[i] = _lerp(lower[i], upper[i], eased);
  }
  return out;
}

String? _evaluateAttribute(
  SvgAnimateAttribute animation,
  double timeSeconds,
) {
  final progress = _progress(animation, timeSeconds);
  if (progress == null) return null;

  final (lowerIndex, upperIndex, blend) =
      _findKeyframeWindow(animation.keyTimes, progress);
  final eased = _applyEasing(animation, lowerIndex, blend);
  final lower = animation.values[lowerIndex];
  final upper = animation.values[upperIndex];

  if (animation.calcMode == SvgCalcMode.discrete) {
    return lower;
  }

  switch (animation.valueType) {
    case SvgAnimateValueType.number:
      final a = double.tryParse(lower);
      final b = double.tryParse(upper);
      if (a == null || b == null) return upper;
      return _formatNumber(_lerp(a, b, eased));
    case SvgAnimateValueType.color:
    case SvgAnimateValueType.paint:
      return _interpolateColor(lower, upper, eased);
  }
}

double _applyEasing(SvgAnimation animation, int segmentIndex, double blend) {
  if (animation.calcMode != SvgCalcMode.spline) return blend;
  if (segmentIndex >= animation.keySplines.length) return blend;
  final spline = animation.keySplines[segmentIndex];
  return _cubicBezier(spline[0], spline[1], spline[2], spline[3], blend);
}

/// Evaluate a CSS-style cubic-bezier easing curve. Endpoints are fixed at
/// (0,0) and (1,1); [x1] [y1] and [x2] [y2] are the two control points.
/// Returns the y value at the [t]-th point along the curve in x.
double _cubicBezier(double x1, double y1, double x2, double y2, double t) {
  if (t <= 0.0) return 0.0;
  if (t >= 1.0) return 1.0;
  // Solve bezierX(s) = t via Newton's method, then return bezierY(s).
  var s = t;
  for (var i = 0; i < 8; i++) {
    final x = _bezier1d(x1, x2, s);
    final diff = x - t;
    if (diff.abs() < 1e-5) break;
    final dx = _bezier1dDerivative(x1, x2, s);
    if (dx.abs() < 1e-6) break;
    s = (s - diff / dx).clamp(0.0, 1.0);
  }
  return _bezier1d(y1, y2, s);
}

double _bezier1d(double c1, double c2, double s) {
  final ms = 1.0 - s;
  return 3.0 * ms * ms * s * c1 + 3.0 * ms * s * s * c2 + s * s * s;
}

double _bezier1dDerivative(double c1, double c2, double s) {
  final ms = 1.0 - s;
  return 3.0 * ms * ms * c1 +
      6.0 * ms * s * (c2 - c1) +
      3.0 * s * s * (1.0 - c2);
}

(int, int, double) _findKeyframeWindow(List<double> keyTimes, double t) {
  if (keyTimes.length <= 1) return (0, 0, 0.0);
  if (t <= keyTimes.first) return (0, 0, 0.0);
  if (t >= keyTimes.last) {
    final last = keyTimes.length - 1;
    return (last, last, 0.0);
  }
  for (var i = 1; i < keyTimes.length; i++) {
    if (t <= keyTimes[i]) {
      final span = keyTimes[i] - keyTimes[i - 1];
      final blend = span <= 0.0 ? 0.0 : (t - keyTimes[i - 1]) / span;
      return (i - 1, i, blend);
    }
  }
  final last = keyTimes.length - 1;
  return (last, last, 0.0);
}

double _lerp(double a, double b, double t) => a + (b - a) * t;

String _formatNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toStringAsFixed(0);
  }
  return value.toString();
}

String _interpolateColor(String a, String b, double t) {
  final colorA = parseSvgColor(a);
  final colorB = parseSvgColor(b);
  if (colorA == null || colorB == null) return b;
  final lerped = Color.lerp(colorA, colorB, t) ?? colorB;
  return formatSvgColor(lerped);
}

/// Format [color] as an SVG paint string: `#RRGGBB`, or `#RRGGBBAA` when it
/// carries alpha. The inverse of [parseSvgColor], and the reason a colour can
/// survive the round trip back into the live attribute map — dropping alpha
/// here used to turn an interpolated `rgba()` keyframe opaque mid-animation.
String formatSvgColor(Color color) {
  String pad(int v) => v.toRadixString(16).padLeft(2, '0');
  final argb = color.toARGB32();
  final alpha = (argb >> 24) & 0xff;
  final rgb = '#${pad((argb >> 16) & 0xff)}'
      '${pad((argb >> 8) & 0xff)}'
      '${pad(argb & 0xff)}';
  return alpha == 0xff ? rgb : '$rgb${pad(alpha)}';
}

/// Parse an SVG colour string. Supports `#RGB`, `#RRGGBB`, `#RRGGBBAA`,
/// `rgb(r,g,b)`, `rgba(r,g,b,a)`, `none`, and a handful of named colours.
/// Returns null when the input is `none` or unrecognised.
Color? parseSvgColor(String input) {
  final value = input.trim();
  if (value.isEmpty || value == 'none' || value == 'transparent') return null;

  if (value.startsWith('#')) {
    final hex = value.substring(1);
    if (hex.length == 3) {
      final r = int.tryParse(hex[0] * 2, radix: 16);
      final g = int.tryParse(hex[1] * 2, radix: 16);
      final b = int.tryParse(hex[2] * 2, radix: 16);
      if (r == null || g == null || b == null) return null;
      return Color.fromARGB(0xff, r, g, b);
    }
    if (hex.length == 6) {
      final rgb = int.tryParse(hex, radix: 16);
      if (rgb == null) return null;
      return Color(0xff000000 | rgb);
    }
    if (hex.length == 8) {
      // #RRGGBBAA — convert to ARGB.
      final rgb = int.tryParse(hex.substring(0, 6), radix: 16);
      final a = int.tryParse(hex.substring(6, 8), radix: 16);
      if (rgb == null || a == null) return null;
      return Color((a << 24) | rgb);
    }
    return null;
  }

  final rgb = RegExp(r'^rgba?\s*\(([^)]+)\)$').firstMatch(value);
  if (rgb != null) {
    final parts = rgb
        .group(1)!
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.length >= 3) {
      final r = _readColorComponent(parts[0]);
      final g = _readColorComponent(parts[1]);
      final b = _readColorComponent(parts[2]);
      final a = parts.length >= 4
          ? (double.tryParse(parts[3]) ?? 1.0).clamp(0.0, 1.0)
          : 1.0;
      return Color.fromARGB((a * 255).round(), r, g, b);
    }
  }

  return _namedColors[value.toLowerCase()];
}

int _readColorComponent(String raw) {
  if (raw.endsWith('%')) {
    final pct = double.tryParse(raw.substring(0, raw.length - 1)) ?? 0.0;
    return (pct * 2.55).round().clamp(0, 255);
  }
  return (int.tryParse(raw) ?? 0).clamp(0, 255);
}

// CSS Color Module Level 3 named colors (the set every browser supports
// for SVG `fill="..."` / `stroke="..."`). Without these, SVGs that use
// any of the long tail of names (`royalblue`, `dimgray`, `salmon`, …)
// silently render as nothing — the same outcome as `fill="none"`, which
// is the worst kind of failure (no warning, no visible shape).
const Map<String, Color> _namedColors = {
  'aliceblue': Color(0xfff0f8ff),
  'antiquewhite': Color(0xfffaebd7),
  'aqua': Color(0xff00ffff),
  'aquamarine': Color(0xff7fffd4),
  'azure': Color(0xfff0ffff),
  'beige': Color(0xfff5f5dc),
  'bisque': Color(0xffffe4c4),
  'black': Color(0xff000000),
  'blanchedalmond': Color(0xffffebcd),
  'blue': Color(0xff0000ff),
  'blueviolet': Color(0xff8a2be2),
  'brown': Color(0xffa52a2a),
  'burlywood': Color(0xffdeb887),
  'cadetblue': Color(0xff5f9ea0),
  'chartreuse': Color(0xff7fff00),
  'chocolate': Color(0xffd2691e),
  'coral': Color(0xffff7f50),
  'cornflowerblue': Color(0xff6495ed),
  'cornsilk': Color(0xfffff8dc),
  'crimson': Color(0xffdc143c),
  'cyan': Color(0xff00ffff),
  'darkblue': Color(0xff00008b),
  'darkcyan': Color(0xff008b8b),
  'darkgoldenrod': Color(0xffb8860b),
  'darkgray': Color(0xffa9a9a9),
  'darkgreen': Color(0xff006400),
  'darkgrey': Color(0xffa9a9a9),
  'darkkhaki': Color(0xffbdb76b),
  'darkmagenta': Color(0xff8b008b),
  'darkolivegreen': Color(0xff556b2f),
  'darkorange': Color(0xffff8c00),
  'darkorchid': Color(0xff9932cc),
  'darkred': Color(0xff8b0000),
  'darksalmon': Color(0xffe9967a),
  'darkseagreen': Color(0xff8fbc8f),
  'darkslateblue': Color(0xff483d8b),
  'darkslategray': Color(0xff2f4f4f),
  'darkslategrey': Color(0xff2f4f4f),
  'darkturquoise': Color(0xff00ced1),
  'darkviolet': Color(0xff9400d3),
  'deeppink': Color(0xffff1493),
  'deepskyblue': Color(0xff00bfff),
  'dimgray': Color(0xff696969),
  'dimgrey': Color(0xff696969),
  'dodgerblue': Color(0xff1e90ff),
  'firebrick': Color(0xffb22222),
  'floralwhite': Color(0xfffffaf0),
  'forestgreen': Color(0xff228b22),
  'fuchsia': Color(0xffff00ff),
  'gainsboro': Color(0xffdcdcdc),
  'ghostwhite': Color(0xfff8f8ff),
  'gold': Color(0xffffd700),
  'goldenrod': Color(0xffdaa520),
  'gray': Color(0xff808080),
  'green': Color(0xff008000),
  'greenyellow': Color(0xffadff2f),
  'grey': Color(0xff808080),
  'honeydew': Color(0xfff0fff0),
  'hotpink': Color(0xffff69b4),
  'indianred': Color(0xffcd5c5c),
  'indigo': Color(0xff4b0082),
  'ivory': Color(0xfffffff0),
  'khaki': Color(0xfff0e68c),
  'lavender': Color(0xffe6e6fa),
  'lavenderblush': Color(0xfffff0f5),
  'lawngreen': Color(0xff7cfc00),
  'lemonchiffon': Color(0xfffffacd),
  'lightblue': Color(0xffadd8e6),
  'lightcoral': Color(0xfff08080),
  'lightcyan': Color(0xffe0ffff),
  'lightgoldenrodyellow': Color(0xfffafad2),
  'lightgray': Color(0xffd3d3d3),
  'lightgreen': Color(0xff90ee90),
  'lightgrey': Color(0xffd3d3d3),
  'lightpink': Color(0xffffb6c1),
  'lightsalmon': Color(0xffffa07a),
  'lightseagreen': Color(0xff20b2aa),
  'lightskyblue': Color(0xff87cefa),
  'lightslategray': Color(0xff778899),
  'lightslategrey': Color(0xff778899),
  'lightsteelblue': Color(0xffb0c4de),
  'lightyellow': Color(0xffffffe0),
  'lime': Color(0xff00ff00),
  'limegreen': Color(0xff32cd32),
  'linen': Color(0xfffaf0e6),
  'magenta': Color(0xffff00ff),
  'maroon': Color(0xff800000),
  'mediumaquamarine': Color(0xff66cdaa),
  'mediumblue': Color(0xff0000cd),
  'mediumorchid': Color(0xffba55d3),
  'mediumpurple': Color(0xff9370db),
  'mediumseagreen': Color(0xff3cb371),
  'mediumslateblue': Color(0xff7b68ee),
  'mediumspringgreen': Color(0xff00fa9a),
  'mediumturquoise': Color(0xff48d1cc),
  'mediumvioletred': Color(0xffc71585),
  'midnightblue': Color(0xff191970),
  'mintcream': Color(0xfff5fffa),
  'mistyrose': Color(0xffffe4e1),
  'moccasin': Color(0xffffe4b5),
  'navajowhite': Color(0xffffdead),
  'navy': Color(0xff000080),
  'oldlace': Color(0xfffdf5e6),
  'olive': Color(0xff808000),
  'olivedrab': Color(0xff6b8e23),
  'orange': Color(0xffffa500),
  'orangered': Color(0xffff4500),
  'orchid': Color(0xffda70d6),
  'palegoldenrod': Color(0xffeee8aa),
  'palegreen': Color(0xff98fb98),
  'paleturquoise': Color(0xffafeeee),
  'palevioletred': Color(0xffdb7093),
  'papayawhip': Color(0xffffefd5),
  'peachpuff': Color(0xffffdab9),
  'peru': Color(0xffcd853f),
  'pink': Color(0xffffc0cb),
  'plum': Color(0xffdda0dd),
  'powderblue': Color(0xffb0e0e6),
  'purple': Color(0xff800080),
  'rebeccapurple': Color(0xff663399),
  'red': Color(0xffff0000),
  'rosybrown': Color(0xffbc8f8f),
  'royalblue': Color(0xff4169e1),
  'saddlebrown': Color(0xff8b4513),
  'salmon': Color(0xfffa8072),
  'sandybrown': Color(0xfff4a460),
  'seagreen': Color(0xff2e8b57),
  'seashell': Color(0xfffff5ee),
  'sienna': Color(0xffa0522d),
  'silver': Color(0xffc0c0c0),
  'skyblue': Color(0xff87ceeb),
  'slateblue': Color(0xff6a5acd),
  'slategray': Color(0xff708090),
  'slategrey': Color(0xff708090),
  'snow': Color(0xfffffafa),
  'springgreen': Color(0xff00ff7f),
  'steelblue': Color(0xff4682b4),
  'tan': Color(0xffd2b48c),
  'teal': Color(0xff008080),
  'thistle': Color(0xffd8bfd8),
  'tomato': Color(0xffff6347),
  'turquoise': Color(0xff40e0d0),
  'violet': Color(0xffee82ee),
  'wheat': Color(0xfff5deb3),
  'white': Color(0xffffffff),
  'whitesmoke': Color(0xfff5f5f5),
  'yellow': Color(0xffffff00),
  'yellowgreen': Color(0xff9acd32),
};
