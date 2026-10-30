import 'package:flutter_cache_manager/flutter_cache_manager.dart';

import 'image_url.dart';
import 'native.dart';
import 'prefs.dart';

/// Downloads the full-size pictures of posts as they scroll into view, into the same disk cache
/// the viewer reads from, so opening a picture decodes a local file instead of waiting on the
/// network. The newest request goes first and the queue is short: a fast fling should spend the
/// bandwidth on what the reader stopped at, not on everything that flew past.
class ImagePrefetcher {
  ImagePrefetcher._();
  static final ImagePrefetcher instance = ImagePrefetcher._();

  static const _parallel = 2;
  static const _queueLimit = 18;
  static const _rememberLimit = 800;

  final List<String> _queue = [];
  final Set<String> _requested = {};
  int _active = 0;
  bool? _metered;
  DateTime _meteredAt = DateTime.fromMillisecondsSinceEpoch(0);

  void request(Iterable<String> urls) {
    if (Prefs.instance.imagePreload == ImagePreload.off) return;
    var added = false;
    for (final raw in urls) {
      final url = sanitizeImageUrl(raw);
      if (url.isEmpty || _requested.contains(url)) continue;
      _queue.remove(url);
      _queue.add(url);
      added = true;
    }
    if (!added) return;
    if (_queue.length > _queueLimit) _queue.removeRange(0, _queue.length - _queueLimit);
    _pump();
  }

  Future<bool> _allowed() async {
    switch (Prefs.instance.imagePreload) {
      case ImagePreload.off:
        return false;
      case ImagePreload.always:
        return true;
      case ImagePreload.wifi:
        final now = DateTime.now();
        if (_metered == null || now.difference(_meteredAt) > const Duration(seconds: 30)) {
          _metered = await Native.isMeteredNetwork();
          _meteredAt = now;
        }
        return _metered == false;
    }
  }

  void _pump() {
    while (_active < _parallel && _queue.isNotEmpty) {
      _active++;
      _work().whenComplete(() {
        _active--;
        _pump();
      });
    }
  }

  Future<void> _work() async {
    if (!await _allowed()) {
      _queue.clear();
      return;
    }
    if (_queue.isEmpty) return;
    final url = _queue.removeLast();
    if (!_requested.add(url)) return;
    if (_requested.length > _rememberLimit) _requested.remove(_requested.first);
    try {
      await DefaultCacheManager().getSingleFile(url, headers: weiboImageHeaders());
    } catch (_) {
      _requested.remove(url);
    }
  }
}
