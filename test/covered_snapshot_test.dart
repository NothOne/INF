import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/widgets/covered_snapshot.dart';

void main() {
  bool snapshotted(WidgetTester tester, String text) => tester
      .widget<SnapshotWidget>(
        find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(SnapshotWidget)),
      )
      .controller
      .allowSnapshotting;

  testWidgets('a page is a snapshot only while a full page moves over it', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const CoveredSnapshot(child: Text('home')),
    ));
    expect(snapshotted(tester, 'home'), isFalse);

    navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const CoveredSnapshot(child: Text('next'))));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(snapshotted(tester, 'home'), isTrue);
    expect(snapshotted(tester, 'next'), isFalse, reason: 'the page opening stays live');

    await tester.pumpAndSettle();
    expect(snapshotted(tester, 'next'), isFalse);

    navigator.currentState!.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(snapshotted(tester, 'home'), isTrue);

    await tester.pumpAndSettle();
    expect(snapshotted(tester, 'home'), isFalse);
  });

  testWidgets('a sheet over the page does not freeze it', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const Scaffold(body: CoveredSnapshot(child: Text('home'))),
    ));
    showModalBottomSheet<void>(context: navigator.currentContext!, builder: (_) => const Text('sheet'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(snapshotted(tester, 'home'), isFalse);
    await tester.pumpAndSettle();
  });
}
