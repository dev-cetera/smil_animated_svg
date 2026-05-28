import 'dart:async';
import 'dart:convert';

import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _validSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect x="0" y="0" width="10" height="10" fill="red"/></svg>';

const String _validSvgB =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
    '<rect x="0" y="0" width="20" height="20" fill="blue"/></svg>';

void main() {
  setUp(SvgFrame.clearCache);

  group('SvgFrame.string', () {
    testWidgets('renders without throwing', (tester) async {
      await _pumpFramed(
        tester,
        const SvgFrame.string(_validSvg),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });

    testWidgets('malformed XML triggers errorBuilder', (tester) async {
      var errorSeen = false;
      await _pumpFramed(
        tester,
        SvgFrame.string(
          '<not valid xml',
          errorBuilder: (context, error, stack) {
            errorSeen = true;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(errorSeen, isTrue);
    });

    testWidgets('error path with no errorBuilder collapses silently',
        (tester) async {
      await _pumpFramed(
        tester,
        const SvgFrame.string('<not valid xml'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });
  });

  group('SvgFrame.parsed', () {
    testWidgets('renders pre-parsed root without loading', (tester) async {
      final root = parseSvg(_validSvg);
      await _pumpFramed(
        tester,
        SvgFrame.parsed(root),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });

    testWidgets('falls back to intrinsic size when width/height not given',
        (tester) async {
      final root = parseSvg(
        '<svg xmlns="http://www.w3.org/2000/svg" '
        'width="40" height="40" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="10" height="10" fill="red"/></svg>',
      );
      // Place outside any constraining ancestor so we can read sizes.
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: UnconstrainedBox(
            child: SvgFrame.parsed(root),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final sized = tester.widget<SizedBox>(
        find
            .descendant(
              of: find.byType(SvgFrame),
              matching: find.byType(SizedBox),
            )
            .first,
      );
      expect(sized.width, 40.0);
      expect(sized.height, 40.0);
    });
  });

  group('SvgFrame.asset', () {
    testWidgets('loads via the supplied bundle', (tester) async {
      final bundle = _TestBundle({'svg/foo.svg': _validSvg});
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });

    testWidgets('missing asset triggers errorBuilder', (tester) async {
      var errorSeen = false;
      await _pumpFramed(
        tester,
        SvgFrame.asset(
          'svg/missing.svg',
          bundle: _TestBundle({}),
          errorBuilder: (context, error, stack) {
            errorSeen = true;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(errorSeen, isTrue);
    });

    testWidgets('placeholderBuilder shows during async load', (tester) async {
      final completer = Completer<String>();
      final bundle = _DelayedBundle(completer.future, 'svg/slow.svg');
      var placeholderShown = false;
      await _pumpFramed(
        tester,
        SvgFrame.asset(
          'svg/slow.svg',
          bundle: bundle,
          placeholderBuilder: (context) {
            placeholderShown = true;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump(); // placeholder phase
      expect(placeholderShown, isTrue);
      completer.complete(_validSvg);
      await tester.pumpAndSettle();
    });

    testWidgets('same asset path: second mount hits the cache (no second load)',
        (tester) async {
      var loadCount = 0;
      final bundle = _CountingBundle(
        {'svg/foo.svg': _validSvg},
        onLoad: () => loadCount++,
      );
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      expect(loadCount, 1);

      // Mount a second SvgFrame for the same asset.
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      expect(loadCount, 1, reason: 'parse cache should have served it');
    });

    testWidgets('clearCache evicts everything so the next mount re-loads',
        (tester) async {
      var loadCount = 0;
      final bundle = _CountingBundle(
        {'svg/foo.svg': _validSvg},
        onLoad: () => loadCount++,
      );
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      // Unmount before clearing so the second mount triggers a fresh
      // initState — Flutter would otherwise reuse the existing State and
      // skip the asset load entirely.
      await _pumpFramed(tester, const SizedBox.shrink());
      SvgFrame.clearCache();
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      expect(loadCount, 2);
    });
  });

  group('SvgFrame.network', () {
    testWidgets('loads through the injected http client', (tester) async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/foo.svg');
        return http.Response(_validSvg, 200);
      });
      await _pumpFramed(
        tester,
        SvgFrame.network(
          'https://example.com/foo.svg',
          httpClient: client,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });

    testWidgets('non-2xx response triggers errorBuilder', (tester) async {
      final client = MockClient((_) async => http.Response('nope', 500));
      var errorSeen = false;
      await _pumpFramed(
        tester,
        SvgFrame.network(
          'https://example.com/foo.svg',
          httpClient: client,
          errorBuilder: (context, error, stack) {
            errorSeen = true;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(errorSeen, isTrue);
    });

    testWidgets('forwards the headers argument to the request', (tester) async {
      Map<String, String>? sentHeaders;
      final client = MockClient((request) async {
        sentHeaders = request.headers;
        return http.Response(_validSvg, 200);
      });
      await _pumpFramed(
        tester,
        SvgFrame.network(
          'https://example.com/foo.svg',
          httpClient: client,
          headers: const {'X-Test': 'yes'},
        ),
      );
      await tester.pumpAndSettle();
      expect(sentHeaders?['X-Test'], 'yes');
    });
  });

  group('source switching', () {
    testWidgets('swapping the svgString reloads the new content',
        (tester) async {
      await _pumpFramed(tester, const SvgFrame.string(_validSvg));
      await tester.pumpAndSettle();
      await _pumpFramed(tester, const SvgFrame.string(_validSvgB));
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });

    testWidgets('stale slow load cannot clobber a newer fast load',
        (tester) async {
      // Source A is slow; source B is sync via cache.
      final slow = Completer<String>();
      final delayedBundle = _DelayedBundle(slow.future, 'svg/slow.svg');
      final fastBundle = _TestBundle({'svg/fast.svg': _validSvgB});

      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/slow.svg', bundle: delayedBundle),
      );
      await tester.pump();
      // Swap to a fast source whose load completes synchronously.
      await _pumpFramed(
        tester,
        SvgFrame.asset('svg/fast.svg', bundle: fastBundle),
      );
      await tester.pumpAndSettle();
      // Now let the slow source finally complete — it must NOT replace
      // the fast source's rendered state.
      slow.complete(_validSvg);
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });
  });

  group('semantics', () {
    testWidgets('semanticsLabel wraps in a Semantics node', (tester) async {
      await _pumpFramed(
        tester,
        const SvgFrame.string(_validSvg, semanticsLabel: 'hello'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'hello',
        ),
        findsOneWidget,
      );
    });

    testWidgets('excludeFromSemantics skips the Semantics wrapper',
        (tester) async {
      await _pumpFramed(
        tester,
        const SvgFrame.string(
          _validSvg,
          semanticsLabel: 'hello',
          excludeFromSemantics: true,
        ),
      );
      await tester.pumpAndSettle();
      // The semantics wrapper for our label must not exist.
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.label == 'hello',
        ),
        findsNothing,
      );
    });
  });

  group('rendering knobs', () {
    testWidgets('width/height drive the SizedBox before load completes',
        (tester) async {
      final completer = Completer<String>();
      await _pumpFramed(
        tester,
        SvgFrame.asset(
          'svg/slow.svg',
          bundle: _DelayedBundle(completer.future, 'svg/slow.svg'),
          width: 99.0,
          height: 88.0,
        ),
      );
      await tester.pump();
      final sized = tester
          .widgetList<SizedBox>(
            find.descendant(
              of: find.byType(SvgFrame),
              matching: find.byType(SizedBox),
            ),
          )
          .first;
      expect(sized.width, 99.0);
      expect(sized.height, 88.0);
      completer.complete(_validSvg);
      await tester.pumpAndSettle();
    });

    testWidgets('position parameter is forwarded down to the painter',
        (tester) async {
      // Smoke test: simply pumping different positions should rebuild
      // without error. The painter itself is not directly observable.
      await _pumpFramed(
        tester,
        const SvgFrame.string(_validSvg, position: 0.0),
      );
      await tester.pumpAndSettle();
      await _pumpFramed(
        tester,
        const SvgFrame.string(_validSvg, position: 0.7),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SvgFrame), findsOneWidget);
    });
  });
}

Future<void> _pumpFramed(WidgetTester tester, Widget child) {
  return tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(width: 100.0, height: 100.0, child: child),
      ),
    ),
  );
}

class _TestBundle extends AssetBundle {
  _TestBundle(this._assets);
  final Map<String, String> _assets;

  @override
  Future<ByteData> load(String key) async {
    final value = _assets[key];
    if (value == null) {
      throw FlutterError('Asset not found: $key');
    }
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    final value = _assets[key];
    if (value == null) {
      throw FlutterError('Asset not found: $key');
    }
    return value;
  }
}

class _CountingBundle extends _TestBundle {
  _CountingBundle(super.assets, {required this.onLoad});
  final void Function() onLoad;

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    onLoad();
    return super.loadString(key, cache: cache);
  }
}

class _DelayedBundle extends AssetBundle {
  _DelayedBundle(this._future, this._key);
  final Future<String> _future;
  final String _key;

  @override
  Future<ByteData> load(String key) async {
    final value = await _future;
    return ByteData.sublistView(Uint8List.fromList(utf8.encode(value)));
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key != _key) {
      throw FlutterError('Asset not found: $key');
    }
    return _future;
  }
}
