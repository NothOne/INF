import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/theme.dart';
import 'package:inf_flutter/core/widgets/city_picker_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A page with one button that opens the sheet, plus a slot for what it answered. The sheet is
/// awaited by the page rather than returned from `pumpWidget`, so the answer is read here.
class _Page extends StatefulWidget {
  const _Page({this.current, this.onLocate});

  final CityChoice? current;
  final Future<CityChoice?> Function()? onLocate;

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  CityChoice? answer;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () async {
            final city = await showCityPickerSheet(context, current: widget.current, onLocate: widget.onLocate);
            if (mounted) setState(() => answer = city);
          },
          child: const Text('open'),
        ),
      ),
    );
  }
}

void main() {
  // Choosing a city plays a haptic, which reads the haptics setting.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  group('searchWeiboCities', () {
    test('the whole name finds the one city', () {
      final matches = searchWeiboCities('北京');
      expect(matches.map((city) => city.name), ['北京']);
      expect(matches.single.code, '800861100');
    });

    test('a leading fragment lists the cities that start with it first, in table order', () {
      expect(
        searchWeiboCities('南').map((city) => city.name),
        ['南京', '南通', '南昌', '南阳', '南宁', '南充', '济南'],
      );
    });

    test('a fragment in the middle still matches', () {
      expect(searchWeiboCities('京').map((city) => city.name), ['北京', '南京']);
    });

    test('prefix matches come before the ones that only contain the query', () {
      final names = searchWeiboCities('海').map((city) => city.name).toList();
      expect(names.first, '海口');
      expect(names, containsAll(['上海', '珠海', '北海', '威海']));
    });

    test('nothing to search for matches nothing', () {
      expect(searchWeiboCities(''), isEmpty);
      expect(searchWeiboCities('   '), isEmpty);
    });

    test('a query nobody answers has no matches', () {
      expect(searchWeiboCities('不存在的城市'), isEmpty);
    });

    test('every row is a weibo city code and no name is listed twice', () {
      final names = <String>{};
      for (final city in kWeiboCities) {
        expect(city.code, matches(RegExp(r'^80086\d{4}$')), reason: city.name);
        expect(names.add(city.name), isTrue, reason: '${city.name} is listed twice');
      }
    });

    test('the hot cities are all in the table', () {
      final names = {for (final city in kWeiboCities) city.name};
      for (final city in CityChoice.hotCities) {
        expect(names, contains(city.name));
      }
    });
  });

  group('showCityPickerSheet', () {
    /// Pumps the page and opens the sheet on it.
    Future<_PageState> open(
      WidgetTester tester, {
      CityChoice? current,
      Future<CityChoice?> Function()? onLocate,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: infTheme(Brightness.light, AccentTheme.brand),
        home: _Page(current: current, onLocate: onLocate),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return tester.state<_PageState>(find.byType(_Page));
    }

    testWidgets('a hot city returns a manual choice', (tester) async {
      final page = await open(tester);
      expect(find.text('选择城市'), findsOneWidget);
      expect(find.text('热门城市'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '上海'));
      await tester.pumpAndSettle();

      expect(page.answer, const CityChoice(code: '800863100', name: '上海', manual: true));
      expect(find.text('热门城市'), findsNothing);
    });

    testWidgets('typing narrows the table and a row returns its city', (tester) async {
      final page = await open(tester);

      await tester.enterText(find.byType(TextField), '苏');
      await tester.pumpAndSettle();
      expect(find.text('热门城市'), findsNothing);
      expect(find.text('苏州'), findsOneWidget);
      expect(find.text('北京'), findsNothing);

      await tester.tap(find.text('苏州'));
      await tester.pumpAndSettle();

      expect(page.answer, const CityChoice(code: '800863205', name: '苏州', manual: true));
    });

    testWidgets('a query with no city says so instead of an empty list', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '不存在的城市');
      await tester.pumpAndSettle();
      expect(find.textContaining('没有找到'), findsOneWidget);
    });

    testWidgets('a locate that answers a city closes the sheet with it', (tester) async {
      final page = await open(
        tester,
        onLocate: () async =>
            const CityChoice(code: '800861100', name: '北京', lon: 116.4, lat: 39.9),
      );

      await tester.tap(find.text('重新定位'));
      await tester.pumpAndSettle();

      // Located, not picked: the choice keeps the coordinates it came with.
      expect(page.answer?.name, '北京');
      expect(page.answer?.lat, 39.9);
      expect(page.answer?.lon, 116.4);
      expect(page.answer?.manual, isFalse);
      expect(find.text('选择城市'), findsNothing);
    });

    testWidgets('a locate that fails leaves the list and says why', (tester) async {
      await open(tester, onLocate: () async => null);

      await tester.tap(find.text('重新定位'));
      await tester.pumpAndSettle();

      expect(find.text('定位失败，请手动选择城市'), findsOneWidget);
      // Still open, with the choices it had, and able to try again.
      expect(find.text('选择城市'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '北京'), findsOneWidget);
      expect(find.text('重新定位'), findsOneWidget);
    });

    testWidgets('the current city is the one marked', (tester) async {
      await open(tester, current: const CityChoice(code: '800864403', name: '深圳', manual: true));

      final chosen = [
        for (final chip in tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)))
          if (chip.selected) (chip.label as Text).data,
      ];
      expect(chosen, ['深圳']);
    });

    testWidgets('no locate callback, no locate button', (tester) async {
      await open(tester);
      expect(find.text('重新定位'), findsNothing);
    });
  });
}
