import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/status_actions.dart';
import 'package:inf_flutter/core/widgets/status_menu_geometry.dart';
import 'package:inf_flutter/core/widgets/status_menu_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // A row plays a selection haptic, which reads the haptics setting.
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });
  group('the menu travels from the widget held to the middle of the screen', () {
    const screen = Size(400, 800);
    const safe = EdgeInsets.only(top: 48, bottom: 24);

    StatusMenuGeometry geometry(Rect origin) => StatusMenuGeometry.centred(
          origin: origin,
          screen: screen,
          safe: safe,
          menu: const Size(268, 300),
        );

    test('rests centred across, whatever the card was', () {
      for (final origin in [
        const Rect.fromLTWH(0, 100, 400, 200),
        const Rect.fromLTWH(16, 600, 368, 120),
        const Rect.fromLTWH(300, 60, 80, 40),
      ]) {
        final target = geometry(origin).target;
        expect(target.center.dx, closeTo(screen.width / 2, 1e-9));
        expect(target.width, closeTo(268, 1e-9));
      }
    });

    test('starts exactly on the widget that was held', () {
      const origin = Rect.fromLTWH(20, 500, 360, 140);
      expect(geometry(origin).rectAt(0), origin);
    });

    test('arrives exactly at its resting rectangle', () {
      const origin = Rect.fromLTWH(20, 500, 360, 140);
      final g = geometry(origin);
      expect(g.rectAt(1), g.target);
    });

    test('moves one way only, never back toward the card', () {
      const origin = Rect.fromLTWH(20, 700, 360, 100);
      final g = geometry(origin);
      var previous = g.rectAt(0);
      for (var i = 1; i <= 100; i++) {
        final rect = g.rectAt(i / 100);
        expect(rect.center.dy, lessThanOrEqualTo(previous.center.dy + 1e-9),
            reason: 'at t=${i / 100}');
        previous = rect;
      }
    });

    test('stays clear of the safe area on a short screen', () {
      final g = StatusMenuGeometry.centred(
        origin: const Rect.fromLTWH(0, 100, 400, 200),
        screen: const Size(400, 300),
        safe: const EdgeInsets.only(top: 48, bottom: 24),
        menu: const Size(268, 260),
      );
      expect(g.target.top, greaterThanOrEqualTo(safe.top + 12));
    });

    test('a narrow screen wins over the preferred width', () {
      final g = StatusMenuGeometry.centred(
        origin: const Rect.fromLTWH(0, 100, 300, 200),
        screen: const Size(320, 700),
        safe: EdgeInsets.zero,
        menu: const Size(268, 200),
      );
      // 268 fits inside 320 - 32, so the preferred width stands.
      expect(g.target.width, closeTo(268, 1e-9));

      final narrower = StatusMenuGeometry.centred(
        origin: const Rect.fromLTWH(0, 100, 280, 200),
        screen: const Size(280, 700),
        safe: EdgeInsets.zero,
        menu: const Size(268, 200),
      );
      expect(narrower.target.width, closeTo(248, 1e-9));
    });
  });

  group('a bar menu opens against the button, not in the middle', () {
    const screen = Size(400, 800);
    const safe = EdgeInsets.only(top: 48, bottom: 24);

    StatusMenuGeometry anchored(Rect origin) => StatusMenuGeometry.anchored(
          origin: origin,
          screen: screen,
          safe: safe,
          menu: const Size(268, 300),
        );

    test('hangs under a button at the top right, its far edge on the button\'s', () {
      const button = Rect.fromLTWH(340, 60, 48, 48);
      final target = anchored(button).target;
      expect(target.top, greaterThan(button.bottom), reason: 'below the button');
      expect(target.right, closeTo(button.right, 1e-9), reason: 'lined up on its edge');
      expect(target.right, lessThanOrEqualTo(screen.width));
    });

    test('lines up on the left for a button on the left', () {
      const button = Rect.fromLTWH(12, 60, 48, 48);
      final target = anchored(button).target;
      expect(target.left, closeTo(button.left, 1e-9));
      expect(target.left, greaterThanOrEqualTo(0));
    });

    test('flips above a button with no room under it', () {
      const button = Rect.fromLTWH(340, 700, 48, 48);
      final target = anchored(button).target;
      expect(target.bottom, lessThan(button.top));
    });

    test('never leaves the screen at either edge', () {
      for (final button in [
        const Rect.fromLTWH(-10, 60, 48, 48),
        const Rect.fromLTWH(380, 60, 48, 48),
        const Rect.fromLTWH(200, 60, 48, 48),
      ]) {
        final target = anchored(button).target;
        expect(target.left, greaterThanOrEqualTo(0), reason: '$button');
        expect(target.right, lessThanOrEqualTo(screen.width), reason: '$button');
      }
    });

    test('starts on the button and arrives at its resting place', () {
      const button = Rect.fromLTWH(340, 60, 48, 48);
      final g = anchored(button);
      expect(g.rectAt(0), button);
      expect(g.rectAt(1), g.target);
    });
  });

  group('the rows are decided once for every style', () {
    // What the menu shows does not depend on the material it is drawn in, so the order and the
    // groups are read from `statusActions` alone. Only the parts that need no stores are pinned.

    test('a destructive row always starts a group', () {
      // The shape the list relies on: the rows that act against the author are set apart.
      const plain = StatusAction(icon: Icons.copy_rounded, label: '复制', run: _noop);
      const destructive = StatusAction(
        icon: Icons.block_rounded,
        label: '屏蔽',
        destructive: true,
        startsGroup: true,
        run: _noop,
      );
      expect(plain.startsGroup, isFalse);
      expect(plain.destructive, isFalse);
      expect(destructive.startsGroup, isTrue);
      expect(destructive.destructive, isTrue);
    });
  });
  group('a row runs on a tap, never on the lift that opened the menu', () {
    testWidgets('opening and letting go runs nothing', (tester) async {
      var ran = 0;
      final actions = [
        StatusAction(icon: Icons.copy_rounded, label: '复制', run: () async => ran++),
        StatusAction(icon: Icons.link_rounded, label: '链接', run: () async => ran++),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    StatusMenuRoute<void>(
                      origin: const Rect.fromLTWH(150, 300, 100, 40),
                      actions: actions,
                      surface: (context, child, _) => Material(child: child),
                      radius: 22,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('复制'), findsOneWidget, reason: 'the menu opens on its own');

      // Dismissing without choosing runs nothing: the lift that opened the menu must not pick a row.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(ran, 0);
      expect(find.text('复制'), findsNothing);
    });

    testWidgets('tapping a row runs it, once the menu has gone', (tester) async {
      var ran = 0;
      final actions = [
        StatusAction(icon: Icons.copy_rounded, label: '复制', run: () async => ran++),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    StatusMenuRoute<void>(
                      origin: const Rect.fromLTWH(150, 300, 100, 40),
                      actions: actions,
                      surface: (context, child, _) => Material(child: child),
                      radius: 22,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(ran, 1);
      expect(find.text('复制'), findsNothing);
    });

    testWidgets('a row works on a panel that is not a Material', (tester) async {
      // The glass styles' panel is a `GlassContainer`, which is not a `Material`. A row paints its
      // press on a `Material` ancestor, so without one of its own the first tap threw "No Material
      // widget found" — and on the glass tiers only, which is why it went unnoticed on classic.
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    StatusMenuRoute<void>(
                      origin: const Rect.fromLTWH(150, 300, 100, 40),
                      actions: [
                        StatusAction(icon: Icons.copy_rounded, label: '复制', run: () async {}),
                      ],
                      surface: (context, child, _) => ColoredBox(
                        color: const Color(0xFF222222),
                        child: child,
                      ),
                      radius: 22,
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('复制'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

Future<void> _noop() async {}
