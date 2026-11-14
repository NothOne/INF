import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/widgets/status_actions.dart';
import 'package:inf_flutter/core/widgets/status_menu_route.dart';

/// Whether the panel actually *grows*, which is not the same as moving.
///
/// The travel's arithmetic was pinned by tests for a while and those passed the whole time the menu
/// was opening at its final size and sliding into place: the rectangle was interpolated, but only
/// its `left`/`top` reached the layout. These tests read the drawn widget's size off the screen, so a
/// route that computes a growing rectangle and ignores its height fails here.
void main() {
  const panelKey = ValueKey('panel');

  /// A route whose panel is a plain keyed box, so what is measured is the route's own geometry
  /// rather than anything the package draws.
  StatusMenuRoute<void> routeFor(Rect origin, Size target) => StatusMenuRoute<void>(
        origin: origin,
        actions: [
          StatusAction(icon: Icons.abc, label: 'row', run: () async {}),
        ],
        surface: (context, child, radius) => KeyedSubtree(key: panelKey, child: child),
        radius: 22,
        originRadius: 10,
      );

  /// Opens [route] over a page and returns the panel's size a moment after it starts.
  Future<Size> earlySize(WidgetTester tester, StatusMenuRoute<void> route) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(route),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    return tester.getSize(find.byKey(panelKey));
  }

  testWidgets('the menu grows in both directions, not just moves', (tester) async {
    // Opened from a point near the top: the menu rests in the middle of the screen.
    final route = routeFor(menuOriginAt(const Offset(200, 120)), const Size(268, 300));
    final early = await earlySize(tester, route);

    await tester.pump(const Duration(milliseconds: 200));
    final middle = tester.getSize(find.byKey(panelKey));

    await tester.pumpAndSettle();
    final settled = tester.getSize(find.byKey(panelKey));

    // Growing means every frame is bigger than the one before. If the height is left to the content,
    // `early.height` is already the resting height and this fails — which is exactly the defect
    // these tests exist for.
    expect(middle.width, greaterThan(early.width));
    expect(middle.height, greaterThan(early.height));
    expect(settled.height, greaterThanOrEqualTo(middle.height));
    // And never bigger than it ends up.
    expect(early.width, lessThanOrEqualTo(settled.width));
    expect(early.height, lessThanOrEqualTo(settled.height));
  });

  testWidgets('a menu opened from a point starts at the point, not at the top of the screen', (tester) async {
    final route = routeFor(menuOriginAt(const Offset(200, 900)), const Size(268, 300));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(route),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final early = tester.getRect(find.byKey(panelKey));
    // Near the finger, which was low on the screen.
    expect(early.center.dy, greaterThan(400));
  });
}
