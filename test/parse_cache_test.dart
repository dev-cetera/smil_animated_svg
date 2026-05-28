import 'package:animated_svg/animated_svg.dart';
import 'package:animated_svg/src/parse_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Cache is global static state. Reset between tests so ordering doesn't
  // leak.
  setUp(SvgParseCache.clear);

  test('get of missing key returns null', () {
    expect(SvgParseCache.get('nope'), isNull);
  });

  test('put then get returns the same root by reference', () {
    final root = _stubRoot();
    SvgParseCache.put('asset:foo.svg', root);
    expect(identical(SvgParseCache.get('asset:foo.svg'), root), isTrue);
  });

  test('clear empties the cache', () {
    SvgParseCache.put('asset:foo.svg', _stubRoot());
    SvgParseCache.clear();
    expect(SvgParseCache.get('asset:foo.svg'), isNull);
  });

  test('eviction kicks in at maxEntries (LRU)', () {
    final extras = SvgParseCache.maxEntries + 5;
    final roots = List.generate(extras, (_) => _stubRoot());
    for (var i = 0; i < extras; i++) {
      SvgParseCache.put('asset:item_$i.svg', roots[i]);
    }
    // The oldest entries should have been evicted.
    expect(SvgParseCache.get('asset:item_0.svg'), isNull);
    expect(SvgParseCache.get('asset:item_4.svg'), isNull);
    // Recent ones survive.
    expect(SvgParseCache.get('asset:item_${extras - 1}.svg'), isNotNull);
  });

  test('get touches LRU order so old entries survive churn', () {
    final keepAlive = _stubRoot();
    SvgParseCache.put('asset:keep.svg', keepAlive);
    // Fill the rest of the cache.
    for (var i = 0; i < SvgParseCache.maxEntries - 1; i++) {
      SvgParseCache.put('asset:filler_$i.svg', _stubRoot());
    }
    // Touch the keep-alive entry so it's now the most-recently-used.
    expect(SvgParseCache.get('asset:keep.svg'), isNotNull);
    // One more put should now evict the oldest filler, NOT keep.svg.
    SvgParseCache.put('asset:extra.svg', _stubRoot());
    expect(SvgParseCache.get('asset:keep.svg'), isNotNull);
    expect(SvgParseCache.get('asset:filler_0.svg'), isNull);
  });
}

SvgRoot _stubRoot() => parseSvg(
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
      '<rect x="0" y="0" width="1" height="1"/></svg>',
    );
