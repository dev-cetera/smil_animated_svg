import 'parser/svg_node.dart';

/// In-memory parse cache for [SvgRoot].
///
/// Used when the same asset path or URL is rendered in many widgets (lists,
/// grids). Parsing an SVG isn't free, so we hold a small LRU keyed by the
/// resolved source string. Cleared on hot reload via the widget's
/// `reassemble` hook.
class SvgParseCache {
  const SvgParseCache._();

  /// A recoloured tree (see `recolor_svg.dart`) lives here alongside the
  /// un-recoloured one it was derived from, so an app rendering its art in two
  /// palettes holds two entries per asset. 64 keeps a screenful of both in
  /// cache instead of evicting the palette that just scrolled off.
  static const int maxEntries = 64;
  static final _entries = <String, SvgRoot>{};

  static SvgRoot? get(String key) {
    final root = _entries.remove(key);
    if (root != null) _entries[key] = root; // LRU touch.
    return root;
  }

  static void put(String key, SvgRoot root) {
    if (_entries.length >= maxEntries) {
      _entries.remove(_entries.keys.first);
    }
    _entries[key] = root;
  }

  static void clear() => _entries.clear();
}
