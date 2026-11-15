import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:inf_flutter/core/widgets/comment_sheet.dart';
import 'package:inf_flutter/core/widgets/surface_card_route.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Where the parts of the comment panel actually end up, and how much empty panel sits between the
/// field and whatever is under it.
///
/// The panel opened from the comment bar used to leave a slab of blank glass between the field and
/// the keyboard: the same keyboard height was held twice, once by the router placing the panel above
/// the keys and once by the panel's own emoji slot standing in for them. Read from the laid-out
/// widgets rather than recomputed, so a route that places things correctly but sizes them wrong
/// still fails here.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();
  });

  /// The keyboard, as the whole app sees it.
  ///
  /// Set on the test's own view rather than through a `MediaQuery` over the page: the panel is a
  /// route, built into the navigator's overlay, which is *above* anything inside `home`. A
  /// `MediaQuery` placed there never reached the panel, so the fixture said 300 and the route read
  /// 0 — every "keyboard up" case here was really a panel on an empty screen.
  void keys(WidgetTester tester, double height) {
    tester.view.viewInsets = FakeViewPadding(bottom: height);
  }

  Future<void> open(WidgetTester tester, {double keyboard = 0}) async {
    // A phone: 400 × 800 is the room the panel is placed in, and the keyboard takes 300 of it.
    tester.view
      ..devicePixelRatio = 1
      ..physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    keys(tester, keyboard);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // The bar rides above the keys by its own padding, the way `edgePanel` bars do; the
          // Scaffold must not also shrink the body for them, or the bar is lifted twice.
          resizeToAvoidBottomInset: false,
          // The comment bar, on the foot of the screen and riding above the keys — the control the
          // comment panel grows out of, and the one it has to fold back into. It moves with the
          // keyboard, which is the whole reason the panel cannot keep the rectangle it opened from.
          body: Builder(
            builder: (page) => Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(page).bottom),
                child: SizedBox(
                  key: const ValueKey('bar'),
                  width: 400,
                  height: 48,
                  child: Builder(
                    builder: (bar) => FilledButton(
                      onPressed: () => showSurfaceCard<bool>(
                        bar,
                        anchor: bar,
                        builder: (context) => CommentSheet(
                          statusId: '1',
                          onSent: () {},
                          target: Status(
                            id: '1',
                            text: '正文',
                            createdAt: DateTime(2026),
                            author: const User(id: 'u', screenName: '某人'),
                            media: const [],
                            repostsCount: 0,
                            commentsCount: 0,
                            likesCount: 0,
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('the field sits under the quoted line, with nothing between them', (tester) async {
    await open(tester);

    final quoted = tester.getRect(find.textContaining('@某人'));
    final field = tester.getRect(find.byType(TextField));
    // A padding of 2 at the foot of the quoted line, and nothing else: the field comes right after.
    expect(
      field.top - quoted.bottom,
      lessThan(8),
      reason: 'the field was pushed away from the text it answers',
    );
  });

  testWidgets('the panel ends just below its last row of controls', (tester) async {
    await open(tester);

    final field = tester.getRect(find.byType(TextField));
    final toolbar = tester.getRect(find.byIcon(Icons.alternate_email_rounded));
    final window = tester.getRect(find.byKey(const ValueKey('surface-card-window')));

    // The controls are under the field, and the panel stops soon after them: no empty tail.
    expect(toolbar.top, greaterThan(field.bottom));
    expect(
      window.bottom - toolbar.bottom,
      lessThan(40),
      reason: 'the panel carried a slab of empty glass below its own controls',
    );
  });

  testWidgets('the panel is no taller than what it holds', (tester) async {
    await open(tester);

    final window = tester.getRect(find.byKey(const ValueKey('surface-card-window')));
    final field = tester.getRect(find.byType(TextField));
    // The quoted line, the field and the controls are all the panel is; a height of several hundred
    // more than that is the empty slab.
    expect(window.height, lessThan(field.height + 260));
  });

  testWidgets('with the keyboard up, the panel still ends at its own controls', (tester) async {
    // The case that showed the slab: measured without a keyboard, the panel was fine; with the keys
    // up, 900 px of room disappeared and the panel was placed in what was left.
    await open(tester, keyboard: 300);

    final window = tester.getRect(find.byKey(const ValueKey('surface-card-window')));
    final toolbar = tester.getRect(find.byIcon(Icons.alternate_email_rounded));
    expect(
      window.bottom - toolbar.bottom,
      lessThan(40),
      reason: 'the panel carried a slab of empty glass below its own controls',
    );
    expect(
      window.top,
      greaterThanOrEqualTo(0),
      reason: 'the panel must not be laid out above the top of the room',
    );
    // The keys are 300 tall, so the panel's foot is 300 up from the bottom of the screen.
    expect(window.bottom, closeTo(800 - 300, 1));
  });

  testWidgets('the emoji board gets room when it opens, and the panel grows for it', (tester) async {
    await open(tester);
    final before = tester.getRect(find.byKey(const ValueKey('surface-card-window')));

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pumpAndSettle();

    final after = tester.getRect(find.byKey(const ValueKey('surface-card-window')));
    // The board is its own surface under the field, so opening it makes the panel taller. A panel
    // that stayed the same height was holding a height measured before the board existed, and the
    // board had nowhere to draw — which is exactly what the picker looked like.
    expect(after.height, greaterThan(before.height + 200));
    // And the panel still sits on the bottom of the room, not pushed off it.
    expect(after.bottom, closeTo(before.bottom, 1));
  });

  testWidgets('the field stays put when the board replaces the keys', (tester) async {
    // With the keys up, the panel is placed above them.
    await open(tester, keyboard: 300);
    final fieldWithKeys = tester.getRect(find.byType(TextField));
    final panelWithKeys = tester.getRect(find.byKey(const ValueKey('surface-card-window')));

    // The composer dismisses the keys and shows the board.
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    keys(tester, 0);
    await tester.pumpAndSettle();

    final fieldWithBoard = tester.getRect(find.byType(TextField));
    final panelWithBoard = tester.getRect(find.byKey(const ValueKey('surface-card-window')));

    // The field must not move: the board takes the keys' place *below* it, so what grows is the
    // panel's foot, not its top. A panel that dropped to the foot of the screen when the keys were
    // dismissed slid the field down with it, which is the jump this pins.
    expect(
      fieldWithBoard.top,
      closeTo(fieldWithKeys.top, 1),
      reason: 'the field slid when the keys were dismissed — '
          'keys: panel=$panelWithKeys field=$fieldWithKeys, '
          'board: panel=$panelWithBoard field=$fieldWithBoard',
    );
    // The panel's top is the field's side of it, so it holds too; its foot follows the room down
    // once the keys are out of the way, and the board is what now fills the space they had.
    expect(panelWithBoard.top, closeTo(panelWithKeys.top, 1));
    expect(panelWithBoard.bottom, closeTo(800, 1));
    expect(panelWithBoard.height, greaterThan(panelWithKeys.height + 200));
  });

  testWidgets('the field holds still while the keys give way to the board', (tester) async {
    await open(tester, keyboard: 300);
    final resting = tester.getRect(find.byType(TextField)).top;

    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    await tester.pump();

    // The keys take a couple of hundred milliseconds to leave. On every frame of that the field is
    // on the same line: the panel's foot follows the keys down and the board fills exactly what
    // they give up. A board that arrived at its full height on the first frame pushed the panel's
    // top — the field — up by the whole keyboard and then slid it back down, which is the move that
    // was visible on the phone.
    for (final inset in [280.0, 240.0, 180.0, 120.0, 60.0, 0.0]) {
      keys(tester, inset);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getRect(find.byType(TextField)).top,
        closeTo(resting, 1),
        reason: 'the field moved while the keys were at $inset',
      );
    }

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TextField)).top, closeTo(resting, 1));
    expect(find.byKey(const ValueKey('emoji')), findsOneWidget);
  });

  testWidgets('the field holds still when the board gives the keys back', (tester) async {
    await open(tester, keyboard: 300);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    keys(tester, 0);
    await tester.pumpAndSettle();
    final resting = tester.getRect(find.byType(TextField)).top;

    // Tapping the same button again asks for the keys. The board is not dropped in one frame — the
    // bar would fall the keyboard's height and jump back up as the keys arrived.
    await tester.tap(find.byIcon(Icons.keyboard_rounded));
    await tester.pump();

    for (final inset in [60.0, 120.0, 180.0, 240.0, 300.0]) {
      keys(tester, inset);
      await tester.pump(const Duration(milliseconds: 16));
      expect(
        tester.getRect(find.byType(TextField)).top,
        closeTo(resting, 1),
        reason: 'the field moved while the keys were at $inset',
      );
    }

    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(TextField)).top, closeTo(resting, 1));
    expect(find.byKey(const ValueKey('emoji')), findsNothing);
  });

  /// Every frame the panel spends going away, from the tap to the last one it is drawn on.
  Future<List<Rect>> dismiss(WidgetTester tester) async {
    final window = find.byKey(const ValueKey('surface-card-window'));
    await tester.tapAt(const Offset(200, 40));
    final frames = <Rect>[];
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (window.evaluate().isEmpty) break;
      frames.add(tester.getRect(window));
    }
    await tester.pumpAndSettle();
    return frames;
  }

  testWidgets('a tap outside folds the panel down into the bar, keys or board alike', (tester) async {
    // The keyboard case, for the shape the fold has to take.
    await open(tester, keyboard: 300);
    final withKeys = await dismiss(tester);

    expect(withKeys, isNotEmpty);
    // Its foot is on the bar from the first frame and never leaves it: the panel collapses *into*
    // the bar rather than flying up off the bottom of the page. The bar under the keys is at 800 −
    // 300, and the panel rests on its top edge.
    for (final rect in withKeys) {
      expect(rect.bottom, closeTo(500, 1), reason: 'the panel left the bar: $rect');
    }
    final firstKeys = withKeys.first;
    expect(firstKeys.height, lessThan(400), reason: 'the panel started folded up: $firstKeys');

    // The board case: the keys are gone by now, so the bar has dropped to the foot of the screen.
    // The panel's foot has to come down with it while it closes, or it folds into the wrong place —
    // it used to shrink into the rectangle the bar had when the panel opened, which is 300 too high.
    await open(tester, keyboard: 300);
    await tester.tap(find.byIcon(Icons.emoji_emotions_outlined));
    keys(tester, 0);
    await tester.pumpAndSettle();
    final withBoard = await dismiss(tester);

    expect(withBoard, isNotEmpty);
    // Never above the bar it is folding into, and reaching it by the end.
    for (final rect in withBoard) {
      expect(rect.bottom, closeTo(800, 1), reason: 'the panel left the bar: $rect');
    }
    expect(withBoard.last.height, lessThan(withBoard.first.height),
        reason: 'the panel did not shrink as it went: ${withBoard.first} → ${withBoard.last}');
  });

  testWidgets('the bar itself still moves with the keys while the panel is open', (tester) async {
    await open(tester, keyboard: 300);
    expect(tester.getRect(find.byKey(const ValueKey('bar'))).bottom, closeTo(500, 1));

    keys(tester, 0);
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byKey(const ValueKey('bar'))).bottom, closeTo(800, 1));
  });
}
