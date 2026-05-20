import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../parser/svg_node.dart';
import 'evaluator.dart';

/// Paints an [SvgRoot] at a given timeline position. Mutating [timeSeconds]
/// and triggering a repaint is enough to animate; the painter has no state.
class AnimatedSvgPainter extends CustomPainter {
  AnimatedSvgPainter({
    required this.root,
    required this.cyclePeriodSeconds,
    this.animation,
    this.position = 0.0,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.transform,
    this.transformAlignment = Alignment.center,
    this.colorFilter,
    this.opacity = 1.0,
    this.clipBehavior = Clip.hardEdge,
    this.colorTween,
    this.transformTween,
    this.opacityTween,
  }) : super(repaint: animation);

  final SvgRoot root;

  /// Period of one full cycle, derived once at construction from the SVG's
  /// natural cycle (or overridden by the controller's duration). Used to
  /// turn a normalised position into a wall-clock time for the SMIL eval.
  final double cyclePeriodSeconds;

  /// Live animation value. When non-null, the painter reads `value` on each
  /// frame and triggers its own repaints — no widget rebuild required. When
  /// null, [position] is used as the fixed source.
  final Animation<double>? animation;

  /// Fallback position when [animation] is null.
  final double position;

  final BoxFit fit;
  final Alignment alignment;
  final Matrix4? transform;
  final Alignment transformAlignment;
  final ColorFilter? colorFilter;
  final double opacity;
  final Clip clipBehavior;

  final Animatable<Color?>? colorTween;
  final Animatable<Matrix4>? transformTween;
  final Animatable<double>? opacityTween;

  double get _liveT {
    final source = animation;
    if (source != null) return source.value.clamp(0.0, 1.0);
    return position.clamp(0.0, 1.0);
  }

  ColorFilter? get _effectiveColorFilter {
    final tween = colorTween;
    if (tween != null) {
      final color = tween.transform(_liveT);
      if (color != null) {
        return ColorFilter.mode(color, BlendMode.srcIn);
      }
    }
    return colorFilter;
  }

  Matrix4? get _effectiveTransform {
    final tween = transformTween;
    if (tween != null) return tween.transform(_liveT);
    return transform;
  }

  double get _effectiveOpacity {
    final tween = opacityTween;
    if (tween != null) return tween.transform(_liveT).clamp(0.0, 1.0);
    return opacity.clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final viewBox = root.viewBox;
    if (viewBox.isEmpty || size.isEmpty) return;

    final t = _liveT;
    final filter = _effectiveColorFilter;
    final dim = _effectiveOpacity;
    final userTransform = _effectiveTransform;
    final timeSeconds = t * cyclePeriodSeconds;

    final needsLayer = filter != null || dim < 1.0;
    if (needsLayer) {
      // For srcOver compositing, [Paint.color]'s alpha controls layer
      // transparency and the RGB acts as a tint. We only want to dim, not
      // tint, so use opaque white scaled to [dim].
      final paint = Paint()
        ..color = const Color(0xffffffff).withValues(alpha: dim);
      if (filter != null) paint.colorFilter = filter;
      canvas.saveLayer(Offset.zero & size, paint);
    } else {
      canvas.save();
    }

    // try/finally ensures the canvas state never leaks if anything below
    // throws (e.g. `path_drawing.parseSvgPathData` on a malformed `d`).
    // An unbalanced `save` corrupts every subsequent paint on the same
    // canvas, so this guarantee is non-negotiable even on the error path.
    try {
      if (clipBehavior != Clip.none) {
        canvas.clipRect(
          Offset.zero & size,
          doAntiAlias: clipBehavior == Clip.antiAlias ||
              clipBehavior == Clip.antiAliasWithSaveLayer,
        );
      }

      if (userTransform != null && !_isIdentity(userTransform)) {
        final pivot = _pivotFromAlignment(transformAlignment, size);
        canvas.translate(pivot.dx, pivot.dy);
        canvas.transform(userTransform.storage);
        canvas.translate(-pivot.dx, -pivot.dy);
      }

      final fitted = applyBoxFit(fit, viewBox.size, size);
      final scaleX = fitted.destination.width / viewBox.width;
      final scaleY = fitted.destination.height / viewBox.height;
      final slackX = size.width - fitted.destination.width;
      final slackY = size.height - fitted.destination.height;
      final dx = (alignment.x + 1.0) / 2.0 * slackX;
      final dy = (alignment.y + 1.0) / 2.0 * slackY;
      canvas.translate(dx, dy);
      canvas.scale(scaleX, scaleY);
      canvas.translate(-viewBox.left, -viewBox.top);

      final inheritedAttributes = <String, String>{};
      for (final node in root.children) {
        _paintNode(canvas, node, inheritedAttributes, timeSeconds);
      }
    } finally {
      canvas.restore();
    }
  }

