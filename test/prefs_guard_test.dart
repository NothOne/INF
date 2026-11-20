import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inf_flutter/core/models.dart';
import 'package:inf_flutter/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Reading preferences before they are loaded.
///
/// Almost every reader here has a natural default (`getString(...) ?? fallback`), so a missing
/// `init()` used to look exactly like "the user never set this": a test forgot to initialise and
/// read an empty block list, and nothing failed — the bug showed up later as a wrong screen. The
/// guard turns that into a stack trace in debug and costs nothing in release.
///
/// The order matters in this file: the first test must run before anything else initialises the
/// singleton.
void main() {
  test('reading before init fails loudly', () {
    expect(() => Prefs.instance.themeMode, throwsA(isA<AssertionError>()));
  });

  test('after init it reads normally', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});
    await Prefs.instance.init();

    expect(Prefs.instance.themeMode, ThemeMode.dark);
  });

  test('a value that was never written still gets its default', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();

    expect(Prefs.instance.themeMode, ThemeMode.system);
    expect(Prefs.instance.blockedIds, isEmpty);
  });

  test('non-appearance writes wake only their scoped notifiers, not global listeners', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.instance.init();

    var globalCalls = 0;
    var viewedCalls = 0;
    var draftsCalls = 0;
    var boardsCalls = 0;
    var blockedCalls = 0;
    void onGlobal() => globalCalls++;
    void onViewed() => viewedCalls++;
    void onDrafts() => draftsCalls++;
    void onBoards() => boardsCalls++;
    void onBlocked() => blockedCalls++;

    Prefs.instance.addListener(onGlobal);
    Prefs.instance.viewedNotifier.addListener(onViewed);
    Prefs.instance.draftsNotifier.addListener(onDrafts);
    Prefs.instance.hotBoardsNotifier.addListener(onBoards);
    Prefs.instance.blockedNotifier.addListener(onBlocked);
    addTearDown(() {
      Prefs.instance.removeListener(onGlobal);
      Prefs.instance.viewedNotifier.removeListener(onViewed);
      Prefs.instance.draftsNotifier.removeListener(onDrafts);
      Prefs.instance.hotBoardsNotifier.removeListener(onBoards);
      Prefs.instance.blockedNotifier.removeListener(onBlocked);
    });

    await Prefs.instance.saveViewed([
      ViewedStatus(statusId: 's1', authorName: 'A', text: 'hi', viewedAt: DateTime(2026)),
    ]);
    await Prefs.instance.saveDrafts([
      Draft(id: 1, type: DraftType.original, text: 'draft', updatedAt: DateTime(2026)),
    ]);
    await Prefs.instance.addSearch('flutter');
    await Prefs.instance.setHotBoards([HotBoard.tech, HotBoard.realtime]);

    expect(globalCalls, 0, reason: 'viewed, drafts, search history and hotBoards must not wake global Prefs listeners');
    expect(viewedCalls, 1);
    expect(draftsCalls, 1);
    expect(boardsCalls, 1);

    const user = User(id: 'u-block', screenName: '路人');
    await Prefs.instance.setBlocked(user, true);
    expect(Prefs.instance.isBlocked('u-block'), isTrue);
    expect(blockedCalls, 1);
    await Prefs.instance.setBlocked(user, false);
    expect(Prefs.instance.isBlocked('u-block'), isFalse);
    expect(blockedCalls, 2);
  });
}
