import 'image_cache.dart';
import 'image_url.dart';
import 'native.dart';
import 'prefs.dart';

/// Warms the disk cache with the renditions a list is about to draw, so scrolling into a picture
/// shows it from the file instead of waiting on the network.
///
/// It used to ask for each post's *original* — nine of them per grid, a megabyte or two each, for
/// every post that went past — which is what made the cache grow without bound and, once a budget
/// was in place, made it churn: download nine originals, trim the oldest nine away, repeat. What
/// is prefetched now is the rendition the grid actually draws; the original is fetched when a
/// picture is opened (`StatusImageGrid` starts it on the way down of the finger, the viewer for
/// both sides of the page), by which time the preview is on disk and shows in the same frame.
/// The newest request goes first and the queue is short: a fast fling should spend the bandwidth
/// on what the reader stopped at, not on everything that flew past.
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
      await InfImageCache.manager.getSingleFile(url, headers: weiboImageHeaders(url));
    } catch (_) {
      _requested.remove(url);
    }
    // A prefetch run is when the cache grows fastest, so this is where the budget is enforced. It
    // is throttled inside, so a run of hundreds of pictures still holds exactly one reading.
    await InfImageCache.instance.sweep();
  }
}