  Offset _pivotFromAlignment(Alignment a, Size size) {
    return Offset(
      (a.x + 1.0) / 2.0 * size.width,
      (a.y + 1.0) / 2.0 * size.height,
    );
  }

  void _paintNode(
    Canvas canvas,
    SvgNode node,
    Map<String, String> inheritedAttributes,
    double timeSeconds,
  ) {
    final evaluation = evaluateNode(
      timeSeconds: timeSeconds,
      baseTransform: node.baseTransform,
      baseAttributes: node.attributes,
      animations: node.animations,
    );

    canvas.save();
    try {
      if (!_isIdentity(evaluation.transform)) {
        canvas.transform(evaluation.transform.storage);
      }

      final merged = _mergeAttributes(inheritedAttributes, evaluation.attributes);

      if (node is SvgGroup) {
        final groupOpacity = _opacityOf(merged);
        final hasLayer = groupOpacity < 1.0;
        if (hasLayer) {
          canvas.saveLayer(
            null,
            Paint()
              ..color = const Color(0xffffffff).withValues(alpha: groupOpacity),
          );
        }
        try {
          // SVG `opacity` is non-inheriting: it applies to the element only.
          // The group's opacity is already on the saveLayer, so children must
          // start with their own (defaulting to 1.0).
          final childAttributes = merged.containsKey('opacity')
              ? (Map<String, String>.of(merged)..remove('opacity'))
              : merged;
          for (final child in node.children) {
            _paintNode(canvas, child, childAttributes, timeSeconds);
          }
        } finally {
          if (hasLayer) canvas.restore();
        }
      } else if (node is SvgShape) {
        _paintShape(canvas, node, merged);
      }
    } finally {
      canvas.restore();
    }
  }

  void _paintShape(
    Canvas canvas,
    SvgShape shape,
    Map<String, String> live,
  ) {
    final path = shape.resolvePath(live);
    final opacity = _opacityOf(live);

    final fill = parseSvgColor(live['fill'] ?? 'black');
    if (fill != null) {
      final fillOpacity = _parseClampedOpacity(live['fill-opacity']);
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fill.withValues(
            alpha: (fill.a * fillOpacity * opacity).clamp(0.0, 1.0),
          ),
      );
    }

