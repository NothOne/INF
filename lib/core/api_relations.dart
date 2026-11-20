part of 'api.dart';

/// Following, blocking, and the people lists a profile shows.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiRelations on WeiboApi {

  Future<void> setFollowing(String uid, bool follow) async {
    final path = follow ? 'api/friendships/create' : 'api/friendships/destory';
    await _post(path, {'uid': uid}, referer: '${WeiboApi._web}/u/$uid');
  }

  /// weibo.com's 加入黑名单, its 屏蔽 dialog with every box ticked: no posts from them, no
  /// interaction, no following. m.weibo.cn has no blacklist of its own.
  Future<void> blacklist(String uid) async {
    await _postWeiboCom(
      'statuses/filterUser',
      {'uid': uid, 'status': 1, 'interact': 1, 'follow': 1},
      referer: 'https://weibo.com/u/$uid',
    );
  }

  Future<String?> resolveUid(String screenName) async {
    final users = await searchUsers(screenName);
    return users.where((user) => user.screenName == screenName).firstOrNull?.id;
  }

  Future<List<User>> searchUsers(String query) async {
    final containerId = query.trim().isEmpty ? '231093_-_selffollowed' : '100103type=3&q=$query';
    final data = await _get('api/container/getIndex', query: {
      'containerid': containerId,
      'page_type': 'searchall',
    });
    final users = <User>[];
    void visit(dynamic element) {
      final map = asMap(element);
      if (map != null) {
        final own = toUser(map['user']);
        if (own != null && own.screenName.isNotEmpty) users.add(own);
        for (final entry in map.entries) {
          if (entry.key != 'user') visit(entry.value);
        }
      } else if (element is List) {
        for (final value in element) {
          visit(value);
        }
      }
    }

    visit(data);
    final seen = <String>{};
    return users.where((user) => seen.add(user.id)).toList();
  }

  Future<PageResult<User>> relationUsers(String containerId, int page) async {
    final data = await _get(
      'api/container/getIndex',
      query: {
        'containerid': containerId,
        if (page > 1) 'page': page.toString(),
      },
      emptyIsOk: true,
    );
    return parseRelations(data, page);
  }

  Future<PageResult<SuperTopic>> superTopics(String? sinceId) async {
    final data = await _get('api/container/getIndex', query: {
      'containerid': '231093_-_chaohua',
      'since_id': sinceId,
    });
    return parseSuperTopics(data);
  }

  // ---- comments -----------------------------------------------------------------------------
}
