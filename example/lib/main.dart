import 'package:animated_svg/animated_svg.dart';
import 'package:flutter/material.dart';

void main() => runApp(const AnimatedSvgExampleApp());

class AnimatedSvgExampleApp extends StatelessWidget {
  const AnimatedSvgExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'animated_svg example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff1976d2)),
        useMaterial3: true,
      ),
      home: const _Home(),
    );
  }
}

class _Home extends StatefulWidget {
  const _Home();

  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  static const List<({String label, String asset})> samples = [
    (label: 'Spinner', asset: 'assets/spinner.svg'),
    (label: 'Pulse', asset: 'assets/pulse.svg'),
    (label: 'Color wave', asset: 'assets/color_wave.svg'),
    (label: 'Bounce', asset: 'assets/bounce.svg'),
    (label: 'Static', asset: 'assets/shapes.svg'),
  ];

  int sampleIndex = 0;
  bool useFrameMode = false;
  double position = 0.0;

  int filterIndex = 0;
  double outerScale = 1.0;
  bool useColorTween = false;
  bool useEaseInOut = false;

  late final List<({String label, ColorFilter? filter})> filters = [
    (label: 'None (preserve SVG colours)', filter: null),
    (
      label: 'Grayscale (luminance-preserving)',
      filter: AnimatedSvgFilters.grayscale,
    ),
    (label: 'Sepia', filter: AnimatedSvgFilters.sepia),
    (label: 'Invert', filter: AnimatedSvgFilters.invert),
    (
      label: 'Tint blue (modulate — preserves shading)',
      filter: AnimatedSvgFilters.tint(Colors.blue),
    ),
    (
      label: 'Colorize blue (replace hue, keep luminance)',
      filter: AnimatedSvgFilters.colorize(Colors.blue),
    ),
    (
      label: 'Silhouette blue (srcIn — replace all pixels)',
      filter: const ColorFilter.mode(Colors.blue, BlendMode.srcIn),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('animated_svg')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<int>(
              segments: [
                for (var index = 0; index < samples.length; index++)
                  ButtonSegment<int>(
                    value: index,
                    label: Text(samples[index].label),
                  ),
              ],
              selected: {sampleIndex},
              onSelectionChanged: (set) =>
                  setState(() => sampleIndex = set.first),
            ),
            const SizedBox(height: 16.0),
            Center(
              child: SizedBox(
                width: 320.0,
                height: 320.0,
                child: _renderActive(),
              ),
            ),
            const SizedBox(height: 16.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Mode'),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('AnimatedSvg')),
                    ButtonSegment(value: true, label: Text('SvgFrame')),
                  ],
                  selected: {useFrameMode},
                  onSelectionChanged: (set) =>
                      setState(() => useFrameMode = set.first),
                ),
              ],
            ),
            if (useFrameMode) ...[
              const SizedBox(height: 8.0),
              Text('position: ${position.toStringAsFixed(2)}'),
              Slider(
                value: position,
                onChanged: (value) => setState(() => position = value),
              ),
            ] else ...[
              const SizedBox(height: 8.0),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Curves.easeInOut'),
                value: useEaseInOut,
                onChanged: (v) => setState(() => useEaseInOut = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Color tween (red → blue)'),
                value: useColorTween,
                onChanged: (v) => setState(() => useColorTween = v),
              ),
            ],
            const SizedBox(height: 8.0),
            const Text('colorFilter recipe'),
            DropdownButton<int>(
              value: filterIndex,
              isExpanded: true,
              onChanged: (v) => setState(() => filterIndex = v ?? 0),
              items: [
                for (var index = 0; index < filters.length; index++)
                  DropdownMenuItem(
                    value: index,
                    child: Text(filters[index].label),
                  ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text('Outer scale: ${outerScale.toStringAsFixed(2)}x'),
            Slider(
              value: outerScale,
              min: 0.25,
              max: 2.0,
              divisions: 35,
              onChanged: (value) => setState(() => outerScale = value),
            ),
          ],
        ),
      ),
    );
  }

  Widget _renderActive() {
    final asset = samples[sampleIndex].asset;
    final scaleTransform = Matrix4.diagonal3Values(outerScale, outerScale, 1.0);
    final activeFilter = filters[filterIndex].filter;

    if (useFrameMode) {
      return SvgFrame.asset(
        asset,
        position: position,
        clipBehavior: Clip.none,
        transform: scaleTransform,
        colorFilter: activeFilter,
        semanticsLabel: 'svg frame at $position',
      );
    }
    return AnimatedSvg.asset(
      asset,
      curve: useEaseInOut ? Curves.easeInOut : Curves.linear,
      colorTween: useColorTween
          ? ColorTween(begin: Colors.red, end: Colors.blue)
          : null,
      clipBehavior: Clip.none,
      transform: scaleTransform,
      colorFilter: activeFilter,
      semanticsLabel: 'animated svg sample',
    );
  }
}
