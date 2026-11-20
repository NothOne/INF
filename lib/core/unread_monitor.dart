import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'session.dart';

/// How many unread items each part of Weibo has for this account.
///
/// One poll on a timer, and one way for a screen to say "the reader is looking at this now". Those
/// two used to be five separate `refresh(force: true)` calls scattered through the shell, the
/// notification list, the message list and the profile page, each with its own idea of when it was
/// worth asking — and `force` was not even read, so a bounce between two tabs could send a request
/// per tap. What is left is a policy here: a minimum gap between requests, which a user-driven
/// refresh is allowed to skip but not to collapse.
class UnreadMonitor extends ChangeNotifier {
  UnreadMonitor._();
  static final UnreadMonitor instance = UnreadMonitor._();

  UnreadCounts counts = const UnreadCounts();

  /// The shortest gap between two requests nobody asked for. The timer polls every two minutes on
  /// its own; this is what stops a screen that rebuilds often from turning into a poll.
  static const quietGap = Duration(seconds: 30);

  /// The shortest gap between two requests even when one was asked for: the same tap arriving
  /// twice (shell and tab both reacting) must not become two requests.
  static const urgentGap = Duration(seconds: 5);

  /// Whether a request may be made now. Public and pure so the policy can be tested without a
  /// clock or a network; [refresh] is the only caller.
  static bool shouldAsk({required DateTime? lastAsked, required DateTime at, required bool immediately}) {
    if (lastAsked == null) return true;
    return at.difference(lastAsked) >= (immediately ? urgentGap : quietGap);
  }

  /// Whether [next] differs from [current] in any part. Comparing the notification total alone
  /// would miss a count moving between the four kinds, which is what happens when one is read.
  static bool sameCounts(UnreadCounts a, UnreadCounts b) =>
      a.mentionsInStatuses == b.mentionsInStatuses &&
      a.mentionsInComments == b.mentionsInComments &&
      a.comments == b.comments &&
      a.likes == b.likes &&
      a.messages == b.messages;

  Timer? _timer;
  bool _refreshing = false;
  DateTime? _askedAt;

  void start() {
    Session.instance.addListener(_sessionChanged);
    refresh(immediately: true);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
  }

  void _sessionChanged() {
    if (Session.instance.state == SessionState.loggedIn) refresh(immediately: true);
    if (Session.instance.state == SessionState.loggedOut) {
      counts = const UnreadCounts();
      _askedAt = null;
      notifyListeners();
    }
  }

  /// Asks for the counts.
  ///
  /// [immediately] is for a screen that has just been brought to the front: the reader is about to look at
  /// these numbers, so the quiet gap is skipped. It is not a promise to send a request — a second
  /// caller within [_urgentGap] joins the answer the first one is already getting.
  Future<void> refresh({bool immediately = false}) async {
    if (Session.instance.state != SessionState.loggedIn) return;
    if (_refreshing) return;
    final now = DateTime.now();
    if (!shouldAsk(lastAsked: _askedAt, at: now, immediately: immediately)) return;
    _refreshing = true;
    _askedAt = now;
    try {
      final next = await WeiboApi.instance.unread();
      if (!sameCounts(next, counts)) {
        counts = next;
        notifyListeners();
      }
    } catch (_) {
      // A failed poll is not worth a snackbar; the next one will try again. The timestamp is left
      // in place, so a service that is down is asked about at the normal pace rather than hammered.
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
