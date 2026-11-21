import '../../core/models.dart';
import '../../core/prefs.dart';

/// Where the reader is in one feed, and what has arrived above them since.
///
/// This used to be a dozen fields inside the feed's `_TimelineState`, mixed in with its slivers, its
/// pills and its measuring. Everything it decides comes from two things — the list of posts and the
/// y offset of the rows — so it is a plain class that a test can drive, and the widget is left to
/// draw what it decides.
///
/// It answers three questions:
///  * Which post the list is laid out from, so new posts load above it and never move the screen.
///  * How many new posts arrived above the one that was on top, for the 「N 条新微博」 pill.
///  * Whether the post being read survived a refresh, and when it did not, whether the way back to
///    it is still worth offering.
///
/// It does not scroll and does not draw: [onRecenter] hands the caller what to scroll to, and the
/// caller does it once it has a viewport.
class FeedReadingPosition {
  FeedReadingPosition(this.sourceKey);

  /// Which feed this is. A saved position belongs to one source, not to the app.
  final String sourceKey;

  /// The post the list is laid out from.
  String? centerId;

  /// The top-most post the reader has been at, and how far its top sits above the bar.
  ({String id, double dy})? position;

  /// The newest post before the latest refresh; 上次看到这里 is drawn above it.
  String? markerId;

  /// Posts that arrived above the top-most one seen since they arrived.
  int unread = 0;

  /// The refresh brought more new posts than one page, so how many is unknown.
  bool unreadOpen = false;

  /// The saved post lies beyond the loaded pages.
  bool canResume = false;

  /// Cumulative vertical scroll distance (logical pixels) over which the 「上次读到」 pill fades
  /// out as the reader scrolls up or down the feed.
  static const double resumeFadeDistance = 260.0;

  double _resumeScroll = 0;

  /// Current opacity of the 「上次读到」 pill: 1 when freshly offered, falling linearly to 0 as
  /// the reader scrolls.
  double get resumeOpacity =>
      !canResume ? 0.0 : (1.0 - _resumeScroll / resumeFadeDistance).clamp(0.0, 1.0);

  /// Records user scrolling while 「上次读到」 is on screen. Returns true once the pill has faded
  /// all the way out and [canResume] has been cleared.
  bool trackResumeScroll(double delta) {
    if (!canResume || delta == 0) return false;
    _resumeScroll += delta.abs();
    if (_resumeScroll >= resumeFadeDistance) {
      canResume = false;
      _resumeScroll = 0;
      return true;
    }
    return false;
  }

  /// The ids the list showed last time; the sliver above the centre is built from them.
  List<String> ids = const [];

  DateTime? _refreshedAt;

  /// Takes in the list as it is now. Returns whether the centre moved — the first page, or a
  /// refresh that lost the post being read.
  bool update(List<Status> items, DateTime? refreshedAt, {required void Function(String id, double dy) onRecenter}) {
    final next = [for (final status in items) status.id];
    if (next.isEmpty) {
      ids = next;
      return false;
    }
    if (ids.isEmpty) {
      ids = next;
      _start(items, onRecenter);
      return false;
    }
    if (refreshedAt == _refreshedAt) {
      ids = next;
      return false;
    }
    _countArrivals(next);
    // The post the feed is laid out from is still there, so the reader has not moved: only the
    // counting above is owed to the refresh. It can only be gone when the refresh found more new
    // posts than the pager could join onto what was loaded.
    var moved = false;
    final here = centerId;
    if (here == null || !next.contains(here)) {
      final previous = position;
      onRecenter(next.first, 0);
      centerId = next.first;
      if (previous != null && !next.contains(previous.id)) {
        canResume = true;
        _resumeScroll = 0;
      }
      moved = true;
    }
    _refreshedAt = refreshedAt;
    ids = next;
    return moved;
  }

