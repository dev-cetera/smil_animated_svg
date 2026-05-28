import 'dart:ui';

import 'package:path_drawing/path_drawing.dart' as path_drawing;
import 'package:vector_math/vector_math_64.dart';

import 'svg_animation.dart';

/// Root of a parsed SVG. Holds the viewBox and the top-level group of nodes.
class SvgRoot {
  SvgRoot({
    required this.viewBox,
    required this.children,
    this.intrinsicSize,
  });

  /// The SVG viewBox: (x, y, width, height). Defines the source coordinate
  /// system; the painter scales it to fit the widget's render box.
  final Rect viewBox;

  /// The intrinsic size declared on the root `<svg>` element (width / height
  /// attributes), if present. The widget falls back to viewBox size when
  /// these are missing.
  final Size? intrinsicSize;

  final List<SvgNode> children;

  /// Implicit cycle period derived from the SVG itself: the longest single
  /// animation `dur` found anywhere in the tree. When the SVG has no
  /// animation children at all, returns [Duration.zero] — callers should
  /// treat that as "no animations, position has no meaningful effect."
  ///
  /// Computed once on first access and cached: a parsed [SvgRoot] is
  /// immutable, so the value never changes.
  late final Duration naturalCyclePeriod = _computeNaturalCyclePeriod();

  Duration _computeNaturalCyclePeriod() {
    var longest = Duration.zero;
    void visit(SvgNode node) {
      for (final animation in node.animations) {
        if (animation.duration > longest) longest = animation.duration;
      }
      if (node is SvgGroup) {
        for (final child in node.children) {
          visit(child);
        }
      }
    }

    for (final child in children) {
      visit(child);
    }
    return longest;
  }

  /// True when at least one animation exists in the tree. Lets [AnimatedSvg]
  /// skip the AnimationController entirely for static SVGs.
  bool get hasAnimations => naturalCyclePeriod > Duration.zero;
}

abstract class SvgNode {
  SvgNode({
    required this.baseTransform,
    required this.attributes,
    required this.animations,
  });

  /// The static transform parsed from the node's `transform="..."` attribute.
  /// Animations may compose additional transforms on top of this base.
  final Matrix4 baseTransform;

  /// Raw XML attributes that participate in styling or geometry. Stored as
  /// strings; resolved at paint time (after applying animation overrides).
  final Map<String, String> attributes;

  /// SMIL animation children attached to this node.
  final List<SvgAnimation> animations;
}

class SvgGroup extends SvgNode {
  SvgGroup({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
    required this.children,
  });

  final List<SvgNode> children;
}

abstract class SvgShape extends SvgNode {
  SvgShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  // Single-entry path cache keyed by the geometry-defining attributes of
  // this shape. For shapes whose geometry isn't animated, the key is
  // identical across frames and the cached Path is reused (skipping
  // `path_drawing.parseSvgPathData` on every paint, which dominates the
  // hot path for path-heavy SVGs). When two painters render the same root
  // at different cycle points and the geometry IS animated, the cache will
  // thrash; that's acceptable.
  String? _cachedPathKey;
  Path? _cachedPath;

  /// Return the geometry for this shape at the current live attribute set,
  /// reusing the cached [Path] when the geometry-defining attributes
  /// haven't changed since the last call.
  Path resolvePath(Map<String, String> live) {
    final key = pathCacheKey(live);
    final cached = _cachedPath;
    if (cached != null && key == _cachedPathKey) return cached;
    final built = buildPath(live);
    _cachedPathKey = key;
    _cachedPath = built;
    return built;
  }

  /// Concise fingerprint of the geometry-defining attributes. When this
  /// value is unchanged across two calls the cached path is reusable.
  String pathCacheKey(Map<String, String> liveAttributes);

  /// Build the geometry for this shape given the live attribute map
  /// (base attributes merged with the current animation overrides).
  Path buildPath(Map<String, String> liveAttributes);
}

class SvgPathShape extends SvgShape {
  SvgPathShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  @override
  String pathCacheKey(Map<String, String> live) => live['d'] ?? '';

