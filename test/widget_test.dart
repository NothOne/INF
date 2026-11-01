import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/image_url.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/paging.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/session.dart';
import 'package:inf_flutter/core/topic_timeline.dart';
import 'package:inf_flutter/core/widgets/rich_text.dart';

void main() {
  test('compactCount formats Weibo counts', () {
    expect(compactCount(999), '999');
    expect(compactCount(12540), '1.2万');
    expect(compactCount(100000), '10万');
    expect(compactCount(120000000), '1.2亿');
  });

  test('weiboHtmlToText keeps mentions and drops the full-text anchor', () {
    const html = '你好 <a href="https://m.weibo.cn/n/%E5%B0%8F%E6%98%8E">@小明</a> '
        '<a href="https://m.weibo.cn/search?containerid=231522type%3D1%26q%3D%23%E7%A7%91%E6%8A%80%23">#科技#</a>'
        '<a href="https://m.weibo.cn/status/1">全文</a>';
    final text = weiboHtmlToText(html);
    expect(text, contains('@小明'));
    expect(text, contains('#科技#'));
    expect(text, isNot(contains('全文')));
  });

  test('absorbSetCookies follows a rotated XSRF-TOKEN', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final session = Session.instance;
    session.cookies
      ..clear()
      ..addAll({'SUB': 'signed', 'XSRF-TOKEN': 'stale1'});
    session.absorbSetCookies([
      'XSRF-TOKEN=deleted; expires=Thu, 01-Jan-1970 00:00:01 GMT; Max-Age=0; path=/; domain=.weibo.cn; HttpOnly',
      'XSRF-TOKEN=b66049; expires=Sun, 01-Nov-2026 02:48:18 GMT; Max-Age=1200; path=/; domain=m.weibo.cn',
      'MLOGIN=1; Max-Age=3600; path=/; domain=.weibo.cn',
    ]);
    expect(session.xsrf, 'b66049');
    expect(session.cookies['SUB'], 'signed');
    expect(session.cookies['MLOGIN'], '1');
    session.absorbSetCookies(['MLOGIN=deleted; Max-Age=0; path=/']);
    expect(session.cookies.containsKey('MLOGIN'), isFalse);
    session.cookies.clear();
  });

  test('secureUrl upgrades cleartext links and video URLs', () {
    expect(secureUrl('http://weibo.com/p/100101B209435DD76CA0F4499E'), 'https://weibo.com/p/100101B209435DD76CA0F4499E');
    expect(secureUrl('HTTP://f.video.weibocdn.com/o0/a.mp4?label=mp4_hd'), 'https://f.video.weibocdn.com/o0/a.mp4?label=mp4_hd');
    expect(secureUrl('//wx1.sinaimg.cn/large/a.jpg'), 'https://wx1.sinaimg.cn/large/a.jpg');
    expect(secureUrl('https://m.weibo.cn/detail/1'), 'https://m.weibo.cn/detail/1');
  });

  test('parseReposts reads the timeline list and the hot list', () {
    final items = parseReposts({
      'hot_data': [
        {'id': '1', 'text': '热门转发', 'user': {'id': '8', 'screen_name': '甲'}},
      ],
      'data': [
        {'id': '2', 'text': '转发微博', 'user': {'id': '9', 'screen_name': '乙'}},
      ],
    });
    expect(items.map((s) => s.id), ['1', '2']);
    expect(items.first.author.screenName, '甲');
  });

  test('parseHotBand ranks entries, skips ads and keeps the pinned one first', () {
    final board = parseHotBand({
      'hotgov': {'word': '#置顶话题#', 'icon_desc': '热', 'icon_desc_color': '#ff9406'},
      'band_list': [
        {'word': '话题甲', 'word_scheme': '#话题甲#', 'topic_flag': 1, 'num': 1180002, 'label_name': '新',
          'category': '剧集', 'onboard_time': 1793353519},
        {'word': '广告', 'is_ad': 1},
        {'word': '关键词乙', 'num': 500000},
      ],
    });
    expect(board.map((e) => e.word), ['置顶话题', '话题甲', '关键词乙']);
    expect(board.first.pinned, isTrue);
    expect(board[1].rank, 1);
    expect(board[1].query, '#话题甲#');
    expect(board[1].isTopic, isTrue);
    expect(board[1].heat, '118万');
    expect(board[1].labelColor, isNull);
    expect(board[2].rank, 2);
    expect(board[2].isTopic, isFalse);
    expect(board.first.rankText, '热搜置顶');
    expect(board[2].rankText, '热搜第2');
  });

  test('toStatus reads live photos from both APIs and leaves GIF clips alone', () {
    const mov = 'https://video.weibo.com/media/play?livephoto=https%3A%2F%2Flivephoto.us.sinaimg.cn%2Fabc.mov';
    final mobile = toStatus({
      'id': '1',
      'text': '',
      'pics': [
        {'pid': 'a', 'url': 'https://wx2.sinaimg.cn/orj360/a.jpg', 'type': 'livephoto', 'videoSrc': mov},
        {'pid': 'b', 'url': 'https://wx2.sinaimg.cn/orj360/b.gif', 'type': 'gifvideos', 'videoSrc': 'https://f.video.weibocdn.com/b.mp4'},
        {'pid': 'c', 'url': 'https://wx2.sinaimg.cn/orj360/c.jpg'},
      ],
    })!;
    expect(mobile.media.map((m) => m.liveUrl).toList(), [mov, null, null]);

    final web = toStatus({
      'id': '2',
      'text': '',
      'pic_ids': ['a', 'b', 'c'],
      'pic_infos': {
        'a': {'type': 'livephoto', 'video': mov, 'large': {'url': 'https://wx2.sinaimg.cn/orj960/a.jpg'}},
        'b': {'type': 'livephoto', 'fid': 'xyz', 'large': {'url': 'https://wx2.sinaimg.cn/orj960/b.jpg'}},
        'c': {'type': 'pic', 'large': {'url': 'https://wx2.sinaimg.cn/orj960/c.jpg'}},
      },
      'pic_video': '2:def',
    })!;
    expect(web.media[0].liveUrl, mov);
    expect(web.media[1].liveUrl, livePhotoUrl('xyz'));
    expect(web.media[2].liveUrl, livePhotoUrl('def'));
    expect(livePhotoUrl('xyz'), contains('livephoto.us.sinaimg.cn%2Fxyz.mov'));
  });

  test('parseTopicDetail reads when each board run started and ended', () {
    final info = parseTopicDetail({
      'baseInfo': {
        'object': {
          'display_name': '话题',
          'creator': {'mid': '5360106272721056', 'create_at': 1793432384},
        },
        'count': {'read': 1000},
      },
      'baseData': {
        'm_rank_pos_duration': {
          'data': [
            {
              'cate_desc': '热搜榜',
              'top_pos': 1,
              'duration_minute': 91,
              'on_board_time': '202610311552',
              'off_board_time': '202610311722',
            },
          ],
        },
      },
    })!;
    final stint = info.boards.single;
    expect(stint.onAt, DateTime.utc(2026, 10, 31, 7, 52).toLocal());
    expect(stint.offAt, DateTime.utc(2026, 10, 31, 9, 22).toLocal());
    expect(info.firstStatusId, '5360106272721056');
  });

  test('buildTopicTimeline orders board runs, the peak hour and posts, ending now', () {
    final now = DateTime(2026, 10, 31, 18, 30);
    User author(String name, {bool verified = false}) => User(id: name, screenName: name, verified: verified);
    Status post(String id, User user, DateTime at, {int likes = 0}) =>
        Status(id: id, author: user, text: id, createdAt: at, likesCount: likes);
    final events = buildTopicTimeline(
      now: now,
      info: TopicInfo(
        reads: 13770000,
        createdAt: DateTime(2026, 10, 31, 15, 20),
        boards: [
          TopicBoardStint(
            board: '热搜榜',
            bestRank: 1,
            minutes: 91,
            onAt: DateTime(2026, 10, 31, 15, 52),
            offAt: DateTime(2026, 10, 31, 17, 23),
          ),
        ],
      ),
      trend: [for (var i = 0; i < 24; i++) TopicTrendPoint('', i == 21 ? 900 : 10)],
      posts: [
        post('loud', author('路人'), DateTime(2026, 10, 31, 16, 40), likes: 5000),
        post('media', author('新闻', verified: true), DateTime(2026, 10, 31, 15, 30)),
        post('quiet', author('路人2'), DateTime(2026, 10, 31, 17, 0)),
      ],
    );
    expect(events.map((e) => e.kind).toList(), [
      TopicEventKind.started,
      TopicEventKind.post,
      TopicEventKind.boardOn,
      TopicEventKind.peak,
      TopicEventKind.post,
      TopicEventKind.boardOff,
      TopicEventKind.now,
    ]);
    expect(events[1].status!.id, 'media');
    expect(events[3].at, DateTime(2026, 10, 31, 16));
    expect(events[4].status!.id, 'loud');
    expect(events[5].detail, '在榜1小时31分钟');
    expect(events.last.detail, '阅读 1377万');
  });

  test('a newest-first pager joins a refresh onto what it already has', () async {
    var round = 0;
    final pager = PagingController<String>(
      id: (item) => item,
      keepTailOnRefresh: true,
      fetch: (cursor) async {
        if (cursor != null) return const PageResult(['c', 'd'], 'end');
        round++;
        return round == 1
            ? const PageResult(['a', 'b'], 'p2')
            : const PageResult(['new', 'a'], 'p2-fresh');
      },
    );
    await pager.refresh();
    await pager.loadMore();
    await pager.refresh();
    expect(pager.items, ['new', 'a', 'b', 'c', 'd']);
    expect(pager.cursor, 'end');
  });

  test('isVideoLink recognises Weibo video pages only', () {
    expect(isVideoLink('https://video.weibo.com/show?fid=1034:5221234567890123'), isTrue);
    expect(isVideoLink('https://weibo.com/tv/show/1034:5221234567890123'), isTrue);
    expect(isVideoLink('https://m.weibo.cn/s/video/show?object_id=1034:5221234567890123'), isTrue);
    expect(isVideoLink('https://weibo.cn/sinaurl?u=https%3A%2F%2Fexample.com'), isFalse);
    expect(isVideoLink('http://t.cn/A6abcdEf'), isFalse);
  });

  test('parseHotBand tags entries of the other boards with their board', () {
    final board = parseHotBand({
      'band_list': [
        {'word': '男子遭女技师侵犯涉事会所已停业', 'word_scheme': '#男子遭女技师侵犯涉事会所已停业#', 'num': 1516134,
          'category': '辟谣/通报', 'icon_desc': '热', 'icon_desc_color': '#ff9406', 'rank': 0, 'realpos': 1},
      ],
    }, board: HotBoard.social);
    expect(board.single.board, HotBoard.social);
    expect(board.single.rankText, '社会榜第1');
    expect(board.single.isTopic, isTrue);
    expect(board.single.label, '热');
  });

  test('parseSearchSuggestions reads completions and accounts', () {
    final result = parseSearchSuggestions({
      'hotquery': [
        {'suggestion': '华为mate90', 'count': 1, 'top_flag': 2},
        {'suggestion': '华为', 'top_flag': 0},
        {'suggestion': '华为'},
      ],
      'users': [
        {'id': 1839167003, 'screen_name': '华为终端', 'followers_count': 100},
      ],
    });
    expect(result.words.map((w) => w.word), ['华为mate90', '华为']);
    expect(result.words.first.hot, isTrue);
    expect(result.words.last.hot, isFalse);
    expect(result.users.single.screenName, '华为终端');
  });

  test('parseTopicInfo reads the label-first stats line and the host', () {
    final info = parseTopicInfo({
      'cardlistInfo': {
        'cardlist_head_cards': [
          {
            'head_data': {
              'title': '#话题#',
              'portrait_url': 'https://wx3.sinaimg.cn/large/a.jpg',
              'midtext': '阅读量501.5万  讨论量1929  详情>',
              'downtext': '主持人：追剧大赏 | 14家媒体发布',
            },
          },
        ],
      },
    })!;
    expect(info.reads, 5015000);
    expect(info.discussions, 1929);
    expect(info.host, '追剧大赏');
    expect(info.note, '14家媒体发布');
  });

  test('parseTopicDetail reads counts, host and board stints', () {
    final info = parseTopicDetail({
      'baseInfo': {
        'count': {'read': 5229388, 'mention': 2044, 'ori_m': 1003, 'interact': 12172},
        'claim_info': {'screen_name': '追剧大赏', 'idstr': '6260534625'},
        'object': {'summary': '', 'image': {'url': 'https://wx3.sinaimg.cn/large/b.jpg'}},
        'dim_data': {'content': '剧集领域热度第1名'},
        'lists_users': [
          {'id': 7398996614, 'screen_name': '贡献者'},
        ],
      },
      'baseData': {
        'm_rank_pos_duration': {
          'data': [
            {'cate_desc': '热搜榜', 'top_pos': 1, 'duration_minute': 36},
          ],
        },
      },
      'media_info': {'show_str': '14家媒体', 'users': []},
    })!;
    expect(info.reads, 5229388);
    expect(info.discussions, 2044);
    expect(info.lead, isNull);
    expect(info.hostId, '6260534625');
    expect(info.highlight, '剧集领域热度第1名');
    expect(info.boards.single.bestRank, 1);
    expect(info.boards.single.minutes, 36);
    expect(info.contributors.single.screenName, '贡献者');
    expect(info.note, '14家媒体发布');
  });

  test('parseRootComment reads the comment a reply thread hangs off', () {
    final root = parseRootComment({
      'rootComment': [
        {'id': '5358955052142106', 'text': 'Kimi，GPT，Opus哪个贵', 'user': {'id': '2843674792', 'screen_name': 'Stupid二白'}},
      ],
    }, '1');
    expect(root?.id, '5358955052142106');
    expect(root?.author.screenName, 'Stupid二白');
  });

  test('parseWeiboResult recognises login-required responses', () {
    final result = parseWeiboResult({'ok': -100, 'url': 'https://passport.weibo.com/'});
    expect(result.needsLogin, isTrue);
    expect(result.loginUrl, contains('passport'));
  });

  test('a video is remembered by its path, not its signed query', () {
    const a = 'https://f.video.weibocdn.com/o0/abc.mp4?label=mp4_720p&Expires=1&ssig=x';
    const b = 'https://f.video.weibocdn.com/o0/abc.mp4?label=mp4_720p&Expires=2&ssig=y';
    expect(Prefs.videoKey(a), Prefs.videoKey(b));
    expect(Prefs.videoKey(a), '/o0/abc.mp4');
  });
}
