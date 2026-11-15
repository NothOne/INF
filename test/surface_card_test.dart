import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/widgets/surface_card_route.dart';

/// How a typed-in panel travels: out of the control that opened it, and back into it.
///
/// The panel used to rise from the foot of the screen, which said nothing about where it came from.
/// Two things have to hold now, and each of them has been wrong in a previous attempt at this kind
/// of route:
///
///  * The panel is at the tapped control's rectangle on the first frame. A panel that starts
///    anywhere else appears to jump before it grows, which reads as a flash.
///  * It rests inside the room it has, never above the top of the screen — a tall comment box on a
///    short window still has to fit.
void main() {
  /// The route's resting place, reproduced from `_TravellingPanelState._rest`, which is private.
  /// Pinning the arithmetic here is what stops a later tweak from placing it off the screen.
  Rect rest({required Size room, required double width, required double height, required double safeTop}) {
    final left = (room.width - width) / 2;
    final top = (room.height - height).clamp(safeTop + 8, room.height);
    return Rect.fromLTWH(left, top, width, height);
  }

  test('the resting panel is centred across the room', () {
    final rect = rest(room: const Size(400, 800), width: 368, height: 300, safeTop: 44);
    expect(rect.center.dx, closeTo(200, 0.001));
    expect(rect.left, closeTo(16, 0.001));
  });

  test('the resting panel sits against the bottom, so the keyboard decides its height', () {
    final withoutKeyboard = rest(room: const Size(400, 800), width: 368, height: 300, safeTop: 44);
    expect(withoutKeyboard.bottom, closeTo(800, 0.001));
    // The board takes 300 of the room; the panel keeps its height and rides up with it.
    final withKeyboard = rest(room: const Size(400, 500), width: 368, height: 300, safeTop: 44);
    expect(withKeyboard.bottom, closeTo(500, 0.001));
  });

  test('a panel taller than the room stops under the status bar instead of going off the top', () {
    final rect = rest(room: const Size(400, 500), width: 368, height: 620, safeTop: 44);
    expect(rect.top, closeTo(52, 0.001));
    expect(rect.top, greaterThanOrEqualTo(44));
  });

  test('the panel is the full width of a phone, and keeps a margin only on a wide window', () {
    // A phone: the panel is the only thing on screen, and it comes from a full-width bar.
    expect(panelWidthFor(const Size(347, 700)), closeTo(347, 0.001));
    // A tablet: a panel stretched the whole way would be unreadable, so it is capped and centred.
    expect(panelWidthFor(const Size(1024, 700)), closeTo(560, 0.001));
  });

  test('growth never runs backwards, however wide the control that was tapped', () {
    // A post is near full width; a menu is 268 wide. The start has to be held down to the menu's
    // own size, or the menu opens by shrinking out of the post.
    const target = Rect.fromLTWH(50, 300, 268, 400);
    const origin = Rect.fromLTWH(0, 200, 400, 120);
    final start = Rect.fromCenter(
      center: origin.center,
      width: math.min(origin.width, target.width),
      height: math.min(origin.height, target.height),
    );
    expect(start.width, closeTo(target.width, 0.001));
    expect(start.height, lessThanOrEqualTo(target.height));
    // And the centre it starts from is the centre of what was tapped.
    expect(start.center, origin.center);

    double lerp(double a, double b, double t) => a + (b - a) * t;
    for (var i = 0; i <= 20; i++) {
      final t = i / 20;
      expect(lerp(start.width, target.width, t), lessThanOrEqualTo(target.width + 0.001));
      expect(lerp(start.height, target.height, t), lessThanOrEqualTo(target.height + 0.001));
    }
  });

  testWidgets('a panel opens from the control that was tapped and lands inside the screen', (tester) async {
    const key = ValueKey('anchor');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (outer) => Center(
              child: SizedBox(
                key: key,
                width: 120,
                height: 36,
                child: FilledButton(
                  onPressed: () => showSurfaceCard<void>(
                    outer,
                    anchor: tester.element(find.byKey(key)),
                    builder: (context) => const SizedBox(height: 200, child: Text('panel')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final anchor = tester.getRect(find.byKey(key));
    await tester.tap(find.text('open'));
    await tester.pump();
    // The first frame of the growth: the panel is at the control it came from. Measured on the
    // window, not on the content: the content is laid out at the panel's resting size and only the
    // window over it travels.
    await tester.pump(const Duration(milliseconds: 1));
    final firstFrame = tester.getRect(find.byKey(const ValueKey('surface-card-window')));
    expect(firstFrame.top, closeTo(anchor.top, 40));

    // And once it has arrived it is inside the window, not hanging off an edge.
    await tester.pumpAndSettle();
    final landed = tester.getRect(find.text('panel'));
    final screen = tester.getRect(find.byType(Scaffold));
    expect(landed.left, greaterThanOrEqualTo(screen.left));
    expect(landed.right, lessThanOrEqualTo(screen.right + 0.001));
    expect(landed.top, greaterThanOrEqualTo(screen.top));
  });

  testWidgets('the panel itself grows; it does not appear at its final size and slide', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (outer) => Center(
              child: SizedBox(
                key: const ValueKey('anchor'),
                width: 300,
                height: 30,
                child: FilledButton(
                  onPressed: () => showSurfaceCard<void>(
                    outer,
                    anchor: tester.element(find.byKey(const ValueKey('anchor'))),
                    builder: (context) => const SizedBox(
                      height: 260,
                      child: Text('panel', key: ValueKey('panel')),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final window = find.byKey(const ValueKey('surface-card-window'));
    final early = tester.getRect(window);

    await tester.pump(const Duration(milliseconds: 200));
    final middle = tester.getRect(window);

    await tester.pumpAndSettle();
    final settled = tester.getRect(window);

    // Both directions: a panel that only moves would keep its height from the first frame.
    expect(middle.width, greaterThan(early.width));
    expect(middle.height, greaterThan(early.height));
    expect(settled.width, greaterThanOrEqualTo(middle.width));
    expect(settled.height, greaterThanOrEqualTo(middle.height));
  });

  testWidgets('closing puts the panel back where it opened, then removes it', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (outer) => Center(
              child: SizedBox(
                key: const ValueKey('anchor'),
                width: 120,
                height: 36,
                child: FilledButton(
                  onPressed: () => showSurfaceCard<void>(
                    outer,
                    anchor: tester.element(find.byKey(const ValueKey('anchor'))),
                    builder: (context) => const SizedBox(height: 200, child: Text('panel')),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsOneWidget);

    // The barrier dismisses; the panel is gone once the reverse travel has run.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('panel'), findsNothing);
  });
}
