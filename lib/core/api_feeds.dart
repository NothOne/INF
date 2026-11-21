part of 'api.dart';

/// Home timelines and the groups they belong to. The lists are m.weibo.cn's; the group names of
/// 全部关注 and 特别关注 come from weibo.com's `feed/allGroups`.
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

  /// The home feed's sources, in the order weibo.com's own home draws them: 最新, 全部关注,
  /// 特别关注, 好友圈, the account's own groups, 悄悄关注, 我赞过的, 我的收藏.
  ///
  /// weibo.com's `feed/allGroups` is where 全部关注 lives with its list id and 特别关注 with its
  /// group id; m.weibo.cn's `api/config/list` knows only the custom groups. So both are asked: the
  /// former for the two system feeds, the latter to fill in what it left out. Either one failing
  /// leaves the other's answer, and the fixed sources below are there in any case.
  Future<List<FeedSource>> feedSources() async {
    ({FeedSource? followingAll, FeedSource? special, List<FeedSource> custom})? groups;
    final (cookie, _) = await WeiboComSession.instance.cookie();
    if (WeiboComSession.hasAuth(cookie)) {
      try {
        groups = parseWeiboComFeedGroups(await _getWeiboCom(
          'feed/allGroups',
          const {'is_new_segment': '1', 'fetch_hot': '1'},
          referer: 'https://weibo.com/',
          whole: true,
        ));
      } catch (_) {
        // A weibo.com identity that is not there is no reason to have no groups at all;
        // `feedGroups` below still has the account's own list.
      }
    }
    var custom = groups?.custom ?? const <FeedSource>[];
    if (custom.isEmpty) custom = await feedGroups();
    return orderedFeedSources(followingAll: groups?.followingAll, special: groups?.special, custom: custom);
  }

  Future<PageResult<Status>> feed(FeedSource source, String uid, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await switch (source.kind) {
      FeedKind.all => _get('feed/friends', query: {'max_id': cursor}),
      FeedKind.followingAll => _getWeiboCom(
          'feed/unreadfriendstimeline',
          {
            'list_id': source.id.isNotEmpty ? source.id : '10001$uid',
            'refresh': cursor == null ? '4' : '2',
            'since_id': '0',
            'max_id': ?cursor,
            'count': '15',
          },
          referer: 'https://weibo.com/',
          whole: true,
        ),
      FeedKind.special => source.id.isEmpty
          ? Future<dynamic>.value(const {'statuses': <Object>[], 'max_id': 0})
          : _getWeiboCom(
              'feed/groupstimeline',
              {
                'list_id': source.id,
                'refresh': cursor == null ? '4' : '2',
                'fast_refresh': '1',
                'max_id': ?cursor,
                'count': '25',
              },
              referer: 'https://weibo.com/mygroups?gid=${source.id}',
              whole: true,
            ),
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

/// The home feed's sources in weibo.com's own order, with each source once.
///
/// 最新, 全部关注, 特别关注 and 好友圈 are the fixed head; the account's own groups follow, then
/// 悄悄关注, 我赞过的 and 我的收藏. A group that turns up twice — `allGroups` and m.weibo.cn's config
/// can both name one — keeps its first place, and a kind without an id falls back to the constant
/// for it, so a picker never shows two rows that select the same feed.
List<FeedSource> orderedFeedSources({
  FeedSource? followingAll,
  FeedSource? special,
  List<FeedSource> custom = const [],
}) {
  final sources = [
    FeedSource.all,
    followingAll ?? FeedSource.followingAll,
    special ?? FeedSource.special,
    FeedSource.circle,
    ...custom,
    FeedSource.private,
    FeedSource.liked,
    FeedSource.favorites,
  ];
  final seen = <String>{};
  return sources.where((source) => seen.add(source.key)).toList();
}
