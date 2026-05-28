import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';
import 'package:xml/xml.dart';

import 'svg_animation.dart';
import 'svg_node.dart';
import 'transform_parser.dart';

/// Parse an SVG document string into a renderable [SvgRoot].
///
/// Only the subset of SVG we actually need is supported. Unknown elements
/// are skipped silently; unknown attributes are kept verbatim in the
/// attribute bag (so future animation targets keep working).
SvgRoot parseSvg(String source) {
  final document = XmlDocument.parse(source);
  final root = document.rootElement;
  if (root.name.local != 'svg') {
    throw FormatException(
      'Expected <svg> root element, got <${root.name.local}>',
    );
  }

  final viewBox = _parseViewBox(root);
  final intrinsicSize = _parseIntrinsicSize(root);
  final children = _parseChildren(root);

  return SvgRoot(
    viewBox: viewBox,
    intrinsicSize: intrinsicSize,
    children: children,
  );
}

List<SvgNode> _parseChildren(XmlElement parent) {
  final out = <SvgNode>[];
  for (final element in parent.childElements) {
    final node = _parseElement(element);
    if (node != null) out.add(node);
  }
  return out;
}

SvgNode? _parseElement(XmlElement element) {
  switch (element.name.local) {
    case 'g':
      return _parseGroup(element);
    case 'path':
      return _parseShape(element, SvgPathShape.new);
    case 'rect':
      return _parseShape(element, SvgRectShape.new);
    case 'circle':
      return _parseShape(element, SvgCircleShape.new);
    case 'ellipse':
      return _parseShape(element, SvgEllipseShape.new);
    case 'line':
      return _parseShape(element, SvgLineShape.new);
    case 'polygon':
      return _parsePolygon(element, closed: true);
    case 'polyline':
      return _parsePolygon(element, closed: false);
  }
  return null;
}

SvgGroup _parseGroup(XmlElement element) {
  return SvgGroup(
    baseTransform: _readTransform(element),
    attributes: _readAttributes(element),
    animations: _readAnimations(element),
    children: _parseChildren(element),
  );
}

SvgShape _parseShape(
  XmlElement element,
  SvgShape Function({
    required Matrix4 baseTransform,
    required Map<String, String> attributes,
    required List<SvgAnimation> animations,
  }) factory,
) {
  return factory(
    baseTransform: _readTransform(element),
    attributes: _readAttributes(element),
    animations: _readAnimations(element),
  );
}

SvgPolygonShape _parsePolygon(XmlElement element, {required bool closed}) {
  return SvgPolygonShape(
    baseTransform: _readTransform(element),
    attributes: _readAttributes(element),
    animations: _readAnimations(element),
    closed: closed,
  );
}

Matrix4 _readTransform(XmlElement element) {
  final raw = element.getAttribute('transform');
  if (raw == null || raw.isEmpty) return Matrix4.identity();
  return parseSvgTransform(raw);
}

Map<String, String> _readAttributes(XmlElement element) {
  final out = <String, String>{};
  for (final attribute in element.attributes) {
    final name = attribute.name.local;
    if (name == 'transform') continue; // tracked separately
    out[name] = attribute.value;
  }
  final style = out.remove('style');
  if (style != null) {
    for (final declaration in style.split(';')) {
      final colon = declaration.indexOf(':');
      if (colon <= 0) continue;
      final key = declaration.substring(0, colon).trim();
      final value = declaration.substring(colon + 1).trim();
      if (key.isEmpty) continue;
      out.putIfAbsent(key, () => value);
    }
  }
  return out;
}

List<SvgAnimation> _readAnimations(XmlElement element) {
  final out = <SvgAnimation>[];
  for (final child in element.childElements) {
    switch (child.name.local) {
      case 'animateTransform':
        final parsed = _parseAnimateTransform(child);
        if (parsed != null) out.add(parsed);
      case 'animate':
        final parsed = _parseAnimate(child);
        if (parsed != null) out.add(parsed);
    }
  }
  return out;
}

