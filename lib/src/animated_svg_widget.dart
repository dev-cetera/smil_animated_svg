import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import 'parse_cache.dart';
import 'parser/svg_node.dart';
import 'parser/svg_parser.dart';
import 'svg_frame.dart';

/// Self-playing SVG widget.
///
/// Owns an [AnimationController] and renders [SvgFrame] at the controlled
/// position each frame. The controller's `duration` defaults to the SVG's
/// natural cycle (longest `dur` in the file); use [curve] to play through
/// that cycle at non-linear rates.
///
/// Supply [position] to freeze the timeline at a specific point in the
/// cycle — the controller doesn't run while [position] is set, so it's the
/// same cost as a [SvgFrame].
///
/// Optional [colorTween], [transformTween], [opacityTween] animate those
/// rendering knobs alongside the cycle, evaluated at the curved controller
/// value. For richer per-frame logic, drive [SvgFrame] yourself inside an
/// [AnimatedBuilder].
///
/// **Pauses when hidden.** The internal ticker uses
/// [TickerProviderStateMixin], so Flutter's [TickerMode] is honoured
/// automatically (inside `Offstage`, `Visibility(maintainState: false)`,
/// etc). The non-`Single` variant is required because `didUpdateWidget`
/// disposes and re-creates the controller when the asset source changes
/// (e.g. swapping `tick.svg` → `tick_love.svg` on a theme toggle), and
/// `SingleTickerProviderStateMixin` refuses to vend a second ticker even
/// after the first is disposed.
class AnimatedSvg extends StatefulWidget {
  const AnimatedSvg.asset(
    String this.assetPath, {
    super.key,
    this.bundle,
    this.duration,
    this.curve = Curves.linear,
    this.autoplay = true,
    this.repeat = true,
    this.stopAt,
    this.position,
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
    this.colorTween,
    this.transformTween,
    this.opacityTween,
    this.placeholderBuilder,
    this.errorBuilder,
    this.semanticsLabel,
    this.excludeFromSemantics = false,
  })  : svgString = null,
        svgRoot = null,
        url = null,
        httpClient = null,
        headers = null;

