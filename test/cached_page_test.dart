import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/cached_page.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/page_cache.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/session.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a list keeps on disk, and what it refuses to.
///
/// The decision used to be an `if (cursor == null)` beside each endpoint, six times in four files.
/// These tests pin the three rules that came out of collecting them: only the first page is kept,
/// only the lists that asked for it are, and a cached page that cannot be read is no page rather
/// than an error.
class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.root);

  final Directory root;

  @override
  Future<String?> getApplicationSupportPath() async => '${root.path}/support';

  @override
  Future<String?> getApplicationDocumentsPath() async => '${root.path}/documents';

  @override
  Future<String?> getTemporaryPath() async => '${root.path}/cache';
}

/// A tiny list of ints, parsed the way the real ones are: from a body that has a `data` member.
PageResult<int> parseInts(dynamic data) {
  final list = (data as Map)['data'] as List;
  return PageResult([for (final item in list) item as int], null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('inf-cache-test');
    await Directory('${root.path}/support').create(recursive: true);
    PathProviderPlatform.instance = _Paths(root);
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
    await PageCache.instance.init();
    await PageCache.instance.clear();
    // PageCache keys by account; these tests are one account, and set it explicitly rather than
    // relying on whatever the session singleton was left as.
    Session.instance.uid = 'u-test';
  });

  tearDown(() async {
    await PageCache.instance.clear();
    Session.instance.uid = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('only the first page is kept', () {
    test('the first page is written and comes back', () {
      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      cache.accept({'data': [1, 2, 3]}, isFirstPage: true);

      expect(cache.read()?.items, [1, 2, 3]);
    });

    test('a later page is parsed but not stored', () {
      // The first page is what a list opens on; a second page stored over it would open the list in
      // the middle of the timeline next launch.
      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      cache.accept({'data': [1, 2]}, isFirstPage: true);
      cache.accept({'data': [3, 4]}, isFirstPage: false);

      expect(cache.read()?.items, [1, 2]);
    });

    test('accept still hands back the page it was given', () {
      // Storing is a side effect; the caller always gets the live answer, not the cached one.
      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      final page = cache.accept({'data': [9]}, isFirstPage: false);
      expect(page.items, [9]);
    });
  });

  group('a list that asked for no cache keeps none', () {
    test('networkOnly neither writes nor reads', () {
      final cache = CachedPage<int>(key: 'search', parse: parseInts, policy: CachePolicy.networkOnly);
      cache.accept({'data': [1]}, isFirstPage: true);

      expect(cache.read(), isNull);
    });

    test('a search does not open on last time\'s results', () {
      // The same key would otherwise be shared by every query the reader typed.
      final all = CachedPage<int>(key: 'search', parse: parseInts);
      all.accept({'data': [1, 2]}, isFirstPage: true);
      final narrowed = CachedPage<int>(key: 'search', parse: parseInts, policy: CachePolicy.networkOnly);
      expect(narrowed.read(), isNull);
    });
  });

  group('what is stored is what the list needs', () {
    test('wrap and unwrap carry a body with the extra it was stored with', () {
      // The feed keeps which source it came from beside the body; a cached feed is only worth
      // opening on the list it was read on.
      final cache = CachedPage<int>(
        key: 'wrapped',
        wrap: (data) => {'meta': 'all', 'data': data},
        unwrap: (stored) => (stored as Map)['data'],
        parse: parseInts,
      );
      cache.accept({'data': [7, 8]}, isFirstPage: true);

      expect(PageCache.instance.read('u-test', 'wrapped'), {'meta': 'all', 'data': {'data': [7, 8]}});
      expect(cache.read()?.items, [7, 8]);
    });

    test('an empty first page is not stored, so a blank list is not what opens next time', () {
      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      cache.accept({'data': <int>[]}, isFirstPage: true);

      expect(cache.read(), isNull);
    });
  });

  group('a cache that cannot be read is no cache', () {
    test('a body the parser cannot handle reads as missing', () {
      // A stored page from an older shape. The page shows its skeleton and asks again — the state it
      // would be in on a first launch — rather than 加载失败 before a request was ever sent.
      PageCache.instance.write('u-test', 'broken', {'data': 'not a list'});
      final cache = CachedPage<int>(key: 'broken', parse: parseInts);

      expect(cache.read(), isNull);
    });

    test('a key nobody wrote reads as missing', () {
      expect(CachedPage<int>(key: 'never-written', parse: parseInts).read(), isNull);
    });
  });

  group('the account is not part of the key', () {
    test('two accounts do not see each other\'s pages', () {
      // The key says what the list is; PageCache puts the account in front of it. Spelling the
      // account into the key as well would make the two disagree the moment one changed.
      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      cache.accept({'data': [1]}, isFirstPage: true);
      expect(cache.read()?.items, [1]);

      Session.instance.uid = 'someone-else';
      expect(cache.read(), isNull);
    });

    test('read and write share cacheScope while session check is still running', () async {
      Session.instance.uid = null;
      Session.instance.state = SessionState.checking;
      await Prefs.instance.setLastUid('u-last');

      final cache = CachedPage<int>(key: 'list', parse: parseInts);
      cache.accept({'data': [4, 5]}, isFirstPage: true);
      expect(cache.read()?.items, [4, 5]);
    });
  });

  group('CachedValue and bounded dynamic cache', () {
    test('CachedValue writes, reads, and tolerates corrupt entries', () {
      final entry = CachedValue<String>(
        key: 'profile',
        wrap: (data) => {'name': (data as Map)['name']},
        parse: (data) => (data as Map)['name'] as String,
      );
      entry.write({'name': 'INF'});
      expect(entry.read(), 'INF');

      PageCache.instance.write('u-test', 'profile', {'name': 123});
      expect(entry.read(), isNull);
    });

    test('comments-* entries are loaded lazily on restart and capped on disk', () async {
      for (var i = 0; i < PageCache.maxDynamicEntries + 15; i++) {
        PageCache.instance.write('u-test', 'comments-post$i-0', {'i': i});
      }
      await PageCache.instance.flush();

      // Re-init simulates cold startup: dynamic comment files are trimmed, not all preloaded.
      await PageCache.instance.init();
      await PageCache.instance.flush();

      final dir = Directory('${root.path}/support/page_cache');
      final commentFiles = dir.listSync().where((e) => e.path.endsWith('.json') && e.path.contains('_comments-')).toList();
      expect(commentFiles.length, lessThanOrEqualTo(PageCache.maxDynamicEntries));

      // A kept entry is still readable synchronously via lazy disk load.
      final latest = PageCache.instance.read('u-test', 'comments-post${PageCache.maxDynamicEntries + 14}-0');
      expect((latest as Map?)?['i'], PageCache.maxDynamicEntries + 14);
    });
  });
}
