import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/layout.dart';
import 'package:inf_flutter/core/prefs.dart';

/// Builds [probe] in a window [width] wide under the given 设备布局 preference.
Future<T> measure<T>(
  WidgetTester tester,
  double width,
  T Function(BuildContext context) probe, {
  DeviceLayout device = DeviceLayout.auto,
  double? area,
  bool? bottomBar,
}) async {
  late T result;
  Widget child = Builder(builder: (context) {
    result = probe(context);
    return const SizedBox.shrink();
  });
  if (area != null) child = ContentArea(width: area, child: child);
  if (bottomBar != null) child = ShellLayout(bottomBar: bottomBar, child: child);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: Size(width, 900)),
      child: InfLayout(device: device, child: child),
    ),
  );
  return result;
}

void main() {
  testWidgets('auto goes by the window width', (tester) async {
    expect(await measure(tester, 411, WindowClass.of), WindowClass.compact);
    expect(await measure(tester, 600, WindowClass.of), WindowClass.medium);
    expect(await measure(tester, 839, WindowClass.of), WindowClass.medium);
    expect(await measure(tester, 1280, WindowClass.of), WindowClass.expanded);
  });

  testWidgets('phone and tablet override the width', (tester) async {
    expect(await measure(tester, 1280, WindowClass.of, device: DeviceLayout.phone), WindowClass.compact);
    expect(await measure(tester, 411, WindowClass.of, device: DeviceLayout.tablet), WindowClass.medium);
    expect(await measure(tester, 1280, WindowClass.of, device: DeviceLayout.tablet), WindowClass.expanded);
  });

  testWidgets('the gutter centres a column of kContentMaxWidth in the content area', (tester) async {
    expect(await measure(tester, 411, contentGutter), 0);
    expect(await measure(tester, 1280, contentGutter), (1280 - kContentMaxWidth) / 2);
    expect(await measure(tester, 1280, contentGutter, area: 1192), (1192 - kContentMaxWidth) / 2);
    expect(await measure(tester, 1280, contentGutter, device: DeviceLayout.phone), 0);
    expect(await measure(tester, 620, contentGutter), 0);
  });

  testWidgets('tabs clear the bottom bar only when there is one', (tester) async {
    double clearance(BuildContext context) => ShellLayout.clearance(context, 104);
    expect(await measure(tester, 411, clearance, bottomBar: true), 104);
    expect(await measure(tester, 1280, clearance, bottomBar: false), 24);
    expect(await measure(tester, 1280, clearance), 104);
  });
}
