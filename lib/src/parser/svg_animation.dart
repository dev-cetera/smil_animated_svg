/// SMIL animation models.
///
/// We support two kinds:
///   - [SvgAnimateTransform] for `<animateTransform>` (rotate, scale,
///     translate, skewX, skewY, matrix).
///   - [SvgAnimateAttribute] for `<animate>` on numeric or colour attributes
///     (fill, stroke, opacity, fill-opacity, stroke-opacity, stroke-width,
///     plus geometry attrs like cx, cy, r, x, y, width, height).
///
/// Easing is linear only. `calcMode`, `keySplines`, `from/to/by`, and
/// `<animateMotion>` are unsupported.
library;

enum SvgTransformType { translate, rotate, scale, skewX, skewY, matrix }

enum AdditiveMode { replace, sum }

/// Whether an attribute interpolates as a number or a colour.
enum SvgAnimateValueType { number, color, paint }

/// Interpolation between adjacent keyframes.
///
/// `linear` is the default. `spline` reads cubic-bezier control points from
/// the animation's [SvgAnimation.keySplines]. `discrete` and `paced` are
/// parsed-but-treated-as-linear for now.
enum SvgCalcMode { linear, spline, discrete, paced }

abstract class SvgAnimation {
  SvgAnimation({
    required this.duration,
    required this.repeatCount,
    required this.begin,
    required this.additive,
    required this.keyTimes,
    this.calcMode = SvgCalcMode.linear,
    this.keySplines = const [],
  });

  /// Duration of one cycle.
  final Duration duration;

  /// Number of cycles. `double.infinity` for `repeatCount="indefinite"`.
  final double repeatCount;

  /// Start offset (e.g. `begin="0.5s"`). Defaults to zero.
  final Duration begin;

  final AdditiveMode additive;

  /// Normalised time markers (0..1) for each entry in `values`. Same length
  /// as the values list. Must start at 0 and end at 1.
  final List<double> keyTimes;

  final SvgCalcMode calcMode;

  /// Cubic-bezier control points for each segment when
  /// [calcMode] is [SvgCalcMode.spline]. Each entry holds
  /// `[x1, y1, x2, y2]`. Length should be `values.length - 1`.
  final List<List<double>> keySplines;
}

class SvgAnimateTransform extends SvgAnimation {
  SvgAnimateTransform({
    required super.duration,
    required super.repeatCount,
    required super.begin,
    required super.additive,
    required super.keyTimes,
    required this.type,
    required this.values,
    super.calcMode,
    super.keySplines,
  });

  final SvgTransformType type;

  /// One tuple per keyframe. Tuple length depends on [type]:
  ///   - translate: 1 or 2 values (tx [, ty])
  ///   - rotate: 1 or 3 values (angle [, cx, cy])
  ///   - scale: 1 or 2 values (sx [, sy])
  ///   - skewX / skewY: 1 value
  ///   - matrix: 6 values
  final List<List<double>> values;
}

class SvgAnimateAttribute extends SvgAnimation {
  SvgAnimateAttribute({
    required super.duration,
    required super.repeatCount,
    required super.begin,
    required super.additive,
    required super.keyTimes,
    required this.attributeName,
    required this.values,
    required this.valueType,
    super.calcMode,
    super.keySplines,
  });

  /// e.g. `fill`, `opacity`, `stroke-width`, `cx`.
  final String attributeName;

  /// Raw value strings for each keyframe. Interpolated at evaluation time
  /// according to [valueType].
  final List<String> values;

  final SvgAnimateValueType valueType;
}
