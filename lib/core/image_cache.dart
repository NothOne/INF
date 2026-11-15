import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

import 'emoji.dart';
import 'prefs.dart';

/// The one picture cache: what `SmartImage` draws, what the viewer opens, what the prefetcher
/// warms and what saving and sharing read from. All of it lives here, under a byte budget the
/// reader picks in the settings.
///
/// `flutter_cache_manager`'s own limit counts *entries*, not bytes, and its trim skips anything
/// touched since yesterday — pictures downloaded today are never over capacity, so a session of
/// scrolling put hundreds of megabytes on disk with nothing to stop it. Here that limit is left
/// wide enough to never fire, and [sweep] enforces the budget itself, by bytes.
class InfImageCache {
  InfImageCache._();

  static final InfImageCache instance = InfImageCache._();

  /// The key this app has always cached pictures under. Keeping it means an upgrade reuses what is
  /// already downloaded — and lets the first sweep measure and trim it — instead of orphaning a
  /// folder nothing would ever delete.
  static const folder = 'libCachedImageData';

  /// The cache itself. The package's entry-count trim is set out of the way; see the class comment.
  /// Building it is what opens the package's metadata store, so nothing does so at import time.
  static final CacheManager manager = _Manager(
    Config(
      folder,
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 1 << 20,
    ),
  );

  static const _minInterval = Duration(minutes: 5);

  bool _sweeping = false;
  DateTime _lastSweep = DateTime.fromMillisecondsSinceEpoch(0);

  /// Trims the cache back to the budget, oldest picture first.
  ///
  /// Runs at startup and again whenever the prefetcher runs dry, but no more often than
  /// [_minInterval]: a fast fling queues hundreds of downloads and would otherwise sweep for each.
  /// [budget] overrides the setting, which is how a trim is put under test.
  Future<void> sweep({bool force = false, int? budget}) async {
    if (_sweeping) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastSweep) < _minInterval) return;
    _sweeping = true;
    _lastSweep = now;
    try {
      final limit = budget ?? Prefs.instance.imageCacheLimit.bytes;
      if (limit == null) return;
      final dir = await _dir();
      if (!await dir.exists()) return;
      // The sizes are read from the files: a picture put in by `putFile` carries no length in the
      // package's own records, so its total would come out too low. Reading the folder first also
      // keeps the common case — inside the budget — away from the database entirely.
      final sizes = await _files(dir);
      if (sizes.isEmpty) return;
      final total = sizes.values.fold<int>(0, (sum, size) => sum + size);
      if (total <= limit) return;
      final emoji = EmojiStore.instance.urls;
      for (final picture in doomed(await _pictures(sizes), budget: limit, keep: (p) => emoji.contains(p.key))) {
        await manager.removeFile(picture.key);
      }
    } catch (_) {
      // A sweep that could not read the cache has changed nothing; the next one tries again.
    } finally {
      _sweeping = false;
    }
  }

  /// What the pictures take now, for the settings to show.
  Future<int> size() async {
    final dir = await _dir();
    if (!await dir.exists()) return 0;
    final sizes = await _files(dir);
    return sizes.values.fold<int>(0, (sum, size) => sum + size);
  }

  /// Empties the cache of post pictures. Emoji stay: they are a fixed set with no other copy, and
  /// the rest of the cache exists for pictures that come back with the next scroll.
  Future<void> clear() async {
    final emoji = EmojiStore.instance.urls;
    final dir = await _dir();
    if (await dir.exists()) {
      for (final picture in await _pictures(await _files(dir))) {
        if (emoji.contains(picture.key)) continue;
        await manager.removeFile(picture.key);
      }
    }
    PaintingBinding.instance.imageCache
      ..clear()
      ..clearLiveImages();
  }

  /// Where the package's `IOFileSystem` puts this key's files.
  Future<Directory> _dir() async => Directory('${(await getTemporaryDirectory()).path}/$folder');

  /// The size of each file in the cache folder, by file name.
  Future<Map<String, int>> _files(Directory dir) async {
    final sizes = <String, int>{};
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File) {
        final name = entity.uri.pathSegments.last;
        try {
          sizes[name] = await entity.length();
        } on FileSystemException {
          // Gone between listing and measuring; not part of the total.
        }
      }
    }
    return sizes;
  }

  /// Every picture the cache has a row for, with the size of its file on disk. A row whose file has
  /// gone is removed here: nothing can be drawn from it, and the package only notices when that
  /// picture is asked for again.
  Future<List<CachedPicture>> _pictures(Map<String, int> sizes) async {
    final repo = manager.config.repo;
    await repo.open();
    final pictures = <CachedPicture>[];
    try {
      for (final object in await repo.getAllObjects()) {
        final size = sizes[object.relativePath];
        if (size == null) {
          await manager.removeFile(object.key);
          continue;
        }
        pictures.add(CachedPicture(object.key, size, object.touched ?? object.validTill));
      }
    } finally {
      // Matches the open above; the cache's own store holds a reference of its own, so the
      // database stays open for the downloads that are still running.
      await repo.close();
    }
    return pictures;
  }
}

/// One picture in the cache, as [doomed] sees it.
class CachedPicture {
  const CachedPicture(this.key, this.size, this.used);

  final String key;
  final int size;

  /// When it was last shown or downloaded; empty for rows the package itself removed.
  final DateTime used;
}

/// Which of [pictures] to delete so the cache fits in [budget]: the least recently used first.
///
/// It trims to [_trimTarget] of the budget rather than to the budget itself, because stopping at
/// the line would put the next download back over it, and every sweep would delete exactly the
/// picture that had just been added.
///
/// [keep] is never deleted, but its bytes still count against the budget: a picture that may not be
/// trimmed is part of the total being trimmed towards. If that leaves too little room the cache ends
/// up over budget rather than deleting them, which is the point — they have no other copy.
List<CachedPicture> doomed(
  List<CachedPicture> pictures, {
  required int budget,
  double trimTo = _trimTarget,
  bool Function(CachedPicture picture)? keep,
}) {
  var total = pictures.fold<int>(0, (sum, picture) => sum + picture.size);
  if (total <= budget) return const [];
  final oldestFirst = [...pictures]..sort((a, b) => a.used.compareTo(b.used));
  final target = (budget * trimTo).round();
  final drop = <CachedPicture>[];
  for (final picture in oldestFirst) {
    if (total <= target) break;
    if (keep != null && keep(picture)) continue;
    drop.add(picture);
    total -= picture.size;
  }
  return drop;
}

/// Where a trim settles: a tenth of the budget is room for a screen or two of new pictures.
const _trimTarget = 0.9;

class _Manager extends CacheManager with ImageCacheManager {
  _Manager(super.config);
}
