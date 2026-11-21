import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/api.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/parse.dart';
import 'package:inf_flutter/features/feed/feed_page.dart';

import 'fixtures/fixture.dart';

/// The home feed's source list: what weibo.com's `feed/allGroups` says the feeds are, how the
/// boards beside 热搜 are read, and whether the bar can show a four-character feed name on a phone.
void main() {
  group('feed/allGroups as the feed sources', () {
    final groups = parseWeiboComFeedGroups(Fixture.load('all_groups').data);

    test('全部关注 keeps the list id its timeline is asked for', () {
      expect(groups.followingAll?.kind, FeedKind.followingAll);
      expect(groups.followingAll?.name, '全部关注');
      expect(groups.followingAll?.id, '100011641537045');
      expect(groups.followingAll?.key, 'followingAll\u001F100011641537045');
    });

    test('a visitor account has no 特别关注, and that is not an error', () {
      // The fixture was taken from an account with no special-follow group; the feed then falls
      // back to the one with an empty id, which the page draws without asking for anything.
      expect(groups.special, isNull);
    });

    test('我的分组 contributes no custom groups, and 悄悄关注 is never one of them', () {
      expect(groups.custom, isEmpty);
      expect(groups.custom.any((source) => source.name == '悄悄关注'), isFalse);
    });

    test('最新微博 and 互相关注 are not feed sources of their own', () {
      // 最新 is the m.weibo.cn chronological feed the app already calls 最新; 互相关注 has no
      // timeline this app can read, so neither is offered.
      final names = [groups.followingAll?.name, groups.special?.name, for (final s in groups.custom) s.name];
      expect(names, isNot(contains('最新微博')));
      expect(names, isNot(contains('互相关注')));
    });

    test('特别关注 and the custom groups come out of the groups of type 0', () {
      final parsed = parseWeiboComFeedGroups({
        'groups': [
          {
            'title': '默认分组',
            'group_type': 0,
            'group': [
              {'gid': '100011', 'title': '全部关注', 'type': '1'},
              {'gid': '100091', 'title': '特别关注', 'type': '9'},
            ],
          },
          {
            'title': '我的分组',
            'group_type': 0,
            'group': [
              {'gid': '100051', 'title': '悄悄关注', 'type': '5'},
              {'gid': '4400001', 'title': '搞笑幽默', 'type': '0'},
              {'gid': '4400002', 'title': '科学探索', 'type': '0'},
            ],
          },
          {
            'title': '我的频道',
            'group_type': 1,
            'group': [
              {'gid': '102803', 'title': '热门'},
            ],
          },
        ],
      });
      expect(parsed.special?.id, '100091');
      expect(parsed.special?.kind, FeedKind.special);
      expect(parsed.custom.map((s) => s.name), ['搞笑幽默', '科学探索']);
      expect(parsed.custom.map((s) => s.kind), everyElement(FeedKind.group));
      // A channel is not a feed: reading 我的频道 here would put 热门 on the feed picker.
      expect(parsed.custom.any((s) => s.name == '热门'), isFalse);
    });

    test('the same group twice is listed once; an empty answer is empty, not a crash', () {
      final twice = parseWeiboComFeedGroups({
        'groups': [
          {
            'title': '我的分组',
            'group_type': 0,
            'group': [
              {'gid': '4400001', 'title': '搞笑幽默'},
              {'gid': '4400001', 'title': '搞笑幽默'},
            ],
          },
        ],
      });
      expect(twice.custom, hasLength(1));
      expect(parseWeiboComFeedGroups(null).custom, isEmpty);
      expect(parseWeiboComFeedGroups('not json').followingAll, isNull);
    });
  });

  group('the feed picker order', () {
    test('it is weibo.com home\'s order, with the fixed feeds at each end', () {
      final sources = orderedFeedSources(
        followingAll: const FeedSource(FeedKind.followingAll, '全部关注', '100011'),
        special: const FeedSource(FeedKind.special, '特别关注', '100091'),
        custom: const [
          FeedSource(FeedKind.group, '搞笑幽默', '4400001'),
          FeedSource(FeedKind.group, '科学探索', '4400002'),
        ],
      );
      expect(sources.map((source) => source.name), [
        '最新',
        '全部关注',
        '特别关注',
        '好友圈',
        '搞笑幽默',
        '科学探索',
        '悄悄关注',
        '我赞过的',
        '我的收藏',
      ]);
    });

    test('without the weibo.com answer the two system feeds are the plain ones', () {
      final sources = orderedFeedSources(custom: const [FeedSource(FeedKind.group, '分组', '44')]);
      expect(sources[1], FeedSource.followingAll);
      expect(sources[2], FeedSource.special);
      expect(sources[1].id, isEmpty);
      expect(sources.map((source) => source.key).toSet(), hasLength(sources.length));
    });

    test('a group both sources name is listed once, where it first appeared', () {
      final sources = orderedFeedSources(custom: const [
        FeedSource(FeedKind.group, '分组', '44'),
        FeedSource(FeedKind.group, '分组', '44'),
      ]);
      expect(sources.where((source) => source.name == '分组'), hasLength(1));
      expect(sources.map((source) => source.key).toSet(), hasLength(sources.length));
    });

    test('a saved source comes back after a restart, including 最新 under its old name', () {
      final sources = orderedFeedSources();
      // 最新 used to be stored as 全部关注's name, but its key has always been `all\u001Fall`.
      expect(FeedSource.fromKey(FeedSource.all.key, sources), FeedSource.all);
      expect(FeedSource.all.key, 'all\u001Fall');
      final group = const FeedSource(FeedKind.group, '分组', '44');
      expect(FeedSource.fromKey(group.key, [...sources, group])?.id, '44');
      // A group the account has since deleted is not a feed any more; the page starts on 最新.
      expect(FeedSource.fromKey(group.key, sources), isNull);
    });
  });

  group('我的热搜: weibo.com statuses/mineBand', () {
    // The list sits under `realtime` rather than `band_list`, and `rank` may be 0-based.
    final board = parseHotBand({
      'realtime': [
        {
          'word': '第一',
          'word_scheme': '#第一#',
          'rank': 0,
          'topic_flag': 1,
          'description': '',
          'label_name': '新',
          'icon_desc_color': '#ff3852',
          'num': 120000,
          'category': '剧集',
          'onboard_time': 1793353519,
        },
        {'word': '第二', 'rank': 1, 'num': 90000, 'icon_desc': '热', 'icon_desc_color': '#ff9406'},
      ],
    }, board: HotBoard.mine);

    test('the rows under realtime are the board, ranked from 1 however rank is written', () {
      expect(board.map((entry) => entry.rank), [1, 2]);
      expect(board.map((entry) => entry.word), ['第一', '第二']);
    });

    test('the badge, the category, the heat and the board all survive', () {
      expect(board.first.query, '#第一#');
      expect(board.first.board, HotBoard.mine);
      expect(board.first.label, '新');
      expect(board.first.category, '剧集');
      expect(board.first.heat, '12万');
      expect(board.first.onboardAt, isNotNull);
      expect(board.first.rankText, '我的热搜第1');
      expect(board.last.label, '热');
    });
  });

  group('同城: weibo.com statuses/city', () {
    final board = parseHotBand({
      'band_list': [
        {
          'query': '北京下雪',
          'display_hot': '12.3万',
          'display_info': '社会',
          'flag': 1,
          'icon_desc': '新',
          'icon_desc_color': '#ff3852',
          'topic_flag': 1,
          'image_url': 'https://simg.s.weibo.com/city.jpg',
        },
        {'query': '地铁新线', 'display_hot': 45600},
        {'query': '广告位', 'is_ad': 1},
      ],
    }, board: HotBoard.city);

    test('query is the words, and the ad row is skipped without using up a rank', () {
      expect(board, hasLength(2));
      expect(board.first.word, '北京下雪');
      expect(board.first.query, '#北京下雪#');
      expect(board.last.rank, 2);
    });

    test('display_hot is drawn as written and read as a number', () {
      // The string the board draws is the string on screen; the number beside it is what sorting
      // and the topic page use.
      expect(board.first.heat, '12.3万');
      expect(board.first.heatValue, 123000);
      expect(board.last.heat, '4.5万');
    });

    test('display_info is the line under the words, and the rest reads as any board', () {
      expect(board.first.category, '社会');
      expect(board.first.label, '新');
      expect(board.first.iconUrl, isNotNull);
      expect(board.first.rankText, '同城榜第1');
    });
  });

  group('同城 answers with the city it drew', () {
    test('a city code and name are kept as a choice', () {
      final city = parseHotCityMeta({'city_code': '800861100', 'city_name': '北京'});
      expect(city?.code, '800861100');
      expect(city?.name, '北京');
    });

    test('nothing, or a half-written answer, is no city', () {
      expect(parseHotCityMeta(null), isNull);
      expect(parseHotCityMeta({'city_code': '800861100'}), isNull);
      expect(parseHotCityMeta({'city_name': '北京'}), isNull);
      expect(parseHotCityMeta({'city_code': '', 'city_name': '北京'}), isNull);
    });
  });

  group('the home bar with a four-character feed name', () {
    Widget bar(String feedName, {double width = 360, int current = 0}) => MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                centerTitle: true,
                leadingWidth: 48,
                leading: const SizedBox.shrink(),
                title: HomeTabs(
                  pages: null,
                  current: current,
                  onSelect: (index) {},
                  feedLabel: HomeTabLabel(title: feedName, active: current == 0),
                  recommendLabel: HomeTabLabel(title: '推荐', active: current == 1),
                  boardLabel: HomeTabLabel(title: '热搜', active: current == 2),
                ),
                actions: [
                  IconButton(onPressed: () {}, icon: const Icon(Icons.search_rounded)),
                ],
              ),
            ),
          ),
        );

    Future<void> pumpAt(WidgetTester tester, double width) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
    }

    testWidgets('特别关注 is drawn whole, with its arrow, on a 360dp phone', (tester) async {
      await pumpAt(tester, 360);
      await tester.pumpWidget(bar('特别关注'));
      await tester.pumpAndSettle();

      final text = tester.widget<Text>(find.text('特别关注'));
      expect(text.overflow, TextOverflow.ellipsis);
      final rendered = tester.renderObject<RenderParagraph>(find.text('特别关注'));
      expect(rendered.didExceedMaxLines, isFalse, reason: 'a four-character name must not ellipsize');
      expect(rendered.size.width, greaterThan(60), reason: 'four characters need more than the old 56dp cap');

      // The whole bar still fits the screen: nothing is clipped by the bar's own width.
      final barWidth = tester.getSize(find.byType(HomeTabs)).width;
      expect(barWidth, lessThanOrEqualTo(360 - 48 - 48));

      // The selected tab's arrow is there, and the two short ones stay compact.
      expect(find.byIcon(Icons.arrow_drop_down_rounded), findsOneWidget);
      expect(tester.getSize(find.text('推荐')).width, lessThan(60));
    });
    testWidgets('the arrow belongs to the selected tab', (tester) async {
      await pumpAt(tester, 360);
      await tester.pumpWidget(bar('最新', current: 1));
      await tester.pumpAndSettle();
      // 推荐 is now the page in view, so the arrow is drawn on its side of the bar.
      final arrow = tester.getCenter(find.byIcon(Icons.arrow_drop_down_rounded));
      expect(arrow.dx, greaterThan(tester.getCenter(find.text('最新')).dx));
      expect(find.text('最新'), findsOneWidget);
    });

    testWidgets('我赞过的 fits too', (tester) async {
      await pumpAt(tester, 360);
      await tester.pumpWidget(bar('我赞过的'));
      await tester.pumpAndSettle();
      expect(tester.renderObject<RenderParagraph>(find.text('我赞过的')).didExceedMaxLines, isFalse);
    });
  });
}
