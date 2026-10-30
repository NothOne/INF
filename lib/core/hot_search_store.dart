import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

/// weibo.com's boards, shared by the home tab, the search page and the topic pages (which look
/// their entry up for its rank and heat). A board younger than [_fresh] is not fetched again.
class HotSearchStore extends ChangeNotifier {
  HotSearchStore._();

  static final HotSearchStore instance = HotSearchStore._();
  static const _fresh = Duration(minutes: 2);

  final Map<HotBoard, _Board> _boards = {for (final board in HotBoard.values) board: _Board()};

  List<HotSearch>? entriesOf(HotBoard board) => _boards[board]!.entries;
  bool loadingOf(HotBoard board) => _boards[board]!.loading;
  String? errorOf(HotBoard board) => _boards[board]!.error;
  DateTime? loadedAtOf(HotBoard board) => _boards[board]!.loadedAt;

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
    return state.inFlight ??= _fetch(board, state).whenComplete(() => state.inFlight = null);
  }

  Future<bool> _fetch(HotBoard board, _Board state) async {
    state.loading = true;
    state.error = null;
    notifyListeners();
    try {
      state.entries = await WeiboApi.instance.hotBoard(board);
      state.loadedAt = DateTime.now();
      return true;
    } catch (e) {
      state.error = e is ApiException ? e.message : '加载失败';
      return false;
    } finally {
      state.loading = false;
      notifyListeners();
    }
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
  String? error;
  DateTime? loadedAt;
  Future<bool>? inFlight;
}
