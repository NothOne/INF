import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
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
}