  const AnimatedSvg.parsed(
    SvgRoot this.svgRoot, {
    super.key,
    this.duration,
    this.curve = Curves.linear,
    this.autoplay = true,
    this.repeat = true,
    this.stopAt,
    this.position,
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
    this.colorTween,
    this.transformTween,
    this.opacityTween,
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

  const AnimatedSvg.string(
    String this.svgString, {
    super.key,
    this.duration,
    this.curve = Curves.linear,
    this.autoplay = true,
    this.repeat = true,
    this.stopAt,
    this.position,
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
    this.colorTween,
    this.transformTween,
    this.opacityTween,
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

  const AnimatedSvg.network(
    String this.url, {
    super.key,
    this.duration,
    this.curve = Curves.linear,
    this.autoplay = true,
    this.repeat = true,
    this.stopAt,
    this.position,
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
    this.colorTween,
    this.transformTween,
    this.opacityTween,
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

  /// Period of one loop. `null` uses the SVG's natural cycle (longest `dur`
  /// in the file). Fallback when both are absent is one second.
  final Duration? duration;
  final Curve curve;
  final bool autoplay;
  final bool repeat;

  /// When [repeat] is false, the controller animates to this position
  /// (0..1) and freezes there instead of running all the way to 1.0.
  /// Use this for SVGs whose final frame is a loop-seam (e.g. a master
  /// opacity envelope that fades the content back out at t=1) — pick a
  /// stop position inside the meaningful timeline, after every element
  /// animation has reached its final state but before the seam.
  /// Ignored when [repeat] is true or [position] is set.
  final double? stopAt;

  /// When set, freezes the timeline at this point (0..1). The internal
  /// controller does not run while this is non-null.
  final double? position;

  final double? width;
  final double? height;
  final BoxFit fit;
  final AlignmentGeometry alignment;

  // Static rendering knobs.
  final Color? color;
  final BlendMode colorBlendMode;
  final ColorFilter? colorFilter;
  final double opacity;
  final Matrix4? transform;
  final AlignmentGeometry transformAlignment;
  final Clip clipBehavior;

  // Tween shortcuts — evaluated at the curved controller value when the
  // controller is running. When [position] is set they evaluate at that
  // point. Null falls through to the static knob.
  final ColorTween? colorTween;
  final Matrix4Tween? transformTween;
  final Tween<double>? opacityTween;

  final WidgetBuilder? placeholderBuilder;
  final AnimatedSvgErrorBuilder? errorBuilder;
  final String? semanticsLabel;
  final bool excludeFromSemantics;

  /// Drop all entries from the in-memory parse cache.
  static void clearCache() => SvgParseCache.clear();

  @override
  State<AnimatedSvg> createState() => _AnimatedSvgState();
}

class _AnimatedSvgState extends State<AnimatedSvg>
    with TickerProviderStateMixin {
  SvgRoot? _root;
  Object? _loadError;
  StackTrace? _loadStack;
  AnimationController? _controller;
  CurvedAnimation? _curved;

  /// See `_SvgFrameState._loadGeneration`. Same race protection: a load
  /// that completes after a newer one started must not clobber the newer
  /// result, and must not spin up an [AnimationController] for the
  /// outgoing root.
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cached = _trySyncCache();
    if (cached != null) {
      _root = cached;
      _startIfReady();
    } else {
      _loadIfNeeded();
    }
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
  void didUpdateWidget(AnimatedSvg oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.assetPath != oldWidget.assetPath ||
        widget.svgString != oldWidget.svgString ||
        widget.svgRoot != oldWidget.svgRoot ||
        widget.url != oldWidget.url) {
      _disposeController();
      _root = null;
      _loadError = null;
      _loadStack = null;
      // Invalidate any in-flight load for the previous source. Even on a
      // sync cache hit (where `_loadIfNeeded` doesn't run) the older load
      // must not be able to commit its result against this state.
      _loadGeneration++;
      final cached = _trySyncCache();
      if (cached != null) {
        _root = cached;
        _startIfReady();
      } else {
        _loadIfNeeded();
      }
      return;
    }
    if (widget.curve != oldWidget.curve && _controller != null) {
      _curved?.dispose();
      _curved = CurvedAnimation(parent: _controller!, curve: widget.curve);
    }
    if (widget.duration != oldWidget.duration && _controller != null) {
      _controller!.duration = _resolveDuration();
    }
    if (widget.position != oldWidget.position) {
      // Toggling between auto-play and frozen: start/stop the controller as
      // needed. Position changes alone don't move the controller (the user
      // is in manual mode).
      if (widget.position == null && oldWidget.position != null) {
        _startIfReady();
      } else if (widget.position != null && oldWidget.position == null) {
        _controller?.stop();
      }
    }
    if ((widget.autoplay != oldWidget.autoplay ||
            widget.repeat != oldWidget.repeat ||
            widget.stopAt != oldWidget.stopAt) &&
        widget.position == null) {
      _applyPlaybackState();
    }
  }

  void _applyPlaybackState() {
    final controller = _controller;
    if (controller == null) return;
    if (!widget.autoplay) {
      controller.stop();
      return;
    }
    // [AnimationController.repeat] / [AnimationController.forward] /
    // [AnimationController.animateTo] each stop any current simulation
    // and resume from the current value, so calling them on every
    // change is safe and avoids needing per-mode status comparisons.
    if (widget.repeat) {
      controller.repeat();
    } else {
      final stopAt = widget.stopAt;
      if (stopAt != null) {
        controller.animateTo(stopAt.clamp(0.0, 1.0), curve: widget.curve);
      } else {
        controller.forward();
      }
    }
  }

  @override
  void reassemble() {
    super.reassemble();
    SvgParseCache.clear();
    _disposeController();
    _root = null;
    _loadError = null;
    _loadStack = null;
    _loadIfNeeded();
  }

  @override
  void dispose() {
    _disposeController();
    super.dispose();
  }

  void _disposeController() {
    _curved?.dispose();
    _curved = null;
    _controller?.dispose();
    _controller = null;
  }

  /// Minimum controller period: an `AnimationController` with a zero or
  /// negative duration would either assert (debug) or loop the
  /// `repeat()`/`forward()` simulation infinitely-fast (release), pinning
  /// the raster thread on a busy SVG. Caller misconfiguration shouldn't
  /// take the app down — clamp to a 1 ms floor.
  static const Duration _minDuration = Duration(milliseconds: 1);

  Duration _resolveDuration() {
    final supplied = widget.duration;
    if (supplied != null) {
      return supplied >= _minDuration ? supplied : _minDuration;
    }
    final root = _root;
    if (root != null) {
      final natural = root.naturalCyclePeriod;
      if (natural >= _minDuration) return natural;
    }
    return const Duration(seconds: 1);
  }

  void _startIfReady() {
    final root = _root;
    if (root == null) return;
    if (widget.position != null) return;
    if (!root.hasAnimations) return;
    _controller ??= AnimationController(
      vsync: this,
      duration: _resolveDuration(),
    );
    _curved ??= CurvedAnimation(parent: _controller!, curve: widget.curve);
    if (widget.autoplay) {
      if (widget.repeat) {
        _controller!.repeat();
      } else {
        final stopAt = widget.stopAt;
        if (stopAt != null) {
          _controller!.animateTo(
            stopAt.clamp(0.0, 1.0),
            curve: widget.curve,
          );
        } else {
          _controller!.forward();
        }
      }
    }
  }

  Future<void> _loadIfNeeded() async {
    final generation = ++_loadGeneration;
    if (widget.svgRoot != null) {
      _onLoaded(widget.svgRoot!, generation);
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
        _onLoaded(cached, generation);
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
      _onLoaded(cached, generation);
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

  void _parseInto(
    String source, {
    required String? cacheKey,
    required int generation,
  }) {
    try {
      final parsed = parseSvg(source);
      if (cacheKey != null) SvgParseCache.put(cacheKey, parsed);
      _onLoaded(parsed, generation);
    } catch (error, stack) {
      _reportError(error, stack, generation: generation);
    }
  }

  void _onLoaded(SvgRoot root, int generation) {
    if (!_stillCurrent(generation)) return;
    setState(() => _root = root);
    _startIfReady();
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
        child: _buildAnimatingChild(root),
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

  Widget _buildAnimatingChild(SvgRoot root) {
    final fixedPosition = widget.position;
    final useAnimation =
        fixedPosition == null && root.hasAnimations && _controller != null;
    // Tweens are always forwarded. The painter's `_liveT` falls back to
    // `position` whenever `animation` is null, so a fixed `position` (or a
    // static SVG with no controller) still drives the tween — matching the
    // docstring on [AnimatedSvg.colorTween] et al. Nulling them out here
    // used to silently break frame-stepping with tweens.
    return buildSvgCustomPaint(
      context: context,
      root: root,
      position: fixedPosition ?? 0.0,
      animation: useAnimation ? (_curved ?? _controller) : null,
      fit: widget.fit,
      alignment: widget.alignment,
      color: widget.color,
      colorBlendMode: widget.colorBlendMode,
      colorFilter: widget.colorFilter,
      opacity: widget.opacity,
      transform: widget.transform,
      transformAlignment: widget.transformAlignment,
      clipBehavior: widget.clipBehavior,
      colorTween: widget.colorTween,
      transformTween: widget.transformTween,
      opacityTween: widget.opacityTween,
    );
  }

  Widget _sizedBox({Widget? child, Size? intrinsic}) {
    final width = widget.width ?? intrinsic?.width;
    final height = widget.height ?? intrinsic?.height;
    return SizedBox(width: width, height: height, child: child);
  }
}
