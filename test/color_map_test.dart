// Colour replacement: `colorMap` on SvgFrame / AnimatedSvg.
//
// The swap happens once, on the parsed tree, which is what makes the animated
// cases below correct — see the docstring on `recolorSvg`.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:smil_animated_svg/src/color_swaps.dart';
import 'package:smil_animated_svg/src/parser/svg_animation.dart';
import 'package:smil_animated_svg/src/recolor_svg.dart';
import 'package:smil_animated_svg/src/render/evaluator.dart';
import 'package:smil_animated_svg/src/render/svg_painter.dart';

const _kGreen = Color(0xFF17924D);
const _kPink = Color(0xFFE1619C);

void main() {
  setUp(SvgFrame.clearCache);

  group('recolorSvg', () {
    test('replaces a mapped fill and leaves an unmapped one alone', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<circle r="4" fill="#17924D"/>'
        '<circle r="2" fill="#40C4FF"/>'
        '</svg>',
      );

      final recolored = recolorSvg(root, SvgColorSwaps({_kGreen: _kPink}));

      expect(_shapes(recolored)[0].attributes['fill'], '#e1619c');
      expect(_shapes(recolored)[1].attributes['fill'], '#40C4FF');
    });

    test('replaces stroke as well as fill', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<circle r="4" fill="none" stroke="#17924D"/>'
        '</svg>',
      );

      final recolored = recolorSvg(root, SvgColorSwaps({_kGreen: _kPink}));

      expect(_shapes(recolored).single.attributes['stroke'], '#e1619c');
      expect(_shapes(recolored).single.attributes['fill'], 'none');
    });

    test('one key matches every spelling of the same colour', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<rect width="1" height="1" fill="white"/>'
        '<rect width="1" height="1" fill="#fff"/>'
        '<rect width="1" height="1" fill="#FFFFFF"/>'
        '<rect width="1" height="1" fill="rgb(255, 255, 255)"/>'
        '</svg>',
      );

      final recolored = recolorSvg(
        root,
        SvgColorSwaps({const Color(0xFFFFFFFF): _kPink}),
      );

      for (final shape in _shapes(recolored)) {
        expect(shape.attributes['fill'], '#e1619c');
      }
    });

    test('matching ignores alpha, and the two alphas multiply', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        // Half-transparent green still matches an opaque green key...
        '<rect width="1" height="1" fill="#17924D80"/>'
        // ...and an opaque green takes on the replacement's alpha.
        '<rect width="1" height="1" fill="#17924D"/>'
        '</svg>',
      );

      final recolored = recolorSvg(
        root,
        SvgColorSwaps({_kGreen: _kPink.withValues(alpha: 0.5)}),
      );

      // 0x80/0xff * 0.5 ≈ 0.251 → 0x40.
      expect(_shapes(recolored)[0].attributes['fill'], '#e1619c40');
      expect(_shapes(recolored)[1].attributes['fill'], '#e1619c80');
    });

    test('leaves none, paint servers and unrecognised values untouched', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<rect width="1" height="1" fill="none"/>'
        '<rect width="1" height="1" fill="url(#grad)"/>'
        '<rect width="1" height="1" fill="currentColor"/>'
        '<rect width="1" height="1" fill="inherit"/>'
        '</svg>',
      );

      final recolored = recolorSvg(root, SvgColorSwaps({_kGreen: _kPink}));

      expect(
        _shapes(recolored).map((s) => s.attributes['fill']),
        ['none', 'url(#grad)', 'currentColor', 'inherit'],
      );
    });

    test('recolours nested groups', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<g fill="#17924D"><g><circle r="4" stroke="#17924D"/></g></g>'
        '</svg>',
      );

      final recolored = recolorSvg(root, SvgColorSwaps({_kGreen: _kPink}));

      final outer = recolored.children.single as SvgGroup;
      expect(outer.attributes['fill'], '#e1619c');
      expect(_shapes(recolored).single.attributes['stroke'], '#e1619c');
    });

    test('an empty map hands back the identical root', () {
      final root = parseSvg('<svg viewBox="0 0 10 10"><circle r="4"/></svg>');
      expect(recolorSvg(root, SvgColorSwaps(const {})), same(root));
    });

    test('a two-way swap is applied exactly once, not cancelled out', () {
      final root = parseSvg(
        '<svg viewBox="0 0 10 10">'
        '<rect width="1" height="1" fill="#17924D"/>'
        '<rect width="1" height="1" fill="#E1619C"/>'
        '</svg>',
      );

      final recolored = recolorSvg(
        root,
        SvgColorSwaps({_kGreen: _kPink, _kPink: _kGreen}),
      );

      expect(_shapes(recolored)[0].attributes['fill'], '#e1619c');
      expect(_shapes(recolored)[1].attributes['fill'], '#17924d');
    });
  });

  group('recolorSvg with an animated fill', () {
    // The reason the swap lives on the tree instead of in the painter: an
    // interpolated colour matches no key, so a paint-time swap could only ever
    // recolour the instants that land exactly on a keyframe.
    const svg = '<svg viewBox="0 0 10 10">'
        '<circle r="4" fill="#17924D">'
        '<animate attributeName="fill" values="#17924D;#FFFFFF" dur="1s"/>'
        '</circle></svg>';

    test('keyframes are swapped', () {
      final recolored = recolorSvg(
        parseSvg(svg),
        SvgColorSwaps({_kGreen: _kPink}),
      );

      final animation =
          _shapes(recolored).single.animations.single as SvgAnimateAttribute;
      expect(animation.values, ['#e1619c', '#FFFFFF']);
    });

    test('the midpoint interpolates in the replacement palette', () {
      final recolored = recolorSvg(
        parseSvg(svg),
        SvgColorSwaps({_kGreen: _kPink}),
      );
      final shape = _shapes(recolored).single;

      final evaluation = evaluateNode(
        timeSeconds: 0.5,
        baseTransform: shape.baseTransform,
        baseAttributes: shape.attributes,
        animations: shape.animations,
      );

      // Halfway from pink to white — nowhere near halfway green-to-white.
      // Compared as packed ARGB: a Color carries floating-point channels, but
      // an SVG paint string only holds 8 bits per channel.
      final mid = parseSvgColor(evaluation.attributes['fill']!)!;
      final expected = Color.lerp(_kPink, const Color(0xFFFFFFFF), 0.5)!;
      expect(mid.toARGB32(), expected.toARGB32());
    });
  });

  group('SvgColorSwaps', () {
    test('cacheKey is insertion-order independent', () {
      expect(
        SvgColorSwaps({_kGreen: _kPink, _kPink: _kGreen}).cacheKey,
        SvgColorSwaps({_kPink: _kGreen, _kGreen: _kPink}).cacheKey,
      );
    });

    test('tables with different replacements are not equal', () {
      expect(
        SvgColorSwaps({_kGreen: _kPink}) ==
            SvgColorSwaps({_kGreen: const Color(0xFF000000)}),
        isFalse,
      );
    });

    test('maybe collapses null and empty to null', () {
      expect(SvgColorSwaps.maybe(null), isNull);
      expect(SvgColorSwaps.maybe(const {}), isNull);
      expect(SvgColorSwaps.maybe({_kGreen: _kPink}), isNotNull);
    });
  });

  group('formatSvgColor', () {
    test('omits alpha when opaque', () {
      expect(formatSvgColor(const Color(0xFF17924D)), '#17924d');
    });

    test('keeps alpha when the colour is translucent', () {
      expect(formatSvgColor(const Color(0x8017924D)), '#17924d80');
    });

    test('round-trips through parseSvgColor', () {
      const color = Color(0x4012AB34);
      expect(parseSvgColor(formatSvgColor(color)), color);
    });
  });

  group('SvgFrame colorMap', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10" fill="#17924D"/></svg>';

    testWidgets('the painter is handed the recoloured tree', (tester) async {
      await _pump(
        tester,
        SvgFrame.string(svg, colorMap: {_kGreen: _kPink}),
      );
      await tester.pumpAndSettle();

      expect(_paintedFill(tester), '#e1619c');
    });

    testWidgets('no colorMap leaves the SVG as authored', (tester) async {
      await _pump(tester, const SvgFrame.string(svg));
      await tester.pumpAndSettle();

      expect(_paintedFill(tester), '#17924D');
    });

    testWidgets('swapping the colorMap re-derives in place', (tester) async {
      await _pump(
        tester,
        SvgFrame.string(svg, colorMap: {_kGreen: _kPink}),
      );
      await tester.pumpAndSettle();
      expect(_paintedFill(tester), '#e1619c');

      await _pump(
        tester,
        SvgFrame.string(svg, colorMap: {_kGreen: const Color(0xFF40C4FF)}),
      );
      await tester.pumpAndSettle();
      expect(_paintedFill(tester), '#40c4ff');

      // …and dropping the map restores the authored colour.
      await _pump(tester, const SvgFrame.string(svg));
      await tester.pumpAndSettle();
      expect(_paintedFill(tester), '#17924D');
    });

    testWidgets('one asset renders in two palettes at once', (tester) async {
      final bundle = _FakeBundle({'a.svg': svg});
      await _pump(
        tester,
        Row(
          children: [
            SvgFrame.asset(
              'a.svg',
              bundle: bundle,
              colorMap: {_kGreen: _kPink},
            ),
            SvgFrame.asset('a.svg', bundle: bundle),
          ],
        ),
      );
      await tester.pumpAndSettle();

      final fills = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.painter)
          .whereType<AnimatedSvgPainter>()
          .map((painter) => _fillOf(painter.root))
          .toList();
      expect(fills, ['#e1619c', '#17924D']);
    });

    testWidgets('a new palette costs no reload', (tester) async {
      final bundle = _FakeBundle({'a.svg': svg});
      await _pump(tester, SvgFrame.asset('a.svg', bundle: bundle));
      await tester.pumpAndSettle();
      expect(bundle.loads, 1);
      expect(_paintedFill(tester), '#17924D');

      await _pump(
        tester,
        SvgFrame.asset('a.svg', bundle: bundle, colorMap: {_kGreen: _kPink}),
      );
      await tester.pumpAndSettle();

      expect(_paintedFill(tester), '#e1619c');
      // Recoloured off the cached tree, not re-read from the bundle.
      expect(bundle.loads, 1);
    });
  });

  group('AnimatedSvg colorMap', () {
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10" fill="#17924D">'
        '<animate attributeName="opacity" values="0;1" dur="1s"/>'
        '</rect></svg>';

    testWidgets('recolours while playing, without restarting', (tester) async {
      await _pump(
        tester,
        AnimatedSvg.string(svg, colorMap: {_kGreen: _kPink}),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(_paintedFill(tester), '#e1619c');

      final before = _painterOf(tester).animation!.value;
      await _pump(
        tester,
        AnimatedSvg.string(svg, colorMap: {_kGreen: const Color(0xFF40C4FF)}),
      );
      await tester.pump();

      expect(_paintedFill(tester), '#40c4ff');
      // The controller kept its position — a palette change is not a reload.
      expect(_painterOf(tester).animation!.value, greaterThanOrEqualTo(before));
    });
  });
}

