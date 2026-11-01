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
  final ValueNotifier<int> feedRevision = ValueNotifier(0);

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
