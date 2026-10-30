import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The raw API payload of the first page of a few lists (feed, notifications, conversations, the
/// signed-in profile), kept on disk so those screens open on what was there last time and refresh
/// in place. Everything is read into memory at startup: the screens need it on their first frame.
class PageCache {
  PageCache._();
  static final PageCache instance = PageCache._();

  Directory? _dir;
  final Map<String, String> _raw = {};
  Future<void> _writes = Future<void>.value();

  Future<void> init() async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/page_cache');
      await dir.create(recursive: true);
      _dir = dir;
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final name = entity.uri.pathSegments.last;
        try {
          _raw[name.substring(0, name.length - 5)] = await entity.readAsString();
        } catch (_) {}
      }
    } catch (_) {
      _dir = null;
    }
  }

  static String _file(String scope, String key) =>
      '${scope}_$key'.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  dynamic read(String? scope, String key) {
    if (scope == null || scope.isEmpty) return null;
    final raw = _raw[_file(scope, key)];
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
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
    if (_raw[name] == text) return;
    _raw[name] = text;
    final dir = _dir;
    if (dir == null) return;
    _writes = _writes.then((_) async {
      try {
        final temp = File('${dir.path}/$name.tmp');
        await temp.writeAsString(text, flush: true);
        await temp.rename('${dir.path}/$name.json');
      } catch (_) {}
    });
  }

  Future<void> clear() async {
    _raw.clear();
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
