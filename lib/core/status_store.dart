import 'package:flutter/foundation.dart';

import 'api.dart';
import 'entities.dart';
import 'failure.dart';
import 'haptics.dart';
import 'models.dart';
import 'prefs.dart';
import 'session.dart';

class _LikeState {
  final bool liked;

  /// The count the server gave when this device's like/same state was recorded, and how many this
  /// device has added since. Kept apart for the same reason the comment counts are: an absolute
  /// number recorded at tap time would overwrite a fresher count that arrived afterwards, and the
  /// list would go back to the number from before the page asked again.
  final int baseline;
  final int delta;

  const _LikeState(this.liked, this.baseline, [this.delta = 0]);

  int countFor(int current) => current == baseline ? (baseline + delta < 0 ? 0 : baseline + delta) : current;
}

/// A change this device made to a post's counts, kept as `baseline + delta` rather than as a new
/// absolute value.
///
/// A delta alone would be counted twice the moment a refresh brought back a server copy that
/// already included the comment. With the baseline, [StatusStore.apply] can tell the two apart: a
/// copy still showing the number from before the comment gets the delta added, and a copy that has
/// moved on (the server has counted it by now) is left as it is.
class _CountsState {
  final int baselineComments;
  final int deltaComments;
  final int baselineReposts;
  final int deltaReposts;

  const _CountsState({
    this.baselineComments = 0,
    this.deltaComments = 0,
    this.baselineReposts = 0,
    this.deltaReposts = 0,
  });

  int commentsFor(int current) =>
      current >= baselineComments && current < baselineComments + deltaComments
          ? baselineComments + deltaComments
          : current;
  int repostsFor(int current) =>
      current >= baselineReposts && current < baselineReposts + deltaReposts
          ? baselineReposts + deltaReposts
          : current;
}

/// The one place a post's like and favourite state lives. The feed, the detail page and search results all read
/// through [apply], so a tap on one screen is the same number everywhere.
///
/// A widget that shows one post should listen to [of] rather than to the store: a store-wide
/// `Listenable` rebuilds every visible row when any post anywhere is liked, which on a feed is the
/// whole screen for one tap. [of] hands back a listener that only wakes for the ids it was asked
/// about; the store decides which ids changed before it notifies.
class StatusStore extends ChangeNotifier {
  StatusStore._() {
    Session.instance.registerAccountReset(reset);
  }
  static final StatusStore instance = StatusStore._();

  final Map<String, _LikeState> _likes = {};
  final Map<String, bool> _favorites = {};
  final Map<String, _LikeState> _commentLikes = {};
  final Map<String, _CountsState> _counts = {};
  final Set<String> _inFlightLikes = {};
  final Set<String> _inFlightFavorites = {};
  final Set<String> _inFlightCommentLikes = {};
  int _generation = 0;
  final ValueNotifier<int> feedRevision = ValueNotifier(0);

  /// Upper bound per delta map so a multi-day session never grows unbounded.
  static const int _stateKept = 500;

  @visibleForTesting
  int get likeStateCount => _likes.length;

  @visibleForTesting
  int get stateKept => _stateKept;

  static void _putBounded<V>(Map<String, V> map, String key, V value) {
    map.remove(key);
    map[key] = value;
    while (map.length > _stateKept) {
      map.remove(map.keys.first);
    }
  }

  /// Which posts (and comments) changed state since the last notification, so a listener that only
  /// cares about one of them can skip the rebuild. Filled by every write and drained by
  /// [notifyListeners].
  final Set<String> _dirty = {};

  /// Listeners registered directly per post/comment id. [AnimatedBuilder] calls [removeListener]
  /// when unmounted or switched to a new [Listenable], never `dispose()`, so storing callbacks by
  /// id and pruning empty sets guarantees zero listener leak across scrolling and rebuilds.
  final Map<String, Set<VoidCallback>> _idListeners = {};
  final Map<VoidCallback, int> _activeScoped = {};

  /// A listener for [ids] only: it wakes when one of them changed, and for no other reason.
  Listenable of(Iterable<String> ids) => _ScopedListenable(this, ids.toSet());

