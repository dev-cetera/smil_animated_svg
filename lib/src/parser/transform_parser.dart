import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

/// Parse an SVG `transform="..."` attribute value into a [Matrix4].
///
/// Supports the functional notation used by SVG 1.1:
///   translate(tx [, ty])
///   rotate(angle [, cx, cy])
///   scale(sx [, sy])
///   skewX(angle)
///   skewY(angle)
///   matrix(a, b, c, d, e, f)
///
/// Multiple functions are post-multiplied in document order.
Matrix4 parseSvgTransform(String input) {
  final result = Matrix4.identity();
  final pattern = RegExp(r'(\w+)\s*\(([^)]*)\)');
  for (final match in pattern.allMatches(input)) {
    final name = match.group(1)!;
    final args = _parseNumberList(match.group(2)!);
    result.multiply(buildAnimatedTransform(name, args));
  }
  return result;
}

/// Build a [Matrix4] from one SMIL animateTransform tuple. Mirrors the
/// semantics of [parseSvgTransform] for a single function call.
Matrix4 buildAnimatedTransform(String type, List<double> values) {
  switch (type) {
    case 'translate':
      return _translate(values);
    case 'rotate':
      return _rotate(values);
    case 'scale':
      return _scale(values);
    case 'skewX':
      return _skewX(values);
    case 'skewY':
      return _skewY(values);
    case 'matrix':
      return _matrix(values);
  }
  return Matrix4.identity();
}

Matrix4 _translate(List<double> a) {
  final tx = a.isNotEmpty ? a[0] : 0.0;
  final ty = a.length > 1 ? a[1] : 0.0;
  return Matrix4.identity()..setTranslationRaw(tx, ty, 0.0);
}

Matrix4 _rotate(List<double> a) {
  final angle = a.isNotEmpty ? a[0] : 0.0;
  final radians = angle * math.pi / 180.0;
  if (a.length >= 3) {
    final cx = a[1];
    final cy = a[2];
    return Matrix4.identity()
      ..setTranslationRaw(cx, cy, 0.0)
      ..multiply(Matrix4.rotationZ(radians))
      ..multiply(Matrix4.identity()..setTranslationRaw(-cx, -cy, 0.0));
  }
  return Matrix4.rotationZ(radians);
}

Matrix4 _scale(List<double> a) {
  final sx = a.isNotEmpty ? a[0] : 1.0;
  final sy = a.length > 1 ? a[1] : sx;
  return Matrix4.diagonal3Values(sx, sy, 1.0);
}

Matrix4 _skewX(List<double> a) {
  final radians = (a.isNotEmpty ? a[0] : 0.0) * math.pi / 180.0;
  return Matrix4.identity()..setEntry(0, 1, math.tan(radians));
}

Matrix4 _skewY(List<double> a) {
  final radians = (a.isNotEmpty ? a[0] : 0.0) * math.pi / 180.0;
  return Matrix4.identity()..setEntry(1, 0, math.tan(radians));
}

Matrix4 _matrix(List<double> a) {
  if (a.length < 6) return Matrix4.identity();
  // SVG matrix(a b c d e f) ⇒ [[a c e], [b d f], [0 0 1]] in 2D.
  return Matrix4.identity()
    ..setEntry(0, 0, a[0])
    ..setEntry(1, 0, a[1])
    ..setEntry(0, 1, a[2])
    ..setEntry(1, 1, a[3])
    ..setEntry(0, 3, a[4])
    ..setEntry(1, 3, a[5]);
}

List<double> _parseNumberList(String raw) {
  final tokens =
      raw.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
  // Filter non-finite (NaN / ±Inf): they propagate into Matrix4 entries and
  // turn the whole canvas transform into garbage — Skia silently produces
  // empty draws downstream, which is the worst kind of failure.
  return tokens
      .map((t) => double.tryParse(t))
      .where((value) => value != null && value.isFinite)
      .cast<double>()
      .toList(growable: false);
}

/// Public for use by the SMIL parser when reading `values` from an
/// `<animateTransform>` element (one tuple per `;`-separated entry).
List<double> parseNumberList(String raw) => _parseNumberList(raw);
