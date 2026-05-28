import 'dart:math' as math;

import 'package:smil_animated_svg/src/parser/transform_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSvgTransform', () {
    test('empty input returns identity', () {
      final m = parseSvgTransform('');
      expect(m.storage[0], 1.0);
      expect(m.storage[5], 1.0);
      expect(m.storage[10], 1.0);
      expect(m.storage[12], 0.0);
      expect(m.storage[13], 0.0);
    });

    test('translate(tx) leaves ty at zero', () {
      final m = parseSvgTransform('translate(10)');
      expect(m.storage[12], 10.0);
      expect(m.storage[13], 0.0);
    });

    test('translate(tx, ty) sets both axes', () {
      final m = parseSvgTransform('translate(10, 20)');
      expect(m.storage[12], 10.0);
      expect(m.storage[13], 20.0);
    });

    test('rotate(angle) rotates around origin', () {
      final m = parseSvgTransform('rotate(90)');
      // 2D rotation matrix top-left is cos(90°) = 0.
      expect(m.storage[0], closeTo(0.0, 1e-9));
      // [0][1] of a 4x4 is storage[4]; for rotZ(90) that's -sin(90) = -1.
      expect(m.storage[4], closeTo(-1.0, 1e-9));
    });

    test('rotate(angle, cx, cy) pivots around (cx, cy)', () {
      // Point (10, 10) rotated 180° around (5, 5) should land at (0, 0).
      final m = parseSvgTransform('rotate(180, 5, 5)');
      final result = _apply(m, 10.0, 10.0);
      expect(result.$1, closeTo(0.0, 1e-9));
      expect(result.$2, closeTo(0.0, 1e-9));
    });

    test('scale(sx) uniform-scales both axes', () {
      final m = parseSvgTransform('scale(2)');
      expect(m.storage[0], 2.0);
      expect(m.storage[5], 2.0);
    });

    test('scale(sx, sy) uses independent axes', () {
      final m = parseSvgTransform('scale(2, 3)');
      expect(m.storage[0], 2.0);
      expect(m.storage[5], 3.0);
    });

    test('skewX produces tan(angle) in the y/x entry', () {
      final m = parseSvgTransform('skewX(45)');
      expect(m.storage[4], closeTo(math.tan(45 * math.pi / 180), 1e-9));
    });

    test('skewY produces tan(angle) in the x/y entry', () {
      final m = parseSvgTransform('skewY(45)');
      expect(m.storage[1], closeTo(math.tan(45 * math.pi / 180), 1e-9));
    });

    test('matrix(a b c d e f) maps to 2D affine entries', () {
      final m = parseSvgTransform('matrix(1, 2, 3, 4, 5, 6)');
      expect(m.storage[0], 1.0); // a
      expect(m.storage[1], 2.0); // b
      expect(m.storage[4], 3.0); // c
      expect(m.storage[5], 4.0); // d
      expect(m.storage[12], 5.0); // e
      expect(m.storage[13], 6.0); // f
    });

    test('multiple transforms compose in document order', () {
      // translate(10,0) then scale(2) ⇒ post-multiply: M = T * S.
      // A point (1, 0) gets scaled first to (2, 0), then translated to (12, 0).
      final m = parseSvgTransform('translate(10, 0) scale(2)');
      final p = _apply(m, 1.0, 0.0);
      expect(p.$1, 12.0);
      expect(p.$2, 0.0);
    });

    test('non-finite numbers in transform args are filtered', () {
      // translate(NaN, 5): NaN dropped, ty=5 takes the first valid slot.
      // The result should be translate(5, 0) — never NaN in any storage cell.
      final m = parseSvgTransform('translate(NaN, 5)');
      for (final cell in m.storage) {
        expect(cell.isFinite, isTrue);
      }
    });

    test('Infinity in transform args is filtered too', () {
      final m = parseSvgTransform('scale(Infinity, 2)');
      for (final cell in m.storage) {
        expect(cell.isFinite, isTrue);
      }
    });

    test('whitespace and commas are both valid separators', () {
      final a = parseSvgTransform('translate(10 20)');
      final b = parseSvgTransform('translate(10,20)');
      final c = parseSvgTransform('translate(10 , 20)');
      expect(a.storage[12], 10.0);
      expect(a.storage[13], 20.0);
      expect(b.storage[12], 10.0);
      expect(b.storage[13], 20.0);
      expect(c.storage[12], 10.0);
      expect(c.storage[13], 20.0);
    });

    test('unknown transform names are silently ignored', () {
      final m = parseSvgTransform('warp(10, 20)');
      // Identity — the unknown function contributes nothing.
      expect(m.storage[0], 1.0);
      expect(m.storage[5], 1.0);
    });
  });

  group('buildAnimatedTransform', () {
    test('handles each documented type', () {
      expect(buildAnimatedTransform('translate', [3.0, 4.0]).storage[12], 3.0);
      expect(buildAnimatedTransform('scale', [2.0]).storage[0], 2.0);
      expect(
        buildAnimatedTransform('rotate', [180.0]).storage[0],
        closeTo(-1.0, 1e-9),
      );
      expect(buildAnimatedTransform('skewX', [0.0]).storage[4], 0.0);
      expect(buildAnimatedTransform('skewY', [0.0]).storage[1], 0.0);
      expect(
        buildAnimatedTransform('matrix', [1, 2, 3, 4, 5, 6]).storage[12],
        5.0,
      );
    });

    test('matrix with <6 args is identity (no partial application)', () {
      final m = buildAnimatedTransform('matrix', [1.0, 2.0, 3.0]);
      expect(m.storage[0], 1.0);
      expect(m.storage[5], 1.0);
      expect(m.storage[12], 0.0);
    });

    test('unknown type returns identity', () {
      final m = buildAnimatedTransform('rocket', [1.0, 2.0, 3.0]);
      expect(m.storage[0], 1.0);
      expect(m.storage[5], 1.0);
    });
  });

  group('parseNumberList', () {
    test('mixed whitespace and commas', () {
      expect(parseNumberList('1, 2 3,  4'), [1.0, 2.0, 3.0, 4.0]);
    });

    test('NaN and Infinity are filtered, finite values pass through', () {
      final result = parseNumberList('1 NaN Infinity -Infinity 2');
      expect(result, [1.0, 2.0]);
    });

    test('empty string yields empty list', () {
      expect(parseNumberList(''), isEmpty);
    });
  });
}

/// Apply [m] to a 2D point. Returns (x', y').
(double, double) _apply(dynamic m, double x, double y) {
  // m is Matrix4 from vector_math; call dynamic to avoid importing it here.
  final s = m.storage as List<double>;
  // Column-major Matrix4: (x', y') = (s[0]*x + s[4]*y + s[12],
  //                                    s[1]*x + s[5]*y + s[13])
  final xp = s[0] * x + s[4] * y + s[12];
  final yp = s[1] * x + s[5] * y + s[13];
  return (xp, yp);
}
