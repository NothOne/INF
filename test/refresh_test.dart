import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/refresh.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The detail page's shape: a scrolling header over a list that is itself the topmost scrollable.
Widget harness({
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
            SliverToBoxAdapter(child: SizedBox(height: 300, child: Placeholder())),
          ],
          body: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: 40,
            itemBuilder: (context, index) => SizedBox(height: 48, child: Text('$index')),
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

  testWidgets('a pull on the inner list refreshes once the predicate accepts its depth', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(harness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
      predicate: nestedScrollRefreshPredicate,
    ));

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(refreshes, 1);
  });

  testWidgets('the depth-0 default predicate misses the inner list', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(harness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
    ));

    await tester.fling(find.byType(ListView), const Offset(0, 320), 1200);
    await tester.pumpAndSettle();

    expect(refreshes, 0);
  });

  testWidgets('the inner list still refreshes when the header is already scrolled up', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(harness(
      onRefresh: () async {
        refreshes++;
        return true;
      },
      predicate: nestedScrollRefreshPredicate,
    ));

    // Scroll the header away, back to the top, then pull: the list is the only thing that can
    // overscroll, and that is the notification the predicate has to accept.
    await tester.drag(find.byType(ListView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(refreshes, 0);

    await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();

    expect(refreshes, 1);
  });
}
