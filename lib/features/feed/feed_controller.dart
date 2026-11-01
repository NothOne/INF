import 'package:flutter/foundation.dart';

import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
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
  bool _loadingSources = false;
  String? _pagerKey;
  bool _disposed = false;
  bool _started = false;

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
      keepTailOnRefresh: true,
    )..seed(page);
  }

  bool get _showingCache => pager != null && pager!.items.isNotEmpty;

  void _sessionChanged() {
    if (!_started) return;
    if (Session.instance.state == SessionState.loggedOut) {
      pager?.dispose();
      pager = null;
      _pagerKey = null;
      mode = FeedMode.needsLogin;
      _notify();
    } else if (Session.instance.state == SessionState.loggedIn) {
      _load();
    } else {
      _load();
    }
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
        pager?.dispose();
        pager = null;
        _pagerKey = null;
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

  Future<void> _ensureSources() async {
    if (sources != null) return;
    if (_loadingSources) return;
    _loadingSources = true;
    try {
      final next = await WeiboApi.instance.feedSources();
      sources = next;
      final saved = FeedSource.fromKey(Prefs.instance.feedSourceKey, next);
      source = saved ?? FeedSource.all;
    } catch (error) {
      sources = const [FeedSource.all];
      source = FeedSource.all;
      message = '分组加载失败：${error is ApiException ? error.message : '未知错误'}';
    } finally {
      _loadingSources = false;
    }
  }

  Future<void> loadSources() async {
    if (sources != null) return;
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
    pager?.dispose();
    _pagerKey = key;
    final controller = PagingController<Status>(fetch: fetch, id: (status) => status.id, keepTailOnRefresh: true);
    pager = controller;
    controller.refresh();
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