// ─── helpers ──────────────────────────────────────────────────────────────────

Future<void> _pump(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    MaterialApp(home: Scaffold(body: Center(child: child))),
  );
}

AnimatedSvgPainter _painterOf(WidgetTester tester) {
  final paint =
      tester.widgetList<CustomPaint>(find.byType(CustomPaint)).firstWhere(
            (candidate) => candidate.painter is AnimatedSvgPainter,
          );
  return paint.painter! as AnimatedSvgPainter;
}

/// The `fill` the painter will actually read for the first shape in the tree.
String? _paintedFill(WidgetTester tester) => _fillOf(_painterOf(tester).root);

String? _fillOf(SvgRoot root) => _shapes(root).first.attributes['fill'];

List<SvgShape> _shapes(SvgRoot root) {
  final out = <SvgShape>[];
  void visit(SvgNode node) {
    switch (node) {
      case SvgGroup():
        node.children.forEach(visit);
      case SvgShape():
        out.add(node);
    }
  }

  root.children.forEach(visit);
  return out;
}

class _FakeBundle extends CachingAssetBundle {
  _FakeBundle(this._contents);

  final Map<String, String> _contents;
  int loads = 0;

  @override
  Future<ByteData> load(String key) async {
    throw UnimplementedError();
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final content = _contents[key];
    if (content == null) throw FlutterError('missing asset: $key');
    loads++;
    return content;
  }
}
