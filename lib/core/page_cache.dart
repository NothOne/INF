import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The raw API payload of the first page of a few lists (feed, notifications, conversations, the
/// signed-in profile, and recent post comments), kept on disk so those screens open on what was
/// there last time and refresh in place.
///
/// Fixed-cardinality tabs (`feed`, `profile`, `notify-*`, `conversations-*`) are preloaded into
/// memory at startup so the first frame never hits disk. High-cardinality per-post caches
/// (`comments-*`) are loaded lazily into an LRU map and trimmed on disk so cold startup and memory
/// stay bounded regardless of how many posts the reader has opened.
class PageCache {
  PageCache._();
  static final PageCache instance = PageCache._();

  /// Maximum number of dynamic (`comments-*`) pages kept in memory or on disk.
  static const int maxDynamicEntries = 40;

  Directory? _dir;
  final Map<String, String> _pinned = {};
  final Map<String, String> _dynamic = {};
  Future<void> _writes = Future<void>.value();
  int _dynamicDiskWrites = 0;

  static bool _isDynamicFile(String name) => name.contains('_comments-');

  static bool _isDynamicKey(String key) => key.startsWith('comments-');

  Future<void> init() async {
    _pinned.clear();
    _dynamic.clear();
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/page_cache');
      await dir.create(recursive: true);
      _dir = dir;
      final dynamicFiles = <File>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        final stem = name.substring(0, name.length - 5);
        if (_isDynamicFile(stem)) {
          dynamicFiles.add(entity);
          continue;
        }
        try {
          _pinned[stem] = await entity.readAsString();
        } catch (_) {}
      }
      if (dynamicFiles.length > maxDynamicEntries) {
        _writes = _writes.then((_) => _trimDynamicDisk());
      }
    } catch (_) {
      _dir = null;
    }
  }

  static String _file(String scope, String key) =>
      '${scope}_$key'.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  dynamic read(String? scope, String key) {
    if (scope == null || scope.isEmpty) return null;
    final name = _file(scope, key);
    String? raw;
    if (_isDynamicKey(key)) {
      raw = _dynamic.remove(name);
      if (raw != null) {
        _dynamic[name] = raw;
      } else {
        final dir = _dir;
        if (dir != null) {
          final file = File('${dir.path}/$name.json');
          try {
            if (file.existsSync()) {
              raw = file.readAsStringSync();
              _putDynamic(name, raw);
            }
          } catch (_) {}
        }
      }
    } else {
      raw = _pinned[name];
    }
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  void _putDynamic(String name, String text) {
    _dynamic.remove(name);
    _dynamic[name] = text;
    while (_dynamic.length > maxDynamicEntries) {
      _dynamic.remove(_dynamic.keys.first);
    }
  }

  void write(String? scope, String key, dynamic data) {
    if (scope == null || scope.isEmpty || data == null) return;
    final String text;
    try {
      text = jsonEncode(data);
    } catch (_) {
      return;
    }
    final name = _file(scope, key);
    final dynamicEntry = _isDynamicKey(key);
    if (dynamicEntry) {
      if (_dynamic[name] == text) return;
      _putDynamic(name, text);
    } else {
      if (_pinned[name] == text) return;
      _pinned[name] = text;
    }
    final dir = _dir;
    if (dir == null) return;
    final shouldTrim = dynamicEntry && (++_dynamicDiskWrites % 10 == 0);
    _writes = _writes.then((_) async {
      try {
        final temp = File('${dir.path}/$name.tmp');
        await temp.writeAsString(text, flush: true);
        await temp.rename('${dir.path}/$name.json');
        if (shouldTrim) await _trimDynamicDisk();
      } catch (_) {}
    });
  }

  Future<void> _trimDynamicDisk() async {
    final dir = _dir;
    if (dir == null) return;
    try {
      final entries = <(File, DateTime)>[];
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final stem = entity.uri.pathSegments.last;
        if (!_isDynamicFile(stem.substring(0, stem.length - 5))) continue;
        entries.add((entity, await entity.lastModified()));
      }
      if (entries.length <= maxDynamicEntries) return;
      entries.sort((a, b) => a.$2.compareTo(b.$2));
      for (final (file, _) in entries.take(entries.length - maxDynamicEntries)) {
        try {
          await file.delete();
        } catch (_) {}
      }
    } catch (_) {}
  }

  Future<void> flush() => _writes;

  Future<void> clear() async {
    _pinned.clear();
    _dynamic.clear();
    final dir = _dir;
    if (dir == null) return;
    await _writes;
    try {
      await for (final entity in dir.list(followLinks: false)) {
        await entity.delete(recursive: true);
      }
    } catch (_) {}
  }
}
