part of 'api.dart';

/// Search, and a topic's own page.
///
/// Part of [WeiboApi] as an extension in a part file: the methods stay on the one singleton every
/// caller already holds, while this file says which domain they belong to. The transport (`_get`,
/// `_post`, `_dio`, `session`) stays in `api.dart`, because an extension cannot call another
/// extension's private members.
extension WeiboApiSearchTopic on WeiboApi {

  Future<SearchSuggestions> searchSuggestions(String query) async {
    final data = await _getPublic('https://weibo.com/ajax/side/search', query: {'q': query});
    return parseSearchSuggestions(data);
  }

  /// Topic autocomplete for `#` in the composer and comment sheet (`weibo.com/ajax/mblog/topic`).
  Future<List<String>> topicSuggestions(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    return _getWeiboComOrVisitor(
      (cookie, xsrf) async => parseTopicSuggestions(await _getPublic(
        'https://weibo.com/ajax/mblog/topic',
        query: {'q': q},
        referer: 'https://weibo.com/',
        cookie: cookie,
        xsrf: xsrf,
      )),
    );
  }

  /// 微博智搜 (`ai.s.weibo.com/api/wis/show.json`), polled with incrementing [loopNum] while
  /// `result.isGenerating` is true.
  Future<AiSearchResult> aiSearch(
    String query, {
    required String requestId,
    int loopNum = 1,
    String? model,
  }) async {
    final data = await _postPublicForm(
      'https://ai.s.weibo.com/api/wis/show.json',
      {
        'query': query,
        'content_type': 'loop',
        'request_id': requestId,
        'cot': '1',
        'loop_num': '$loopNum',
        if (model != null && model.isNotEmpty) 'model': model,
      },
      referer: 'https://s.weibo.com/',
    );
    return parseAiSearchResult(data, query);
  }

  /// One page of a search channel's posts, and on the first page the channels the search offers.
  Future<(PageResult<Status>, List<SearchChannel>?)> searchStatuses(String query, int type, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final data = await _searchPage(query, type, page);
    return (parseContainerStatuses(data, page), page == 1 ? parseSearchChannels(data) : null);
  }

  /// A channel whose cards are not posts: topics, super topics, places …
  Future<PageResult<SearchEntry>> searchEntries(String query, int type, String? cursor) async {
    final page = int.tryParse(cursor ?? '') ?? 1;
    final entries = parseSearchEntries(await _searchPage(query, type, page));
    return PageResult(entries, entries.isEmpty ? null : '${page + 1}');
  }

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
}
