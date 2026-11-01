import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'emoji.dart';
import 'models.dart';
import 'page_cache.dart';
import 'parse.dart';
import 'session.dart';

class LoginRequiredException implements Exception {
  final String? loginUrl;
  LoginRequiredException([this.loginUrl]);
  @override
  String toString() => '需要登录微博';
}

class ApiException implements Exception {
  final String message;
  final int? code;
  ApiException(this.message, {this.code});
  @override
  String toString() => message;
}

/// Calls the JSON endpoints used by m.weibo.cn, with the same paths, parameters and headers the
/// Compose app verified on-device. Only the HTTP engine changed (OkHttp -> Dio).
class WeiboApi {
  WeiboApi._(this.session)
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://m.weibo.cn',
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 20),
          sendTimeout: const Duration(seconds: 30),
          responseType: ResponseType.plain,
          validateStatus: (_) => true,
        )) {
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final headers = options.headers;
        headers['User-Agent'] = session.userAgent;
        headers['Accept'] = 'application/json, text/plain, */*';
        headers['X-Requested-With'] = 'XMLHttpRequest';
        headers['MWeibo-Pwa'] = '1';
        headers.putIfAbsent('Referer', () => '${_web}/');
        if (session.cookieHeader.isNotEmpty && options.uri.host == 'm.weibo.cn') {
          headers['Cookie'] = session.cookieHeader;
        }
        if (options.method != 'GET' && session.xsrf != null) {
          headers.putIfAbsent('X-XSRF-TOKEN', () => session.xsrf!);
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        final setCookies = response.headers.map['set-cookie'];
        if (setCookies != null && response.requestOptions.uri.host == 'm.weibo.cn') {
          session.absorbSetCookies(setCookies);
        }
        handler.next(response);
      },
    ));
  }

  static final WeiboApi instance = WeiboApi._(Session.instance);
  static const _web = 'https://m.weibo.cn';

  final Session session;
  final Dio _dio;

  Future<WeiboConfig> config() async {
    final data = await _get('api/config');
    final json = asMap(data);
    final config = WeiboConfig(
      login: json?['login'] == true,
      uid: idOf(json?['uid']),
      st: textOf(json?['st']),
    );
    if (config.st != null) session.st = config.st;
    return config;
  }

  // ---- feeds --------------------------------------------------------------------------------

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
    if (cursor == null) {
      PageCache.instance.write(session.uid, 'feed', {'source': source.key, 'name': source.name, 'data': data});
    }
    return _parseFeed(source.kind, data, page);
  }

  /// The first page of the feed last shown, and the source it came from.
  (FeedSource, PageResult<Status>)? cachedFeed() {
    final cached = asMap(PageCache.instance.read(session.cacheScope, 'feed'));
    final key = textOf(cached?['source']);
    if (cached == null || key == null) return null;
    final parts = key.split('\u001F');
    final kind = parts.length == 2 ? FeedKind.values.where((k) => k.name == parts[0]).firstOrNull : null;
    if (kind == null) return null;
    final source = FeedSource(kind, textOf(cached['name']) ?? '', parts[1] == kind.name ? '' : parts[1]);
    try {
      final page = _parseFeed(kind, cached['data'], 1);
      return page.items.isEmpty ? null : (source, page);
    } catch (_) {
      return null;
    }
  }

  PageResult<Status> _parseFeed(FeedKind kind, dynamic data, int page) => switch (kind) {
        FeedKind.all || FeedKind.group || FeedKind.circle || FeedKind.private => parseFriendsFeed(data),
        _ => parseContainerStatuses(data, page),
      };

  Future<dynamic> _listFeed(String path, String? cursor, [Map<String, dynamic>? params]) =>
      _get(path, query: {...?params, 'max_id': cursor}, emptyIsOk: true);

  Future<dynamic> _cardFeed(String containerId, int page) => _get(
        'api/container/getIndex',
        query: {
          'containerid': containerId,
          if (page > 1) 'page': page.toString(),
        },
        emptyIsOk: true,
      );

  // ---- statuses -----------------------------------------------------------------------------

  Future<Status?> status(String id) async {
    final data = await _get('statuses/show', query: {'id': id});
    return toStatus(data);
  }

  Future<({String text, Map<String, WeiboLink> links})?> longText(String id) async {
    final data = await _get('statuses/extend', query: {'id': id});
    final raw = textOf(asMap(data)?['longTextContent']);
    if (raw == null) return null;
    final rich = weiboHtmlToRichText(raw);
    final text = rich.text.trim();
    return text.isEmpty ? null : (text: text, links: rich.links);
  }

  Future<PageResult<Status>> userTimeline(String uid, String? cursor) async {
    final data = await _get(
      'api/container/getIndex',
      query: {
        'type': 'uid',
        'value': uid,
        'containerid': '107603$uid',
        'since_id': cursor,
      },
    );
    return parseUserTimeline(data);
  }

  Future<UserProfile?> userProfile(String uid) async {
    final data = await _get('api/container/getIndex', query: {'type': 'uid', 'value': uid});
    final profile = parseUserProfile(data);
    if (profile != null && uid == session.uid) {
      PageCache.instance.write(uid, 'profile', {'userInfo': asMap(data)?['userInfo']});
    }
    return profile;
  }

  UserProfile? cachedSelfProfile() {
    try {
      return parseUserProfile(PageCache.instance.read(session.cacheScope, 'profile'));
    } catch (_) {
      return null;
    }
  }

  Future<User?> user(String uid) async => (await userProfile(uid))?.user;

  /// weibo.com's board carries rank, badge, category and time on the list; m.weibo.cn's only the
  /// words, so it is the fallback.
  Future<List<HotSearch>> hotSearch() async {
    try {
      final band = parseHotBand(await _getPublic('https://weibo.com/ajax/statuses/hot_band'));
      if (band.isNotEmpty) return band;
    } catch (_) {}
    final data = await _get(
      'api/container/getIndex',
      query: {'containerid': '106003type=25&t=3&disable_hot=1&filter_type=realtimehot'},
    );
    return parseHotSearch(data);
  }

  /// One of weibo.com's boards. Those behind the visitor wall get a visitor cookie; a stale one is
  /// replaced once.
  Future<List<HotSearch>> hotBoard(HotBoard board) async {
    if (board == HotBoard.realtime) return hotSearch();
    final url = 'https://weibo.com/ajax/statuses/${board.path}';
    return _asVisitor(
      (cookie) async => parseHotBand(await _getPublic(url, cookie: cookie), board: board),
      accept: (band) => band.isNotEmpty,
    );
  }

  /// weibo.com's 推荐 channels. They are the same for every visitor, so no account is needed.
  Future<List<RecommendChannel>> recommendChannels() => _asVisitor(
        (cookie) async => parseRecommendChannels(await _getPublic(
          'https://weibo.com/ajax/feed/allGroups',
          query: {'is_new_segment': '1', 'fetch_hot': '1'},
          cookie: cookie,
          whole: true,
        )),
        accept: (channels) => channels.isNotEmpty,
      );

  /// One channel's posts; 热门 signed in is m.weibo.cn's, tuned to the account. weibo.com draws a fresh batch on every call and its `max_id` stays 1,
  /// so the cursor is only a page count; the pager drops the repeats.
  Future<PageResult<Status>> recommendFeed(RecommendChannel channel, String? cursor) async {
    if (channel.personal && session.uid != null) {
      final page = int.tryParse(cursor ?? '') ?? 1;
      return _parseFeed(FeedKind.card, await _cardFeed(channel.containerId, page), page);
    }
    final page = int.tryParse(cursor ?? '') ?? 0;
    final items = await _asVisitor(
      (cookie) async => parseHotTimeline(await _getPublic(
        'https://weibo.com/ajax/feed/hottimeline',
        query: {
          'since_id': '0',
          'refresh': page == 0 ? '1' : '0',
          'group_id': channel.gid,
          'containerid': channel.containerId,
          'extparam': 'discover|new_feed',
          'max_id': '$page',
          'count': '10',
        },
        referer: 'https://weibo.com/hot/weibo/${channel.gid}',
        cookie: cookie,
        whole: true,
      )),
      accept: (items) => items.isNotEmpty,
    );
    return PageResult(items, items.isEmpty || page >= 30 ? null : '${page + 1}');
  }

  /// A weibo.com request behind the visitor wall; a refused or [accept]-failing answer gets one
  /// more try with a new visitor cookie.
  Future<T> _asVisitor<T>(Future<T> Function(String cookie) request, {bool Function(T result)? accept}) async {
    for (var attempt = 0;; attempt++) {
      try {
        final result = await request(await _visitorCookie());
        if (attempt > 0 || (accept?.call(result) ?? true)) return result;
      } catch (_) {
        if (attempt > 0) rethrow;
      }
      _visitor = null;
    }
  }

  Future<String>? _visitor;

  Future<String> _visitorCookie() => _visitor ??= _newVisitor()..catchError((_) {
        _visitor = null;
        return '';
      });

  /// passport.weibo.com hands any client an anonymous SUB/SUBP pair, wrapped in a JSONP callback.
  Future<String> _newVisitor() async {
    final response = await _dio.post<String>(
      'https://passport.weibo.com/visitor/genvisitor2',
      data: {'cb': 'visitor_gray_callback', 'tid': '', 'from': 'weibo'},
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.plain,
        headers: {'Referer': 'https://passport.weibo.com/visitor/visitor'},
      ),
    );
    final body = response.data ?? '';
    final start = body.indexOf('(');
    final end = body.lastIndexOf(')');
    if (start < 0 || end <= start) throw ApiException('游客身份获取失败');
    final data = asMap(asMap(jsonDecode(body.substring(start + 1, end)))?['data']);
    final sub = textOf(data?['sub']);
    if (sub == null || sub.isEmpty) throw ApiException('游客身份获取失败');
    return 'SUB=$sub; SUBP=${textOf(data?['subp']) ?? ''}';
  }

  Future<SearchSuggestions> searchSuggestions(String query) async {
    final data = await _getPublic('https://weibo.com/ajax/side/search', query: {'q': query});
    return parseSearchSuggestions(data);
  }

  Future<PageResult<Status>> searchStatuses(String query, String? cursor) =>
      _containerStatuses('100103type=1&q=$query', cursor);

  Future<PageResult<Status>> topicStatuses(String name, String? keyword, String? cursor) =>
      _containerStatuses(topicQuery(name, keyword), cursor);

  /// The card m.s.weibo.com keeps for a hashtag: counts, host, boards, contributors, media.
  Future<TopicInfo?> topicDetail(String topic) async =>
      parseTopicDetail(await _getPublic('https://m.s.weibo.com/ajax_topic/detail', query: {'q': topic}, referer: _vtopic(topic)));

  Future<List<TopicTrendPoint>> topicTrend(String topic) async => parseTopicTrend(await _getPublic(
        'https://m.s.weibo.com/ajax_topic/trend',
        query: {'q': topic, 'time': '24h', 'type': 'read'},
        referer: _vtopic(topic),
      ));

  /// m.s.weibo.com only answers its own topic page.
  String _vtopic(String topic) => 'https://m.s.weibo.com/vtopic/detail_new?q=${Uri.encodeQueryComponent(topic)}';

  /// One page of a topic or hot-search page, and on the first page whatever its head says about
  /// it. [query] is sent as is: `#话题#` for a hashtag, the bare words otherwise.
  Future<(PageResult<Status>, TopicInfo?)> hotTopicPage(String query, HotTopicTab tab, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _get(
      'api/container/getIndex',
      query: {
        'containerid': '100103type=${tab.type}&q=$query',
        'page_type': 'searchall',
        if (page > 1) 'page': page.toString(),
      },
      emptyIsOk: true,
    );
    return (parseContainerStatuses(data, page), page == 1 ? parseTopicInfo(data) : null);
  }

  Future<PageResult<Status>> _containerStatuses(String containerId, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _get(
      'api/container/getIndex',
      query: {
        'containerid': containerId,
        'page_type': 'searchall',
        if (page > 1) 'page': page.toString(),
      },
    );
    return parseContainerStatuses(data, page);
  }

  // ---- notifications and messages -----------------------------------------------------------

  Future<UnreadCounts> unread() async {
    final data = await _get('api/remind/unread', query: {
      't': DateTime.now().millisecondsSinceEpoch.toString(),
    });
    return parseUnread(data);
  }

  Future<PageResult<NotificationItem>> notifications(NotificationKind kind, String? cursor) async {
    final path = switch (kind) {
      NotificationKind.mentionInStatus => 'message/mentionsAt',
      NotificationKind.mentionInComment => 'message/mentionsCmt',
      NotificationKind.comment => 'message/cmt',
      NotificationKind.like => 'message/attitude',
    };
    return _numberedPage(cursor, (page) async {
      final data = await _get(path, query: {'page': page}, emptyIsOk: true);
      if (page == '1') PageCache.instance.write(session.uid, 'notify-${kind.name}', data);
      return parseNotifications(data, kind);
    });
  }

  PageResult<NotificationItem>? cachedNotifications(NotificationKind kind) =>
      _cachedNumbered(PageCache.instance.read(session.cacheScope, 'notify-${kind.name}'),
          (data) => parseNotifications(data, kind));

  Future<PageResult<Conversation>> conversations(bool strangers, String? cursor) async {
    final path = strangers ? 'message/notelist' : 'message/msglist';
    return _numberedPage(cursor, (page) async {
      final data = await _get(path, query: {'page': page}, emptyIsOk: true);
      if (page == '1') PageCache.instance.write(session.uid, 'conversations-$strangers', data);
      return parseConversations(data);
    });
  }

  PageResult<Conversation>? cachedConversations(bool strangers) =>
      _cachedNumbered(PageCache.instance.read(session.cacheScope, 'conversations-$strangers'), parseConversations);

  PageResult<T>? _cachedNumbered<T>(dynamic data, List<T> Function(dynamic data) parse) {
    if (data == null) return null;
    try {
      final items = parse(data);
      return items.isEmpty ? null : PageResult(items, '2');
    } catch (_) {
      return null;
    }
  }

  Future<PageResult<DirectMessage>> chat(String uid, String? cursor) async {
    final data = await _get('api/chat/list', query: {
      'uid': uid,
      'count': '20',
      'unfollowing': '0',
      'max_id': cursor,
    });
    final parsed = parseChat(data);
    final messages = parsed.$1;
    return PageResult(messages, messages.length > 1 ? messages.last.id : null);
  }

  Future<PageResult<DirectMessage>> groupChat(String gid, String? cursor) async {
    final data = await _get('api/groupchat/list', query: {
      'gid': gid,
      'count': '20',
      'max_mid': cursor,
    });
    final messages = parseGroupChat(data);
    return PageResult(messages, messages.length > 1 ? messages.last.id : null);
  }

  Future<void> sendMessage(String uid, String content) async {
    await _post('api/chat/send', {
      'uid': uid,
      'content': content,
    }, referer: '${_web}/message/chat?uid=$uid');
  }

  Future<void> sendGroupMessage(String gid, String content) async {
    await _post('api/groupchat/send', {
      'gid': gid,
      'content': content,
    }, referer: '${_web}/message/chat?gid=$gid');
  }

  Future<String> uploadChatImage(File file, ChatTarget target) async {
    final data = await _postMultipart(
      'api/chat/upload',
      fields: {
        if (target.isGroup) 'tochatid': target.id else 'tuid': target.id,
      },
      fileField: 'file',
      file: file,
      referer: '${_web}/message/chat?${target.isGroup ? 'gid' : 'uid'}=${target.id}',
    );
    final fids = textOf(asMap(data)?['fids']);
    if (fids == null || fids.isEmpty) throw ApiException('图片上传失败');
    return fids;
  }

  Future<void> sendChatImage(ChatTarget target, String fids) async {
    final path = target.isGroup ? 'api/groupchat/send' : 'api/chat/send';
    final key = target.isGroup ? 'gid' : 'uid';
    await _post(path, {
      key: target.id,
      'media_type': '1',
      'fids': fids,
    }, referer: '${_web}/message/chat?${key}=${target.id}');
  }

  /// The path really is "quite" (a typo in Weibo's own API); do not correct it.
  Future<void> leaveGroup(String gid) async {
    await _post('api/groupchat/quite', {'gid': gid},
        referer: '${_web}/message/chat?gid=$gid');
  }

  // ---- relationships and people -------------------------------------------------------------

  Future<void> setFollowing(String uid, bool follow) async {
    final path = follow ? 'api/friendships/create' : 'api/friendships/destory';
    await _post(path, {'uid': uid}, referer: '${_web}/u/$uid');
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

  Future<PageResult<Status>> reposts(String statusId, String? cursor) {
    return _numberedPage(cursor, (page) async {
      final data = await _get(
        'api/statuses/repostTimeline',
        query: {'id': statusId, 'page': page},
        emptyIsOk: true,
        referer: '$_web/detail/$statusId',
      );
      return parseReposts(data);
    });
  }

  Future<PageResult<Comment>> comments(String statusId, String? cursor) async {
    final parts = cursor?.split(':');
    final maxId = (parts != null && parts.length == 2) ? parts[0] : null;
    final maxIdType = (parts != null && parts.length == 2) ? parts[1] : '0';
    final data = await _get(
      'comments/hotflow',
      query: {
        'id': statusId,
        'mid': statusId,
        'max_id': maxId,
        'max_id_type': maxIdType,
      },
      emptyIsOk: true,
    );
    return parseCommentPage(asMap(data), statusId);
  }

  Future<PageResult<Comment>> replies(String statusId, String commentId, String? cursor) async =>
      (await replyThread(statusId, commentId, cursor)).$1;

  /// A page of replies, and the comment they answer.
  Future<(PageResult<Comment>, Comment?)> replyThread(String statusId, String commentId, String? cursor) async {
    final parts = cursor?.split(':');
    final maxId = (parts != null && parts.length == 2) ? parts[0] : '0';
    final maxIdType = (parts != null && parts.length == 2) ? parts[1] : '0';
    final root = await _get(
      'comments/hotFlowChild',
      returnRoot: true,
      query: {
        'cid': commentId,
        'max_id': maxId,
        'max_id_type': maxIdType,
      },
      emptyIsOk: true,
    );
    final map = asMap(root);
    return (parseCommentPage(map, statusId), parseRootComment(map, statusId));
  }

  // ---- writes -------------------------------------------------------------------------------

  Future<void> setLiked(String statusId, bool liked) async {
    final path = liked ? 'api/attitudes/create' : 'api/attitudes/destroy';
    await _post(path, {
      'id': statusId,
      'attitude': 'heart',
    }, referer: '${_web}/detail/$statusId');
  }

  /// m.weibo.cn's own menu posts these; the path names are its own.
  Future<void> setFavorited(String statusId, bool favorited) async {
    final path = favorited ? 'api/statuses/createfav' : 'api/statuses/destroyfav';
    await _post(path, {'id': statusId}, referer: '$_web/detail/$statusId');
  }

  Future<String> uploadImage(File file) async {
    final st = await _token(refresh: true);
    final response = await _dio.post(
      'api/statuses/uploadPic',
      data: FormData.fromMap({
        'type': 'json',
        'st': st,
        'pic': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split(Platform.pathSeparator).last,
          contentType: DioMediaType.parse(_imageType(file.path)),
        ),
      }),
      options: Options(headers: {
        'X-XSRF-TOKEN': st,
        'Origin': _web,
        'Referer': '${_web}/compose/',
      }),
    );
    final root = _decodeEnvelope(response, false, returnRoot: true);
    final direct = textOf(asMap(root)?['pic_id']);
    if (direct != null && direct.isNotEmpty) return direct;
    final nested = textOf(asMap(asMap(root)?['data'])?['pic_id']);
    if (nested != null && nested.isNotEmpty) return nested;
    throw ApiException('图片上传失败');
  }

  Future<void> postStatus(String content, List<String> picIds) async {
    await _post('api/statuses/update', {
      'content': content,
      if (picIds.isNotEmpty) 'picId': picIds.join(','),
    }, referer: '${_web}/compose/');
  }

  Future<void> repost(String statusId, String content, bool alsoComment) async {
    await _post('api/statuses/repost', {
      'id': statusId,
      'mid': statusId,
      'content': content,
      if (alsoComment) 'dualPost': '1',
    }, referer: '${_web}/compose/');
  }

  Future<void> comment(String statusId, String content) async {
    await _post('api/comments/create', {
      'content': content,
      'mid': statusId,
    }, referer: '${_web}/detail/$statusId');
  }

  Future<void> reply(String statusId, String commentId, String content) async {
    await _post('api/comments/reply', {
      'id': statusId,
      'mid': statusId,
      'cid': commentId,
      'reply': commentId,
      'content': content,
    }, referer: '${_web}/detail/$statusId');
  }

  // ---- plumbing -----------------------------------------------------------------------------

  Future<dynamic> _get(
    String path, {
    Map<String, dynamic>? query,
    bool emptyIsOk = false,
    String? referer,
    bool returnRoot = false,
  }) async {
    try {
      final params = <String, String>{};
      query?.forEach((key, value) {
        if (value != null) params[key] = value.toString();
      });
      final response = await _dio.get(
        '/$path',
        queryParameters: params.isEmpty ? null : params,
        options: Options(headers: referer == null ? null : {'Referer': referer}),
      );
      return _decodeEnvelope(response, emptyIsOk, returnRoot: returnRoot);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  /// An anonymous weibo.com endpoint: no m.weibo.cn cookie, and a refusal is just an error, never
  /// a sign the session ended.
  /// [whole] is for the endpoints that answer without a `data` wrapper.
  Future<dynamic> _getPublic(
    String url, {
    Map<String, String>? query,
    String? referer,
    String? cookie,
    bool whole = false,
  }) async {
    try {
      final response = await _dio.get(
        url,
        queryParameters: query,
        options: Options(headers: {'Referer': referer ?? 'https://weibo.com/', 'Cookie': ?cookie}),
      );
      final status = response.statusCode ?? 0;
      if (status >= 400) throw ApiException('HTTP $status');
      final body = response.data;
      final map = asMap(body is String ? jsonDecode(body) : body);
      // weibo.com answers {ok: 1}, m.s.weibo.com {code: "100000"}.
      if (map == null || (intOf(map['ok']) != 1 && textOf(map['code']) != '100000')) {
        throw ApiException(textOf(map?['msg']) ?? '接口返回格式错误');
      }
      return whole ? map : map['data'];
    } on DioException catch (error) {
      throw _dioError(error);
    } on FormatException {
      throw ApiException('接口返回格式错误');
    }
  }

  Future<dynamic> _post(
    String path,
    Map<String, String?> fields, {
    String? referer,
  }) async {
    try {
      final st = await _token(refresh: true);
      final response = await _dio.post(
        '/$path',
        data: <String, String>{
          for (final entry in fields.entries)
            if (entry.value != null) entry.key: entry.value!,
          'st': st,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {
            'X-XSRF-TOKEN': st,
            'Origin': _web,
            if (referer != null) 'Referer': referer,
          },
        ),
      );
      return _decodeEnvelope(response, false);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  Future<dynamic> _postMultipart(
    String path, {
    required Map<String, String> fields,
    required String fileField,
    required File file,
    String? referer,
  }) async {
    try {
      final st = await _token(refresh: true);
      final response = await _dio.post(
        '/$path',
        data: FormData.fromMap({
          'st': st,
          ...fields,
          fileField: await MultipartFile.fromFile(
            file.path,
            filename: file.path.split(Platform.pathSeparator).last,
            contentType: DioMediaType.parse(_imageType(file.path)),
          ),
        }),
        options: Options(headers: {
          'X-XSRF-TOKEN': st,
          'Origin': _web,
          if (referer != null) 'Referer': referer,
        }),
      );
      return _decodeEnvelope(response, false);
    } on DioException catch (error) {
      throw _dioError(error);
    }
  }

  dynamic _decodeEnvelope(Response response, bool emptyIsOk, {bool returnRoot = false}) {
    final status = response.statusCode ?? 0;
    if (status >= 400) {
      throw ApiException('HTTP $status');
    }
    final body = response.data;
    dynamic root;
    if (body is String) {
      try {
        root = jsonDecode(body);
      } catch (_) {
        throw LoginRequiredException(null);
      }
    } else {
      root = body;
    }
    final map = asMap(root);
    if (map == null) throw ApiException('接口返回格式错误');
    EmojiStore.instance.learn(collectEmoji(map));
    final envelope = parseWeiboResult(map);
    if (envelope.isOk) return returnRoot ? map : envelope.data;
    if (envelope.needsLogin) {
      session.onLoginRequired();
      throw LoginRequiredException(envelope.loginUrl);
    }
    final code = envelope.errno ?? envelope.ok;
    if (emptyIsOk && (code == 0 || code == 100011)) return null;
    throw ApiException(envelope.message ?? '微博接口错误（$code）', code: code);
  }

  Future<String> _token({bool refresh = false}) async {
    if (!refresh && session.st != null && session.st!.isNotEmpty) return session.st!;
    final config = await this.config();
    final token = config.st;
    if (token == null || token.isEmpty) throw LoginRequiredException(null);
    session.st = token;
    return token;
  }

  Exception _dioError(DioException error) {
    final type = error.type;
    if (type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.sendTimeout ||
        type == DioExceptionType.receiveTimeout) {
      return ApiException('网络连接超时');
    }
    if (type == DioExceptionType.connectionError || type == DioExceptionType.badCertificate) {
      return ApiException('网络连接失败');
    }
    return ApiException(error.message ?? '网络请求失败');
  }

  String _imageType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<PageResult<T>> _numberedPage<T>(
    String? cursor,
    Future<List<T>> Function(String page) fetch,
  ) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final items = await fetch(page.toString());
    return PageResult(items, items.isEmpty ? null : (page + 1).toString());
  }
}

/// The containerid for a topic search. A blank keyword asks for the hashtag stream; a keyword
/// switches to the space-separated AND search, the only way m.weibo.cn narrows a topic.
String topicQuery(String name, String? keyword) {
  final topic = name.trim().replaceAll('#', '');
  final needle = (keyword ?? '').trim().replaceAll('#', '');
  if (needle.isEmpty) return '231522type=1&t=10&q=#$topic#';
  return '231522type=1&t=10&q=$topic $needle';
}
