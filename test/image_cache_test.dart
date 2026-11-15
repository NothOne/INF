import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_cache_manager/flutter_cache_manager.dart' show ImageCacheManager;
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/emoji.dart';
import 'package:inf_flutter/core/image_cache.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/image_grid.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A directory of this run's own, so a test measures only the files it made.
class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);

  final Directory root;

  @override
  Future<String?> getTemporaryPath() async => root.path;

  @override
  Future<String?> getApplicationSupportPath() async => '${root.path}/support';
}

CachedPicture _picture(int mb, {required DateTime used}) =>
    CachedPicture('pic-$mb-${used.millisecondsSinceEpoch}', mb << 20, used);

DateTime _at(int minutesAgo) => DateTime.now().subtract(Duration(minutes: minutesAgo));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  // One directory for the whole file: `InfImageCache.manager` is a singleton and its file system
  // resolves the temporary directory once, so the paths must stay the same across tests.
  setUpAll(() async {
    root = await Directory.systemTemp.createTemp('inf-cache-test');
    await Directory('${root.path}/support').create(recursive: true);
    PathProviderPlatform.instance = _Paths(root);
  });

  tearDownAll(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  test('the picture cache is the folder earlier versions wrote to, and can resize', () {
    // The same key, so an upgrade keeps the files already on disk — and the first sweep has
    // something to measure and trim.
    expect(InfImageCache.folder, 'libCachedImageData');
    expect(InfImageCache.manager.config.cacheKey, InfImageCache.folder);
    // `SmartImage` passes a cacheWidth for avatars; that needs an ImageCacheManager, or the width
    // is silently ignored and every avatar is decoded at full size.
    expect(InfImageCache.manager, isA<ImageCacheManager>());
  });

  test('the entry-count trim never decides anything: the budget is in bytes', () {
    // The package's own limit skips anything touched since yesterday, which is why the cache grew
    // without bound. It is now far out of reach, and `sweep` trims instead.
    expect(InfImageCache.manager.config.maxNrOfCacheObjects, greaterThan(100000));
  });

  test('sweep takes the pictures used longest ago until the cache fits the budget', () async {
    final manager = InfImageCache.manager;
    final bytes = Uint8List(400 << 10);
    for (var i = 0; i < 6; i++) {
      await manager.putFile(
        'https://wx1.sinaimg.cn/large/$i.jpg',
        bytes,
        maxAge: const Duration(days: 30),
        fileExtension: 'jpg',
        // Spread the ages out so there is an order to trim in; `putFile` would otherwise stamp
        // them all with the same moment.
      );
    }
    final before = await InfImageCache.instance.size();
    expect(before, greaterThanOrEqualTo(2400 << 10));

    // Inside the budget: nothing goes.
    await InfImageCache.instance.sweep(force: true, budget: 200 << 20);
    expect(await InfImageCache.instance.size(), before);

    // 1 MB is less than the 2.4 MB on disk, so the oldest are removed until it fits.
    await InfImageCache.instance.sweep(force: true, budget: 1 << 20);
    final after = await InfImageCache.instance.size();
    expect(after, lessThan(before));
    expect(after, lessThanOrEqualTo(1 << 20));

    await manager.emptyCache();
    expect(await InfImageCache.instance.size(), 0);
  });

  /// Emptying the picture cache must leave emoji alone, and so must a trim: both would otherwise
  /// take the one set of pictures the app cannot re-fetch on demand.
  test('a trim and a clear both leave the learned emoji in the cache', () async {
    final manager = InfImageCache.manager;
    final emoji = 'https://face.t.sinajs.cn/t4/appstyle/expression/ext/normal/40/heart.png';
    EmojiStore.instance.learn({'[心]': emoji});
    expect(EmojiStore.instance.urls, contains(emoji));

    final bytes = Uint8List(400 << 10);
    final emojiFile = await manager.putFile(emoji, bytes, fileExtension: 'png');
    for (var i = 0; i < 6; i++) {
      await manager.putFile(
        'https://wx1.sinaimg.cn/large/$i.jpg',
        bytes,
        maxAge: const Duration(days: 30),
        fileExtension: 'jpg',
      );
    }

    // Far under the budget: nothing may go, and the emoji certainly may not.
    await InfImageCache.instance.sweep(force: true, budget: 4 << 20);
    expect(await emojiFile.exists(), isTrue);

    await InfImageCache.instance.clear();
    expect(await emojiFile.exists(), isTrue);
    // The six post pictures, which the next scroll brings back, are gone; only the emoji remains.
    expect(await InfImageCache.instance.size(), 400 << 10);
  });

  group('doomed', () {
    test('keeps everything while the cache is inside its budget', () {      final pictures = [_picture(100, used: _at(60)), _picture(100, used: _at(1))];
      expect(doomed(pictures, budget: 200 << 20), isEmpty);
    });

    test('takes the least recently used first, and stops below the budget', () {
      final oldest = _picture(100, used: _at(30));
      final middle = _picture(100, used: _at(20));
      final newest = _picture(100, used: _at(1));
      final drop = doomed([newest, oldest, middle], budget: 250 << 20);
      // 300 MB in a 250 MB budget: one picture is enough to get under the target. Trimming to the
      // budget itself would leave 250 MB, so the very next picture would put it over again.
      expect(drop, [oldest]);
    });

    test('takes as many as it needs to get under the target', () {
      final pictures = [
        for (var i = 0; i < 10; i++) _picture(100, used: _at(100 - i)),
      ];
      // 1 GB in a 500 MB budget targets 450 MB; each picture is 100 MB, so six go.
      final drop = doomed(pictures, budget: 500 << 20);
      expect(drop, hasLength(6));
      expect(drop.first, same(pictures.first));
    });

    test('a cache of rows left without files has nothing to free', () {
      final pictures = [
        for (var i = 0; i < 3; i++) CachedPicture('gone-$i', 0, _at(60 - i)),
      ];
      expect(doomed(pictures, budget: 1 << 20), isEmpty);
    });

    test('a kept picture is never dropped, though its bytes still count', () {
      final emoji = _picture(100, used: _at(90));
      final oldest = _picture(50, used: _at(60));
      final newest = _picture(100, used: _at(1));
      // 250 MB in a 200 MB budget, target 180 MB. Without `keep` the emoji, being oldest, would be
      // first out and one picture would be enough. With it the trim goes past the emoji, and the
      // two post pictures have to go before the total (100 MB) is under the target.
      final drop = doomed([emoji, oldest, newest], budget: 200 << 20, keep: (p) => p.key == emoji.key);
      expect(drop, [oldest, newest]);
    });
  });

  group('ImageCacheLimit', () {
    test('every limit but none has a byte budget, and they grow', () {
      expect(ImageCacheLimit.none.bytes, isNull);
      final budgets = [
        for (final limit in ImageCacheLimit.values)
          if (limit.bytes != null) limit.bytes!,
      ];
      expect(budgets, hasLength(4));
      expect(budgets, orderedEquals([...budgets]..sort()));
    });

    test('the default is 500 MB', () {
      expect(ImageCacheLimit.values.where((limit) => limit.bytes == 500 << 20), isNotEmpty);
    });
  });

  group('thumbnailUrl', () {
    final uploaded = 'https://wx1.sinaimg.cn/mw2000/abcd.jpg';
    final preview = 'https://wx1.sinaimg.cn/orj360/abcd.jpg';

    test('a lone picture asks for the 690px rendition the cell is drawn at', () {
      final media = Media.image(uploaded, previewUrl: preview, width: 1200, height: 900);
      expect(thumbnailUrl(media, single: true), 'https://wx1.sinaimg.cn/mw690/abcd.jpg');
    });

    test('a grid cell asks for the preview', () {
      final media = Media.image(uploaded, previewUrl: preview, width: 1200, height: 900);
      expect(thumbnailUrl(media, single: false), preview);
    });

    test('a long picture keeps the preview: decoding it larger costs far more memory', () {
      final media = Media.image(uploaded, previewUrl: preview, width: 800, height: 9000);
      expect(media.isLong, isTrue);
      expect(thumbnailUrl(media, single: true), preview);
    });

    test('never the original, which is what the prefetcher used to download', () {
      for (final single in [true, false]) {
        final media = Media.image(uploaded, previewUrl: preview);
        expect(thumbnailUrl(media, single: single), isNot(uploaded));
      }
    });
  });
}
