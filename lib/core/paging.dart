import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'models.dart';

/// A small cursor pager. The Compose app used androidx Paging; a list this size does not justify a
/// port of that machinery, but the states (first load, append, end, error) and the deduplication
/// around Weibo's repeated boundary items are identical.
class PagingController<T> extends ChangeNotifier {
  PagingController({
    required this.fetch,
    required this.id,
    this.pageSize = 20,
    this.keepTailOnRefresh = false,
  });

  final Future<PageResult<T>> Function(String? cursor) fetch;
  final String Function(T item) id;
  final int pageSize;

  /// For newest-first lists: when the fresh first page reaches down into what is already loaded,
  /// it is joined on top of it instead of replacing it, so the place being read survives.
  final bool keepTailOnRefresh;

  final List<T> items = [];
  final Set<String> _seen = {};
  String? cursor;
  bool loading = false;
  bool loadingMore = false;
  bool hasMore = true;
  Object? error;
  Object? moreError;
  bool _inFlight = false;
  bool _disposed = false;
  bool _background = false;

  /// The items shown came from the on-disk cache and have not been refreshed yet.
  bool stale = false;

  /// When the last successful refresh landed.
  DateTime? refreshedAt;

  /// Ids the latest refresh added above or between items that were already on screen; list rows
  /// use it to grow in instead of appearing in place. Cleared shortly after, so a row scrolled
  /// back into view later does not animate again.
  Set<String> fresh = const {};
  Timer? _freshTimer;

  bool get isEmpty => items.isEmpty;
  bool get isInitialLoading => loading && items.isEmpty;

  /// A refresh nobody pulled for is running over content that is already visible.
  bool get backgroundRefreshing => loading && _background && items.isNotEmpty;

  /// Shows a cached first page until the first refresh replaces it.
  void seed(PageResult<T>? page) {
    if (page == null || items.isNotEmpty || page.items.isEmpty) return;
    _append(page.items);
    cursor = page.nextCursor;
    hasMore = page.nextCursor != null;
    stale = true;
    _notify();
  }

  /// Completes with whether the first page arrived. [background] marks a refresh the user did
  /// not start by pulling, so the list can show its own quiet progress instead of the spinner.
  Future<bool> refresh({bool quiet = false, bool background = false}) async {
    if (_inFlight) return true;
    _inFlight = true;
    _background = background;
    if (!quiet) {
      loading = true;
      error = null;
      _notify();
    }
    try {
      // Keep the old list visible while the refresh request is in flight;
      // this is what makes pull-to-refresh and the home double-tap feel like
      // a refresh instead of a jump back to the skeleton.
      final page = await fetch(null);
      final before = items.isEmpty ? const <String>{} : _seen.toSet();
      final fresh = {for (final item in page.items) id(item)};
      final joins = keepTailOnRefresh && items.any((item) => fresh.contains(id(item)));
      final tail = joins ? items.where((item) => !fresh.contains(id(item))).toList() : <T>[];
      _seen.clear();
      items.clear();
      _append(page.items);
      if (joins) {
        // The older pages and their cursor carry on below the fresh one.
        _append(tail);
      } else {
        cursor = page.nextCursor;
        hasMore = page.nextCursor != null && page.items.isNotEmpty;
      }
      _markFresh(before);
      error = null;
      stale = false;
      refreshedAt = DateTime.now();
      return true;
    } catch (e) {
      if (items.isEmpty) {
        error = e;
        hasMore = false;
      } else if (!background) {
        error = e;
      }
      return false;
    } finally {
      loading = false;
      _inFlight = false;
      _background = false;
      _notify();
    }
  }

  void _markFresh(Set<String> before) {
    _freshTimer?.cancel();
    if (before.isEmpty) {
      fresh = const {};
      return;
    }
    final added = <String>{};
    for (final item in items) {
      final key = id(item);
      if (!before.contains(key)) added.add(key);
    }
    fresh = added;
    if (added.isEmpty) return;
    _freshTimer = Timer(const Duration(milliseconds: 1200), () => fresh = const {});
  }

  Future<void> loadMore() async {
    if (_inFlight || loading || loadingMore || !hasMore) return;
    _inFlight = true;
    loadingMore = true;
    moreError = null;
    _notify();
    try {
      final page = await fetch(cursor);
      _append(page.items);
      final previous = cursor;
      cursor = page.nextCursor;
      if (page.items.isEmpty || page.nextCursor == null || page.nextCursor == previous) {
        hasMore = false;
      }
    } catch (e) {
      moreError = e;
    } finally {
      loadingMore = false;
      _inFlight = false;
      _notify();
    }
  }

  void _append(List<T> incoming) {
    for (final item in incoming) {
      if (_seen.add(id(item))) items.add(item);
    }
  }

  /// Lets a keyed list find a row again after a refresh moved it, so its state (and its decoded
  /// pictures) move with it instead of being rebuilt for whatever now sits at that index.
  int? indexOfKey(Key key, {int offset = 0}) {
    if (key is! ValueKey<String>) return null;
    for (var index = 0; index < items.length; index++) {
      if (id(items[index]) == key.value) return index + offset;
    }
    return null;
  }

  /// Call from a scroll notification; loads the next page a little before the bottom.
  void onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return;
    final metrics = notification.metrics;
    if (metrics.pixels >= metrics.maxScrollExtent - 480 && hasMore && !loadingMore) {
      loadMore();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _freshTimer?.cancel();
    super.dispose();
  }
}
