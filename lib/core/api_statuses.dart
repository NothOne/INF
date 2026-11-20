part of 'api.dart';

/// One post, a person's page and its tabs, and the audio behind a voice post.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiStatuses on WeiboApi {

  Future<Status?> status(String id) async {
    final data = await _get('statuses/show', query: {'id': id});
    final parsed = toStatus(data);
    if (parsed == null) return null;
    final map = asMap(data);
    if (map != null && _needsWeiboComSupplement(map, parsed)) {
      final extra = await _weiboComStatus(id).catchError((Object _) => null);
      if (extra != null) return mergeStatusDetails(parsed, extra);
    }
    return parsed;
  }

  /// Fetches weibo.com's fuller copy of a post: m.weibo.cn drops mixed-media videos, caps `pics`
  /// at 9 on mixed posts, and collapses multi-picture 「查看图片」 links in repost chains to one URL.
  Future<Status?> _weiboComStatus(String id) async {
    final json = await _asVisitor((cookie) async => asMap(await _getPublic(
          'https://weibo.com/ajax/statuses/show',
          query: {'id': id, 'isGetLongText': 'true'},
          cookie: cookie,
          whole: true,
        )));
    return toStatus(json);
  }

  /// Resolves every picture bundled behind a 「查看图片」 link (e.g. a repost chain carrying 2+
  /// pictures) when m.weibo.cn only included the first picture's URL in the feed text.
  Future<List<Media>> resolveInlineImages(String statusId, String imageUrl) async {
    final pid = picIdOfUrl(imageUrl);
    if (pid == null) return const [];
    final extra = await _weiboComStatus(statusId).catchError((Object _) => null);
    if (extra == null) return const [];
    for (final post in [extra, if (extra.repostOf != null) extra.repostOf!]) {
      for (final link in post.links.values) {
        if (link.images.length <= 1) continue;
        if (link.images.any((m) => picIdOfUrl(m.url) == pid || picIdOfUrl(m.previewUrl) == pid)) {
          return link.images;
        }
      }
    }
    return const [];
  }

  static bool _needsWeiboComSupplement(Map<String, dynamic> raw, Status status) {
    bool hasMixedOrExtra(Map<String, dynamic>? json) {
      if (json == null) return false;
      return (intOf(json['pic_num']) ?? 0) > 9 ||
          asList(json['pic_ids']).length > 9 ||
          asList(json['mix_media_ids']).isNotEmpty ||
          boolOf(json['is_show_mixed']) ||
          (intOf(json['mixed_count']) ?? 0) > 0;
    }

    bool hasInlinePicture(Status? s) =>
        s != null && inlineSinaimgUrls(s.text).any((url) => (s.links[url]?.images.length ?? 0) <= 1);

    return hasMixedOrExtra(raw) ||
        hasMixedOrExtra(asMap(raw['retweeted_status'])) ||
        hasInlinePicture(status) ||
        hasInlinePicture(status.repostOf);
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

  /// 搜他的微博. m.weibo.cn's own search box searches the whole site; weibo.com's profile search
  /// narrows to the account, but answers only the signed-in weibo.com cookie, never a visitor.
  Future<PageResult<Status>> searchUserStatuses(String uid, String query, String? cursor) => _numberedPage(
        cursor,
        (page) async => parseStatusList(await _getWeiboCom(
          'profile/searchblog',
          {'uid': uid, 'page': page, 'feature': '0', 'q': query},
          referer: 'https://weibo.com/u/$uid',
        )),
      );

  static final _profileCache = CachedValue<UserProfile>(
    key: 'profile',
    wrap: (data) => {'userInfo': asMap(data)?['userInfo']},
    parse: parseUserProfile,
  );

  Future<UserProfile?> userProfile(String uid) async {
    final data = await _get('api/container/getIndex', query: {'type': 'uid', 'value': uid});
    final profile = parseUserProfile(data);
    if (profile != null && uid == session.uid) {
      _profileCache.write(data);
    }
    return profile;
  }

  UserProfile? cachedSelfProfile() => _profileCache.read();

  Future<User?> user(String uid) async => (await userProfile(uid))?.user;

  /// The sections weibo.com shows on someone's page; the usual four when it does not answer.
  Future<ProfileExtras> profileExtras(String uid) async {
    Future<dynamic> visit(String path) => _asVisitor((cookie) => _getPublic(
          'https://weibo.com/ajax/profile/$path',
          query: {'uid': uid},
          referer: 'https://weibo.com/u/$uid',
          cookie: cookie,
        ));
    final detail = visit('detail').then<dynamic>((data) => data, onError: (_) => null);
    try {
      return parseProfileExtras(await visit('info'), await detail);
    } catch (_) {
      return parseProfileExtras(null, await detail);
    }
  }

  /// 精选: what weibo.com calls the account's 热门内容.
  Future<PageResult<Status>> profileFeatured(String uid, String? cursor) =>
      _profileContainer(uid, '231002${uid}_-_HOTMBLOG', cursor);

  /// The 微博 tab narrowed to originals, pictures, videos or articles; [ProfilePostFilter.all] is
  /// [userTimeline].
  Future<PageResult<Status>> profilePosts(String uid, String suffix, String? cursor) =>
      _profileContainer(uid, '230413${uid}_-_WEIBO_SECOND_PROFILE_WEIBO${suffix.isEmpty ? '' : '_$suffix'}', cursor);

  Future<PageResult<Status>> profileVideos(String uid, String? cursor) async => parseCursorStatuses(await _asVisitor(
        (cookie) => _getPublic(
          'https://weibo.com/ajax/profile/getWaterFallContent',
          query: {'uid': uid, 'cursor': cursor ?? '0'},
          referer: 'https://weibo.com/u/$uid',
          cookie: cookie,
        ),
      ));

  Future<PageResult<Status>> profileAudio(String uid, String? cursor) async => parseCursorStatuses(await _asVisitor(
        (cookie) => _getPublic(
          'https://weibo.com/ajax/profile/getAudioList',
          query: {'profile_uid': uid, 'cursor': cursor ?? ''},
          referer: 'https://weibo.com/u/$uid',
          cookie: cookie,
        ),
      ));

  Future<PageResult<ProfilePhoto>> profilePhotos(String uid, String? cursor) async => parseImageWall(await _asVisitor(
        (cookie) => _getPublic(
          'https://weibo.com/ajax/profile/getImageWall',
          query: {'uid': uid, 'sinceid': cursor ?? '0', 'has_album': cursor == null ? 'true' : 'false'},
          referer: 'https://weibo.com/u/$uid',
          cookie: cookie,
        ),
      ));

  /// Where a post's card goes when the feed left the address out: weibo.com's copy of the post
  /// still has it. Null when it does not either.
  Future<String?> cardUrl(String statusId) async {
    final json = await _asVisitor((cookie) async => asMap(await _getPublic(
          'https://weibo.com/ajax/statuses/show',
          query: {'id': statusId},
          cookie: cookie,
          whole: true,
        )));
    final pageUrl = textOf(asMap(json?['page_info'])?['page_url']);
    if (pageUrl != null && pageUrl.isNotEmpty) return pageUrl;
    for (final entry in asList(json?['url_struct'])) {
      final url = textOf(asMap(entry)?['h5_target_url']);
      if (url != null && url.isNotEmpty) return url;
    }
    return null;
  }

  /// A post's sound with a signed address and its transcript: m.weibo.cn leaves voice posts'
  /// audio out or unsigned, weibo.com's copy has both.
  Future<AudioClip?> audioClip(String statusId) async => audioClipOf(await _asVisitor((cookie) => _getPublic(
        'https://weibo.com/ajax/statuses/show',
        query: {'id': statusId},
        cookie: cookie,
        whole: true,
      )));
}
