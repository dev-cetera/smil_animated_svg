import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'parse_cache.dart';
import 'parser/svg_node.dart';
import 'parser/svg_parser.dart';
import 'render/svg_painter.dart';

/// Signature for [SvgFrame.errorBuilder] / [AnimatedSvg.errorBuilder].
/// Matches [Image.errorBuilder].
typedef AnimatedSvgErrorBuilder = Widget Function(
  BuildContext context,
  Object error,
  StackTrace? stackTrace,
);

/// Renders a single frozen frame of an SVG at [position] (0..1 across the
/// SVG's natural cycle).
///
/// Pure renderer — no ticker, no animation controller, no rebuild scheduling.
/// Drop one in for a static SVG, or wrap one in an `AnimatedBuilder` to drive
/// [position] (and any of the other knobs) from a Flutter animation. The
/// playing convenience is [AnimatedSvg].
///
/// Honours the loaded SVG's parse cache: rendering the same asset path or
/// URL in many widgets at once parses it once.
class SvgFrame extends StatefulWidget {
  /// Load the SVG from a Flutter asset bundle path.
  const SvgFrame.asset(
    String this.assetPath, {
    super.key,
    this.bundle,
    this.position = 0.0,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode = BlendMode.srcIn,
    this.colorFilter,
    this.opacity = 1.0,
    this.transform,
    this.transformAlignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
    this.placeholderBuilder,
    this.errorBuilder,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : svgString = null,
        svgRoot = null,
        url = null,
        httpClient = null,
        headers = null;

  /// Render an already-parsed [SvgRoot] (zero load cost).
  const SvgFrame.parsed(
    SvgRoot this.svgRoot, {
    super.key,
    this.position = 0.0,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode = BlendMode.srcIn,
    this.colorFilter,
    this.opacity = 1.0,
    this.transform,
    this.transformAlignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : assetPath = null,
        svgString = null,
        bundle = null,
        url = null,
        httpClient = null,
        headers = null,
        placeholderBuilder = null,
        errorBuilder = null;

  /// Render from a raw SVG string.
  const SvgFrame.string(
    String this.svgString, {
    super.key,
    this.position = 0.0,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode = BlendMode.srcIn,
    this.colorFilter,
    this.opacity = 1.0,
    this.transform,
    this.transformAlignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
    this.errorBuilder,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : assetPath = null,
        svgRoot = null,
        bundle = null,
        url = null,
        httpClient = null,
        headers = null,
        placeholderBuilder = null;

  /// Fetch the SVG from [url] over HTTP.
  const SvgFrame.network(
    String this.url, {
    super.key,
    this.position = 0.0,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.alignment = Alignment.center,
    this.color,
    this.colorBlendMode = BlendMode.srcIn,
    this.colorFilter,
    this.opacity = 1.0,
    this.transform,
    this.transformAlignment = Alignment.center,
    this.clipBehavior = Clip.hardEdge,
    this.placeholderBuilder,
    this.errorBuilder,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
    this.httpClient,
    this.headers,
  })  : assetPath = null,
        svgString = null,
        svgRoot = null,
        bundle = null;

  final String? assetPath;
  final String? svgString;
  final String? url;
  final SvgRoot? svgRoot;
  final AssetBundle? bundle;
  final http.Client? httpClient;
  final Map<String, String>? headers;

  /// Position in the SVG's natural cycle: `0.0` first frame, `1.0` last.
  /// Clamped to `[0, 1]`.
  final double position;

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;
  final Color? color;
  final BlendMode colorBlendMode;
  final ColorFilter? colorFilter;

  /// Multiplied with the SVG's intrinsic alpha. `1.0` is opaque, `0.0` is
  /// transparent. Folded into the same offscreen layer used by [colorFilter]
  /// when both are set, so the cost is one [Canvas.saveLayer], not two.
  final double opacity;

  final Matrix4? transform;
  final AlignmentGeometry transformAlignment;
  final Clip clipBehavior;
  final WidgetBuilder? placeholderBuilder;
  final AnimatedSvgErrorBuilder? errorBuilder;
  final String? semanticsLabel;
  final bool excludeFromSemantics;

  /// Drop all entries from the in-memory parse cache. Useful in tests.
  /// Hot reload already invalidates automatically.
  static void clearCache() => SvgParseCache.clear();

  @override
  State<SvgFrame> createState() => _SvgFrameState();
}

class _SvgFrameState extends State<SvgFrame> {
  SvgRoot? _root;
  Object? _loadError;
  StackTrace? _loadStack;

  /// Monotonically increasing token incremented on every `_loadIfNeeded`
  /// entry. Async load callbacks compare their captured token against
  /// [_loadGeneration] before calling setState, so a load that started for
  /// the previous source can never overwrite the result of a later one.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    // Synchronous cache hit avoids the one-frame placeholder when the SVG
    // is already in the parse cache (e.g. switching modes/samples).
    _root = _trySyncCache();
    if (_root == null) _loadIfNeeded();
  }

  SvgRoot? _trySyncCache() {
    if (widget.svgRoot != null) return widget.svgRoot;
    if (widget.assetPath != null) {
      return SvgParseCache.get('asset:${widget.assetPath}');
    }
    if (widget.url != null) return SvgParseCache.get('url:${widget.url}');
    return null;
  }

  @override
  void didUpdateWidget(SvgFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath != oldWidget.assetPath ||
        widget.svgString != oldWidget.svgString ||
        widget.svgRoot != oldWidget.svgRoot ||
        widget.url != oldWidget.url) {
      _root = null;
      _loadError = null;
      _loadStack = null;
      // _loadIfNeeded bumps the generation, so a sync cache hit below is
      // also safely fenced against any in-flight load for the prior source.
      _loadIfNeeded();
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    SvgParseCache.clear();
    _root = null;
    _loadError = null;
    _loadStack = null;
    _loadIfNeeded();
  }

  Future<void> _loadIfNeeded() async {
    final generation = ++_loadGeneration;
    if (widget.svgRoot != null) {
      _applyRoot(widget.svgRoot, generation);
      return;
    }
    if (widget.svgString != null) {
      _parseInto(widget.svgString!, cacheKey: null, generation: generation);
      return;
    }
    if (widget.url != null) {
      final cacheKey = 'url:${widget.url}';
      final cached = SvgParseCache.get(cacheKey);
      if (cached != null) {
        _applyRoot(cached, generation);
        return;
      }
      final ownsClient = widget.httpClient == null;
      final client = widget.httpClient ?? http.Client();
      try {
        final response = await client.get(
          Uri.parse(widget.url!),
          headers: widget.headers,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw http.ClientException(
            'HTTP ${response.statusCode}',
            Uri.parse(widget.url!),
          );
        }
        _parseInto(response.body, cacheKey: cacheKey, generation: generation);
      } catch (error, stack) {
        _reportError(error, stack, generation: generation);
      } finally {
        if (ownsClient) client.close();
      }
      return;
    }
    final assetPath = widget.assetPath;
    if (assetPath == null) return;
    final cacheKey = 'asset:$assetPath';
    final cached = SvgParseCache.get(cacheKey);
    if (cached != null) {
      _applyRoot(cached, generation);
      return;
    }
    final bundle = widget.bundle ?? DefaultAssetBundle.of(context);
    try {
      final source = await bundle.loadString(assetPath);
      _parseInto(source, cacheKey: cacheKey, generation: generation);
    } catch (error, stack) {
      _reportError(error, stack, generation: generation);
    }
  }

  bool _stillCurrent(int generation) =>
      mounted && generation == _loadGeneration;

  void _applyRoot(SvgRoot? root, int generation) {
    if (!_stillCurrent(generation)) return;
    setState(() => _root = root);
  }

  void _parseInto(
    String source, {
    required String? cacheKey,
    required int generation,
  }) {
    try {
      final parsed = parseSvg(source);
      if (cacheKey != null) SvgParseCache.put(cacheKey, parsed);
      _applyRoot(parsed, generation);
    } catch (error, stack) {
      _reportError(error, stack, generation: generation);
    }
  }

  void _reportError(Object error, StackTrace stack, {required int generation}) {
    if (!_stillCurrent(generation)) return;
    setState(() {
      _loadError = error;
      _loadStack = stack;
    });
  }

  @override
  Widget build(BuildContext context) {
    final root = _root;
    final loadError = _loadError;

    Widget child;
    if (loadError != null) {
      final builder = widget.errorBuilder;
      child = builder != null
          ? builder(context, loadError, _loadStack)
          : _sizedBox(child: const SizedBox.shrink());
    } else if (root == null) {
      final builder = widget.placeholderBuilder;
      child = builder != null
          ? _sizedBox(child: builder(context))
          : _sizedBox(child: const SizedBox.shrink());
    } else {
      child = _sizedBox(
        intrinsic: root.intrinsicSize ?? root.viewBox.size,
        child: buildSvgCustomPaint(
          context: context,
          root: root,
          position: widget.position,
          fit: widget.fit,
          alignment: widget.alignment,
          color: widget.color,
          colorBlendMode: widget.colorBlendMode,
          colorFilter: widget.colorFilter,
          opacity: widget.opacity,
          transform: widget.transform,
          transformAlignment: widget.transformAlignment,
          clipBehavior: widget.clipBehavior,
        ),
      );
    }

    if (widget.excludeFromSemantics) return child;
    final semanticsLabel = widget.semanticsLabel;
    if (semanticsLabel == null) return child;
    return Semantics(
      container: true,
      image: true,
      label: semanticsLabel,
      child: child,
    );
  }

  Widget _sizedBox({Widget? child, Size? intrinsic}) {
    final width = widget.width ?? intrinsic?.width;
    final height = widget.height ?? intrinsic?.height;
    return SizedBox(width: width, height: height, child: child);
  }
}

/// Builds the [CustomPaint] used by both [SvgFrame] and [AnimatedSvg]. The
/// painter handles its own per-frame repaints via [animation] when provided
/// — no `AnimatedBuilder` needed.
Widget buildSvgCustomPaint({
  required BuildContext context,
  required SvgRoot root,
  required BoxFit fit,
  required AlignmentGeometry alignment,
  required Color? color,
  required BlendMode colorBlendMode,
  required ColorFilter? colorFilter,
  required double opacity,
  required Matrix4? transform,
  required AlignmentGeometry transformAlignment,
  required Clip clipBehavior,
  double position = 0.0,
  Animation<double>? animation,
  Animatable<Color?>? colorTween,
  Animatable<Matrix4>? transformTween,
  Animatable<double>? opacityTween,
}) {
  final effectiveColorFilter = colorFilter ??
      (color != null ? ColorFilter.mode(color, colorBlendMode) : null);
  // [AlignmentDirectional.resolve] requires a non-null direction; default
  // to LTR when no Directionality ancestor exists (e.g. WidgetsApp before
  // MaterialApp / tests).
  final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

  final cyclePeriod = root.naturalCyclePeriod;
  final cycleSeconds = cyclePeriod.inMicroseconds / 1e6;

  return RepaintBoundary(
    child: CustomPaint(
      painter: AnimatedSvgPainter(
        root: root,
        cyclePeriodSeconds: cycleSeconds,
        animation: animation,
        position: position,
        fit: fit,
        alignment: alignment.resolve(textDirection),
        transform: transform,
        transformAlignment: transformAlignment.resolve(textDirection),
        colorFilter: effectiveColorFilter,
        opacity: opacity,
        clipBehavior: clipBehavior,
        colorTween: colorTween,
        transformTween: transformTween,
        opacityTween: opacityTween,
      ),
    ),
  );
}
