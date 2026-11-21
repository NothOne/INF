part of 'api.dart';

/// What needs a weibo.com cookie or a visitor identity: the hot boards, the recommendation channels, and the QR login.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiWeiboCom on WeiboApi {
  /// The city 同城微博 and 同城热搜 are drawn for, from the device's own fix: weibo.com names the
  /// city the coordinates fall in and its `city_code`, which the boards are asked for afterwards.
  ///
  /// Null when there is no fix (permission refused, location off, no answer in time) and when the
  /// answer names no city — the picker then keeps its manual list, and the boards show the prompt
  /// to set a city instead of an error, since none of this is the reader's fault.
  Future<CityChoice?> locateCity() async {
    final coords = await Native.currentLocation();
    if (coords == null) return null;
    final CityChoice? city;
    try {
      final data = await _getWeiboComOrVisitor(
        (cookie, xsrf) async => await _getPublic(
          'https://weibo.com/ajax/statuses/city',
          query: {'lon': coords.lon.toStringAsFixed(6), 'lat': coords.lat.toStringAsFixed(6)},
          referer: 'https://weibo.com/hot/weibo/1028032222',
          cookie: cookie,
          xsrf: xsrf,
        ),
        accept: (data) => parseHotCityMeta(data) != null,
      );
      final meta = parseHotCityMeta(data);
      city = meta == null ? null : CityChoice(code: meta.code, name: meta.name, lon: coords.lon, lat: coords.lat);
    } catch (_) {
      return null;
    }
    if (city == null) return null;
    // A city the reader picked stays theirs: locating again must not silently move them to
    // wherever the phone is at the moment.
    final saved = Prefs.instance.cityChoice;
    if (saved == null || !saved.manual) await Prefs.instance.setCityChoice(city);
    return city;
  }

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

  /// One of weibo.com's boards. [HotBoard.mine] uses the signed-in weibo.com cookie; [HotBoard.city]
  /// asks for the selected city, or the one the device is in; all others fall back to a visitor
  /// cookie.
  Future<List<HotSearch>> hotBoard(HotBoard board, {CityChoice? city}) async {
    if (board == HotBoard.realtime) return hotSearch();
    if (board == HotBoard.mine) {
      final data = await _getWeiboCom('statuses/mineBand', const {}, referer: 'https://weibo.com/hot/mine');
      return parseHotBand(data, board: board);
    }
    final query = <String, String>{};
    if (board == HotBoard.city) {
      final chosen = city ?? Prefs.instance.cityChoice ?? await locateCity();
      // No fix and no saved city: an empty board draws the prompt to set one, which is more use
      // than an error about a request that had nothing to ask for.
      if (chosen == null) return const [];
      if (!chosen.manual && chosen.hasCoordinates) {
        // A located city is asked for by its fix, so the answer can name a different one when the
        // phone has moved; a picked city is asked for by its code and stays picked.
        query['lon'] = chosen.lon!.toStringAsFixed(6);
        query['lat'] = chosen.lat!.toStringAsFixed(6);
      } else if (chosen.code.isNotEmpty) {
        query['citycode'] = chosen.code;
      }
    }
    final url = 'https://weibo.com/ajax/statuses/${board.path}';
    final data = await _getWeiboComOrVisitor(
      (cookie, xsrf) async => await _getPublic(url, query: query.isEmpty ? null : query, cookie: cookie, xsrf: xsrf),
      accept: (data) => parseHotBand(data, board: board).isNotEmpty,
    );
    if (board == HotBoard.city) {
      // The answer names the city it drew. Keeping that name means 同城 shows 北京 rather than
      // nothing until the next manual pick, and a saved city that was located follows the phone.
      final meta = parseHotCityMeta(data);
      final saved = Prefs.instance.cityChoice;
      if (meta != null && (saved == null || !saved.manual)) {
        await Prefs.instance.setCityChoice(CityChoice(
          code: meta.code,
          name: meta.name,
          lon: saved?.lon ?? city?.lon,
          lat: saved?.lat ?? city?.lat,
        ));
      }
    }
    return parseHotBand(data, board: board);
  }

  /// One sub-tab of weibo.com's 热门榜单 (小时榜 / 昨日 / 前日 / 周榜 / 男榜 / 女榜).
  Future<PageResult<Status>> hotRankFeed(HotRankTab tab, String? cursor) => recommendFeed(
        RecommendChannel(gid: tab.gid, containerId: tab.containerId, title: tab.title),
        cursor,
      );

  /// weibo.com's 推荐 channels: the signed-in account's own 我的频道 first, a visitor's when there
  /// is no account.
  Future<List<RecommendChannel>> recommendChannels() => _getWeiboComOrVisitor(
        (cookie, xsrf) async => parseRecommendChannels(await _getPublic(
          'https://weibo.com/ajax/feed/allGroups',
          query: {'is_new_segment': '1', 'fetch_hot': '1'},
          cookie: cookie,
          xsrf: xsrf,
          whole: true,
        )),
        accept: (channels) => channels.isNotEmpty,
      );

  /// One channel's posts; 热门 signed in is m.weibo.cn's, tuned to the account. weibo.com draws a
  /// fresh batch on every call, so the cursor is only a page count for every channel but 同城, whose
  /// answer carries a `max_id` of its own that must be handed back for the next page.
  Future<PageResult<Status>> recommendFeed(RecommendChannel channel, String? cursor) async {
    if (channel.personal && session.uid != null) {
      final page = int.tryParse(cursor ?? '') ?? 1;
      return _parseFeed(FeedKind.card, await _cardFeed(channel.containerId, page), page);
    }
    // 同城 is the one channel weibo.com draws for a place rather than for everyone.
    final local = channel.gid == '1028032222' || channel.containerId == '102803_2222';
    final city = local ? Prefs.instance.cityChoice ?? await locateCity() : null;
    final page = int.tryParse(cursor ?? '') ?? 0;
    final query = <String, String>{
      'since_id': '0',
      'refresh': local ? (cursor == null ? '1' : '2') : (page == 0 ? '1' : '0'),
      'group_id': channel.gid,
      'containerid': channel.containerId,
      'extparam': 'discover|new_feed',
      'max_id': local ? cursor ?? '0' : '$page',
      'count': '10',
    };
    if (city != null && city.hasCoordinates) {
      query['lon'] = city.lon!.toStringAsFixed(6);
      query['lat'] = city.lat!.toStringAsFixed(6);
    }
    if (city != null && city.code.isNotEmpty) query['citycode'] = city.code;
    final raw = await _getWeiboComOrVisitor(
      (cookie, xsrf) async => await _getPublic(
        'https://weibo.com/ajax/feed/hottimeline',
        query: query,
        referer: 'https://weibo.com/hot/weibo/${channel.gid}',
        cookie: cookie,
        xsrf: xsrf,
        whole: true,
      ),
      accept: (raw) => parseHotTimeline(raw).isNotEmpty,
    );
    final items = parseHotTimeline(raw);
    if (local) {
      // 同城's `max_id` is the whole query state (`2_-_m_-_116.41_39.90_-_…`), not a number: it is
      // handed back as it came, and `0` means there is no next page.
      final next = textOf(asMap(raw)?['max_id'])?.trim();
      return PageResult(items, items.isEmpty || next == null || next.isEmpty || next == '0' ? null : next);
    }
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
