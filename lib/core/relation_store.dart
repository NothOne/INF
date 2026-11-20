import 'package:flutter/foundation.dart';

import 'api.dart';
import 'failure.dart';
import 'haptics.dart';
import 'models.dart';
import 'prefs.dart';
import 'session.dart';

/// Whether this account follows each user, and whether this device has blocked them.
///
/// Before this, following was held in three places that could not see each other: a `_following` map
/// inside the search page, `UserProfile.following` on someone's own page, and whatever
/// `PeoplePagerList` was handed. Tapping 关注 in a search result and then opening that person showed
/// the old state, and tapping it again from there silently undid the first tap.
///
/// Blocking is INF's own and lives on this device only — Weibo is never told — but it is read from
/// every list, so it belongs in the same place rather than in each page's `Prefs.instance` call.
class RelationStore extends ChangeNotifier {
  RelationStore._() {
    Session.instance.registerAccountReset(reset);
  }
  static final RelationStore instance = RelationStore._();

  static const int _kept = 500;

  /// What this session changed, on top of whatever the server's answer said.
  final Map<String, bool> _following = {};
  final Set<String> _inFlight = {};
  int _generation = 0;

  /// Clears account-scoped follow overrides on sign-out or account switch.
  void reset() {
    _generation++;
    _inFlight.clear();
    if (_following.isEmpty) return;
    _following.clear();
    notifyListeners();
  }

  /// The follow state to draw for [user]: this session's change if there is one, the answer's
  /// otherwise.
  bool following(User user) => _following[user.id] ?? user.following;

  /// Whether this device hides this user's posts.
  ///
  /// Asks [Prefs] every time instead of holding a copy: a copy taken in the constructor is what used
  /// to make this store read preferences before the app had loaded them.
  bool isBlocked(String uid) => Prefs.instance.isBlocked(uid);

  void _putFollowing(String uid, bool value) {
    _following.remove(uid);
    _following[uid] = value;
    while (_following.length > _kept) {
      _following.remove(_following.keys.first);
    }
  }

  /// Follows or unfollows, and completes with the message to show — null when it worked.
  ///
  /// Optimistic, like the like button: the row flips at the tap and flips back if the request is
  /// refused, which for a request Weibo rate-limits is the common case and not worth a spinner.
  Future<String?> toggleFollowing(User user) async {
    if (!_inFlight.add(user.id)) return null;
    final gen = _generation;
    final previous = _following[user.id];
    final next = !following(user);
    _putFollowing(user.id, next);
    notifyListeners();
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await WeiboApi.instance.setFollowing(user.id, next);
      Haptic.success.play();
      return null;
    } catch (error) {
      if (_generation == gen) {
        if (previous == null) {
          _following.remove(user.id);
        } else {
          _putFollowing(user.id, previous);
        }
        notifyListeners();
      }
      Haptic.error.play();
      return Failure.from(error).message;
    } finally {
      if (_generation == gen) _inFlight.remove(user.id);
    }
  }

  /// INF's own 屏蔽: kept on this device, Weibo is not told.
  Future<void> setBlocked(User user, bool blocked) async {
    await Prefs.instance.setBlocked(user, blocked);
    notifyListeners();
  }

  /// Puts a user on Weibo's own blacklist, which is a different thing from [setBlocked]: this one
  /// the server knows about. They are kept together here because the user page offers both.
  Future<String?> blacklist(User user) async {
    try {
      await WeiboApi.instance.blacklist(user.id);
      Haptic.success.play();
      return null;
    } catch (error) {
      Haptic.error.play();
      return Failure.from(error).message;
    }
  }
}
