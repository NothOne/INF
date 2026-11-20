import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';

import 'fixtures/fixture.dart';

/// Golden tests: one real answer per endpoint, through the parser that reads it.
///
/// Every fixture is a response the service sent (see `fixtures/README.md`), so these fail for the
/// reason they exist: Weibo changed a field name, or a parser started reading a different one.
/// That is the failure the hand-written cases elsewhere cannot produce — both sides of those were
/// written by whoever wrote the parser, so they agree with each other by construction.
///
/// They assert what a screen actually shows: the author's name, the words, the counts, the
/// picture addresses, the next page's cursor. Not the whole object — a field can be added without
/// these tests caring, which is right, because adding one breaks nothing.
void main() {
  group('a post: m.weibo.cn statuses/show', () {
    // A real post: eighteen pictures, 1.9k reposts, the author's V and 会员, a long text body.
    final status = toStatus(Fixture.load('status_show').payload)!;

    test('the post and its author', () {
      expect(status.id, '5246969136287056');
      expect(status.author.id, '1727858283');
      expect(status.author.screenName, '宝玉xp');
      expect(status.author.verified, isTrue);
      expect(status.author.followersCount, 1156000);
    });

    test('the counts are the ones on the post', () {
      expect(status.repostsCount, 1944);
      expect(status.commentsCount, 190);
      expect(status.likesCount, 2296);
      expect(status.liked, isFalse);
    });

    test('the words survive the HTML, and the anchor keeps its address', () {
      expect(status.text, startsWith('整理个置顶贴'));
      expect(status.text, isNot(contains('<br')));
      expect(status.text, isNot(contains('<a ')));
      expect(status.links, contains('https://weibo.com/1727858283/QfCLYnJyZ'));
    });

    test('every picture is in the grid, full size and with a thumbnail', () {
      expect(status.media, hasLength(18));
      expect(status.images, hasLength(18));
      expect(status.images.first.url, contains('/mw2000/'));
      expect(status.images.first.previewUrl, contains('/orj360/'));
      expect(status.images.first.width, greaterThan(0));
    });

    test('the post knows where it was posted from and that it is a long one', () {
      expect(status.region, contains('美国'));
      expect(status.isLongText, isTrue);
      expect(status.source, '微博网页版');
      expect(status.createdAt.year, 2025);
    });
  });

  group('comments: m.weibo.cn comments/hotflow', () {
    final fixture = Fixture.load('comments_hotflow');
    final page = parseCommentPage(fixture.payload, '5246969136287056');

    test('the page comes back with its own cursor, type and all', () {
      expect(page.items, isNotEmpty);
      // `max_id` and `max_id_type` have to survive as a pair: the type is what keeps 按时间 from
      // falling back into 按热度 on the second page.
      expect(page.nextCursor, '140263258797044:0');
    });

    test('a comment reads as the list draws it', () {
      final comment = page.items.first;
      expect(comment.author.screenName, '业余草');
      expect(comment.likesCount, 1);
      expect(comment.region, startsWith('来自'));
      expect(comment.createdAt.year, greaterThanOrEqualTo(2025));
    });

    test('the replies under a comment are there, and the count is the total', () {
      final withReplies = page.items.first;
      expect(withReplies.replies, isNotEmpty);
      // The answer inline carries a few replies but reports the real total; the total is what a
      // "N 条回复" line has to show.
      expect(withReplies.repliesCount, greaterThanOrEqualTo(withReplies.replies.length));
    });

    test('the emoji in a comment is text, not markup', () {
      final withEmoji = page.items.firstWhere(
        (comment) => comment.text.contains('['),
        orElse: () => page.items.first,
      );
      expect(withEmoji.text, isNot(contains('<img')));
    });

    test('newest-first pages carry their own type', () {
      final byTime = parseCommentPage(
        Fixture.load('comments_by_time').payload,
        '5246969136287056',
        maxIdType: '1',
      );
      expect(byTime.items, isNotEmpty);
      expect(byTime.nextCursor, endsWith(':1'));
      // Newest first means the later date comes first.
      expect(byTime.items.first.createdAt.isAfter(byTime.items.last.createdAt), isTrue);
    });
  });

  group('a long post: m.weibo.cn statuses/extend', () {
    test('longTextContent is far longer than the truncated copy, and keeps its links', () {
      final raw = textOf(asMap(Fixture.load('longtext').payload)?['longTextContent'])!;
      final rich = weiboHtmlToRichText(raw);
      expect(rich.text.length, greaterThan(2900));
      expect(rich.text, isNot(contains('<br')));
      expect(rich.links, hasLength(48));
    });
  });

  group('unread: m.weibo.cn api/remind/unread', () {
    test('an empty answer is zero of everything, not a crash', () {
      final counts = parseUnread(Fixture.load('unread_empty').payload);
      expect(counts.comments, 0);
      expect(counts.likes, 0);
      expect(counts.messages, 0);
      expect(counts.mentionsInStatuses, 0);
    });
  });

  group('channels: m.weibo.cn api/config/list', () {
    test('a visitor is in no group but is offered the channels', () {
      final payload = Fixture.load('config_list').payload;
      expect(parseFeedGroups(payload), isEmpty);
      final channels = asList(asMap(payload)?['channel']);
      expect(channels, isNotEmpty);
      expect(textOf(asMap(channels.first)?['gid']), isNotNull);
    });
  });

  group('the hot board: weibo.com statuses/hot_band', () {
    final board = parseHotBand(Fixture.load('hot_band').payload);

    test('the pinned government entry comes first and has no rank', () {
      expect(board.first.pinned, isTrue);
      expect(board.first.rank, isNull);
      expect(board.first.label, isNotNull);
      expect(board.first.labelColor, isNotNull);
    });

    test('the ranked rows carry rank, heat, category and when they made the list', () {
      final first = board.firstWhere((entry) => !entry.pinned);
      expect(first.rank, 1);
      expect(first.heatValue, 1067453);
      expect(first.heat, '106.7万');
      expect(first.category, '国内时政');
      expect(first.label, '新');
      expect(first.onboardAt, isNotNull);
      expect(first.board, HotBoard.realtime);
    });

    test('a topic row asks for the hashtag, a plain row for the words', () {
      final topic = board.firstWhere((entry) => entry.word == '中美元首深圳会晤');
      expect(topic.query, '#中美元首深圳会晤#');
      final plain = board.firstWhere((entry) => entry.word.contains('后会友期'));
      expect(plain.query, isNot(startsWith('#')));
    });

    test('the advertisement in the list is dropped, and does not use up a rank', () {
      // The answer carries an `is_ad` row; showing it would be showing an ad as news, and
      // counting it would shift every rank below it by one.
      expect(board.any((entry) => entry.word.contains('百岁山')), isFalse);
      final ranks = [for (final entry in board) if (entry.rank != null) entry.rank!];
      expect(ranks, List.generate(ranks.length, (index) => index + 1));
    });

    test('another board is the same shape without the pinned entry', () {
      final ent = parseHotBand(Fixture.load('hot_board_entertainment').payload, board: HotBoard.entertainment);
      expect(ent, isNotEmpty);
      expect(ent.any((entry) => entry.pinned), isFalse);
      expect(ent.first.rank, 1);
      expect(ent.first.board, HotBoard.entertainment);
    });
  });

  group('search: weibo.com side/search', () {
    final suggestions = parseSearchSuggestions(Fixture.load('side_search').payload);

    test('completions keep their order and their heat', () {
      expect(suggestions.words, isNotEmpty);
      expect(suggestions.words.first.word, contains('科技'));
      expect(suggestions.words.first.count, greaterThan(0));
    });

    test('the accounts that match come with ids and names', () {
      expect(suggestions.users, isNotEmpty);
      expect(suggestions.users.first.id, isNotEmpty);
      expect(suggestions.users.first.screenName, isNotEmpty);
    });
  });

  group('推荐 channels: weibo.com feed/allGroups', () {
    // This one answers without a `data` wrapper (`_getPublic(..., whole: true)`), so the parser is
    // handed the whole body.
    final channels = parseRecommendChannels(Fixture.load('all_groups').data);

    test('热门 comes first, as the signed-in account sees it, then 推荐 for everyone', () {
      expect(channels.first, RecommendChannel.hot);
      expect(channels[1], RecommendChannel.everyone);
      expect(channels[0].personal, isTrue);
      expect(channels[1].personal, isFalse);
    });

    test('the channels after them carry a gid and a container to page', () {
      final rest = channels.skip(2).toList();
      expect(rest, isNotEmpty);
      for (final channel in rest) {
        expect(channel.gid, isNotEmpty);
        expect(channel.containerId, isNotEmpty);
        expect(channel.title, isNotEmpty);
      }
    });

    test('the groups of feed sources are not channels', () {
      // `group_type: 1` marks a 推荐 channel; everything else in this answer is a feed group, and
      // reading those as channels would put 全部关注 in the 推荐 picker.
      expect(channels.any((channel) => channel.title == '全部关注'), isFalse);
    });
  });

  group('a profile: weibo.com profile/info and profile/detail', () {
    final extras = parseProfileExtras(
      Fixture.load('profile_info').payload,
      Fixture.load('profile_detail').payload,
    );

    test('the tabs weibo.com shows come in INF\'s order', () {
      expect(extras.tabs, [
        ProfileTab.posts,
        ProfileTab.featured,
        ProfileTab.videos,
        ProfileTab.photos,
        ProfileTab.audio,
        ProfileTab.articles,
      ]);
    });

    test('转评赞 read out of status_total_counter', () {
      expect(extras.interactions, 4205192);
      expect(extras.likes, 1962158);
      expect(extras.comments, 241872);
      expect(extras.reposts, 2001162);
    });

    test('the facts are the ones the profile page lists', () {
      expect(extras.facts, contains('2010-04-10 加入微博'));
      expect(extras.facts, contains('阳光信用极好'));
      expect(extras.facts.any((fact) => fact.contains('AI')), isTrue);
    });

    test('the cover comes back at full size, not as a 640 crop', () {
      expect(extras.coverUrl, isNotNull);
      expect(extras.coverUrl, contains('mw2000'));
      expect(extras.coverUrl, isNot(contains('crop.0.0.640.640.640')));
    });

    test('the V colour and the 会员 icon are read from the account\'s own fields', () {
      expect(extras.verified, VerifiedBadge.gold);
      expect(extras.vip, isNotNull);
      expect(extras.vip!.url, contains('vvip_'));
      expect(extras.gender, 'm');
    });
  });

  group('a profile\'s walls: weibo.com profile/get*', () {
    test('the video wall pages by cursor', () {
      final page = parseCursorStatuses(Fixture.load('waterfall').payload);
      expect(page.items, hasLength(2));
      expect(page.items.first.author.screenName, '宝玉xp');
      expect(page.nextCursor, '5363848162050932');
    });

    test('the audio wall ends with a cursor of -1, which is no next page', () {
      final page = parseCursorStatuses(Fixture.load('audiowall').payload);
      expect(page.items, hasLength(1));
      expect(page.nextCursor, isNull);
    });

    test('the picture wall gives each picture a full and a thumbnail address', () {
      final page = parseImageWall(Fixture.load('imagewall').payload);
      expect(page.items, hasLength(2));
      expect(page.items.first.media.url, contains('/mw2000/'));
      expect(page.items.first.media.previewUrl, contains('/orj360/'));
      expect(page.items.first.statusId, isNotEmpty);
      expect(page.nextCursor, isNotNull);
    });
  });

  group('a topic: m.s.weibo.com ajax_topic', () {
    final info = parseTopicDetail(Fixture.load('topic_detail').payload)!;

    test('the counts are the figures the head shows', () {
      expect(info.title, '科技');
      expect(info.reads, 7562112049);
      expect(info.discussions, 9076975);
      expect(info.originals, 2091648);
      expect(info.interactions, 13424893);
    });

    test('the category, the media line and the contributors', () {
      expect(info.category, '科普');
      expect(info.note, contains('媒体发布'));
      expect(info.contributors, isNotEmpty);
      expect(info.media, isNotEmpty);
      expect(info.createdAt?.year, 2013);
    });

    test('the trend is hourly reads for the day', () {
      final trend = parseTopicTrend(Fixture.load('topic_trend').payload);
      expect(trend, hasLength(24));
      expect(trend.first.label, isNotEmpty);
      expect(trend.first.value, greaterThan(0));
    });
  });

  group('a login QR code: passport', () {
    test('the image address carries the address the Weibo app can open', () {
      final login = parseQrLogin(Fixture.load('qrcode_image').data)!;
      expect(login.qrid, isNotEmpty);
      expect(login.scanUrl, startsWith('https://passport.weibo.cn/'));
      expect(login.scanUrl, contains('qr='));
    });

    test('a code nobody has scanned yet is 未使用, which is still waiting', () {
      final status = parseQrLoginStatus(Fixture.load('qrcode_check').data);
      expect(status.state, QrLoginState.waiting);
      expect(status.message, '未使用');
    });
  });
}