  /// How many new posts the refresh put above the one that was on top.
  void _countArrivals(List<String> next) {
    // Match against the first surviving old post rather than only `ids.first`: if the old top post
    // was deleted or moved, matching only index 0 mistook it for a full-page gap.
    var added = -1;
    String? anchor;
    for (final oldId in ids) {
      final at = next.indexOf(oldId);
      if (at >= 0) {
        added = at;
        anchor = oldId;
        break;
      }
    }
    if (added > 0) {
      // Preserve an existing unread marker across consecutive background refreshes so the new count
      // accumulates instead of shrinking to just the latest batch.
      if (unread == 0 || markerId == null || !next.contains(markerId)) {
        markerId = anchor;
      }
      if (unreadOpen) {
        unread = next.length;
      } else {
        unread = (unread + added).clamp(0, next.length);
      }
    } else if (added < 0) {
      // More arrived than the pager could join onto what was loaded, so the count is not known.
      markerId = null;
      unread = next.length;
      unreadOpen = true;
    }
  }

  /// The first page shown: from where reading stopped last time when that page holds it, with what
  /// arrived since then counted against the newest post loaded last time.
  void _start(List<Status> items, void Function(String id, double dy) onRecenter) {
    final saved = Prefs.instance.feedPosition(sourceKey);
    if (saved == null) {
      centerId = items.first.id;
      onRecenter(items.first.id, 0);
      return;
    }
    position = (id: saved.id, dy: saved.dy);
    if (items.any((status) => status.id == saved.id)) {
      centerId = saved.id;
      onRecenter(saved.id, saved.dy);
    } else {
      centerId = items.first.id;
      onRecenter(items.first.id, 0);
      canResume = saved.id != items.first.id;
      _resumeScroll = 0;
    }
    final head = saved.head;
    final at = head == null ? -1 : items.indexWhere((status) => status.id == head);
    if (at > 0) {
      markerId = head;
      unread = at;
    } else if (saved.headAt != null) {
      // Nothing was claimed as read since then, so the count comes from the timestamps.
      final newer = items.where((status) => status.createdAt.isAfter(saved.headAt!)).length;
      unread = newer;
      unreadOpen = newer == items.length;
    }
  }

  /// Records where reading is, from the measured top-most visible post. [index] is its position in
  /// the list, used to notice that the reader has gone down through the new posts.
  ///
  /// Returns whether the pills changed and the caller has to rebuild.
  bool record({required String id, required int index, required double dy}) {
    position = (id: id, dy: dy);
    if (id == _savedId) {
      canResume = false;
      _resumeScroll = 0;
    }
    final next = unread > index ? index : unread;
    // Reading down through the posts that arrived means the reader has taken to the new list, so
    // the way back stops being what they want. A refresh that lost the place counts no new posts,
    // and there the offer is the only way back — it stays until it is used or scrolled away.
    final dropResume = canResume && unread > 0 && index >= 3;
    if (next == unread && !dropResume) return false;
    unread = next;
    if (dropResume) {
      canResume = false;
      _resumeScroll = 0;
    }
    return true;
  }

  /// A refresh the reader pulled asks for the newest posts, so they land on them.
  ///
  /// Keeps [markerId] so the 「上次看到这里」 divider still marks where the previous batch began
  /// as the reader scrolls down through the newly arrived posts.
  void toTop([String? topId]) {
    if (topId != null) {
      centerId = topId;
      position = (id: topId, dy: 0);
    }
    unread = 0;
    unreadOpen = false;
    canResume = false;
    _resumeScroll = 0;
  }

  /// Moves the list's anchor to a saved post found by paging down.
  void resumeAt(String id, double dy) {
    centerId = id;
    position = (id: id, dy: dy);
    canResume = false;
    _resumeScroll = 0;
  }

  /// Writes the position down. [items] is the list as it stands: the newest post actually seen
  /// stays new for next time, and when more arrived than one page nothing is claimed as read.
  void save(List<Status> items) {
    final here = position;
    if (here == null || canResume || items.isEmpty) return;
    final head = unreadOpen || unread >= items.length ? null : items[unread];
    Prefs.instance.setFeedPosition(
      sourceKey,
      FeedPosition(id: here.id, dy: here.dy, head: head?.id, headAt: head?.createdAt),
    );
  }

  String? get _savedId => Prefs.instance.feedPosition(sourceKey)?.id;
}
