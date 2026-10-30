import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';

/// Polls unread counts every two minutes while the app is alive, exactly like the Compose shell.
class UnreadMonitor extends ChangeNotifier {
  UnreadMonitor._();
  static final UnreadMonitor instance = UnreadMonitor._();

  UnreadCounts counts = const UnreadCounts();
  Timer? _timer;
  bool _refreshing = false;

  void start() {
    Session.instance.addListener(_sessionChanged);
    refresh(force: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
  }

  void _sessionChanged() {
    if (Session.instance.state == SessionState.loggedIn) refresh(force: true);
    if (Session.instance.state == SessionState.loggedOut) {
      counts = const UnreadCounts();
      notifyListeners();
    }
  }

  Future<void> refresh({bool force = false}) async {
    if (_refreshing) return;
    final state = Session.instance.state;
    if (state != SessionState.loggedIn && !force) return;
    if (state != SessionState.loggedIn) return;
    _refreshing = true;
    try {
      final next = await WeiboApi.instance.unread();
      if (next.notifications != counts.notifications ||
          next.messages != counts.messages ||
          next.comments != counts.comments ||
          next.likes != counts.likes ||
          next.mentionsInStatuses != counts.mentionsInStatuses ||
          next.mentionsInComments != counts.mentionsInComments) {
        counts = next;
        notifyListeners();
      }
    } catch (_) {
      // A failed poll is not worth a snackbar; the next one will try again.
    } finally {
      _refreshing = false;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    Session.instance.removeListener(_sessionChanged);
    super.dispose();
  }
}