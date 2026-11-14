import 'dart:async';

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

  /// For newest-first lists: a refresh the reader did not pull keeps what was already loaded below
  /// the fresh first page instead of throwing it away, so the post being read survives — the feed
  /// lays the list out from that post, and losing it is what used to send the reader back to the
  /// top. When the first page does not reach down to the kept posts, the pages in between are
  /// fetched as part of the same refresh, so the list never shows a break in the timeline. A pull,
  /// which the reader starts from the top, keeps the old behaviour.
  final bool keepTailOnRefresh;

  /// How many pages a kept-back refresh may walk to reach the posts it kept. More new posts than
  /// this means the reader has been away long enough that the place they were at is not worth
  /// holding: the list is replaced and the offer to go back is shown instead.
  static const _bridgePages = 4;

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
      final headIds = {for (final item in page.items) id(item)};
      // A refresh the reader pulled starts from the top on purpose, so when the fresh page does not
      // reach the posts already loaded the list is simply replaced. One that happens on its own —
      // coming back to the app, after posting — keeps those posts below the fresh page instead: the
      // feed lays its list out from the post being read, and dropping it is what used to send the
      // reader back to the top.
      final keeps = keepTailOnRefresh && items.isNotEmpty;
      final joined = keeps && items.any((item) => headIds.contains(id(item)));
      final List<T> kept = keeps ? List<T>.of(items) : <T>[];
      final keptIds = {for (final item in kept) id(item)};
      // Walk down from the fresh page to the first kept post, so the list has no break in the
      // timeline. Too many new posts to reach it means the reader has been away long enough that
      // the place is not worth holding: the list is replaced and the offer to go back is shown.
      final bridged = <T>[];
      var reached = joined;
      var next = page.nextCursor;
      final walk = keptIds.isNotEmpty && (background || quiet);
      for (var walked = 0; walk && !reached && next != null && walked < _bridgePages; walked++) {
        final more = await fetch(next);
        final after = more.nextCursor;
        if (more.items.isEmpty || after == next) break;
        for (final item in more.items) {
          final key = id(item);
          if (headIds.contains(key) || keptIds.contains(key)) continue;
          bridged.add(item);
        }
        reached = more.items.any((item) => keptIds.contains(id(item)));
        next = after;
      }
      _seen.clear();
      items.clear();
      _append(page.items);
      if (reached) {
        // The older pages carry on below the fresh one. The cursor is not touched: it points below
        // the last post loaded, and what lies below that has not changed.
        _append(bridged);
        _append(kept);
      } else {
        cursor = page.nextCursor;
        hasMore = page.nextCursor != null && page.items.isNotEmpty;
      }
      _markFresh(before, fresh: headIds);
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

  /// Marks the posts that were not on screen before the refresh so their rows grow in. [fresh] is
  /// what the first page brought; the pages walked to keep the old posts are not news to anyone and
  /// are left out, or the whole stretch between the two ends would animate at once.
  void _markFresh(Set<String> before, {Set<String>? fresh}) {
    _freshTimer?.cancel();
    if (before.isEmpty) {
      this.fresh = const {};
      return;
    }
    final added = <String>{};
    for (final item in items) {
      final key = id(item);
      if (before.contains(key)) continue;
      if (fresh != null && !fresh.contains(key)) continue;
      added.add(key);
    }
    this.fresh = added;
    if (added.isEmpty) return;
    _freshTimer = Timer(const Duration(milliseconds: 1200), () => this.fresh = const {});
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
