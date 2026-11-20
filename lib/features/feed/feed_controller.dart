import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/failure.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/status_store.dart';
import '../../core/prefs.dart';
import '../../core/session.dart';

enum FeedMode { checking, needsLogin, unreachable, timeline }

class FeedController extends ChangeNotifier {
  FeedController() {
    Session.instance.addListener(_sessionChanged);
  }

  PagingController<Status>? pager;
  FeedMode mode = FeedMode.checking;
  FeedSource source = FeedSource.all;
  List<FeedSource>? sources;
  String? unreachable;
  String? message;
  bool _sourcesLoaded = false;
  Future<void>? _sourcesInFlight;
  String? _pagerKey;
  bool _disposed = false;
  bool _started = false;

  bool get sourcesLoaded => _sourcesLoaded;

  void start() {
    if (_started) return;
    _started = true;
    _seedFromCache();
    _load();
  }

  /// At launch the session check, the group list and the first page are three round trips; the
  /// page from last time fills that wait, and the first refresh replaces it in place.
  void _seedFromCache() {
    if (Session.instance.state != SessionState.checking) return;
    final cached = WeiboApi.instance.cachedFeed();
    if (cached == null) return;
    final (cachedSource, page) = cached;
    // 热门 moved to the 推荐 page beside the feed; a feed last left on it starts on 全部关注.
    if (cachedSource.kind == FeedKind.card) return;
    final saved = Prefs.instance.feedSourceKey;
    if (saved == null ? cachedSource.kind != FeedKind.all : cachedSource.key != saved) return;
    source = cachedSource;
    mode = FeedMode.timeline;
    _pagerKey = '${cachedSource.key}|${Session.instance.cacheScope ?? ''}';
    pager = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.feed(cachedSource, Session.instance.uid ?? '', cursor),
      id: (status) => status.id,
      remember: StatusStore.instance.remember,
      keepTailOnRefresh: true,
    )..seed(page);
  }

  bool get _showingCache => pager != null && pager!.items.isNotEmpty;

  void _sessionChanged() {
    if (!_started) return;
    if (Session.instance.state == SessionState.loggedOut) {
      _clearSignedInState();
      mode = FeedMode.needsLogin;
      _notify();
    } else {
      _load();
    }
  }

  void _clearSignedInState() {
    pager?.disposeDeferred();
    pager = null;
    _pagerKey = null;
    sources = null;
    _sourcesLoaded = false;
    source = FeedSource.all;
  }

  Future<void> _load() async {
    if (_disposed) return;
    message = null;
    unreachable = null;
    final state = Session.instance.state;
    switch (state) {
      case SessionState.checking:
        if (!_showingCache) mode = FeedMode.checking;
        _notify();
        return;
      case SessionState.loggedOut:
        _clearSignedInState();
        mode = FeedMode.needsLogin;
        _notify();
        return;
      case SessionState.unreachable:
        unreachable = Session.instance.unreachableMessage;
        if (_showingCache) {
          message = '网络不可用，显示的是上次的内容';
        } else {
          mode = FeedMode.unreachable;
        }
        _notify();
        return;
      case SessionState.loggedIn:
        mode = FeedMode.timeline;
        final uid = Session.instance.uid ?? '';
        await _ensureSources();
        if (!_disposed && Session.instance.state == SessionState.loggedIn) {
          final key = '${source.key}|$uid';
          _installPager(key, (cursor) => WeiboApi.instance.feed(source, uid, cursor));
        }
        _notify();
    }
  }

  Future<void> _ensureSources() {
    if (_sourcesLoaded) return Future.value();
    return _sourcesInFlight ??= _fetchSources().whenComplete(() => _sourcesInFlight = null);
  }

  Future<void> _fetchSources() async {
    try {
      final next = await WeiboApi.instance.feedSources();
      if (_disposed) return;
      sources = next;
      _sourcesLoaded = true;
      final saved = FeedSource.fromKey(Prefs.instance.feedSourceKey, next);
      source = saved ?? FeedSource.all;
    } catch (error) {
      if (_disposed) return;
      sources ??= const [FeedSource.all];
      message = '分组加载失败：${Failure.from(error).message}';
    }
  }

  Future<void> loadSources() async {
    if (_sourcesLoaded) return;
    await _ensureSources();
    _notify();
  }

  void _installPager(
    String key,
    Future<PageResult<Status>> Function(String? cursor) fetch,
  ) {
    if (_pagerKey == key && pager != null) {
      pager!.refresh(background: true);
      return;
    }
    final previous = pager;
    _pagerKey = key;
    final controller = PagingController<Status>(
      fetch: fetch,
      id: (status) => status.id,
      remember: StatusStore.instance.remember,
      keepTailOnRefresh: true,
    );
    pager = controller;
    controller.refresh();
    previous?.disposeDeferred();
  }

  void selectSource(FeedSource next) {
    source = next;
    Prefs.instance.setFeedSourceKey(next.key);
    final uid = Session.instance.uid ?? '';
    _installPager('${next.key}|$uid', (cursor) => WeiboApi.instance.feed(next, uid, cursor));
    _notify();
  }

  Future<void> retrySession() async {
    mode = FeedMode.checking;
    _notify();
    await Session.instance.refresh();
    _load();
  }

  void clearMessage() => message = null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    Session.instance.removeListener(_sessionChanged);
    pager?.dispose();
    super.dispose();
  }
}