  @override
  Path buildPath(Map<String, String> live) {
    final data = live['d'] ?? '';
    if (data.isEmpty) return Path();
    try {
      return path_drawing.parseSvgPathData(data);
    } catch (_) {
      // Malformed `d`: render nothing rather than poisoning the entire
      // paint. The error surfaces visually as an empty shape, which is the
      // same fallback the rest of the painter uses for unrenderable inputs.
      return Path();
    }
  }
}

class SvgRectShape extends SvgShape {
  SvgRectShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  @override
  String pathCacheKey(Map<String, String> live) =>
      '${live['x']}|${live['y']}|${live['width']}|${live['height']}|'
      '${live['rx']}|${live['ry']}';

  @override
  Path buildPath(Map<String, String> live) {
    final x = _num(live['x']) ?? 0.0;
    final y = _num(live['y']) ?? 0.0;
    final width = _num(live['width']) ?? 0.0;
    final height = _num(live['height']) ?? 0.0;
    final rx = _num(live['rx']);
    final ry = _num(live['ry']);
    final rect = Rect.fromLTWH(x, y, width, height);
    if (rx != null || ry != null) {
      final radius = Radius.elliptical(rx ?? ry ?? 0.0, ry ?? rx ?? 0.0);
      return Path()..addRRect(RRect.fromRectAndRadius(rect, radius));
    }
    return Path()..addRect(rect);
  }
}

class SvgCircleShape extends SvgShape {
  SvgCircleShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  @override
  String pathCacheKey(Map<String, String> live) =>
      '${live['cx']}|${live['cy']}|${live['r']}';

  @override
  Path buildPath(Map<String, String> live) {
    final cx = _num(live['cx']) ?? 0.0;
    final cy = _num(live['cy']) ?? 0.0;
    final r = _num(live['r']) ?? 0.0;
    return Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
  }
}

class SvgEllipseShape extends SvgShape {
  SvgEllipseShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  @override
  String pathCacheKey(Map<String, String> live) =>
      '${live['cx']}|${live['cy']}|${live['rx']}|${live['ry']}';

  @override
  Path buildPath(Map<String, String> live) {
    final cx = _num(live['cx']) ?? 0.0;
    final cy = _num(live['cy']) ?? 0.0;
    final rx = _num(live['rx']) ?? 0.0;
    final ry = _num(live['ry']) ?? 0.0;
    return Path()
      ..addOval(
        Rect.fromCenter(
          center: Offset(cx, cy),
          width: rx * 2.0,
          height: ry * 2.0,
        ),
      );
  }
}

class SvgLineShape extends SvgShape {
  SvgLineShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
  });

  @override
  String pathCacheKey(Map<String, String> live) =>
      '${live['x1']}|${live['y1']}|${live['x2']}|${live['y2']}';

  @override
  Path buildPath(Map<String, String> live) {
    final x1 = _num(live['x1']) ?? 0.0;
    final y1 = _num(live['y1']) ?? 0.0;
    final x2 = _num(live['x2']) ?? 0.0;
    final y2 = _num(live['y2']) ?? 0.0;
    return Path()
      ..moveTo(x1, y1)
      ..lineTo(x2, y2);
  }
}

class SvgPolygonShape extends SvgShape {
  SvgPolygonShape({
    required super.baseTransform,
    required super.attributes,
    required super.animations,
    required this.closed,
  });

  final bool closed;

  @override
  String pathCacheKey(Map<String, String> live) => '${live['points']}|$closed';

  @override
  Path buildPath(Map<String, String> live) {
    final points = _parsePoints(live['points'] ?? '');
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    if (closed) path.close();
    return path;
  }
}

double? _num(String? raw) {
  if (raw == null) return null;
  return double.tryParse(raw.trim());
}

List<Offset> _parsePoints(String raw) {
  final tokens =
      raw.split(RegExp(r'[\s,]+')).where((t) => t.isNotEmpty).toList();
  final out = <Offset>[];
  for (var i = 0; i + 1 < tokens.length; i += 2) {
    final x = double.tryParse(tokens[i]);
    final y = double.tryParse(tokens[i + 1]);
    if (x == null || y == null) continue;
    out.add(Offset(x, y));
  }
  return out;
}
