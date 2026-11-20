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
    this.remember,
  });

  final Future<PageResult<T>> Function(String? cursor) fetch;
  final String Function(T item) id;
  final int pageSize;

  /// Called for every item that arrives, including the ones a cache seeded the list with.
  ///
  /// This is the ingestion point for posts: [Entities] needs to see each answer once, and a list is
  /// where answers land. Filing from a widget's `build` instead would re-file whatever copy that
  /// row happens to hold — including an older one — and putting an old count back over a fresher
  /// one is exactly the drift this is meant to stop.
  final void Function(T item)? remember;

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
  bool _refreshing = false;
  int _generation = 0;
  bool _disposed = false;
  bool _background = false;

  /// A failed append is not retried by scrolling. [onScroll] is called on every frame of a fling,
  /// so a list left at the bottom kept sending the same request — and Weibo answers that with
  /// 「操作频繁」 rather than a page. Only [retryMore], which the footer's button calls, tries again.
  bool _moreBlocked = false;

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
    final foreground = !background && !quiet;
    if (_refreshing) {
      // A user-pulled refresh preempts an in-flight background refresh (such as startup bridging);
      // otherwise a duplicate or lower-priority refresh steps aside without faking success.
      if (!foreground || !_background) return false;
    } else if (_inFlight) {
      // A user-pulled refresh preempts an in-flight loadMore; a background refresh leaves it alone.
      if (!foreground) return false;
      loadingMore = false;
    }
    final gen = ++_generation;
    _inFlight = true;
    _refreshing = true;
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
      if (_disposed || gen != _generation) return false;
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
        final PageResult<T> more;
        try {
          more = await fetch(next);
        } catch (_) {
          // Keep the fresh first page even if bridging an older gap fails.
          break;
        }
        if (_disposed || gen != _generation) return false;
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
      // A later page that failed before is not reported again once the list has been reloaded: its
      // footer said 「加载失败」 over content that has since been replaced.
      moreError = null;
      stale = false;
      _moreBlocked = false;
      refreshedAt = DateTime.now();
      return true;
    } catch (e) {
      if (_disposed || gen != _generation) return false;
      if (items.isEmpty) {
        error = e;
        hasMore = false;
      } else if (!background) {
        error = e;
      }
      return false;
    } finally {
      if (gen == _generation) {
        loading = false;
        _inFlight = false;
        _refreshing = false;
        _background = false;
        _notify();
      }
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
    if (_inFlight || loading || loadingMore || !hasMore || _moreBlocked) return;
    final gen = _generation;
    _inFlight = true;
    loadingMore = true;
    moreError = null;
    _notify();
    try {
      final page = await fetch(cursor);
      if (_disposed || gen != _generation) return;
      _append(page.items);
      final previous = cursor;
      cursor = page.nextCursor;
      if (page.items.isEmpty || page.nextCursor == null || page.nextCursor == previous) {
        hasMore = false;
      }
    } catch (e) {
      if (_disposed || gen != _generation) return;
      moreError = e;
      _moreBlocked = true;
    } finally {
      if (gen == _generation) {
        loadingMore = false;
        _inFlight = false;
        _notify();
      }
    }
  }

  /// Tries the failed page again; the footer's 「加载失败，点此重试」 calls this rather than
  /// [loadMore], so a scroll can never be the thing that retries.
  Future<void> retryMore() {
    _moreBlocked = false;
    return loadMore();
  }

  void _append(List<T> incoming) {
    for (final item in incoming) {
      remember?.call(item);
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

  /// Disposes after the current frame finishes so widgets listening to this controller can detach
  /// during their rebuild instead of calling [removeListener] on a disposed [ChangeNotifier].
  void disposeDeferred() {
    if (_disposed) return;
    if (!hasListeners) {
      dispose();
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) dispose();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _freshTimer?.cancel();
    super.dispose();
  }
}
