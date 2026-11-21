import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Detail-page shape: a scrolling header directly over a list (inner depth 1).
Widget nestedHarness({
  required Future<Object?> Function() onRefresh,
  ScrollNotificationPredicate? predicate,
}) {
  return MaterialApp(
    home: Scaffold(
      body: InfRefreshIndicator(
        onRefresh: onRefresh,
        notificationPredicate: predicate ?? defaultScrollNotificationPredicate,
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => const [
            SliverToBoxAdapter(child: SizedBox(height: 220, child: Center(child: Text('header')))),
          ],
          body: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 40,
            itemBuilder: (context, index) => SizedBox(height: 48, child: Text('row-$index')),
          ),
        ),
      ),
    ),
  );
}

/// Profile / hot-topic shape: NestedScrollView → TabBarView (depth 1) → inner list (depth 2).
Widget tabbedNestedHarness({
  required Future<Object?> Function() onRefresh,
}) {
  return MaterialApp(
    home: DefaultTabController(
      length: 2,
      child: Scaffold(
        body: InfRefreshIndicator(
          onRefresh: onRefresh,
          notificationPredicate: nestedScrollRefreshPredicate,
          child: NestedScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            headerSliverBuilder: (context, _) => const [
              SliverToBoxAdapter(child: SizedBox(height: 200, child: Center(child: Text('profile-header')))),
            ],
            body: TabBarView(
              children: [
                ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: 40,
                  itemBuilder: (context, index) => SizedBox(height: 48, child: Text('tab0-$index')),
                ),
                ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: 40,
                  itemBuilder: (context, index) => SizedBox(height: 48, child: Text('tab1-$index')),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  test('commitDistance caps at min(120dp, 20% viewport)', () {
    expect(InfRefreshIndicator.commitDistance(800), 120.0);
    expect(InfRefreshIndicator.commitDistance(600), 120.0);
    expect(InfRefreshIndicator.commitDistance(500), 100.0);
    expect(InfRefreshIndicator.commitDistance(400), 80.0);
  });

  testWidgets('standard list commits at min(120dp, 20%) and ignores shorter drags', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfRefreshIndicator(
            onRefresh: () async {
              refreshes++;
              return true;
            },
            child: ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: 40,
              itemBuilder: (context, index) => SizedBox(height: 48, child: Text('item-$index')),
            ),
          ),
        ),
      ),
    );

    // Default test viewport is 800x600 -> commitDistance = min(120, 120) = 120dp.
    await tester.drag(find.byType(ListView), const Offset(0, 90));
    await tester.pumpAndSettle();
    expect(refreshes, 0);

    await tester.drag(find.byType(ListView), const Offset(0, 140));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets('a pull on the inner list refreshes once the predicate accepts its depth', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(nestedHarness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
      predicate: nestedScrollRefreshPredicate,
    ));

    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pumpAndSettle();

    expect(refreshes, 1);
  });

  testWidgets('pulling the NestedScrollView header itself also refreshes', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(nestedHarness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
      predicate: nestedScrollRefreshPredicate,
    ));

    await tester.drag(find.text('header'), const Offset(0, 160));
    await tester.pumpAndSettle();

    expect(refreshes, 1);
  });

  testWidgets('the depth-0 default predicate misses the inner list', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(nestedHarness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
    ));

    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();

    expect(refreshes, 0);
  });

  testWidgets('NestedScrollView with TabBarView (depth 2) refreshes from top and after pulling back to top', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(tabbedNestedHarness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
    ));

    // Direct pull on the depth-2 inner list inside TabBarView.
    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(refreshes, 1);

    // Scroll down into the header, then pull back to the top without overscrolling past threshold.
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 160));
    await tester.pumpAndSettle();
    expect(refreshes, 1);

    // Scroll slightly down, then pull past the top in one continuous stroke.
    await tester.drag(find.byType(ListView), const Offset(0, -80));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 240));
    await tester.pumpAndSettle();
    expect(refreshes, 2);

    // Swiping horizontally between tabs must never trigger a pull-to-refresh.
    await tester.drag(find.byType(TabBarView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(refreshes, 2);
  });

  testWidgets('programmatic show() triggers onRefresh and false shows error feedback', (tester) async {
    final key = GlobalKey<InfRefreshIndicatorState>();
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: InfRefreshIndicator(
            key: key,
            onRefresh: () async {
              refreshes++;
              return false;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [SizedBox(height: 100)],
            ),
          ),
        ),
      ),
    );

    final future = key.currentState!.show();
    await tester.pumpAndSettle();
    await future;

    expect(refreshes, 1);
    expect(find.text('刷新失败'), findsOneWidget);
  });
}