  void _addScoped(Set<String> ids, VoidCallback listener) {
    if (ids.isEmpty) return;
    var added = 0;
    for (final id in ids) {
      if ((_idListeners[id] ??= {}).add(listener)) added++;
    }
    if (added > 0) _activeScoped[listener] = (_activeScoped[listener] ?? 0) + added;
  }

  void _removeScoped(Set<String> ids, VoidCallback listener) {
    if (ids.isEmpty) return;
    var removed = 0;
    for (final id in ids) {
      final set = _idListeners[id];
      if (set != null && set.remove(listener)) {
        removed++;
        if (set.isEmpty) _idListeners.remove(id);
      }
    }
    if (removed > 0) {
      final left = (_activeScoped[listener] ?? 0) - removed;
      if (left <= 0) {
        _activeScoped.remove(listener);
      } else {
        _activeScoped[listener] = left;
      }
    }
  }

  @visibleForTesting
  int get scopedListenerCount => _idListeners.values.fold(0, (sum, set) => sum + set.length);

  @visibleForTesting
  int get scopedKeyCount => _idListeners.length;

  void _touch(String id) => _dirty.add(id);

  /// Drops all account-scoped state on sign-out or account switch while keeping mounted listeners
  /// attached and waking them to re-read clean state.
  void reset() {
    _generation++;
    final affected = <String>{
      ..._likes.keys,
      ..._favorites.keys,
      ..._commentLikes.keys,
      ..._counts.keys,
    };
    _likes.clear();
    _favorites.clear();
    _commentLikes.clear();
    _counts.clear();
    _inFlightLikes.clear();
    _inFlightFavorites.clear();
    _inFlightCommentLikes.clear();
    _longTextRequests.clear();
    _longTexts.clear();
    _dirty.addAll(affected);
    notifyListeners();
  }

  @override
  void notifyListeners() {
    final changed = Set<String>.of(_dirty);
    _dirty.clear();
    super.notifyListeners();
    if (changed.isEmpty) return;
    final toWake = <VoidCallback>{};
    for (final id in changed) {
      final listeners = _idListeners[id];
      if (listeners != null) toWake.addAll(listeners);
    }
    for (final listener in toWake) {
      if (_activeScoped.containsKey(listener)) listener();
    }
  }

  /// The feed cuts a long post at six lines and links to the rest, so the detail page has to ask
  /// for the whole text — by the time it is pushed the tap has usually already started that.
  final Map<String, Future<({String text, Map<String, WeiboLink> links})?>> _longTextRequests = {};
  final Map<String, ({String text, Map<String, WeiboLink> links})> _longTexts = {};

  /// How many long texts stay around: enough for the posts a session opens, and the oldest goes
  /// first. Each one is a few kilobytes of text.
  static const int _longTextKept = 50;

  /// The whole text of a long post, fetched once per id while it is remembered. A failure is not
  /// remembered, so the next tap asks again; there is no retry loop, which Weibo reads as abuse.
  /// Errors reach whoever asked, as before; a prefetch taps the future's errors away.
  Future<({String text, Map<String, WeiboLink> links})?> longText(String id) {
    final done = _longTexts[id];
    if (done != null) return Future.value(done);
    final pending = _longTextRequests[id];
    if (pending != null) return pending;
    return _longTextRequests[id] = WeiboApi.instance.longText(id).then((value) {
      _longTextRequests.remove(id);
      if (value != null) {
        _longTexts[id] = value;
        if (_longTexts.length > _longTextKept) _longTexts.remove(_longTexts.keys.first);
      }
      return value;
    }, onError: (Object error, StackTrace stack) {
      _longTextRequests.remove(id);
      Error.throwWithStackTrace(error, stack);
    });
  }

  /// The whole text if it has already arrived, so a page can show it on its first frame.
  ({String text, Map<String, WeiboLink> links})? longTextNow(String id) => _longTexts[id];

