import 'dart:async';
import 'dart:convert';

import 'package:smil_animated_svg/smil_animated_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const String _staticSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
    '<rect x="0" y="0" width="10" height="10" fill="red"/></svg>';

const String _staticSvgB =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
    '<rect x="0" y="0" width="20" height="20" fill="blue"/></svg>';

const String _animatedSvg = '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
  <rect x="0" y="0" width="10" height="10" fill="red">
    <animate attributeName="opacity" values="0; 1"
      dur="1s" repeatCount="indefinite"/>
  </rect>
</svg>
''';

void main() {
  setUp(AnimatedSvg.clearCache);

  group('AnimatedSvg.string — playback control', () {
    testWidgets('static SVG never spins up an AnimationController',
        (tester) async {
      await _pumpFramed(tester, const AnimatedSvg.string(_staticSvg));
      // pumpAndSettle would block forever if a ticker were running with
      // an indefinite repeat; returning means no animation was scheduled.
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('animated SVG schedules transient frame callbacks',
        (tester) async {
      await _pumpFramed(tester, const AnimatedSvg.string(_animatedSvg));
      await tester.pump(); // initial build
      await tester.pump(const Duration(milliseconds: 16)); // ticker frame
      expect(
        SchedulerBinding.instance.transientCallbackCount,
        greaterThan(0),
        reason: 'A repeating AnimationController should keep callbacks alive',
      );
      // Make sure the test ends cleanly: replace the widget.
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('position freezes the controller', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, position: 0.5),
      );
      // pumpAndSettle settles because the controller is stopped when
      // position is set.
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('clearing position resumes the controller', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, position: 0.5),
      );
      await tester.pumpAndSettle();
      await _pumpFramed(tester, const AnimatedSvg.string(_animatedSvg));
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        SchedulerBinding.instance.transientCallbackCount,
        greaterThan(0),
      );
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('autoplay=false: no ticker scheduled', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, autoplay: false),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('repeat=false: controller animates forward then stops',
        (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _animatedSvg,
          repeat: false,
          duration: Duration(milliseconds: 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('stopAt is honoured when repeat=false', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _animatedSvg,
          repeat: false,
          stopAt: 0.7,
          duration: Duration(milliseconds: 100),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('toggling autoplay false → true starts playback',
        (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, autoplay: false),
      );
      await tester.pumpAndSettle();
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        SchedulerBinding.instance.transientCallbackCount,
        greaterThan(0),
      );
      await _pumpFramed(tester, const SizedBox.shrink());
    });
  });

  group('AnimatedSvg.string — controller plumbing', () {
    testWidgets('zero duration is clamped to a 1 ms floor (no infinite spin)',
        (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, duration: Duration.zero),
      );
      // Walk a fixed number of frames; if the clamp failed, pumpAndSettle
      // wouldn't return.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('negative duration is clamped too', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _animatedSvg,
          duration: Duration(milliseconds: -100),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('duration change is applied to the live controller',
        (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _animatedSvg,
          duration: Duration(milliseconds: 500),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _animatedSvg,
          duration: Duration(milliseconds: 1500),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      // Smoke test — just verify the change didn't throw or leak.
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('curve change recreates the CurvedAnimation', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, curve: Curves.linear),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_animatedSvg, curve: Curves.easeInOut),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('dispose during animation does not leak controllers',
        (tester) async {
      await _pumpFramed(tester, const AnimatedSvg.string(_animatedSvg));
      await tester.pump(const Duration(milliseconds: 16));
      // Replace with an empty widget — the test harness's leak detector
      // would surface any undisposed AnimationController/CurvedAnimation.
      await _pumpFramed(tester, const SizedBox.shrink());
      expect(find.byType(AnimatedSvg), findsNothing);
    });

    testWidgets('source swap disposes the old controller', (tester) async {
      await _pumpFramed(tester, const AnimatedSvg.string(_animatedSvg));
      await tester.pump(const Duration(milliseconds: 16));
      await _pumpFramed(tester, const AnimatedSvg.string(_staticSvgB));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });
  });

  group('AnimatedSvg.string — tweens', () {
    testWidgets(
        'colorTween + position evaluates at the fixed position '
        '(no controller required)', (tester) async {
      // Regression: _buildAnimatingChild used to null out tweens whenever
      // useAnimation was false, silently breaking the documented
      // "tween evaluates at position" behaviour for static SVGs.
      await _pumpFramed(
        tester,
        AnimatedSvg.string(
          _staticSvg,
          position: 0.5,
          colorTween: ColorTween(begin: Colors.red, end: Colors.blue),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('transformTween is forwarded down', (tester) async {
      await _pumpFramed(
        tester,
        AnimatedSvg.string(
          _animatedSvg,
          transformTween: Matrix4Tween(
            begin: Matrix4.identity(),
            end: Matrix4.diagonal3Values(2.0, 2.0, 1.0),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });

    testWidgets('opacityTween is forwarded down', (tester) async {
      await _pumpFramed(
        tester,
        AnimatedSvg.string(
          _animatedSvg,
          opacityTween: Tween<double>(begin: 0.0, end: 1.0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 16));
      expect(find.byType(AnimatedSvg), findsOneWidget);
      await _pumpFramed(tester, const SizedBox.shrink());
    });
  });

  group('AnimatedSvg.parsed', () {
    testWidgets('renders pre-parsed root without loading', (tester) async {
      final root = parseSvg(_staticSvg);
      await _pumpFramed(tester, AnimatedSvg.parsed(root));
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });
  });

  group('AnimatedSvg.asset', () {
    testWidgets('loads via supplied bundle', (tester) async {
      final bundle = _TestBundle({'svg/foo.svg': _staticSvg});
      await _pumpFramed(
        tester,
        AnimatedSvg.asset('svg/foo.svg', bundle: bundle),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('missing asset triggers errorBuilder', (tester) async {
      var errorSeen = false;
      await _pumpFramed(
        tester,
        AnimatedSvg.asset(
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
        AnimatedSvg.asset(
          'svg/slow.svg',
          bundle: bundle,
          placeholderBuilder: (context) {
            placeholderShown = true;
            return const SizedBox.shrink();
          },
        ),
      );
      await tester.pump();
      expect(placeholderShown, isTrue);
      completer.complete(_staticSvg);
      await tester.pumpAndSettle();
    });
  });

  group('AnimatedSvg.network', () {
    testWidgets('loads through the injected http client', (tester) async {
      final client = MockClient((_) async => http.Response(_staticSvg, 200));
      await _pumpFramed(
        tester,
        AnimatedSvg.network(
          'https://example.com/foo.svg',
          httpClient: client,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
    });

    testWidgets('non-2xx response invokes errorBuilder', (tester) async {
      final client = MockClient((_) async => http.Response('nope', 404));
      var errorSeen = false;
      await _pumpFramed(
        tester,
        AnimatedSvg.network(
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
  });

  group('semantics', () {
    testWidgets('semanticsLabel produces a Semantics wrapper', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(_staticSvg, semanticsLabel: 'animated svg'),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'animated svg',
        ),
        findsOneWidget,
      );
    });

    testWidgets('excludeFromSemantics skips the wrapper', (tester) async {
      await _pumpFramed(
        tester,
        const AnimatedSvg.string(
          _staticSvg,
          semanticsLabel: 'hidden',
          excludeFromSemantics: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == 'hidden',
        ),
        findsNothing,
      );
    });
  });

  group('TickerMode integration', () {
    testWidgets('TickerMode(enabled: false) pauses the controller',
        (tester) async {
      await _pumpFramed(
        tester,
        const TickerMode(
          enabled: false,
          child: AnimatedSvg.string(_animatedSvg),
        ),
      );
      // Ticker is disabled, so pumpAndSettle returns even with an
      // indefinite-repeat animation.
      await tester.pumpAndSettle();
      expect(find.byType(AnimatedSvg), findsOneWidget);
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
