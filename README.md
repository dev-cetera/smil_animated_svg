[![pub](https://img.shields.io/pub/v/animated_svg.svg)](https://pub.dev/packages/animated_svg)
[![tag](https://img.shields.io/badge/Tag-v0.1.0-purple?logo=github)](https://github.com/dev-cetera/animated_svg/tree/v0.1.0)
[![buymeacoffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-FFDD00?logo=buy-me-a-coffee&logoColor=black)](https://www.buymeacoffee.com/dev_cetera)
[![sponsor](https://img.shields.io/badge/Sponsor-grey?logo=github-sponsors&logoColor=pink)](https://github.com/sponsors/dev-cetera)
[![patreon](https://img.shields.io/badge/Patreon-grey?logo=patreon)](https://www.patreon.com/robelator)
[![discord](https://img.shields.io/badge/Discord-5865F2?logo=discord&logoColor=white)](https://discord.gg/gEQ8y2nfyX)
[![instagram](https://img.shields.io/badge/Instagram-E4405F?logo=instagram&logoColor=white)](https://www.instagram.com/dev_cetera/)
[![license](https://img.shields.io/badge/License-MIT-blue.svg)](https://raw.githubusercontent.com/dev-cetera/animated_svg/main/LICENSE)

---

<!-- BEGIN _README_CONTENT -->

## Summary

Render **SMIL-animated SVGs** in Flutter with programmatic pause / resume / speed / colour control — no native plugins, no platform channels, no external rasteriser.

Two widgets ship in the box:

| Widget | What it does |
| --- | --- |
| `SvgFrame` | Leaf renderer. Draws one frame of an SVG at a given `position` (0..1). No ticker, no animation controller. Drop one in for a static SVG, or wrap one in an `AnimatedBuilder` to drive `position` yourself. |
| `AnimatedSvg` | Self-playing. Owns an internal `AnimationController` and plays the SVG's natural cycle (or a custom `duration`). Adds `curve`, `repeat`, `stopAt`, `position` (freeze), and tween shortcuts for `color`, `transform`, and `opacity`. |

Built-in `AnimatedSvgFilters`: `grayscale`, `sepia`, `invert`, `tint`, `colorize`.

Supported SVG subset: `<g>`, `<path>`, `<rect>`, `<circle>`, `<ellipse>`, `<line>`, `<polygon>`, `<polyline>`, `<animate>`, `<animateTransform>` (translate, rotate, scale, skewX, skewY, matrix). `calcMode="linear|spline|discrete"` with `keyTimes` and `keySplines`. From/to/by shorthands. Indefinite and finite `repeatCount`. **No gradients, no `<use>`, no `<text>`, no `<image>`, no `<animateMotion>`, no CSS filter effects.**

## Installation

```sh
flutter pub add animated_svg
```

## Usage

```dart
import 'package:animated_svg/animated_svg.dart';
import 'package:flutter/material.dart';

class Loader extends StatelessWidget {
  const Loader({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedSvg.asset(
      'assets/spinner.svg',
      width: 64,
      height: 64,
      // Override the SVG's intrinsic cycle.
      duration: const Duration(seconds: 1),
      // Tint to match the active theme without re-authoring the SVG.
      color: Theme.of(context).colorScheme.primary,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
```

### Other source constructors

```dart
SvgFrame.string(svgXml, position: 0.4);
SvgFrame.network('https://example.com/icon.svg');
AnimatedSvg.parsed(parseSvg(svgXml));   // pre-parsed, zero load cost
```

### Frame-stepping a static `SvgFrame`

```dart
AnimatedBuilder(
  animation: myController,
  builder: (context, _) => SvgFrame.asset(
    'assets/pulse.svg',
    position: myController.value,
  ),
);
```

### Tweens that ride the playback timeline

```dart
AnimatedSvg.asset(
  'assets/icon.svg',
  colorTween: ColorTween(begin: Colors.red, end: Colors.blue),
  transformTween: Matrix4Tween(
    begin: Matrix4.identity(),
    end: Matrix4.diagonal3Values(1.2, 1.2, 1.0),
  ),
);
```

Tween values are evaluated at the curved controller value during playback, or at the frozen `position` when one is supplied.

<!-- END _README_CONTENT -->

---

🔍 For more information, refer to the [API reference](https://pub.dev/documentation/animated_svg/).

---

## 💬 Contributing and Discussions

This is an open-source project, and we warmly welcome contributions from everyone, regardless of experience level. Whether you're a seasoned developer or just starting out, contributing to this project is a fantastic way to learn, share your knowledge, and make a meaningful impact on the community.

### ☝️ Ways you can contribute

- **Find us on Discord:** Feel free to ask questions and engage with the community here: https://discord.gg/gEQ8y2nfyX.
- **Share your ideas:** Every perspective matters, and your ideas can spark innovation.
- **Help others:** Engage with other users by offering advice, solutions, or troubleshooting assistance.
- **Report bugs:** Help us identify and fix issues to make the project more robust.
- **Suggest improvements or new features:** Your ideas can help shape the future of the project.
- **Help clarify documentation:** Good documentation is key to accessibility. You can make it easier for others to get started by improving or expanding our documentation.
- **Write articles:** Share your knowledge by writing tutorials, guides, or blog posts about your experiences with the project. It's a great way to contribute and help others learn.

No matter how you choose to contribute, your involvement is greatly appreciated and valued!

### ☕ We drink a lot of coffee...

If you're enjoying this package and find it valuable, consider showing your appreciation with a small donation. Every bit helps in supporting future development. You can donate here: https://www.buymeacoffee.com/dev_cetera

<a href="https://www.buymeacoffee.com/dev_cetera" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/default-orange.png" height="40"></a>

## LICENSE

This project is released under the [MIT License](https://raw.githubusercontent.com/dev-cetera/animated_svg/main/LICENSE). See [LICENSE](https://raw.githubusercontent.com/dev-cetera/animated_svg/main/LICENSE) for more information.
