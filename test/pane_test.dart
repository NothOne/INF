import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/pane.dart';

void main() {
  late ValueNotifier<bool> open;
  late GlobalKey<DetailPaneState> paneKey;

  setUp(() {
    open = ValueNotifier<bool>(false);
    paneKey = GlobalKey<DetailPaneState>();
  });

  Future<BuildContext> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    late BuildContext list;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DetailPane(
          key: paneKey,
          emptyText: '选择一条微博',
          open: open,
          list: Builder(builder: (context) {
            list = context;
            return const SizedBox.expand();
          }),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return list;
  }

  Widget page(String name, {VoidCallback? onTap}) => Builder(
        builder: (context) => Scaffold(body: Center(child: TextButton(onPressed: onTap, child: Text(name)))),
      );

  testWidgets('empty until something opens, then back to empty', (tester) async {
    final list = await pump(tester);
    expect(find.text('选择一条微博'), findsOneWidget);
    expect(open.value, isFalse);

    paneKey.currentState!.open(list, page('A'), key: 'status:a');
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(open.value, isTrue);
    expect(paneKey.currentState!.selected.value, 'status:a');

    expect(paneKey.currentState!.back(), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    expect(open.value, isFalse);
    expect(paneKey.currentState!.selected.value, isNull);
    expect(paneKey.currentState!.back(), isFalse);
  });

  testWidgets('the list replaces, the pane stacks', (tester) async {
    final list = await pump(tester);
    final pane = paneKey.currentState!;

    late BuildContext inside;
    pane.open(list, Builder(builder: (context) {
      inside = context;
      return page('A');
    }), key: 'status:a');
    await tester.pumpAndSettle();

    pane.open(inside, page('A2'), key: 'user:1');
    await tester.pumpAndSettle();
    expect(find.text('A2'), findsOneWidget);
    expect(pane.selected.value, 'status:a');

    pane.open(list, page('B'), key: 'status:b');
    await tester.pumpAndSettle();
    expect(find.text('B'), findsOneWidget);
    expect(find.text('A'), findsNothing);
    expect(find.text('A2'), findsNothing);
    expect(pane.selected.value, 'status:b');

    // One step back from a replaced entry empties the pane.
    pane.back();
    await tester.pumpAndSettle();
    expect(open.value, isFalse);
  });

  testWidgets('opening the open entry again goes back to its first page', (tester) async {
    final list = await pump(tester);
    final pane = paneKey.currentState!;

    late BuildContext inside;
    pane.open(list, Builder(builder: (context) {
      inside = context;
      return page('A');
    }), key: 'status:a');
    await tester.pumpAndSettle();
    pane.open(inside, page('A2'), key: 'user:1');
    await tester.pumpAndSettle();

    pane.open(list, page('A again'), key: 'status:a');
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    expect(find.text('A2'), findsNothing);
    expect(find.text('A again'), findsNothing);
  });
}
