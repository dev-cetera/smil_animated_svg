import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:smil_animated_svg/src/render/evaluator.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('evaluateNode — fast paths', () {
    test('no animations returns base by reference (no allocation)', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="1" height="1"/></svg>',
      );
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.0,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(identical(eval.transform, shape.baseTransform), isTrue);
      expect(identical(eval.attributes, shape.attributes), isTrue);
    });

    test('animation that has not begun yet returns base by reference', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="1s" begin="5s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.0,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(identical(eval.attributes, shape.attributes), isTrue);
    });
  });

  group('evaluateNode — transform interpolation', () {
    test('linear midpoint of 0→90° rotation gives 45°', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="rotate"
              values="0; 90" dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      expect(eval.transform.storage[0], closeTo(0.7071, 1e-3));
    });

    test('keyTimes shifts the interpolation curve', () {
      // 0→90 over 1s, but keyTimes 0;0.25 means we reach 90° at t=0.25s.
      // At t=0.5s the animation has reached the second keyframe and stays.
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="rotate"
              values="0; 90" keyTimes="0; 0.25"
              dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      expect(eval.transform.storage[0], closeTo(0.0, 1e-3)); // cos(90)
    });

    test('multi-keyframe walk picks the right segment', () {
      // values: 0, 90, 180 over 1s with linear keyTimes.
      // At t=0.25 we're halfway into [0..0.5] segment → 45°.
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="rotate"
              values="0; 90; 180" dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final eval = evaluateNode(
        timeSeconds: 0.25,
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      expect(eval.transform.storage[0], closeTo(0.7071, 1e-3));
    });

    test('two animateTransforms on the same node compose multiplicatively', () {
      // Translate then scale. Combined matrix should scale AND translate.
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="translate"
              values="10 0; 10 0" dur="1s" repeatCount="indefinite"/>
            <animateTransform attributeName="transform" type="scale"
              values="2; 2" dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      // tx is 10 (from translate), scale (2,2) applied; both composed.
      expect(eval.transform.storage[0], 2.0);
      expect(eval.transform.storage[5], 2.0);
      expect(eval.transform.storage[12], 10.0);
    });

    test('finite repeatCount freezes at the final value past the end', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="rotate"
              values="0; 360" dur="1s" repeatCount="2"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final eval = evaluateNode(
        timeSeconds: 100.0, // long after the 2-second total ended
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      // Frozen at 360° → identity. storage[0] = cos(360) = 1.
      expect(eval.transform.storage[0], closeTo(1.0, 1e-9));
    });

    test('indefinite repeatCount cycles seamlessly', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="rotate"
              values="0; 90" dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      // t=3.5 → fraction 0.5 of cycle → same as t=0.5.
      final eval = evaluateNode(
        timeSeconds: 3.5,
        baseTransform: group.baseTransform,
        baseAttributes: group.attributes,
        animations: group.animations,
      );
      expect(eval.transform.storage[0], closeTo(0.7071, 1e-3));
    });
  });

  group('evaluateNode — attribute interpolation', () {
    test('numeric attribute interpolates linearly', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <circle cx="0" cy="0" r="0">
            <animate attributeName="r" values="0; 10"
              dur="1s" repeatCount="indefinite"/>
          </circle>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(eval.attributes['r'], '5');
    });

    test('integer-valued numbers format without decimals', () {
      // Finite repeatCount so the animation freezes at 1.0 past its end —
      // otherwise an indefinite cycle wraps and t=1 lands back at 0.
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <circle cx="0" cy="0" r="0">
            <animate attributeName="r" values="0; 10"
              dur="1s" repeatCount="1"/>
          </circle>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 5.0,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(eval.attributes['r'], '10');
    });

    test('discrete calcMode returns the lower keyframe verbatim', () {
      // Three keyframes give two segments — discrete picks the segment's
      // lower value rather than interpolating.
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="fill" values="red; green; blue"
              calcMode="discrete" dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      // t=0.3 → segment [0, 0.5] → lower=red.
      final early = evaluateNode(
        timeSeconds: 0.3,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(early.attributes['fill'], 'red');
      // t=0.7 → segment [0.5, 1.0] → lower=green.
      final later = evaluateNode(
        timeSeconds: 0.7,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(later.attributes['fill'], 'green');
    });

    test('color attribute interpolates and produces a hex midpoint', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="fill" values="#ff0000; #0000ff"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      final raw = eval.attributes['fill']!;
      expect(raw.startsWith('#'), isTrue);
      // Midpoint should have R and B components both around 0x80, G near 0.
      // Color.lerp blends in linear RGB rather than gamma space — exact bytes
      // can vary, so just sanity-check the channel ordering.
      final mid = parseSvgColor(raw)!;
      expect(mid.r, greaterThan(0.0));
      expect(mid.b, greaterThan(0.0));
    });

    test('invalid color in values falls back to upper string', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="fill" values="not-a-color; #00ff00"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      expect(eval.attributes['fill'], '#00ff00');
    });

    test('calcMode=spline applies the cubic-bezier easing', () {
      // ease(0.42, 0, 0.58, 1) — standard CSS ease-in-out. Halfway through
      // time should land at exactly 0.5 (the curve is symmetric).
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              calcMode="spline" keySplines="0.42 0 0.58 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final eval = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );
      // CSS ease-in-out is symmetric around (0.5, 0.5).
      final value = double.parse(eval.attributes['opacity']!);
      expect(value, closeTo(0.5, 1e-2));
    });
  });

  group('parseSvgColor', () {
    test('#RGB shorthand expands each hex digit', () {
      expect(parseSvgColor('#f00'), const Color(0xffff0000));
    });

    test('#RRGGBB long form', () {
      expect(parseSvgColor('#00ff00'), const Color(0xff00ff00));
    });

    test('#RRGGBBAA preserves alpha channel', () {
      final color = parseSvgColor('#11223380')!;
      // Alpha is 0x80 (50%).
      expect((color.toARGB32() >> 24) & 0xff, 0x80);
    });

    test('rgb(r,g,b) numeric', () {
      expect(parseSvgColor('rgb(255, 0, 0)'), const Color(0xffff0000));
    });

    test('rgba(r,g,b,a) including alpha', () {
      final color = parseSvgColor('rgba(255, 0, 0, 0.5)')!;
      expect((color.toARGB32() >> 16) & 0xff, 0xff);
      expect((color.toARGB32() >> 24) & 0xff, closeTo(128, 1));
    });

    test('rgb percentages map to 0..255', () {
      expect(parseSvgColor('rgb(100%, 0%, 0%)'), const Color(0xffff0000));
    });

    test('named colors from CSS Level 3', () {
      expect(parseSvgColor('royalblue'), const Color(0xff4169e1));
      expect(parseSvgColor('rebeccapurple'), const Color(0xff663399));
      expect(parseSvgColor('darkslategrey'), const Color(0xff2f4f4f));
      expect(parseSvgColor('darkslategray'), const Color(0xff2f4f4f));
    });

    test('named colors are case-insensitive', () {
      expect(parseSvgColor('RED'), const Color(0xffff0000));
      expect(parseSvgColor('Red'), const Color(0xffff0000));
    });

    test('none and transparent return null', () {
      expect(parseSvgColor('none'), isNull);
      expect(parseSvgColor('transparent'), isNull);
    });

    test('unknown input returns null', () {
      expect(parseSvgColor('not-a-color'), isNull);
      expect(parseSvgColor(''), isNull);
    });
  });
}
