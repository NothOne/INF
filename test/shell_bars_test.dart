import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/shell_tabs.dart';
import 'package:inf_flutter/core/widgets/shell_top_bar.dart';

void main() {
  tearDown(() => shellBarsVisible.value = true);

  Widget host(Widget child, {bool ticking = true}) => MaterialApp(
        home: Scaffold(
          body: TickerMode(
            enabled: ticking,
            child: Align(alignment: Alignment.topCenter, child: child),
          ),
        ),
      );

  /// The tab pages read `MediaQuery.paddingOf(context).top` under their Scaffold for the list's top
  /// padding: with the body behind the bar that has to be the whole bar, or the list starts under it.
  testWidgets('the body sees the whole bar as its top padding', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late double padding;
    late double barHeight;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: ShellTopBar(
          child: AppBar(
            title: const Text('通知'),
            bottom: const PreferredSize(preferredSize: Size.fromHeight(47), child: SizedBox()),
          ),
        ),
        body: Builder(builder: (context) {
          padding = MediaQuery.paddingOf(context).top;
          barHeight = tester.getSize(find.byType(ShellTopBar)).height;
          return const SizedBox.expand();
        }),
      ),
    ));

    expect(barHeight, 24 + kToolbarHeight + 47);
    expect(padding, barHeight);
  });

  testWidgets('showShellBars only brings the bars back', (tester) async {
    shellBarsVisible.value = false;
    showShellBars();
    expect(shellBarsVisible.value, isTrue);
    shellBarsVisible.value = false;
    showShellBars();
    expect(shellBarsVisible.value, isTrue);
  });

  testWidgets('the bar leaves with the shell and keeps its height', (tester) async {
    await tester.pumpWidget(host(ShellTopBar(child: AppBar(title: const Text('首页')))));
    final height = tester.getSize(find.byType(ShellTopBar)).height;
    expect(height, greaterThan(0));
    final shown = tester.getTopLeft(find.text('首页'));

    shellBarsVisible.value = false;
    await tester.pumpAndSettle();

    // Room is still held: the list below does not move.
    expect(tester.getSize(find.byType(ShellTopBar)).height, height);
    // The toolbar is above the top edge, out of the list's way.
    expect(tester.getTopLeft(find.text('首页')).dy, lessThan(shown.dy));
  });

  testWidgets('a hidden bar takes no taps, nor one on its way out', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(ShellTopBar(
      child: AppBar(title: TextButton(onPressed: () => taps++, child: const Text('搜索'))),
    )));
    await tester.tap(find.text('搜索'));
    expect(taps, 1);

    shellBarsVisible.value = false;
    // The first pump only starts the slide; a frame in, it is under way.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tap(find.text('搜索'), warnIfMissed: false);
    expect(taps, 1);

    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'), warnIfMissed: false);
    expect(taps, 1);
  });

  testWidgets('a tab built ahead of time arrives with the bar where the shell says', (tester) async {
    shellBarsVisible.value = false;
    await tester.pumpWidget(host(ShellTopBar(child: AppBar(title: const Text('通知'))), ticking: false));
    // No slide: the bar starts gone, with its paused ticker left alone.
    expect(tester.getTopLeft(find.text('通知')).dy, lessThan(0));

    shellBarsVisible.value = true;
    await tester.pump();
    expect(tester.getTopLeft(find.text('通知')).dy, greaterThanOrEqualTo(0));
  });

  testWidgets('the list below does not move when the bar leaves', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: ShellTopBar(child: AppBar(title: const Text('我'))),
        body: Builder(
          builder: (context) => ListView(
            padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
            children: const [Text('第一行')],
          ),
        ),
      ),
    ));
    final top = tester.getTopLeft(find.text('第一行')).dy;

    shellBarsVisible.value = false;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('第一行')).dy, top);
  });

  testWidgets('the band under the bar leaves and returns with it', (tester) async {
    await tester.pumpWidget(host(ShellBarBand(travel: 120, child: const Text('热搜'))));
    final shown = tester.getTopLeft(find.text('热搜'));

    shellBarsVisible.value = false;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('热搜')).dy, shown.dy - 120);

    shellBarsVisible.value = true;
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('热搜')).dy, shown.dy);
  });
}
