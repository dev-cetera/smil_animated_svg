import 'dart:ui' show Size;

import 'package:animated_svg/animated_svg.dart';
import 'package:animated_svg/src/parser/svg_animation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseSvg — document structure', () {
    test('rejects non-<svg> root with FormatException', () {
      expect(
        () => parseSvg('<foo xmlns="http://www.w3.org/2000/svg"/>'),
        throwsA(isA<FormatException>()),
      );
    });

    test('viewBox is taken from the attribute when present', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="10 20 30 40"/>',
      );
      expect(root.viewBox.left, 10.0);
      expect(root.viewBox.top, 20.0);
      expect(root.viewBox.width, 30.0);
      expect(root.viewBox.height, 40.0);
    });

    test('viewBox falls back to width/height when missing', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" width="50" height="60"/>',
      );
      expect(root.viewBox.size, const Size(50.0, 60.0));
    });

    test('viewBox falls back to 100x100 when both viewBox and size missing',
        () {
      final root = parseSvg('<svg xmlns="http://www.w3.org/2000/svg"/>');
      expect(root.viewBox.size, const Size(100.0, 100.0));
    });

    test('zero / negative viewBox falls back to default 100x100', () {
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

    test('intrinsicSize is populated when both width and height present', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="200" height="150" viewBox="0 0 10 10"/>',
      );
      expect(root.intrinsicSize, const Size(200.0, 150.0));
    });

    test('intrinsicSize is null when width or height absent', () {
      expect(
        parseSvg(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"/>',
        ).intrinsicSize,
        isNull,
      );
      expect(
        parseSvg(
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" '
          'viewBox="0 0 10 10"/>',
        ).intrinsicSize,
        isNull,
      );
    });

    test('intrinsicSize is null when non-finite or non-positive', () {
      expect(
        parseSvg(
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'width="-100" height="50" viewBox="0 0 10 10"/>',
        ).intrinsicSize,
        isNull,
      );
    });
  });

  group('parseSvg — element coverage', () {
    test('parses each supported shape kind', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g><rect x="0" y="0" width="1" height="1"/></g>
          <path d="M0 0 L1 1"/>
          <rect x="0" y="0" width="1" height="1"/>
          <circle cx="0" cy="0" r="1"/>
          <ellipse cx="0" cy="0" rx="1" ry="1"/>
          <line x1="0" y1="0" x2="1" y2="1"/>
          <polygon points="0,0 1,0 0,1"/>
          <polyline points="0,0 1,1"/>
        </svg>
      ''');
      expect(root.children, hasLength(8));
      expect(root.children[0], isA<SvgGroup>());
      expect(root.children[1], isA<SvgPathShape>());
      expect(root.children[2], isA<SvgRectShape>());
      expect(root.children[3], isA<SvgCircleShape>());
      expect(root.children[4], isA<SvgEllipseShape>());
      expect(root.children[5], isA<SvgLineShape>());
      expect(root.children[6], isA<SvgPolygonShape>());
      expect((root.children[6] as SvgPolygonShape).closed, isTrue);
      expect(root.children[7], isA<SvgPolygonShape>());
      expect((root.children[7] as SvgPolygonShape).closed, isFalse);
    });

    test('unknown elements are skipped silently', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <text x="0" y="0">hi</text>
          <use href="#x"/>
          <rect x="0" y="0" width="1" height="1"/>
        </svg>
      ''');
      // Only the rect survives.
      expect(root.children, hasLength(1));
      expect(root.children.single, isA<SvgRectShape>());
    });

    test('groups nest recursively', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <g>
              <rect x="0" y="0" width="1" height="1"/>
            </g>
          </g>
        </svg>
      ''');
      final outer = root.children.single as SvgGroup;
      final inner = outer.children.single as SvgGroup;
      expect(inner.children.single, isA<SvgRectShape>());
    });
  });

  group('parseSvg — attribute handling', () {
    test('unknown attributes are preserved verbatim', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="1" height="1" '
        'data-custom="hello" mask="url(#m)"/></svg>',
      );
      final shape = root.children.single;
      expect(shape.attributes['data-custom'], 'hello');
      expect(shape.attributes['mask'], 'url(#m)');
    });

    test('transform attribute is consumed into baseTransform, not attrs', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<g transform="translate(5, 5)"><rect x="0" y="0" '
        'width="1" height="1"/></g></svg>',
      );
      final group = root.children.single;
      expect(group.attributes.containsKey('transform'), isFalse);
      expect(group.baseTransform.storage[12], 5.0);
      expect(group.baseTransform.storage[13], 5.0);
    });

    test('style="..." declarations split into individual attributes', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1"
            style="fill: red; stroke: blue; stroke-width: 2"/>
        </svg>
      ''');
      final shape = root.children.single;
      expect(shape.attributes['fill'], 'red');
      expect(shape.attributes['stroke'], 'blue');
      expect(shape.attributes['stroke-width'], '2');
    });

    test(
        'presentation attributes win over style declarations '
        '(implementation defines first-wins)', () {
      // Note: SVG spec actually gives style higher specificity, but this
      // package uses putIfAbsent — presentation attribute wins. This test
      // documents current behaviour rather than spec compliance.
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="1" height="1" '
        'fill="green" style="fill: red"/></svg>',
      );
      final shape = root.children.single;
      expect(shape.attributes['fill'], 'green');
    });

    test('malformed style entries (no colon) are skipped', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1"
            style="fill red; ; stroke: blue;"/>
        </svg>
      ''');
      final shape = root.children.single;
      expect(shape.attributes.containsKey('fill'), isFalse);
      expect(shape.attributes['stroke'], 'blue');
    });
  });

  group('parseSvg — animation parsing', () {
    test('values list is split on `;` into ordered keyframes', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0;0.5;1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final animation = shape.animations.single as SvgAnimateAttribute;
      expect(animation.values, ['0', '0.5', '1']);
    });

    test('from/to shorthand becomes a two-keyframe values list', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animateTransform attributeName="transform" type="scale"
              from="1" to="2" dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final animation = shape.animations.single as SvgAnimateTransform;
      expect(animation.values, [
        [1.0],
        [2.0],
      ]);
    });

    test('from/by numeric shorthand computes from + by', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animateTransform attributeName="transform" type="translate"
              from="10 20" by="5 5" dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final animation = shape.animations.single as SvgAnimateTransform;
      expect(animation.values, [
        [10.0, 20.0],
        [15.0, 25.0],
      ]);
    });

    test('from/by on non-numeric attribute is dropped (no animation)', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="fill" from="red" by="blue"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      expect(shape.animations, isEmpty);
    });

    test('attribute value type is inferred from attributeName', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="fill" values="red; blue"
              dur="1s" repeatCount="indefinite"/>
            <animate attributeName="stroke" values="red; blue"
              dur="1s" repeatCount="indefinite"/>
            <animate attributeName="stop-color" values="red; blue"
              dur="1s" repeatCount="indefinite"/>
            <animate attributeName="color" values="red; blue"
              dur="1s" repeatCount="indefinite"/>
            <animate attributeName="opacity" values="0; 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final shape = root.children.single;
      final byName = {
        for (final a in shape.animations.cast<SvgAnimateAttribute>())
          a.attributeName: a.valueType,
      };
      expect(byName['fill'], SvgAnimateValueType.paint);
      expect(byName['stroke'], SvgAnimateValueType.paint);
      expect(byName['stop-color'], SvgAnimateValueType.paint);
      expect(byName['color'], SvgAnimateValueType.color);
      expect(byName['opacity'], SvgAnimateValueType.number);
    });

    test('calcMode parses to all four enum values', () {
      const variants = {
        'linear': SvgCalcMode.linear,
        'spline': SvgCalcMode.spline,
        'discrete': SvgCalcMode.discrete,
        'paced': SvgCalcMode.paced,
      };
      for (final entry in variants.entries) {
        final root = parseSvg('''
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <rect x="0" y="0" width="1" height="1">
              <animate attributeName="opacity" values="0; 1"
                calcMode="${entry.key}" dur="1s" repeatCount="indefinite"/>
            </rect>
          </svg>
        ''');
        final animation =
            root.children.single.animations.single as SvgAnimateAttribute;
        expect(animation.calcMode, entry.value);
      }
    });

    test('keyTimes defaults to evenly-spaced when omitted', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 0.5; 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.keyTimes, [0.0, 0.5, 1.0]);
    });

    test('keyTimes mismatched length is re-derived linearly', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity"
              values="0; 0.5; 1"
              keyTimes="0; 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.keyTimes, [0.0, 0.5, 1.0]);
    });

    test('keySplines with wrong segment count is ignored', () {
      // values has 3 entries -> 2 segments; supplying only 1 should drop the
      // whole splines list (we don't want to partially apply easing).
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 0.5; 1"
              calcMode="spline" keySplines="0.42 0 0.58 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.keySplines, isEmpty);
    });

    test('keySplines parses through when count matches', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity"
              values="0; 0.5; 1"
              calcMode="spline"
              keySplines="0.42 0 0.58 1; 0 0 0.5 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.keySplines, [
        [0.42, 0.0, 0.58, 1.0],
        [0.0, 0.0, 0.5, 1.0],
      ]);
    });

    test('dur parsing covers seconds, milliseconds, and bare numbers', () {
      Duration durFor(String raw) {
        final root = parseSvg('''
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <rect x="0" y="0" width="1" height="1">
              <animate attributeName="opacity" values="0; 1"
                dur="$raw" repeatCount="indefinite"/>
            </rect>
          </svg>
        ''');
        return (root.children.single.animations.single as SvgAnimateAttribute)
            .duration;
      }

      expect(durFor('1s'), const Duration(seconds: 1));
      expect(durFor('500ms'), const Duration(milliseconds: 500));
      expect(durFor('2.5'), const Duration(milliseconds: 2500));
    });

    test('dur="indefinite" falls back to zero (no defined cycle)', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="indefinite" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.duration, Duration.zero);
    });

    test('NaN dur is rejected, animation contributes no cycle', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="NaN" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.duration, Duration.zero);
      expect(root.hasAnimations, isFalse);
    });

    test('negative dur is rejected', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="-2s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.duration, Duration.zero);
    });

    test('repeatCount="indefinite" is infinity', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateAttribute;
      expect(animation.repeatCount, double.infinity);
    });

    test('numeric repeatCount survives, negative/NaN fall back to 1', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="1s" repeatCount="3"/>
            <animate attributeName="fill" values="red; blue"
              dur="1s" repeatCount="-2"/>
            <animate attributeName="stroke" values="red; blue"
              dur="1s" repeatCount="NaN"/>
          </rect>
        </svg>
      ''');
      final animations =
          root.children.single.animations.cast<SvgAnimateAttribute>().toList();
      expect(animations[0].repeatCount, 3.0);
      expect(animations[1].repeatCount, 1.0);
      expect(animations[2].repeatCount, 1.0);
    });

    test('begin offset is parsed; default is zero', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              begin="0.5s" dur="1s"/>
            <animate attributeName="fill" values="red; blue"
              dur="1s"/>
          </rect>
        </svg>
      ''');
      final animations =
          root.children.single.animations.cast<SvgAnimateAttribute>().toList();
      expect(animations[0].begin, const Duration(milliseconds: 500));
      expect(animations[1].begin, Duration.zero);
    });

    test('additive="sum" is parsed; default is replace', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <g>
            <animateTransform attributeName="transform" type="translate"
              values="0 0; 10 0" additive="sum"
              dur="1s" repeatCount="indefinite"/>
            <animateTransform attributeName="transform" type="scale"
              values="1; 2" dur="1s" repeatCount="indefinite"/>
            <rect x="0" y="0" width="1" height="1"/>
          </g>
        </svg>
      ''');
      final group = root.children.single as SvgGroup;
      final animations = group.animations.cast<SvgAnimateTransform>();
      expect(animations.first.additive, AdditiveMode.sum);
      expect(animations.last.additive, AdditiveMode.replace);
    });

    test('animateTransform with unsupported type is dropped', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animateTransform attributeName="transform" type="warp"
              from="0" to="1" dur="1s"/>
          </rect>
        </svg>
      ''');
      expect(root.children.single.animations, isEmpty);
    });

    test('<animate> without attributeName is dropped', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate values="0; 1" dur="1s"/>
          </rect>
        </svg>
      ''');
      expect(root.children.single.animations, isEmpty);
    });

    test('animateTransform values default type is translate when omitted', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animateTransform attributeName="transform"
              from="0 0" to="5 5" dur="1s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      final animation =
          root.children.single.animations.single as SvgAnimateTransform;
      expect(animation.type, SvgTransformType.translate);
    });
  });

  group('parseSvg — natural cycle period', () {
    test('longest dur in the tree wins', () {
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

    test('static SVG: hasAnimations false, naturalCyclePeriod zero', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1" fill="red"/>
        </svg>
      ''');
      expect(root.hasAnimations, isFalse);
      expect(root.naturalCyclePeriod, Duration.zero);
    });
  });
}
