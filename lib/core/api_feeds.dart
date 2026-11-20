part of 'api.dart';

/// Home timelines and the groups they belong to. All m.weibo.cn.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiFeeds on WeiboApi {

  Future<List<FeedSource>> feedGroups() async {
    final data = await _get('api/config/list');
    return parseFeedGroups(data);
  }

  Future<List<FeedSource>> feedSources() async {
    final groups = await feedGroups();
    return [
      FeedSource.all,
      ...groups,
      FeedSource.circle,
      FeedSource.private,
      FeedSource.liked,
      FeedSource.favorites,
    ];
  }

  Future<PageResult<Status>> feed(FeedSource source, String uid, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await switch (source.kind) {
      FeedKind.all => _get('feed/friends', query: {'max_id': cursor}),
      FeedKind.group => _listFeed('feed/group', cursor, {'gid': source.id}),
      FeedKind.circle => _listFeed('feed/circle', cursor),
      FeedKind.private => _listFeed('feed/private', cursor),
      FeedKind.liked => _cardFeed(likedContainer(uid), page),
      FeedKind.favorites => _cardFeed('230259', page),
      FeedKind.card => _cardFeed(source.id.isEmpty ? '102803' : source.id, page),
    };
    return _feedPage(source, page).accept(data, isFirstPage: cursor == null);
  }

  /// The feed's cache: the first page, and which source it came from — a cached feed is only worth
  /// opening on the list it was last read on.
  CachedPage<Status> _feedPage(FeedSource source, [int page = 1]) => CachedPage<Status>(
        key: 'feed',
        wrap: (data) => {'source': source.key, 'name': source.name, 'data': data},
        unwrap: (stored) => asMap(stored)?['data'],
        parse: (data) => _parseFeed(source.kind, data, page),
      );

  /// The first page of the feed last shown, and the source it came from.
  (FeedSource, PageResult<Status>)? cachedFeed() {
    final cached = asMap(readRawCached('feed'));
    final key = textOf(cached?['source']);
    if (cached == null || key == null) return null;
    final parts = key.split('\u001F');
    final kind = parts.length == 2 ? FeedKind.values.where((k) => k.name == parts[0]).firstOrNull : null;
    if (kind == null) return null;
    final source = FeedSource(kind, textOf(cached['name']) ?? '', parts[1] == kind.name ? '' : parts[1]);
    final page = _feedPage(source).decode(cached);
    return page == null ? null : (source, page);
  }
}
