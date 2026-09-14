import 'color_swaps.dart';
import 'parse_cache.dart';
import 'parser/svg_animation.dart';
import 'parser/svg_node.dart';
import 'render/evaluator.dart';

/// Attributes whose value is a paint, and so a candidate for replacement.
///
/// `fill` is the one to be careful with: on an `<animate>` element it means
/// the SMIL fill mode (`fill="freeze"`), not a colour. That case is safe here
/// by construction — animation elements are parsed into [SvgAnimation] models
/// and never reach a node's attribute map — and doubly safe because
/// [parseSvgColor] returns null for `freeze`, which this skips.
const _kPaintAttributes = <String>{
  'fill',
  'stroke',
  'stop-color',
  'color',
  'flood-color',
  'lighting-color',
};

/// Returns [root] with every paint that [swaps] knows about replaced.
///
/// The swap happens here — once, on the parsed tree — rather than per shape
/// per frame in the painter, for one decisive reason: **an SVG can animate its
/// own `fill`.** Recolouring the keyframe values means the SMIL evaluator
/// interpolates in the *replacement* palette, so a fill animating green →
/// white becomes pink → white throughout, not just at the instant it sits
/// exactly on a keyframe. Swapping at paint time could only ever match the
/// endpoints, and re-matching the evaluator's interpolated output would apply
/// a two-entry swap (A→B, B→A) twice and cancel it out.
///
/// The tree is immutable, so the result is safe to cache and share; the
/// painter and evaluator need no knowledge of colour replacement at all.
SvgRoot recolorSvg(SvgRoot root, SvgColorSwaps swaps) {
  if (swaps.isEmpty) return root;
  return SvgRoot(
    viewBox: root.viewBox,
    intrinsicSize: root.intrinsicSize,
    children: _recolorNodes(root.children, swaps),
  );
}

/// [recolorSvg] against the shared parse cache.
///
/// [sourceKey] is the cache key of the *un*recoloured root (`asset:…` /
/// `url:…`), or null for a source that isn't cacheable (a raw SVG string, or
/// an already-parsed root handed in by the caller). Recolouring is cheap, but
/// it does rebuild the node tree — and with it every shape's path cache — so
/// a list of 40 rows rendering one asset in one palette should pay for it
/// once, not 40 times.
SvgRoot recolorSvgCached(
  SvgRoot root,
  SvgColorSwaps? swaps, {
  required String? sourceKey,
}) {
  if (swaps == null || swaps.isEmpty) return root;
  if (sourceKey == null) return recolorSvg(root, swaps);
  final cacheKey = recolorCacheKey(sourceKey, swaps);
  final cached = SvgParseCache.get(cacheKey);
  if (cached != null) return cached;
  final recolored = recolorSvg(root, swaps);
  SvgParseCache.put(cacheKey, recolored);
  return recolored;
}

/// Cache key for [sourceKey] rendered through [swaps]. The `#` separator can't
/// collide with an asset path or URL key, both of which are `<scheme>:<path>`.
String recolorCacheKey(String sourceKey, SvgColorSwaps swaps) =>
    '$sourceKey#${swaps.cacheKey}';

List<SvgNode> _recolorNodes(List<SvgNode> nodes, SvgColorSwaps swaps) {
  return nodes.map((node) => _recolorNode(node, swaps)).toList(growable: false);
}

SvgNode _recolorNode(SvgNode node, SvgColorSwaps swaps) {
  final attributes = _recolorAttributes(node.attributes, swaps);
  final animations = _recolorAnimations(node.animations, swaps);
  // Exhaustive by virtue of SvgNode / SvgShape being sealed: a new shape type
  // fails to compile here until it is handled.
  return switch (node) {
    SvgGroup() => SvgGroup(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
        children: _recolorNodes(node.children, swaps),
      ),
    SvgPathShape() => SvgPathShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
      ),
    SvgRectShape() => SvgRectShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
      ),
    SvgCircleShape() => SvgCircleShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
      ),
    SvgEllipseShape() => SvgEllipseShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
      ),
    SvgLineShape() => SvgLineShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
      ),
    SvgPolygonShape() => SvgPolygonShape(
        baseTransform: node.baseTransform,
        attributes: attributes,
        animations: animations,
        closed: node.closed,
      ),
  };
}

/// Returns the same map instance when no paint on this node changed, so an
/// untouched subtree costs no allocations beyond the node itself.
Map<String, String> _recolorAttributes(
  Map<String, String> attributes,
  SvgColorSwaps swaps,
) {
  Map<String, String>? out;
  for (final name in _kPaintAttributes) {
    final raw = attributes[name];
    if (raw == null) continue;
    final swapped = _swapPaint(raw, swaps);
    if (swapped == null) continue;
    (out ??= Map<String, String>.of(attributes))[name] = swapped;
  }
  return out ?? attributes;
}

List<SvgAnimation> _recolorAnimations(
  List<SvgAnimation> animations,
  SvgColorSwaps swaps,
) {
  List<SvgAnimation>? out;
  for (var i = 0; i < animations.length; i++) {
    final animation = animations[i];
    // The parser already decided which attributes interpolate as colour;
    // trust that classification rather than re-deriving it from the name.
    if (animation is! SvgAnimateAttribute) continue;
    if (animation.valueType == SvgAnimateValueType.number) continue;
    final values = _swapPaintValues(animation.values, swaps);
    if (values == null) continue;
    (out ??= List<SvgAnimation>.of(animations))[i] = SvgAnimateAttribute(
      duration: animation.duration,
      repeatCount: animation.repeatCount,
      begin: animation.begin,
      additive: animation.additive,
      keyTimes: animation.keyTimes,
      attributeName: animation.attributeName,
      values: values,
      valueType: animation.valueType,
      calcMode: animation.calcMode,
      keySplines: animation.keySplines,
    );
  }
  return out ?? animations;
}

/// Null when no keyframe changed.
List<String>? _swapPaintValues(List<String> values, SvgColorSwaps swaps) {
  List<String>? out;
  for (var i = 0; i < values.length; i++) {
    final swapped = _swapPaint(values[i], swaps);
    if (swapped == null) continue;
    (out ??= List<String>.of(values))[i] = swapped;
  }
  return out;
}

/// The replacement paint string for [raw], or null to leave it exactly as the
/// author wrote it.
///
/// Left alone: anything [parseSvgColor] doesn't recognise as a colour —
/// `none`, `inherit`, `currentColor`, a `url(#gradient)` paint server — and
/// any colour the table has no entry for. Matching on the *parsed* colour is
/// the point: the author's spelling (`#48C374` vs `#48c374` vs a named
/// colour) never has to match the caller's.
String? _swapPaint(String raw, SvgColorSwaps swaps) {
  final color = parseSvgColor(raw);
  if (color == null) return null;
  final swapped = swaps.apply(color);
  if (swapped == color) return null;
  return formatSvgColor(swapped);
}
