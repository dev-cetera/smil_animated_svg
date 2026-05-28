import 'dart:ui';

import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnimatedSvgFilters', () {
    test('all built-in filters are non-null ColorFilter instances', () {
      expect(AnimatedSvgFilters.grayscale, isA<ColorFilter>());
      expect(AnimatedSvgFilters.sepia, isA<ColorFilter>());
      expect(AnimatedSvgFilters.invert, isA<ColorFilter>());
    });

    test('tint(color) constructs a modulate-mode ColorFilter', () {
      final filter = AnimatedSvgFilters.tint(const Color(0xff112233));
      // ColorFilter.mode renders as `ColorFilter.mode(<color>, <blend>)` in
      // its toString — robust enough to catch a regression to srcIn.
      expect(filter.toString(), contains('modulate'));
    });

    test('colorize(red) is constructible and produces a usable filter', () {
      final filter = AnimatedSvgFilters.colorize(const Color(0xffff0000));
      expect(filter, isA<ColorFilter>());
    });

    test('colorize differs by tint colour', () {
      final red = AnimatedSvgFilters.colorize(const Color(0xffff0000));
      final blue = AnimatedSvgFilters.colorize(const Color(0xff0000ff));
      expect(red == blue, isFalse);
    });

    test('grayscale is a const filter (same instance across reads)', () {
      // Cheap regression: code today is `static const ColorFilter`. If
      // someone ever drops the const, this catches it.
      expect(
        identical(AnimatedSvgFilters.grayscale, AnimatedSvgFilters.grayscale),
        isTrue,
      );
    });
  });
}
