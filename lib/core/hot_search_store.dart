import 'package:flutter/foundation.dart';

import 'api.dart';
import 'failure.dart';
import 'models.dart';
import 'prefs.dart';
import 'session.dart';
import 'weibo_com_session.dart';

/// weibo.com's boards, shared by the home tab, the search page and the topic pages (which look
/// their entry up for its rank and heat). A board younger than [_fresh] is not fetched again.
///
/// 同城 is the one board whose content is about something the reader can change while the app runs:
/// the city is heard here and the old board is dropped, so the next look asks for the new place.
class HotSearchStore extends ChangeNotifier {
  HotSearchStore._() {
    Prefs.instance.cityNotifier.addListener(_cityChanged);
    // 我的热搜 is per account: someone else's board must not be shown under this login.
    Session.instance.registerAccountReset(_resetMine);
  }

  static final HotSearchStore instance = HotSearchStore._();
  static const _fresh = Duration(minutes: 2);

  /// The line 我的热搜 draws when the weibo.com cookie carries no account: the board exists only
  /// for a signed-in reader, and asking for it anyway is answered with a shape this app cannot
  /// read, which used to surface as a parse error.
  static const mineNeedsLogin = '登录后查看我的热搜';

  final Map<HotBoard, _Board> _boards = {for (final board in HotBoard.values) board: _Board()};

  List<HotSearch>? entriesOf(HotBoard board) => _boards[board]!.entries;
  bool loadingOf(HotBoard board) => _boards[board]!.loading;
  String? errorOf(HotBoard board) => _boards[board]!.error;
  DateTime? loadedAtOf(HotBoard board) => _boards[board]!.loadedAt;

  /// The board is unavailable until the reader signs in to weibo.com, rather than broken.
  bool needsLoginOf(HotBoard board) => _boards[board]!.needsLogin;

  List<HotSearch>? get entries => entriesOf(HotBoard.realtime);
  bool get loading => loadingOf(HotBoard.realtime);
  String? get error => errorOf(HotBoard.realtime);
  DateTime? get loadedAt => loadedAtOf(HotBoard.realtime);

  /// Completes with whether the board is available afterwards.
  Future<bool> load({HotBoard board = HotBoard.realtime, bool force = false}) {
    final state = _boards[board]!;
    final at = state.loadedAt;
    if (!force && state.entries != null && at != null && DateTime.now().difference(at) < _fresh) {
      return Future.value(true);
    }
    final running = state.inFlight;
    if (running != null && !force) return running;
    // A forced load — the reader changed the city, or asked again from the failure — goes out even
    // while an answer is on its way, and the generation retires whichever answer arrives first for
    // a request nobody is waiting for any more.
    final generation = ++state.generation;
    return state.inFlight = _fetch(board, state, generation).whenComplete(() {
      if (state.generation == generation) state.inFlight = null;
    });
  }

  Future<bool> _fetch(HotBoard board, _Board state, int generation) async {
    state.loading = true;
    state.error = null;
    state.needsLogin = false;
    notifyListeners();
    try {
      if (board == HotBoard.mine) {
        final (cookie, _) = await WeiboComSession.instance.cookie();
        if (!WeiboComSession.hasAuth(cookie)) {
          state.needsLogin = true;
          state.error = mineNeedsLogin;
          return false;
        }
      }
      // May save the city a 同城 answer names. That is the city this request asked for, so the
      // entries below do belong to it; a request sent for a city the reader has since left is
      // retired by its generation in [_cityChanged].
      final entries = await WeiboApi.instance.hotBoard(board, city: Prefs.instance.cityChoice);
      if (generation != state.generation) return false;
      state.entries = entries;
      state.loadedAt = DateTime.now();
      return true;
    } catch (e) {
      if (generation != state.generation) return false;
      state.error = Failure.from(e).message;
      return false;
    } finally {
      if (generation == state.generation) {
        state.loading = false;
        notifyListeners();
      }
    }
  }

  /// A new city is a different 同城: the entries on screen are for the old place and go, and the
  /// new city is asked for at once when 同城 was the board being looked at. Doing it here rather
  /// than in each page is what keeps the home page's 热搜 and the search page's 微博热搜 showing the
  /// same place — the city can be changed from either.
  void _cityChanged() {
    final state = _boards[HotBoard.city]!;
    final wasShowing = state.entries != null || state.error != null || state.inFlight != null;
    state.generation++;
    state.inFlight = null;
    state.entries = null;
    state.loadedAt = null;
    state.error = null;
    if (wasShowing) {
      load(board: HotBoard.city);
    } else {
      notifyListeners();
    }
  }

  /// The account is gone: its boards, and the places the reader had been, are not this one's.
  void _resetMine() {
    for (final board in const [HotBoard.mine, HotBoard.city]) {
      final state = _boards[board]!;
      state.generation++;
      state.inFlight = null;
      state.entries = null;
      state.loadedAt = null;
      state.error = null;
      state.needsLogin = false;
    }
    notifyListeners();
  }

  /// The entry for a topic name or keyword, with or without its #s; the hot-search board first.
  HotSearch? lookup(String query) {
    final needle = query.replaceAll('#', '').trim();
    if (needle.isEmpty) return null;
    for (final board in HotBoard.values) {
      for (final entry in _boards[board]!.entries ?? const <HotSearch>[]) {
        if (entry.word.replaceAll('#', '').trim() == needle) return entry;
      }
    }
    return null;
  }
}

class _Board {
  List<HotSearch>? entries;
  bool loading = false;
  bool needsLogin = false;
  String? error;
  DateTime? loadedAt;
  Future<bool>? inFlight;

  /// Counts requests so a superseded one cannot write the entries over a newer answer.
  int generation = 0;
}
