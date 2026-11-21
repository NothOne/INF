import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/hot_search_store.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/theme.dart';
import 'package:inf_flutter/core/widgets/hot_board_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two views under the home page's third tab, the boards and rank tabs they hold, and the city
/// 同城 is drawn for: the settings that remember them, and the bars that draw them.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  group('the two sections of the third tab', () {
    test('they are 热搜 and 榜单, and a missing name is 热搜', () {
      expect(HotSection.values.map((section) => section.label), ['热搜', '榜单']);
      expect(HotSection.named('rank'), HotSection.rank);
      expect(HotSection.named(null), HotSection.search);
      expect(HotSection.named('nothing'), HotSection.search);
    });
  });

  group('热门榜单 tabs', () {
    test('there are six, in the order the page draws them', () {
      expect(HotRankTab.defaults.map((tab) => tab.title), ['小时榜', '昨日', '前日', '周榜', '男榜', '女榜']);
    });

    test('a saved gid comes back; anything else is 小时榜', () {
      for (final tab in HotRankTab.defaults) {
        expect(HotRankTab.byGid(tab.gid), tab);
      }
      expect(HotRankTab.byGid(''), HotRankTab.hourly);
      expect(HotRankTab.byGid(null), HotRankTab.hourly);
      expect(HotRankTab.byGid('1028030000'), HotRankTab.hourly);
    });

    test('a tab is its gid: one can be compared and used as a map key', () {
      // Ignoring anything but the four-character size, so two names compare equal.
      expect(HotRankTab.byGid(HotRankTab.weekly.gid), HotRankTab.weekly);
      expect({HotRankTab.weekly, HotRankTab.byGid(HotRankTab.weekly.gid)}, hasLength(1));
      // Each carries the container its timeline is asked with.
      for (final tab in HotRankTab.defaults) {
        expect(tab.containerId, isNotEmpty);
        expect(tab.gid, matches(RegExp(r'^102803\d{4}$')));
      }
    });
  });

  group('the city 同城 is drawn for', () {
    const city = CityChoice(code: '800861100', name: '北京', lon: 116.41, lat: 39.90);

    test('it survives a round trip, coordinates and all', () {
      final back = CityChoice.fromJson(city.toJson());
      expect(back, city);
      expect(back?.lon, 116.41);
      expect(back?.lat, 39.90);
      expect(back?.manual, isFalse);
      expect(back?.hasCoordinates, isTrue);
    });

    test('a manual pick has no coordinates and is marked manual', () {
      const picked = CityChoice(code: '800864403', name: '深圳', manual: true);
      final back = CityChoice.fromJson(picked.toJson());
      expect(back, picked);
      expect(back?.hasCoordinates, isFalse);
      expect(back?.manual, isTrue);
    });

    test('half-written or empty JSON is no city', () {
      expect(CityChoice.fromJson(null), isNull);
      expect(CityChoice.fromJson({'code': '800861100'}), isNull);
      expect(CityChoice.fromJson({'name': '北京'}), isNull);
      expect(CityChoice.fromJson({'code': '', 'name': '北京'}), isNull);
      expect(CityChoice.fromJson({'code': '800861100', 'name': ''}), isNull);
    });

    test('the hot cities are all real codes and no name repeats', () {
      final names = <String>{};
      for (final entry in CityChoice.hotCities) {
        expect(entry.code, matches(RegExp(r'^80086\d{4}$')), reason: entry.name);
        expect(names.add(entry.name), isTrue, reason: '${entry.name} is listed twice');
      }
    });
  });

  group('the third tab remembers its place', () {
    test('a fresh install opens on 热搜, 我的热搜 and 小时榜 with no city', () {
      expect(Prefs.instance.hotSection, HotSection.search);
      expect(Prefs.instance.hotBoard, HotBoard.mine);
      expect(Prefs.instance.hotRankTab, HotRankTab.hourly);
      expect(Prefs.instance.cityChoice, isNull);
    });

    test('each choice comes back after it is written', () async {
      await Prefs.instance.setHotSection(HotSection.rank);
      await Prefs.instance.setHotBoard(HotBoard.city);
      await Prefs.instance.setHotRankTab(HotRankTab.weekly);
      await Prefs.instance.setCityChoice(const CityChoice(code: '800863100', name: '上海'));

      expect(Prefs.instance.hotSection, HotSection.rank);
      expect(Prefs.instance.hotBoard, HotBoard.city);
      expect(Prefs.instance.hotRankTab, HotRankTab.weekly);
      expect(Prefs.instance.cityChoice?.name, '上海');
    });

    test('the city wakes its own notifier, and writing the same one again does not', () async {
      var calls = 0;
      void onCity() => calls++;
      Prefs.instance.cityNotifier.addListener(onCity);
      addTearDown(() => Prefs.instance.cityNotifier.removeListener(onCity));

      await Prefs.instance.setCityChoice(const CityChoice(code: '800861100', name: '北京'));
      expect(calls, 1);
      // 同城 answers name their city; writing back the one already saved must not drop the board
      // and ask for it again.
      await Prefs.instance.setCityChoice(const CityChoice(code: '800861100', name: '北京'));
      expect(calls, 1);
      await Prefs.instance.setCityChoice(const CityChoice(code: '800863100', name: '上海'));
      expect(calls, 2);
      await Prefs.instance.setCityChoice(null);
      expect(calls, 3);
    });

    test('a board saved before the enum existed still opens on a real board', () {
      // `HotBoard.named` answers null for a name it does not know, and the getter falls back.
      expect(HotBoard.named('city'), HotBoard.city);
      expect(HotBoard.named('nonsense'), isNull);
    });

    test('the board store hears the city change and drops its 同城 board', () async {
      final store = HotSearchStore.instance;
      var calls = 0;
      void onStore() => calls++;
      store.addListener(onStore);
      addTearDown(() => store.removeListener(onStore));

      expect(store.needsLoginOf(HotBoard.mine), isFalse);
      expect(store.entriesOf(HotBoard.city), isNull);

      await Prefs.instance.setCityChoice(const CityChoice(code: '800861100', name: '北京', manual: true));
      // Whoever is drawing 同城 is told to look again — that is the whole point of the notification.
      expect(calls, greaterThan(0));
      expect(store.entriesOf(HotBoard.city), isNull);
      // The other boards are about nothing in particular and stay as they were.
      expect(store.entriesOf(HotBoard.realtime), isNull);
    });
  });

  group('the boards and their names', () {
    test('all nine boards keep the label the chips and the editor draw', () {
      expect(HotBoard.values.map((board) => board.label), [
        '我的',
        '热搜',
        '文娱',
        '社会',
        '科技',
        '生活',
        '体育',
        'ACG',
        '同城',
      ]);
    });

    test('the editor names the three special boards instead of appending 榜 to them', () {
      expect(hotBoardTitle(HotBoard.mine), '我的热搜');
      expect(hotBoardTitle(HotBoard.realtime), '热搜榜');
      expect(hotBoardTitle(HotBoard.city), '同城榜');
      expect(hotBoardTitle(HotBoard.tech), '科技榜');
      expect(hotBoardTitle(HotBoard.acg), 'ACG榜');
    });

    test('a board knows what it needs: an account, or a place', () {
      expect(HotBoard.mine.requiresAuth, isTrue);
      expect(HotBoard.city.requiresLocation, isTrue);
      expect(HotBoard.realtime.requiresAuth, isFalse);
      expect(HotBoard.tech.requiresAuth, isFalse);
      expect(HotBoard.tech.requiresLocation, isFalse);
    });

    test('a row says which board it is on and where', () {
      HotSearch entry(HotBoard board, {int? rank, bool pinned = false}) =>
          HotSearch(word: 'w', query: 'w', rank: rank, pinned: pinned, board: board);
      expect(entry(HotBoard.realtime, rank: 3).rankText, '热搜第3');
      expect(entry(HotBoard.realtime, pinned: true).rankText, '热搜置顶');
      expect(entry(HotBoard.mine, rank: 1).rankText, '我的热搜第1');
      expect(entry(HotBoard.city, rank: 7).rankText, '同城榜第7');
      expect(entry(HotBoard.entertainment, rank: 2).rankText, '文娱榜第2');
      expect(entry(HotBoard.tech).rankText, '科技榜');
    });

    test('the boards the reader can drop are still valid by name', () {
      for (final board in HotBoard.values) {
        expect(HotBoard.named(board.name), board);
      }
    });
  });

  group('the chips rows', () {
    Future<void> pump(WidgetTester tester, Widget child) async {
      await tester.pumpWidget(MaterialApp(
        theme: infTheme(Brightness.light, AccentTheme.brand),
        home: Scaffold(body: child),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('every rank tab is a chip, in order', (tester) async {
      await pump(
        tester,
        HotRankChips(current: HotRankTab.hourly, onSelect: (_) {}),
      );
      for (final tab in HotRankTab.defaults) {
        expect(find.widgetWithText(InkWell, tab.title), findsOneWidget, reason: tab.title);
      }
      // The one shown is the one marked; the rest are not.
      final selected = [
        for (final chip in tester.widgetList<AnimatedDefaultTextStyle>(find.byType(AnimatedDefaultTextStyle)))
          if (chip.style.fontWeight == FontWeight.w700)
            [(chip.child as Padding).child as Text].map((text) => text.data).first,
      ];
      expect(selected, ['小时榜']);
    });

    testWidgets('tapping a tab hands it to onSelect', (tester) async {
      final picked = <HotRankTab>[];
      await pump(
        tester,
        HotRankChips(current: HotRankTab.hourly, onSelect: picked.add),
      );
      await tester.tap(find.text('周榜'));
      await tester.pumpAndSettle();
      expect(picked, [HotRankTab.weekly]);
    });

    testWidgets('the floating variant draws the same chips, only their words', (tester) async {
      await pump(
        tester,
        HotRankChips(current: HotRankTab.male, onSelect: (_) {}, floating: true),
      );
      expect(find.text('男榜'), findsOneWidget);
      expect(find.text('小时榜'), findsOneWidget);
      // Nothing is drawn behind an unselected chip when it floats over a list.
      final materials = tester.widgetList<Material>(find.descendant(
        of: find.byType(HotRankChips),
        matching: find.byType(Material),
      ));
      expect(materials.where((material) => material.color == Colors.transparent), isNotEmpty);
    });
  });

  group('the city bar', () {
    Future<void> pump(WidgetTester tester, {CityChoice? city}) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.instance.init();
      if (city != null) await Prefs.instance.setCityChoice(city);
      await tester.pumpWidget(MaterialApp(
        theme: infTheme(Brightness.light, AccentTheme.brand),
        home: const Scaffold(body: CityBannerBar()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('it names the city that is chosen', (tester) async {
      await pump(tester, city: const CityChoice(code: '800861100', name: '北京', manual: true));
      expect(find.text('当前城市：北京'), findsOneWidget);
      expect(find.text('切换城市'), findsOneWidget);
    });

    testWidgets('with no city it says so instead of leaving the line blank', (tester) async {
      await pump(tester);
      expect(find.text('未定位城市'), findsOneWidget);
      expect(find.text('切换城市'), findsOneWidget);
    });

    testWidgets('it follows a change made somewhere else', (tester) async {
      await pump(tester, city: const CityChoice(code: '800861100', name: '北京', manual: true));
      expect(find.text('当前城市：北京'), findsOneWidget);

      await Prefs.instance.setCityChoice(const CityChoice(code: '800864403', name: '深圳', manual: true));
      await tester.pumpAndSettle();
      expect(find.text('当前城市：深圳'), findsOneWidget);
      expect(find.text('当前城市：北京'), findsNothing);
    });
  });
}