SvgAnimateTransform? _parseAnimateTransform(XmlElement element) {
  final typeName = element.getAttribute('type') ?? 'translate';
  final type = _transformTypeFor(typeName);
  if (type == null) return null;

  final rawValues = element.getAttribute('values');
  List<List<double>>? entries;
  if (rawValues != null) {
    entries = rawValues
        .split(';')
        .map((entry) => parseNumberList(entry))
        .where((entry) => entry.isNotEmpty)
        .toList(growable: false);
  } else {
    final from = element.getAttribute('from');
    final to = element.getAttribute('to');
    final by = element.getAttribute('by');
    if (from != null && to != null) {
      entries = [parseNumberList(from), parseNumberList(to)];
    } else if (from != null && by != null) {
      final base = parseNumberList(from);
      final delta = parseNumberList(by);
      final target = List<double>.generate(
        base.length,
        (i) => base[i] + (i < delta.length ? delta[i] : 0.0),
      );
      entries = [base, target];
    }
  }
  if (entries == null || entries.isEmpty) return null;

  final calcMode = _parseCalcMode(element.getAttribute('calcMode'));
  final keyTimes = _parseKeyTimes(element, entries.length);
  final keySplines = _parseKeySplines(
    element.getAttribute('keySplines'),
    expectedCount: entries.length - 1,
  );

  return SvgAnimateTransform(
    duration: _parseDuration(element.getAttribute('dur')),
    repeatCount: _parseRepeatCount(element.getAttribute('repeatCount')),
    begin:
        _parseDuration(element.getAttribute('begin'), fallback: Duration.zero),
    additive: _parseAdditive(element.getAttribute('additive')),
    keyTimes: keyTimes,
    type: type,
    values: entries,
    calcMode: calcMode,
    keySplines: keySplines,
  );
}

SvgAnimateAttribute? _parseAnimate(XmlElement element) {
  final attributeName = element.getAttribute('attributeName');
  if (attributeName == null) return null;

  final rawValues = element.getAttribute('values');
  List<String>? values;
  if (rawValues != null) {
    values = rawValues
        .split(';')
        .map((entry) => entry.trim())
        .toList(growable: false);
  } else {
    final from = element.getAttribute('from');
    final to = element.getAttribute('to');
    final by = element.getAttribute('by');
    if (from != null && to != null) {
      values = [from, to];
    } else if (from != null && by != null) {
      // Best-effort: numeric attributes only. Non-numeric `by` is undefined.
      final base = double.tryParse(from);
      final delta = double.tryParse(by);
      if (base != null && delta != null) {
        values = [from, (base + delta).toString()];
      }
    }
  }
  if (values == null || values.isEmpty) return null;

  final valueType = _valueTypeFor(attributeName);
  final calcMode = _parseCalcMode(element.getAttribute('calcMode'));
  final keyTimes = _parseKeyTimes(element, values.length);
  final keySplines = _parseKeySplines(
    element.getAttribute('keySplines'),
    expectedCount: values.length - 1,
  );

  return SvgAnimateAttribute(
    duration: _parseDuration(element.getAttribute('dur')),
    repeatCount: _parseRepeatCount(element.getAttribute('repeatCount')),
    begin:
        _parseDuration(element.getAttribute('begin'), fallback: Duration.zero),
    additive: _parseAdditive(element.getAttribute('additive')),
    keyTimes: keyTimes,
    attributeName: attributeName,
    values: values,
    valueType: valueType,
    calcMode: calcMode,
    keySplines: keySplines,
  );
}

SvgCalcMode _parseCalcMode(String? raw) {
  switch (raw) {
    case 'spline':
      return SvgCalcMode.spline;
    case 'discrete':
      return SvgCalcMode.discrete;
    case 'paced':
      return SvgCalcMode.paced;
  }
  return SvgCalcMode.linear;
}

List<List<double>> _parseKeySplines(String? raw, {required int expectedCount}) {
  if (raw == null || expectedCount <= 0) return const [];
  final segments = raw
      .split(';')
      .map((entry) => parseNumberList(entry))
      .where((entry) => entry.length == 4)
      .toList(growable: false);
  if (segments.length != expectedCount) {
    return const [];
  }
  return segments;
}

