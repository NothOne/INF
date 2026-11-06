import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/theme.dart';
import 'package:inf_flutter/features/search/search_page.dart';

/// Rows [widths] take in a [Wrap] as wide as [maxWidth]; the real thing lays them out the same way.
int wrapRows(List<double> widths, double maxWidth, {double spacing = 8}) {
  var rows = 1;
  var used = 0.0;
  for (final width in widths) {
    if (used > 0 && used + spacing + width > maxWidth) {
      rows++;
      used = width;
    } else {
      used += (used > 0 ? spacing : 0) + width;
    }
  }
  return rows;
}

void main() {
  group('collapsedChipCount', () {
    test('everything fits in two rows: nothing is hidden', () {
      expect(collapsedChipCount([100, 100], maxWidth: 400, trailingWidth: 50), 2);
      expect(collapsedChipCount([100, 100, 100], maxWidth: 400, trailingWidth: 50), 3);
    });

    test('stops on the second row and leaves room for the toggle', () {
      // 100 + 8 + 100 + 8 + 100 + 8 + 100 = 424 > 400, so three fit on each row.
      final widths = [for (var i = 0; i < 10; i++) 100.0];
      final count = collapsedChipCount(widths, maxWidth: 400, trailingWidth: 50);
      expect(count, 6);
      // The toggle shares the second row: 3 chips (316) + 8 + 50 = 374.
      expect(wrapRows([...widths.take(count), 50], 400), 2);
      // One more would need a third row, or push the toggle off the second.
      expect(wrapRows([...widths.take(count + 1), 50], 400), greaterThan(2));
    });

    test('a wide last chip does not push the toggle onto a row of its own', () {
      final count = collapsedChipCount([300, 300, 300], maxWidth: 400, trailingWidth: 80);
      expect(count, 2);
      expect(wrapRows([300, 300, 80], 400), 2);
    });

    test('a single chip wider than the line still gets counted, and one is always shown', () {
      // Each chip takes a row; the toggle cannot share the second one, so only one chip fits.
      final count = collapsedChipCount([500, 500, 500], maxWidth: 400, trailingWidth: 80);
      expect(count, 1);
      expect(wrapRows([math.min(500, 400), 80], 400), 2);
    });

    test('an empty history or no width shows nothing', () {
      expect(collapsedChipCount([], maxWidth: 400, trailingWidth: 50), 0);
      expect(collapsedChipCount([100, 100], maxWidth: 0, trailingWidth: 50), 0);
    });

    test('text scaled up folds sooner', () {
      final narrow = [for (var i = 0; i < 6; i++) 120.0];
      expect(collapsedChipCount(narrow, maxWidth: 400, trailingWidth: 50), 6);
      // 120 → 200: still one chip per 400pt line once the gap is counted, so two rows hold two.
      final wide = [for (var i = 0; i < 6; i++) 200.0];
      expect(collapsedChipCount(wide, maxWidth: 400, trailingWidth: 50), 2);
    });
  });

  group('chip widths', () {
    const entries = ['a', 'hello', '中文四个字', '搜索历史条目文本', 'a rather long search query'];

    Widget chips() => MaterialApp(
          theme: infTheme(Brightness.light, AccentTheme.brand),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in entries)
                    InputChip(
                      key: ValueKey(entry),
                      label: Text(entry, maxLines: 1, overflow: TextOverflow.ellipsis),
                      onPressed: () {},
                      onDeleted: () {},
                      deleteIcon: const Icon(Icons.close_rounded, size: 15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ActionChip(
                    key: const ValueKey('toggle'),
                    label: const Text('展开'),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );

    testWidgets('a history chip is estimated at least as wide as it lays out', (tester) async {
      await tester.pumpWidget(chips());
      final context = tester.element(find.byKey(const ValueKey('a')));
      for (final entry in entries) {
        final actual = tester.getSize(find.byKey(ValueKey(entry))).width;
        final estimate = historyChipWidth(context, entry);
        // Never short: a chip the estimate thinks fits but does not would start a third row.
        expect(estimate, greaterThanOrEqualTo(actual), reason: 'estimate for "$entry" vs $actual');
        expect(estimate - actual, lessThan(4), reason: 'estimate for "$entry" wastes $actual');
      }
      final toggle = tester.getSize(find.byKey(const ValueKey('toggle'))).width;
      final toggleEstimate = plainChipWidth(context, '展开');
      expect(toggleEstimate, greaterThanOrEqualTo(toggle));
      expect(toggleEstimate - toggle, lessThan(4), reason: 'toggle estimate vs $toggle');
    });

    testWidgets('the folded rows end where the estimate says', (tester) async {
      const widths = [120.0, 240.0, 160.0, 90.0, 200.0, 300.0, 110.0, 250.0, 140.0, 180.0];
      const line = 360.0;
      const toggleWidth = 60.0;
      const spacing = 8.0;

      Widget folded(int shown) => MaterialApp(
            theme: infTheme(Brightness.light, AccentTheme.brand),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: line,
                  child: Wrap(
                    spacing: spacing,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < shown; i++)
                        SizedBox(
                          key: ValueKey('chip$i'),
                          width: widths[i],
                          height: 40,
                          child: const InputChip(label: Text('词'), onPressed: null),
                        ),
                      SizedBox(
                        key: const ValueKey('toggle'),
                        width: toggleWidth,
                        height: 40,
                        child: const ActionChip(label: Text('展开'), onPressed: null),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

      Future<int> rows(int shown) async {
        await tester.pumpWidget(folded(shown));
        final tops = <double>{
          for (var i = 0; i < shown; i++) tester.getTopLeft(find.byKey(ValueKey('chip$i'))).dy,
          tester.getTopLeft(find.byKey(const ValueKey('toggle'))).dy,
        };
        return tops.length;
      }

      final count = collapsedChipCount(widths, maxWidth: line, trailingWidth: toggleWidth, spacing: spacing);
      expect(count, greaterThan(0));
      expect(count, lessThan(widths.length));
      expect(await rows(count), 2, reason: 'the fold and its toggle take exactly two rows');
      expect(await rows(count + 1), 3, reason: 'one more chip would take a third row');
    });

    testWidgets('few enough chips: nothing is folded', (tester) async {
      final count = collapsedChipCount([100, 100, 100], maxWidth: 400, trailingWidth: 50);
      expect(count, 3);
    });
  });
}
