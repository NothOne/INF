part of 'api.dart';

/// What needs a weibo.com cookie or a visitor identity: the hot boards, the recommendation channels, and the QR login.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiWeiboCom on WeiboApi {

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

  /// A QR code for the m.weibo.cn SSO entry. Confirming it in the Weibo app needs no captcha: the
  /// app is already signed in.
  Future<QrLogin> qrLogin() async {
    final login = parseQrLogin(await _getPublic(
      'https://passport.weibo.com/sso/v2/qrcode/image',
      query: {'entry': 'wapsso', 'size': '180'},
      referer: Session.loginUrl,
      whole: true,
    ));
    if (login == null) throw ApiException('二维码获取失败');
    return login;
  }

  Future<QrLoginStatus> qrLoginStatus(String qrid) async => parseQrLoginStatus(await _getPublic(
        'https://passport.weibo.com/sso/v2/qrcode/check',
        query: {
          'entry': 'wapsso',
          'source': 'wapssowb',
          'url': 'https://m.weibo.cn/',
          'qrid': qrid,
          'rid': 'norid',
          'ver': '20250520',
        },
        referer: Session.loginUrl,
        whole: true,
      ));
}