    final stroke = parseSvgColor(live['stroke'] ?? 'none');
    if (stroke != null) {
      final strokeOpacity = _parseClampedOpacity(live['stroke-opacity']);
      final strokeWidth =
          double.tryParse(live['stroke-width'] ?? '') ?? 1.0;
      final dashPattern = _parseLengthList(live['stroke-dasharray']);
      final dashOffset =
          double.tryParse(live['stroke-dashoffset'] ?? '') ?? 0.0;
      final strokePath = dashPattern.isEmpty
          ? path
          : _dashedPath(path, dashPattern, dashOffset);
      canvas.drawPath(
        strokePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = _strokeCap(live['stroke-linecap'])
          ..strokeJoin = _strokeJoin(live['stroke-linejoin'])
          ..color = stroke.withValues(
            alpha: (stroke.a * strokeOpacity * opacity).clamp(0.0, 1.0),
          ),
      );
    }
  }

  double _parseClampedOpacity(String? raw) {
    if (raw == null) return 1.0;
    return (double.tryParse(raw) ?? 1.0).clamp(0.0, 1.0);
  }

  List<double> _parseLengthList(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == 'none') {
      return const [];
    }
    return raw
        .split(RegExp(r'[\s,]+'))
        .where((t) => t.isNotEmpty)
        // Reject non-finite — NaN in a dash entry causes `_dashedPath` to
        // never terminate (NaN comparisons are always false).
        .map((t) {
          final value = double.tryParse(t);
          if (value == null || !value.isFinite || value < 0.0) return 0.0;
          return value;
        })
        .toList(growable: false);
  }

  /// Hard cap on dash iterations per path metric. Pathological patterns
  /// (e.g. `stroke-dasharray="0.0001"` on a 1000-unit path) would otherwise
  /// allocate millions of segments and OOM Skia.
  static const int _dashIterationCap = 10000;

  Path _dashedPath(Path source, List<double> rawPattern, double offset) {
    // SVG: a single-value pattern repeats as [a, a]. Total pattern length
    // must be positive.
    var pattern = rawPattern;
    if (pattern.length.isOdd) {
      pattern = [...pattern, ...pattern];
    }
    final patternLength = pattern.fold<double>(0.0, (a, b) => a + b);
    if (!patternLength.isFinite || patternLength <= 0.0) return source;

    double startOffset = offset.isFinite ? offset % patternLength : 0.0;
    if (startOffset < 0.0) startOffset += patternLength;

    final result = Path();
    for (final metric in source.computeMetrics()) {
      final pathLength = metric.length;
      if (!pathLength.isFinite || pathLength <= 0.0) continue;

      var patternIndex = 0;
      var remainingInSegment = pattern[0];
      var drawing = true;

      // Advance through the pattern by [startOffset] before walking.
      var skip = startOffset;
      var skipIterations = 0;
      while (skip > 0.0 && skipIterations < pattern.length) {
        if (skip < remainingInSegment) {
          remainingInSegment -= skip;
          skip = 0.0;
        } else {
          skip -= remainingInSegment;
          patternIndex = (patternIndex + 1) % pattern.length;
          remainingInSegment = pattern[patternIndex];
          drawing = !drawing;
        }
        skipIterations++;
      }

      var position = 0.0;
      var iterations = 0;
      while (position < pathLength && iterations < _dashIterationCap) {
        final segmentEnd =
            (position + remainingInSegment).clamp(0.0, pathLength);
        if (drawing && segmentEnd > position) {
          result.addPath(metric.extractPath(position, segmentEnd), Offset.zero);
        }
        if (segmentEnd >= pathLength) break;
        position = segmentEnd;
        patternIndex = (patternIndex + 1) % pattern.length;
        remainingInSegment = pattern[patternIndex];
        drawing = !drawing;
        iterations++;
      }
    }
    return result;
  }

  Map<String, String> _mergeAttributes(
    Map<String, String> inherited,
    Map<String, String> local,
  ) {
    // Local always wins (including the special `inherit` case where the
    // child re-asserts a property). For attributes the child omits we keep
    // the inherited value so SVG-style cascade works for paint properties.
    if (inherited.isEmpty) return local;
    final out = Map<String, String>.of(inherited);
    out.addAll(local);
    return out;
  }

  double _opacityOf(Map<String, String> attrs) {
    final raw = attrs['opacity'];
    if (raw == null) return 1.0;
    return (double.tryParse(raw) ?? 1.0).clamp(0.0, 1.0);
  }

  StrokeCap _strokeCap(String? raw) {
    switch (raw) {
      case 'round':
        return StrokeCap.round;
      case 'square':
        return StrokeCap.square;
    }
    return StrokeCap.butt;
  }

  StrokeJoin _strokeJoin(String? raw) {
    switch (raw) {
      case 'round':
        return StrokeJoin.round;
      case 'bevel':
        return StrokeJoin.bevel;
    }
    return StrokeJoin.miter;
  }

  bool _isIdentity(Matrix4 m) {
    return m.storage[0] == 1.0 &&
        m.storage[5] == 1.0 &&
        m.storage[10] == 1.0 &&
        m.storage[15] == 1.0 &&
        m.storage[1] == 0.0 &&
        m.storage[2] == 0.0 &&
        m.storage[4] == 0.0 &&
        m.storage[6] == 0.0 &&
        m.storage[8] == 0.0 &&
        m.storage[9] == 0.0 &&
        m.storage[12] == 0.0 &&
        m.storage[13] == 0.0 &&
        m.storage[14] == 0.0;
  }

  @override
  bool shouldRepaint(AnimatedSvgPainter oldDelegate) {
    return oldDelegate.root != root ||
        oldDelegate.animation != animation ||
        oldDelegate.position != position ||
        oldDelegate.cyclePeriodSeconds != cyclePeriodSeconds ||
        oldDelegate.fit != fit ||
        oldDelegate.alignment != alignment ||
        oldDelegate.transform != transform ||
        oldDelegate.transformAlignment != transformAlignment ||
        oldDelegate.colorFilter != colorFilter ||
        oldDelegate.opacity != opacity ||
        oldDelegate.clipBehavior != clipBehavior ||
        oldDelegate.colorTween != colorTween ||
        oldDelegate.transformTween != transformTween ||
        oldDelegate.opacityTween != opacityTween;
  }
}
