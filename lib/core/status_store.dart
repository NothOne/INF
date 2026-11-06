import 'package:flutter/foundation.dart';

import 'api.dart';
import 'haptics.dart';
import 'models.dart';
import 'prefs.dart';

class _LikeState {
  final bool liked;
  final int count;
  const _LikeState(this.liked, this.count);
}

/// The one place a post's like and favourite state lives. The feed, the detail page and search results all read
/// through [apply], so a tap on one screen is the same number everywhere.
class StatusStore extends ChangeNotifier {
  StatusStore._();
  static final StatusStore instance = StatusStore._();

  final Map<String, _LikeState> _likes = {};
  final Map<String, bool> _favorites = {};
  final Map<String, _LikeState> _commentLikes = {};
  final ValueNotifier<int> feedRevision = ValueNotifier(0);

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

  Status apply(Status status) {
    final state = _likes[status.id];
    final favorited = _favorites[status.id];
    if (state == null && favorited == null) return status;
    return status.copyWith(liked: state?.liked, likesCount: state?.count, favorited: favorited);
  }

  /// Completes with the message to show.
  Future<String> toggleFavorite(Status status) async {
    final next = !apply(status).favorited;
    _favorites[status.id] = next;
    notifyListeners();
    try {
      await WeiboApi.instance.setFavorited(status.id, next);
      Haptic.success.play();
      return next ? '已收藏' : '已取消收藏';
    } catch (error) {
      _favorites[status.id] = !next;
      notifyListeners();
      Haptic.error.play();
      return error is ApiException ? error.message : '操作失败';
    }
  }

  void seed(Status status) {
    _likes.putIfAbsent(status.id, () => _LikeState(status.liked, status.likesCount));
  }

  Future<String?> toggleLike(Status status) async {
    final current = apply(status);
    final next = !current.liked;
    _likes[status.id] = _LikeState(next, (current.likesCount + (next ? 1 : -1)).clamp(0, 1 << 62));
    notifyListeners();
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await WeiboApi.instance.setLiked(status.id, next);
      return null;
    } catch (error) {
      _likes[status.id] = _LikeState(current.liked, current.likesCount);
      notifyListeners();
      Haptic.error.play();
      return error is ApiException ? error.message : '操作失败';
    }
  }

  Comment applyComment(Comment comment) {
    final state = _commentLikes[comment.id];
    return state == null ? comment : comment.copyWith(liked: state.liked, likesCount: state.count);
  }

  Future<String?> toggleCommentLike(Comment comment) async {
    final current = applyComment(comment);
    final next = !current.liked;
    _commentLikes[comment.id] = _LikeState(next, (current.likesCount + (next ? 1 : -1)).clamp(0, 1 << 62));
    notifyListeners();
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await WeiboApi.instance.setCommentLiked(comment.id, next, statusId: comment.statusId);
      return null;
    } catch (error) {
      _commentLikes[comment.id] = _LikeState(current.liked, current.likesCount);
      notifyListeners();
      Haptic.error.play();
      return error is ApiException ? error.message : '操作失败';
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
