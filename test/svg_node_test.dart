import 'dart:ui';

import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SvgRectShape', () {
    test('without rx/ry builds a plain rect path', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="1" y="2" width="3" height="4" fill="red"/></svg>',
      );
      final shape = root.children.single as SvgRectShape;
      final path = shape.resolvePath(shape.attributes);
      final bounds = path.getBounds();
      expect(bounds.left, 1.0);
      expect(bounds.top, 2.0);
      expect(bounds.width, 3.0);
      expect(bounds.height, 4.0);
    });

    test('with rx/ry builds an RRect path', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="10" height="10" rx="2" ry="3"/></svg>',
      );
      final shape = root.children.single as SvgRectShape;
      final path = shape.resolvePath(shape.attributes);
      // Naive bounds still tight to the rect; the rounded corners are inside.
      expect(path.getBounds(), const Rect.fromLTWH(0.0, 0.0, 10.0, 10.0));
    });

    test('with only rx (ry omitted) treats ry == rx', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="10" height="10" rx="2"/></svg>',
      );
      final shape = root.children.single as SvgRectShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });

    test('cache key changes when any geometry attribute changes', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="10" height="10"/></svg>',
      );
      final shape = root.children.single as SvgRectShape;
      final a = shape.resolvePath({
        'x': '0',
        'y': '0',
        'width': '10',
        'height': '10',
      });
      final b = shape.resolvePath({
        'x': '0',
        'y': '0',
        'width': '12',
        'height': '10',
      });
      expect(identical(a, b), isFalse);
    });
  });

  group('SvgCircleShape', () {
    test('builds an oval bounded by the circumscribing rect', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<circle cx="5" cy="5" r="3"/></svg>',
      );
      final shape = root.children.single as SvgCircleShape;
      final bounds = shape.resolvePath(shape.attributes).getBounds();
      expect(bounds.center.dx, closeTo(5.0, 1e-9));
      expect(bounds.center.dy, closeTo(5.0, 1e-9));
      expect(bounds.width, closeTo(6.0, 1e-9));
      expect(bounds.height, closeTo(6.0, 1e-9));
    });

    test('missing cx/cy/r default to zero', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<circle/></svg>',
      );
      final shape = root.children.single as SvgCircleShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });
  });

  group('SvgEllipseShape', () {
    test('uses independent rx and ry', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
        '<ellipse cx="10" cy="10" rx="6" ry="3"/></svg>',
      );
      final shape = root.children.single as SvgEllipseShape;
      final bounds = shape.resolvePath(shape.attributes).getBounds();
      expect(bounds.width, closeTo(12.0, 1e-9));
      expect(bounds.height, closeTo(6.0, 1e-9));
    });
  });

  group('SvgLineShape', () {
    test('builds an open segment from x1,y1 to x2,y2', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<line x1="1" y1="2" x2="9" y2="8"/></svg>',
      );
      final shape = root.children.single as SvgLineShape;
      final bounds = shape.resolvePath(shape.attributes).getBounds();
      expect(bounds, const Rect.fromLTRB(1.0, 2.0, 9.0, 8.0));
    });
  });

  group('SvgPolygonShape', () {
    test('closed polygon includes the closing edge in its bounds', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<polygon points="0,0 10,0 5,10"/></svg>',
      );
      final shape = root.children.single as SvgPolygonShape;
      expect(shape.closed, isTrue);
      final bounds = shape.resolvePath(shape.attributes).getBounds();
      expect(bounds, const Rect.fromLTRB(0.0, 0.0, 10.0, 10.0));
    });

    test('polyline is unclosed (cache key encodes closed flag)', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100">'
        '<polyline points="0,0 10,0 5,10"/></svg>',
      );
      final shape = root.children.single as SvgPolygonShape;
      expect(shape.closed, isFalse);
    });

    test('empty points list yields an empty Path without throwing', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<polygon points=""/></svg>',
      );
      final shape = root.children.single as SvgPolygonShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });

    test('odd-length points list drops the trailing unpaired token', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<polygon points="0,0 5,5 10"/></svg>',
      );
      final shape = root.children.single as SvgPolygonShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });
  });

  group('SvgPathShape', () {
    test('parses standard path data', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path d="M0 0 L10 10"/></svg>',
      );
      final shape = root.children.single as SvgPathShape;
      final path = shape.resolvePath(shape.attributes);
      expect(path.getBounds(), const Rect.fromLTRB(0.0, 0.0, 10.0, 10.0));
    });

    test('missing d defaults to an empty path', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path/></svg>',
      );
      final shape = root.children.single as SvgPathShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });

    test('empty d yields an empty path without calling path_drawing', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path d=""/></svg>',
      );
      final shape = root.children.single as SvgPathShape;
      expect(shape.resolvePath(shape.attributes).getBounds(), Rect.zero);
    });

    test('malformed d does not throw — returns empty Path', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path d="this is not a path"/></svg>',
      );
      final shape = root.children.single as SvgPathShape;
      expect(() => shape.resolvePath(shape.attributes), returnsNormally);
    });
  });

  group('shape path cache', () {
    test('identical live attributes return the same Path instance', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path d="M0 0 L10 10"/></svg>',
      );
      final shape = root.children.single as SvgShape;
      final first = shape.resolvePath(shape.attributes);
      final second = shape.resolvePath(shape.attributes);
      expect(identical(first, second), isTrue);
    });

    test('changed live attributes rebuild the Path', () {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<path d="M0 0 L10 10"/></svg>',
      );
      final shape = root.children.single as SvgShape;
      final first = shape.resolvePath({'d': 'M0 0 L10 10'});
      final second = shape.resolvePath({'d': 'M0 0 L20 20'});
      expect(identical(first, second), isFalse);
    });
  });

  group('SvgRoot', () {
    test('naturalCyclePeriod is computed once and cached', () {
      final root = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1"
              dur="2s" repeatCount="indefinite"/>
          </rect>
        </svg>
      ''');
      expect(
        identical(root.naturalCyclePeriod, root.naturalCyclePeriod),
        isTrue,
      );
    });

    test('hasAnimations distinguishes static vs animated SVGs', () {
      final static = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="1" height="1"/></svg>',
      );
      final animated = parseSvg('''
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <rect x="0" y="0" width="1" height="1">
            <animate attributeName="opacity" values="0; 1" dur="1s"/>
          </rect>
        </svg>
      ''');
      expect(static.hasAnimations, isFalse);
      expect(animated.hasAnimations, isTrue);
    });
  });
}