SvgTransformType? _transformTypeFor(String raw) {
  switch (raw) {
    case 'translate':
      return SvgTransformType.translate;
    case 'rotate':
      return SvgTransformType.rotate;
    case 'scale':
      return SvgTransformType.scale;
    case 'skewX':
      return SvgTransformType.skewX;
    case 'skewY':
      return SvgTransformType.skewY;
    case 'matrix':
      return SvgTransformType.matrix;
  }
  return null;
}

SvgAnimateValueType _valueTypeFor(String attributeName) {
  switch (attributeName) {
    case 'fill':
    case 'stroke':
    case 'stop-color':
      return SvgAnimateValueType.paint;
    case 'color':
      return SvgAnimateValueType.color;
  }
  return SvgAnimateValueType.number;
}

List<double> _parseKeyTimes(XmlElement element, int valueCount) {
  final raw = element.getAttribute('keyTimes');
  if (raw == null) {
    if (valueCount <= 1) return const [0.0];
    return List<double>.generate(
      valueCount,
      (i) => i / (valueCount - 1),
    );
  }
  final out = raw
      .split(';')
      .map((entry) => double.tryParse(entry.trim()))
      .whereType<double>()
      .toList(growable: false);
  if (out.length != valueCount) {
    // Re-derive linearly if keyTimes doesn't match values count.
    return List<double>.generate(
      valueCount,
      (i) => valueCount == 1 ? 0.0 : i / (valueCount - 1),
    );
  }
  return out;
}

Duration _parseDuration(String? raw, {Duration fallback = Duration.zero}) {
  if (raw == null || raw.isEmpty) return fallback;
  final trimmed = raw.trim();
  if (trimmed == 'indefinite') return fallback;
  double? parsedSeconds;
  if (trimmed.endsWith('ms')) {
    final value = double.tryParse(trimmed.substring(0, trimmed.length - 2));
    if (value != null) parsedSeconds = value / 1000.0;
  } else if (trimmed.endsWith('s')) {
    parsedSeconds = double.tryParse(trimmed.substring(0, trimmed.length - 1));
  } else {
    // Bare number, treated as seconds.
    parsedSeconds = double.tryParse(trimmed);
  }
  // Reject NaN, Infinity, and negatives: `(value * 1e6).round()` would throw
  // on non-finite inputs, and a negative SMIL duration has no defined
  // playback semantics — fall back to whatever the caller wants instead.
  if (parsedSeconds == null || !parsedSeconds.isFinite || parsedSeconds < 0.0) {
    return fallback;
  }
  return Duration(microseconds: (parsedSeconds * 1e6).round());
}

double _parseRepeatCount(String? raw) {
  if (raw == null || raw.isEmpty) return 1.0;
  if (raw.trim() == 'indefinite') return double.infinity;
  final parsed = double.tryParse(raw.trim());
  if (parsed == null || parsed.isNaN || parsed < 0.0) return 1.0;
  return parsed;
}

AdditiveMode _parseAdditive(String? raw) {
  return raw == 'sum' ? AdditiveMode.sum : AdditiveMode.replace;
}

Rect _parseViewBox(XmlElement root) {
  final raw = root.getAttribute('viewBox');
  if (raw != null) {
    final numbers = parseNumberList(raw);
    if (numbers.length == 4 &&
        numbers[2] > 0.0 &&
        numbers[3] > 0.0 &&
        numbers.every((n) => n.isFinite)) {
      return Rect.fromLTWH(numbers[0], numbers[1], numbers[2], numbers[3]);
    }
  }
  final width = double.tryParse(root.getAttribute('width') ?? '');
  final height = double.tryParse(root.getAttribute('height') ?? '');
  if (width != null &&
      height != null &&
      width.isFinite &&
      height.isFinite &&
      width > 0.0 &&
      height > 0.0) {
    return Rect.fromLTWH(0.0, 0.0, width, height);
  }
  return const Rect.fromLTWH(0.0, 0.0, 100.0, 100.0);
}

Size? _parseIntrinsicSize(XmlElement root) {
  final width = double.tryParse(root.getAttribute('width') ?? '');
  final height = double.tryParse(root.getAttribute('height') ?? '');
  if (width == null || height == null) return null;
  if (!width.isFinite || !height.isFinite || width <= 0.0 || height <= 0.0) {
    return null;
  }
  return Size(width, height);
}