  /// The post as every screen should draw it: the copy [Entities] holds, with this device's own
  /// changes laid over it.
  ///
  /// The base is looked up by id rather than taken from the caller. A row holds the copy its list
  /// parsed, which may be older or poorer than what the app now knows — a long post whose full text
  /// a detail page fetched, a count a fresh fetch corrected. Reading through here means the row
  /// draws the better copy without the list having to re-parse or replace anything.
  Status apply(Status status) {
    final base = Entities.instance.status(status.id) ?? status;
    final state = _likes[base.id];
    final favorited = _favorites[base.id];
    final counts = _counts[base.id];
    if (state == null && favorited == null && counts == null) return base;
    return base.copyWith(
      liked: state?.liked,
      likesCount: state?.countFor(base.likesCount),
      favorited: favorited,
      commentsCount: counts?.commentsFor(base.commentsCount),
      repostsCount: counts?.repostsFor(base.repostsCount),
    );
  }

  /// Counts a comment this device just posted. The detail page used to raise only its own copy of
  /// the post, so the card in the list behind it showed the old number again on the way back.
  void addComment(Status status, {int by = 1}) => _bump(status.id, comments: by);

  /// Counts a repost this device just made.
  void addRepost(Status status, {int by = 1}) => _bump(status.id, reposts: by);

  /// For a page that only has the post's id and counts — a notification replying to a comment.
  ///
  /// The counts passed here are only used when the app has never seen the post: a notification
  /// carries a snapshot that is usually older than what is stored, and taking its baseline would
  /// put the count back.
  void addCommentById(String statusId, {required int commentsCount, required int repostsCount, int by = 1}) =>
      _bump(statusId, comments: by, fallbackComments: commentsCount, fallbackReposts: repostsCount);

  void _bump(
    String statusId, {
    int comments = 0,
    int reposts = 0,
    int? fallbackComments,
    int? fallbackReposts,
  }) {
    final current = _counts[statusId];
    // The baseline is the count as the app knows it, which is the stored copy rather than whatever
    // the caller happens to hold: a notification's snapshot, or a row's older parse, would otherwise
    // become the number every screen counts from.
    final known = Entities.instance.status(statusId);
    final commentsNow = known?.commentsCount ?? fallbackComments ?? 0;
    final repostsNow = known?.repostsCount ?? fallbackReposts ?? 0;
    _touch(statusId);
    _putBounded(
      _counts,
      statusId,
      _CountsState(
        // A second comment on the same post keeps the first baseline and adds to the delta, so two
        // comments count as two.
        baselineComments: current?.baselineComments ?? commentsNow,
        deltaComments: (current?.deltaComments ?? 0) + comments,
        baselineReposts: current?.baselineReposts ?? repostsNow,
        deltaReposts: (current?.deltaReposts ?? 0) + reposts,
      ),
    );
    notifyListeners();
  }

  /// Completes with the message to show.
  Future<String> toggleFavorite(Status status) async {
    if (!_inFlightFavorites.add(status.id)) return apply(status).favorited ? '已收藏' : '已取消收藏';
    final gen = _generation;
    final next = !apply(status).favorited;
    _putBounded(_favorites, status.id, next);
    _touch(status.id);
    notifyListeners();
    try {
      await WeiboApi.instance.setFavorited(status.id, next);
      Haptic.success.play();
      return next ? '已收藏' : '已取消收藏';
    } catch (error) {
      if (_generation == gen) {
        _putBounded(_favorites, status.id, !next);
        _touch(status.id);
        notifyListeners();
      }
      Haptic.error.play();
      return Failure.from(error).message;
    } finally {
      if (_generation == gen) _inFlightFavorites.remove(status.id);
    }
  }

  /// The post as parsed, filed away so every screen reads the same copy.
  ///
  /// Called by whatever gets an answer: a pager's fetch, a detail page's own request, a list's
  /// cached first page. Filing it here rather than having each page keep its own copy is what
  /// makes the detail page's whole text show up in the feed's truncated card after going back.
  /// Pass [notify] when an async update (such as fetching full text or refreshing a detail view)
  /// should wake mounted cards watching this id immediately.
  Status remember(Status status, {bool notify = false}) {
    final previous = Entities.instance.status(status.id);
    final stored = Entities.instance.put(status);
    if (notify && previous != null && !identical(previous, stored)) {
      _touch(status.id);
      notifyListeners();
    }
    return stored;
  }

  /// Files a post into [Entities] so every screen reads the latest server copy.
  ///
  /// Does not populate [_likes]: only posts the user actually liked/unliked on this device carry a
  /// local delta entry, keeping [_likes] small and letting fresh server counts pass straight through
  /// for untouched posts.
  void seed(Status status) => remember(status);

