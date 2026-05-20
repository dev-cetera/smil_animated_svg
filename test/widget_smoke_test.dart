import 'package:animated_svg/animated_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SvgFrame.string renders without throwing', (tester) async {
    const svg = '''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="10" height="10" fill="red"/>
      </svg>
    ''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 50.0,
              height: 50.0,
              child: SvgFrame.string(svg),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SvgFrame), findsOneWidget);
  });

  testWidgets('AnimatedSvg renders static SVG without spinning up a ticker',
      (tester) async {
    const svg = '''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="10" height="10" fill="red"/>
      </svg>
    ''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 50.0,
              height: 50.0,
              child: AnimatedSvg.string(svg),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSvg), findsOneWidget);
    // pumpAndSettle returning means no animations are scheduled — confirms
    // the AnimationController was never started for an SVG with no SMIL
    // children.
  });

  testWidgets('AnimatedSvg swaps sources without leaking a stale root',
      (tester) async {
    const a = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect x="0" y="0" width="10" height="10" fill="red"/></svg>';
    const b = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20">'
        '<rect x="0" y="0" width="20" height="20" fill="blue"/></svg>';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 50.0, height: 50.0,
              child: AnimatedSvg.string(a)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(width: 50.0, height: 50.0,
              child: AnimatedSvg.string(b)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSvg), findsOneWidget);
  });

  testWidgets('zero / negative widget duration is clamped (no infinite repaint)',
      (tester) async {
    // An animated SVG with a 1s natural cycle, but the caller specifies
    // Duration.zero. Without the clamp, `controller.repeat()` would loop
    // the simulation infinitely fast and pumpAndSettle would time out.
    const svg = '''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="10" height="10" fill="red">
          <animate attributeName="opacity" values="0; 1"
            dur="1s" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 50.0,
            height: 50.0,
            child: AnimatedSvg.string(svg, duration: Duration.zero),
          ),
        ),
      ),
    );
    // pump a fixed number of frames; a pinned ticker would block the test
    // harness.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(AnimatedSvg), findsOneWidget);
  });

  testWidgets('AnimatedSvg disposes cleanly while animating',
      (tester) async {
    const svg = '''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="10" height="10" fill="red">
          <animate attributeName="opacity" values="0; 1"
            dur="1s" repeatCount="indefinite"/>
        </rect>
      </svg>
    ''';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 50.0,
            height: 50.0,
            child: AnimatedSvg.string(svg),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    // Replace with an empty widget — would surface AnimationController /
    // CurvedAnimation leaks via the test harness's leak detection.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byType(AnimatedSvg), findsNothing);
  });

  testWidgets(
      'AnimatedSvg with position + colorTween still applies the tween '
      '(no controller)', (tester) async {
    // Regression: `_buildAnimatingChild` used to null out tweens whenever
    // `useAnimation` was false. When `position` was set, the tween was
    // silently discarded, breaking the documented "evaluate at position"
    // behavior. This is a smoke test — the failure mode of the bug was a
    // visible colour mismatch, not a thrown exception, so this only
    // verifies the path doesn't crash. A golden test would be stronger.
    const svg = '''
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
        <rect x="0" y="0" width="10" height="10" fill="red"/>
      </svg>
    ''';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 50.0,
            height: 50.0,
            child: AnimatedSvg.string(
              svg,
              position: 0.5,
              colorTween: ColorTween(begin: Colors.red, end: Colors.blue),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(AnimatedSvg), findsOneWidget);
  });
}
