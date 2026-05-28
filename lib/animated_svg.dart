//.title
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//
// Copyright © dev-cetera.com & contributors.
//
// The use of this source code is governed by an MIT-style license described in
// the LICENSE file located in this project's root directory.
//
// See: https://opensource.org/license/mit
//
// ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
//.title~

/// Render SMIL-animated SVGs in Flutter.
///
/// Two widgets:
///   * [SvgFrame] — leaf renderer; draws one frame at a given `position`.
///   * [AnimatedSvg] — owns an internal [AnimationController] and plays the
///     SVG; accepts the same rendering knobs plus `duration` / `curve` /
///     `repeat`, and tween shortcuts for `color` / `transform` / `opacity`.
///
/// Drive things yourself by wrapping a [SvgFrame] in an `AnimatedBuilder`.
library;

export 'src/animated_svg_widget.dart';
export 'src/filters.dart';
export 'src/svg_frame.dart' show SvgFrame, AnimatedSvgErrorBuilder;
export 'src/parser/svg_parser.dart' show parseSvg;
export 'src/parser/svg_node.dart';