  /// Files [status] only if [Entities] has never seen it, so a recycled list card never overwrites
  /// fresher counts fetched by a detail screen or a later refresh.
  void seedIfAbsent(Status status) => Entities.instance.putIfAbsent(status);

  /// Files a page's worth of posts, for a pager that just parsed them.
  void rememberAll(Iterable<Status> statuses) {
    for (final status in statuses) {
      remember(status);
    }
  }

  Future<String?> toggleLike(Status status) async {
    if (!_inFlightLikes.add(status.id)) return null;
    final gen = _generation;
    final base = Entities.instance.status(status.id) ?? status;
    final current = apply(status);
    final previous = _likes[status.id];
    final next = !current.liked;
    final resetBase = previous == null || previous.baseline != base.likesCount;
    final baseline = resetBase ? base.likesCount : previous.baseline;
    final delta = (resetBase ? 0 : previous.delta) + (next ? 1 : -1);
    _putBounded(_likes, status.id, _LikeState(next, baseline, delta));
    _touch(status.id);
    notifyListeners();
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await WeiboApi.instance.setLiked(status.id, next);
      return null;
    } catch (error) {
      if (_generation == gen) {
        if (previous == null) {
          _likes.remove(status.id);
        } else {
          _putBounded(_likes, status.id, previous);
        }
        _touch(status.id);
        notifyListeners();
      }
      Haptic.error.play();
      return Failure.from(error).message;
    } finally {
      if (_generation == gen) _inFlightLikes.remove(status.id);
    }
  }

  Comment applyComment(Comment comment) {
    final state = _commentLikes[comment.id];
    return state == null ? comment : comment.copyWith(liked: state.liked, likesCount: state.countFor(comment.likesCount));
  }

  Future<String?> toggleCommentLike(Comment comment) async {
    if (!_inFlightCommentLikes.add(comment.id)) return null;
    final gen = _generation;
    final current = applyComment(comment);
    final previous = _commentLikes[comment.id];
    final next = !current.liked;
    final resetBase = previous == null || previous.baseline != comment.likesCount;
    final baseline = resetBase ? comment.likesCount : previous.baseline;
    final delta = (resetBase ? 0 : previous.delta) + (next ? 1 : -1);
    _putBounded(_commentLikes, comment.id, _LikeState(next, baseline, delta));
    _touch(comment.id);
    notifyListeners();
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await WeiboApi.instance.setCommentLiked(comment.id, next, statusId: comment.statusId);
      return null;
    } catch (error) {
      if (_generation == gen) {
        if (previous == null) {
          _commentLikes.remove(comment.id);
        } else {
          _putBounded(_commentLikes, comment.id, previous);
        }
        _touch(comment.id);
        notifyListeners();
      }
      Haptic.error.play();
      return Failure.from(error).message;
    } finally {
      if (_generation == gen) _inFlightCommentLikes.remove(comment.id);
    }
  }

  void bumpFeed() => feedRevision.value++;

  void recordViewed(Status status, {bool enabled = true}) {
    if (!enabled) return;
    final entries = Prefs.instance.viewed.where((entry) => entry.statusId != status.id).toList();
    entries.insert(
      0,
      ViewedStatus(
        statusId: status.id,
        authorName: status.author.screenName,
        avatarUrl: status.author.avatarUrl,
        text: status.text,
        viewedAt: DateTime.now(),
      ),
    );
    Prefs.instance.saveViewed(entries.take(60).toList());
  }

  void clearViewed() => Prefs.instance.saveViewed(const []);
}

/// Lightweight [Listenable] proxy that binds directly into [StatusStore._idListeners].
///
/// Unlike a nested [ChangeNotifier], this needs no `dispose()` call from [AnimatedBuilder]: its
/// [removeListener] hook cleans up the entry immediately when the widget unmounts or updates.
class _ScopedListenable implements Listenable {
  const _ScopedListenable(this._store, this._ids);

  final StatusStore _store;
  final Set<String> _ids;

  @override
  void addListener(VoidCallback listener) => _store._addScoped(_ids, listener);

  @override
  void removeListener(VoidCallback listener) => _store._removeScoped(_ids, listener);
}
