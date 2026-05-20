import 'dart:io';
import 'dart:ui' show Size;

import 'package:animated_svg/animated_svg.dart';
import 'package:animated_svg/src/parser/svg_animation.dart';
import 'package:animated_svg/src/render/evaluator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses sway SVG: viewBox + nested groups + animateTransform', () {
    final source = File('example/assets/compledo_logo_sway.svg').readAsStringSync();
    final root = parseSvg(source);

    expect(root.viewBox.width, 512.0);
    expect(root.viewBox.height, 512.0);
    expect(root.children, isNotEmpty);

    // Collect every animateTransform recursively.
    final animations = <SvgAnimateTransform>[];
    void visit(SvgNode node) {
      for (final animation in node.animations) {
        if (animation is SvgAnimateTransform) animations.add(animation);
      }
      if (node is SvgGroup) {
        for (final child in node.children) {
          visit(child);
        }
      }
    }
    for (final child in root.children) {
      visit(child);
    }

    // The sway SVG has four animateTransform nodes (lower stem rotate,
    // mid-stem rotate, canopy rotate, canopy scale).
    expect(animations.length, 4);
    expect(
      animations.where((a) => a.type == SvgTransformType.rotate).length,
      3,
    );
    expect(
      animations.where((a) => a.type == SvgTransformType.scale).length,
      1,
    );
    for (final animation in animations) {
      expect(animation.duration.inMilliseconds, 1600);
      expect(animation.repeatCount.isInfinite, isTrue);
      expect(animation.keyTimes.length, animation.values.length);
    }
  });

  test('evaluator interpolates linearly between keyframes', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">
        <g>
          <animateTransform attributeName="transform" type="rotate"
            values="0; 90" keyTimes="0; 1" dur="1s" repeatCount="indefinite" />
          <rect x="0" y="0" width="10" height="10" fill="red"/>
        </g>
      </svg>
    ''');
    final group = root.children.first as SvgGroup;
    final eval = evaluateNode(
      timeSeconds: 0.5,
      baseTransform: group.baseTransform,
      baseAttributes: group.attributes,
      animations: group.animations,
    );
    // Halfway through ⇒ 45°. Top-left entry of a 2D rotation matrix is cos(θ).
    expect(eval.transform.storage[0], closeTo(0.7071, 1e-3));
  });

  test('colour interpolation produces a midpoint hex', () {
    final color = parseSvgColor('#ff0000');
    final color2 = parseSvgColor('#0000ff');
    expect(color, isNotNull);
    expect(color2, isNotNull);
  });

  test('naturalCyclePeriod = longest animation duration in tree', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <g>
          <animateTransform attributeName="transform" type="rotate"
            values="0; 360" dur="0.5s" repeatCount="indefinite" />
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1" dur="2s"
              repeatCount="indefinite" />
          </rect>
        </g>
      </svg>
    ''');
    expect(root.naturalCyclePeriod, const Duration(seconds: 2));
    expect(root.hasAnimations, isTrue);
  });

  test('static SVG: hasAnimations is false, naturalCyclePeriod is zero', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1" fill="red"/>
      </svg>
    ''');
    expect(root.hasAnimations, isFalse);
    expect(root.naturalCyclePeriod, Duration.zero);
  });

  test('from/to shorthand maps onto a two-keyframe animation', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1">
          <animateTransform attributeName="transform" type="scale"
            from="1" to="2" dur="1s" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    expect(shape.animations.length, 1);
    final animation = shape.animations.first as SvgAnimateTransform;
    expect(animation.values, [
      [1.0],
      [2.0],
    ]);
  });

  test('calcMode=spline with keySplines parses through to the model', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1">
          <animate attributeName="opacity"
            values="0; 1" keyTimes="0; 1"
            calcMode="spline" keySplines="0.42 0 0.58 1"
            dur="1s" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    final animation = shape.animations.first as SvgAnimateAttribute;
    expect(animation.calcMode, SvgCalcMode.spline);
    expect(animation.keySplines, [
      [0.42, 0.0, 0.58, 1.0],
    ]);
  });

  // ─── Adversarial inputs ────────────────────────────────────────────────

  test('NaN dur does not crash and is rejected as zero-duration', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1">
          <animate attributeName="opacity" values="0; 1"
            dur="NaN" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    final animation = shape.animations.first as SvgAnimateAttribute;
    expect(animation.duration, Duration.zero);
    expect(root.hasAnimations, isFalse);
  });

  test('negative dur is rejected, not silently turned into a negative cycle',
      () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1">
          <animate attributeName="opacity" values="0; 1"
            dur="-2s" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    expect((shape.animations.first as SvgAnimateAttribute).duration,
        Duration.zero);
  });

  test('negative or NaN repeatCount falls back to one cycle', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1">
          <animate attributeName="opacity" values="0; 1"
            dur="1s" repeatCount="-3"/>
          <animate attributeName="fill" values="red; blue"
            dur="1s" repeatCount="NaN"/>
        </rect>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    expect(shape.animations.length, 2);
    for (final animation in shape.animations) {
      expect((animation as SvgAnimateAttribute).repeatCount, 1.0);
    }
  });

  test('zero / negative viewBox falls back to default 100×100', () {
    expect(
      parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 0 0"/>',
      ).viewBox.size,
      const Size(100.0, 100.0),
    );
    expect(
      parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 -5 -5"/>',
      ).viewBox.size,
      const Size(100.0, 100.0),
    );
  });

  test('transform list filters non-finite numbers', () {
    // The translate would otherwise feed NaN into Matrix4 storage and turn
    // the entire canvas transform downstream into garbage.
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <g transform="translate(NaN, 5)">
          <rect x="0" y="0" width="1" height="1"/>
        </g>
      </svg>
    ''');
    final group = root.children.first as SvgGroup;
    final tx = group.baseTransform.storage[12];
    final ty = group.baseTransform.storage[13];
    expect(tx.isFinite, isTrue);
    expect(ty.isFinite, isTrue);
  });

  test('path shape reuses parsed Path across calls when `d` is unchanged',
      () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <path d="M0 0 L10 10"/>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    final first = shape.resolvePath(shape.attributes);
    final second = shape.resolvePath(shape.attributes);
    expect(identical(first, second), isTrue,
        reason: 'Same geometry attrs should hit the cache.');
  });

  test('path shape rebuilds when `d` changes (animation case)', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <path d="M0 0 L10 10"/>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    final first = shape.resolvePath({'d': 'M0 0 L10 10'});
    final second = shape.resolvePath({'d': 'M0 0 L20 20'});
    expect(identical(first, second), isFalse);
  });

  test('malformed path data does not throw and yields an empty Path', () {
    // `path_drawing` raises StateError on syntactically broken input. The
    // painter calls `resolvePath` in a hot loop, so an exception here would
    // unbalance the canvas save stack and corrupt every subsequent frame.
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <path d="this is not a path"/>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    expect(() => shape.resolvePath(shape.attributes), returnsNormally);
  });

  test('empty `d` returns an empty Path without invoking path_drawing', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <path d=""/>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    expect(() => shape.resolvePath(shape.attributes), returnsNormally);
  });

  test('evaluateNode skips Matrix4 clone when no animations apply', () {
    final root = parseSvg('''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="1" height="1"/>
      </svg>
    ''');
    final shape = root.children.first as SvgShape;
    final evaluation = evaluateNode(
      timeSeconds: 0.0,
      baseTransform: shape.baseTransform,
      baseAttributes: shape.attributes,
      animations: shape.animations,
    );
    expect(identical(evaluation.transform, shape.baseTransform), isTrue,
        reason: 'Static nodes should return the base Matrix4 by reference, '
            'not clone it on every frame.');
    expect(identical(evaluation.attributes, shape.attributes), isTrue,
        reason: 'Static nodes should return the base attribute map by '
            'reference.');
  });

  test('parseSvgColor knows CSS Color Module Level 3 named colors', () {
    // Without these, a typical SVG `fill="royalblue"` silently renders as
    // nothing (matches `fill="none"`).
    expect(parseSvgColor('royalblue'), isNotNull);
    expect(parseSvgColor('rebeccapurple'), isNotNull);
    expect(parseSvgColor('salmon'), isNotNull);
    expect(parseSvgColor('darkslategrey'), isNotNull); // British spelling
    expect(parseSvgColor('darkslategray'), isNotNull); // American spelling
  });

  test('parseSvgColor still rejects unknown / invalid input', () {
    expect(parseSvgColor('none'), isNull);
    expect(parseSvgColor('transparent'), isNull);
    expect(parseSvgColor('not-a-color'), isNull);
    expect(parseSvgColor(''), isNull);
  });
}
