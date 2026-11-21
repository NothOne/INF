import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/endpoints.dart';

/// `core/endpoints.dart` says which host and which credential each endpoint uses. Those two facts
/// cannot be checked by running anything — they are true only because the method that calls the
/// endpoint does so on the right transport. So this test reads the transports themselves and
/// compares.
///
/// Reading source text is a blunt instrument, so it asks three narrow questions rather than one
/// broad one: is every path in the API layer in the table, is every path that goes through a
/// specific transport declared as that transport's host, and is every row actually asked for. Each
/// catches something the others miss, and each fails loudly rather than silently.
void main() {
  final apiFiles = [
    for (final entity in Directory('lib/core').listSync())
      if (entity.path.endsWith('.dart') &&
          (entity.uri.pathSegments.last.startsWith('api_') || entity.uri.pathSegments.last == 'api.dart'))
        entity.path,
  ];
  final sources = {
    for (final path in apiFiles) path: File(path).readAsStringSync(),
    'lib/core/group_chat_api.dart': File('lib/core/group_chat_api.dart').readAsStringSync(),
  };
  final all = sources.values.join('\n');

  /// Every string literal in the API layer that looks like a path below a host.
  final literals = {
    for (final source in sources.values)
      for (final match in RegExp(r"'([a-z0-9][a-z0-9_.]*(?:/[A-Za-z0-9_.\-]+)+)'").allMatches(source))
        match.group(1)!,
  }..removeWhere((path) => path.startsWith('image/'));

  final declared = {for (final endpoint in Endpoint.values) endpoint.path};

  test('every path the API layer asks for is in the table', () {
    expect(literals.difference(declared), isEmpty);
  });

  test('a path sent through weibo.com\'s transport is declared as weibo.com\'s', () {
    // `_getWeiboCom` and `_postWeiboCom` add the weibo.com cookie and XSRF pair. A row that called
    // one of these `mWeibo` would be wrong about which session the request uses — the mistake this
    // table exists to stop being restated in prose.
    final weiboCom = Endpoint.pathsOn(EndpointHost.weiboCom);
    final throughWeiboCom = {
      for (final source in sources.values)
        for (final match in RegExp(r"_(?:get|post)WeiboCom(?:Form)?\(\s*'([^']+)'").allMatches(source)) match.group(1)!,
    };
    expect(throughWeiboCom, isNotEmpty);
    expect(throughWeiboCom.difference(weiboCom), isEmpty);
  });

  test('a path sent through a full URL is declared on that URL\'s host', () {
    // These three hosts are reached by address rather than by a path below the base URL, which is
    // how a request ends up on the wrong cookie: the base is m.weibo.cn and its interceptor only
    // attaches the session's cookie to that host.
    final byPrefix = <String, EndpointHost>{
      'https://weibo.com/ajax/': EndpointHost.weiboCom,
      'https://passport.weibo.com/': EndpointHost.passport,
      'https://m.s.weibo.com/': EndpointHost.msWeibo,
      'https://ai.s.weibo.com/': EndpointHost.aiWeibo,
      'https://api.weibo.com/webim/': EndpointHost.apiWeibo,
      'https://upload.api.weibo.com/': EndpointHost.uploadWeibo,
      'https://up.video.weibocdn.com/': EndpointHost.videoUpload,
    };
    for (final path in literals) {
      if (!path.startsWith('https://')) continue;
      if (path.contains(r'$')) continue; // interpolated; the row is checked by name below
      final host = byPrefix.entries.where((entry) => path.startsWith(entry.key)).firstOrNull;
      expect(host, isNotNull, reason: '$path is on no host this table knows');
      final rest = path.substring(host!.key.length);
      expect(Endpoint.pathsOn(host.value), contains(rest), reason: '$path is declared on the wrong host');
    }
  });

  test('the group chat paths are declared as api.weibo.com\'s', () {
    final groupChat = File('lib/core/group_chat_api.dart').readAsStringSync();
    final asked = {
      for (final match in RegExp(r"_call\(\s*'([^']+)'").allMatches(groupChat)) match.group(1)!,
    };
    expect(asked, isNotEmpty);
    expect(asked.difference(Endpoint.pathsOn(EndpointHost.apiWeibo)), isEmpty);
  });

  test('every row is asked for by something', () {
    // A row nobody calls is a claim about a request that does not exist. Matched on the whole path
    // where it appears whole (`_get('statuses/show')`), and on the last segment otherwise, because
    // some are reached through a full URL or a variable. The profile paths and the 热搜 boards are
    // interpolated (`'profile/$path'`, `'statuses/${board.path}'`), so they are matched against the
    // file that builds the variable instead.
    final models = File('lib/core/models.dart').readAsStringSync();
    final statuses = sources['lib/core/api_statuses.dart']!;
    for (final endpoint in Endpoint.values) {
      final asked = literals.contains(endpoint.path) || all.contains("'${endpoint.path}'");
      if (asked) continue;
      if (endpoint.host == EndpointHost.weiboCom && endpoint.path.startsWith('statuses/')) {
        final name = endpoint.path.substring('statuses/'.length);
        expect(models, contains("'$name'"), reason: '${endpoint.name} is not one of HotBoard\'s paths');
        continue;
      }
      if (endpoint.host == EndpointHost.weiboCom && endpoint.path.startsWith('profile/')) {
        expect(statuses, contains(r'profile/$path'), reason: '${endpoint.name} is never visited');
        continue;
      }
      final segments = endpoint.path.split('/');
      final tail = segments.length > 1 ? segments.sublist(segments.length - 2).join('/') : endpoint.path;
      expect(all, contains('/$tail'), reason: '${endpoint.name} (${endpoint.path}) is declared but never asked');
    }
  });

  test('a captcha is only risked where the envelope can carry one', () {
    // A captcha id arrives in the m.weibo.cn envelope's `error_type`. weibo.com answers `ok`,
    // passport and m.s.weibo.com answer `retcode`, group chat answers `result: false` — none has a
    // captcha field, so declaring a risk there would warn about something that cannot happen.
    for (final endpoint in Endpoint.captchaRisks) {
      expect(endpoint.host, EndpointHost.mWeibo, reason: '${endpoint.name} cannot raise a captcha');
      expect(endpoint.auth, EndpointAuth.user, reason: '${endpoint.name} needs a session to be refused');
    }
  });

  test('every write to m.weibo.cn is declared, and nothing else is', () {
    // These are the calls that go through `_post`, which is where the retry lives. Spelled out
    // rather than counted: a write added without a row here is exactly the case a page would fail
    // to warn the reader about.
    const writes = {
      'like',
      'unlike',
      'likeComment',
      'unlikeComment',
      'favorite',
      'unfavorite',
      'uploadPicture',
      'postStatus',
      'repost',
      'comment',
      'reply',
      'follow',
      'unfollow',
      'sendMessage',
      'sendGroupMessage',
      'uploadChatPicture',
      'leaveGroup',
    };
    expect({for (final endpoint in Endpoint.captchaRisks) endpoint.name}, writes);
  });

  test('nothing on an anonymous host claims to need the account', () {
    // A `visitor` request must never be sent with the account's cookie, and a `none` one must not
    // be sent at all — the rule that keeps a weibo.com request from picking up m.weibo.cn's
    // session, which this project has got wrong before.
    for (final endpoint in Endpoint.values) {
      if (endpoint.host == EndpointHost.passport ||
          endpoint.host == EndpointHost.msWeibo ||
          endpoint.host == EndpointHost.aiWeibo) {
        expect(endpoint.auth, isNot(EndpointAuth.user), reason: '${endpoint.name} is anonymous');
      }
    }
  });

  test('the container path is declared once per kind of list it answers', () {
    // Reading any list is the same address below the host; only the container id differs. Getting
    // it wrong shows an empty list rather than an error, so each kind keeps its own row.
    final containers = {
      for (final endpoint in Endpoint.values)
        if (endpoint.path == 'api/container/getIndex') endpoint.name,
    };
    expect(containers, containsAll(<String>[
      'feedContainer',
      'userTimeline',
      'userProfile',
      'searchStatuses',
      'searchUsers',
      'relations',
      'superTopics',
      'hotSearchFallback',
      'topicPage',
    ]));
  });

  test('the fixture set is the one the golden tests read', () {
    final fixtures = {
      for (final entity in Directory('test/fixtures').listSync())
        if (entity.path.endsWith('.json')) entity.uri.pathSegments.last.replaceAll('.json', ''),
    };
    expect(fixtures, containsAll(<String>[
      'status_show',
      'comments_hotflow',
      'comments_by_time',
      'longtext',
      'config_list',
      'unread_empty',
      'hot_band',
      'hot_board_entertainment',
      'side_search',
      'all_groups',
      'profile_info',
      'profile_detail',
      'profile_feature',
      'waterfall',
      'audiowall',
      'imagewall',
      'topic_detail',
      'topic_trend',
      'qrcode_image',
      'qrcode_check',
    ]));
  });
}
