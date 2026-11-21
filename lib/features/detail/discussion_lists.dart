import 'package:flutter/material.dart';

import '../../core/comment_store.dart';
import '../../core/error_text.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/motion.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/comment_tile.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pager_tail.dart';
import '../../core/widgets/repost_tile.dart';
import '../../core/widgets/transitions.dart';

/// The discussion under a post: 转发 and 评论 as two lists that cross-fade into one another, with a
/// horizontal swipe between them.
///
/// This was the inside of the detail page, where it shared a file with the page shell, the bottom
/// bar, the comment rows and the reply thread. It only deals with the two lists now, and takes the
/// post it is about so it does not have to reach back into the page.
class DiscussionLists extends StatefulWidget {
  const DiscussionLists({
    super.key,
    required this.status,
    required this.comments,
    required this.reposts,
    required this.byTime,
    required this.onSort,
    required this.showingReposts,
    required this.onShowReposts,
    required this.onShowComments,
    required this.onComment,
  });

  final Status status;
  final PagingController<Comment> comments;
  final PagingController<Status> reposts;
  final bool byTime;
  final ValueChanged<bool> onSort;
  final bool showingReposts;
  final VoidCallback onShowReposts;
  final VoidCallback onShowComments;
  final void Function(BuildContext anchor) onComment;

  @override
  State<DiscussionLists> createState() => _DiscussionListsState();
}

class _DiscussionListsState extends State<DiscussionLists> {
  /// Ids from the first page, and the ones that have already played [AppearIn].
  /// A later page is not in the first set, so it is appended in place.
  final Set<String> _commentIntro = {};
  final Set<String> _repostIntro = {};
  final Set<String> _commentPlayed = {};
  final Set<String> _repostPlayed = {};
  bool _commentIntroClosed = false;
  bool _repostIntroClosed = false;

  /// A horizontal fling over the lists changes tab; a drag that starts at the screen edge belongs
  /// to the system back gesture instead.
  static const double _swipeCommit = 64;
  static const double _swipeVelocity = 300;
  static const double _edgeGuard = 24;
  double _swipeDistance = 0;
  bool _swipeFromEdge = false;

  @override
  void initState() {
    super.initState();
    widget.comments.addListener(_captureCommentIntro);
    widget.reposts.addListener(_captureRepostIntro);
    _captureCommentIntro();
    _captureRepostIntro();
  }

  @override
  void didUpdateWidget(covariant DiscussionLists oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != widget.comments) {
      oldWidget.comments.removeListener(_captureCommentIntro);
      widget.comments.addListener(_captureCommentIntro);
      _commentIntro.clear();
      _commentPlayed.clear();
      _commentIntroClosed = false;
      _captureCommentIntro();
    }
  }

  @override
  void dispose() {
    widget.comments.removeListener(_captureCommentIntro);
    widget.reposts.removeListener(_captureRepostIntro);
    super.dispose();
  }

  void _captureCommentIntro() {
    final comments = widget.comments;
    if (_commentIntroClosed || comments.loading || comments.items.isEmpty) return;
    for (final item in comments.items) {
      _commentIntro.add(item.id);
    }
    _commentIntroClosed = true;
  }

  void _captureRepostIntro() {
    final reposts = widget.reposts;
    if (_repostIntroClosed || reposts.loading || reposts.items.isEmpty) return;
    for (final item in reposts.items) {
      _repostIntro.add(item.id);
    }
    _repostIntroClosed = true;
  }

  /// True the first time a first-page row is built. Recording it here means a later rebuild,
  /// or the row leaving the screen and coming back, does not play again.
  bool _playIntro(Set<String> eligible, Set<String> played, String id) {
    if (!eligible.contains(id) || !played.add(id)) return false;
    return true;
  }

  /// Recorded at the pointer down, before the drag is recognised: by the time the horizontal
  /// gesture wins, the finger has already moved off the edge.
  void _startSwipe(DragDownDetails details) {
    final width = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    _swipeDistance = 0;
    _swipeFromEdge = x < _edgeGuard || x > width - _edgeGuard;
  }

  void _trackSwipe(DragUpdateDetails details) {
    _swipeDistance += details.delta.dx;
  }

  /// The finger moves left to reach the right-hand tab (评论) and right to reach 转发, the way the
  /// tabs sit. A drag that started at an edge is the system's, and a mostly vertical one is the list's.
  void _endSwipe(DragEndDetails details) {
    if (_swipeFromEdge) return;
    final velocity = details.primaryVelocity ?? 0;
    final bool left;
    if (velocity.abs() > _swipeVelocity) {
      left = velocity < 0;
    } else if (_swipeDistance.abs() > _swipeCommit) {
      left = _swipeDistance < 0;
    } else {
      return;
    }
    if (left && !widget.showingReposts) return;
    if (!left && widget.showingReposts) return;
    left ? widget.onShowComments() : widget.onShowReposts();
  }

  @override
  Widget build(BuildContext context) {
    final comments = widget.comments;
    final reposts = widget.reposts;
    // This is the body of the page's NestedScrollView: the post and the two tabs are its header,
    // and only these rows scroll under them. The list directly beneath sits at depth 0 here.
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.depth != 0) return false;
        (widget.showingReposts ? reposts : comments).onScroll(notification);
        return false;
      },
      child: GestureDetector(
        // Opaque so a drag that starts on the empty tail of a short list still counts.
        behavior: HitTestBehavior.opaque,
        onHorizontalDragDown: _startSwipe,
        onHorizontalDragUpdate: _trackSwipe,
        onHorizontalDragEnd: _endSwipe,
        onHorizontalDragCancel: () => _swipeDistance = 0,
        child: _DiscussionCrossfade(
          showingReposts: widget.showingReposts,
          page: _page,
        ),
      ),
    );
  }

  /// The list for a tab: `reposts` is which list, `primary` whether it drives the scroll.
  Widget _page(bool reposts, bool primary) => reposts ? _repostList(primary) : _commentList(primary);

  Widget _pagedList({
    required bool primary,
    required int count,
    required Widget Function(BuildContext, int) item,
    required Widget tail,
  }) {
    return ListView.builder(
      primary: primary,
      physics: primary ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        bottom: 28 + MediaQuery.paddingOf(context).bottom,
        left: contentGutter(context),
        right: contentGutter(context),
      ),
      itemCount: count + 1,
      itemBuilder: (context, index) => index == count ? tail : item(context, index),
    );
  }

  Widget _repostList(bool primary) {
    final reposts = widget.reposts;
    if (reposts.loading && reposts.items.isEmpty) {
      return _pagedList(primary: primary, count: 0, item: (_, _) => const SizedBox.shrink(), tail: const LoadingFooter());
    }
    if (reposts.error != null && reposts.items.isEmpty) {
      return _pagedList(
        primary: primary,
        count: 0,
        item: (_, _) => const SizedBox.shrink(),
        tail: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(child: ErrorView(error: reposts.error, onRetry: reposts.refresh)),
        ),
      );
    }
    if (reposts.items.isEmpty) {
      return _pagedList(
        primary: primary,
        count: 0,
        item: (_, _) => const SizedBox.shrink(),
        tail: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: EmptyHint(text: '还没有转发'),
        ),
      );
    }
    return _pagedList(
      primary: primary,
      count: reposts.items.length,
      item: (context, index) {
        final item = reposts.items[index];
        return AppearIn(
          key: ValueKey(item.id),
          animate: _playIntro(_repostIntro, _repostPlayed, item.id),
          grow: false,
          child: Column(
            children: [
              RepostTile(status: item),
              const Divider(indent: 64),
            ],
          ),
        );
      },
      tail: PagerTail(reposts),
    );
  }

  Widget _commentList(bool primary) {
    final comments = widget.comments;
    final status = widget.status;
    // Comments sent from this device that the server has not returned yet. They head the list so
    // the reader sees what they wrote where it will end up, instead of a list that looks like it
    // swallowed the comment until the next reload.
    final pending = CommentStore.instance.pendingFor(status.id);
    final pendingIds = {for (final item in pending) item.id};
    final loaded = [
      for (final item in comments.items)
        if (!pendingIds.contains(item.id)) item,
    ];
    if (loaded.isEmpty && pending.isEmpty) {
      if (comments.loading) {
        return _pagedList(primary: primary, count: 0, item: (_, _) => const SizedBox.shrink(), tail: const LoadingFooter());
      }
      if (comments.error != null) {
        return _pagedList(
          primary: primary,
          count: 0,
          item: (_, _) => const SizedBox.shrink(),
          tail: Padding(
            padding: const EdgeInsets.all(28),
            child: Center(child: ErrorView(error: comments.error, onRetry: comments.refresh)),
          ),
        );
      }
      return _pagedList(
        primary: primary,
        count: 0,
        item: (_, _) => const SizedBox.shrink(),
        tail: const Padding(
          padding: EdgeInsets.symmetric(vertical: 40),
          child: EmptyHint(text: '还没有评论'),
        ),
      );
    }
    final count = pending.length + loaded.length;
    return _pagedList(
      primary: primary,
      count: count,
      item: (context, index) {
        if (index < pending.length) {
          final item = pending[index];
          final awaitable = CommentStore.instance.isPending(item);
          return Column(
            children: [
              CommentTile(
                comment: item,
                awaitable: awaitable,
                onOpenUser: (uid) => openUser(context, uid),
                onOpenTopic: (name) => openTopic(context, name),
                onOpenUrl: (url) => openLink(context, url),
                onOpenFloor: awaitable ? () {} : () => openCommentFloor(context, status: status, root: item),
                onReply: awaitable ? (_) {} : (anchor) => _reply(anchor, item),
                onTap: awaitable ? null : (anchor) => _reply(anchor, item),
                onLongPress: awaitable
                    ? null
                    : (anchor, point) => showCommentActions(
                          context,
                          comment: item,
                          status: status,
                          anchor: anchor,
                          pointer: point,
                          onReply: () => _reply(anchor, item),
                        ),
                onOpenImage: (images, imageIndex, tag) {
                  openImage(context, media: images, index: imageIndex, heroTag: tag);
                },
              ),
              const Divider(indent: 64),
            ],
          );
        }
        final comment = loaded[index - pending.length];
        return AppearIn(
          key: ValueKey(comment.id),
          animate: _playIntro(_commentIntro, _commentPlayed, comment.id),
          grow: false,
          child: Column(
            children: [
              CommentTile(
                comment: comment,
                onOpenUser: (uid) => openUser(context, uid),
                onOpenTopic: (name) => openTopic(context, name),
                onOpenUrl: (url) => openLink(context, url),
                onOpenFloor: () => openCommentFloor(context, status: status, root: comment),
                onReply: (anchor) => _reply(anchor, comment),
                onTap: (anchor) => _reply(anchor, comment),
                onLongPress: (anchor, point) => showCommentActions(
                  context,
                  comment: comment,
                  status: status,
                  anchor: anchor,
                  pointer: point,
                  onReply: () => _reply(anchor, comment),
                ),
                onOpenImage: (images, imageIndex, tag) {
                  openImage(context, media: images, index: imageIndex, heroTag: tag);
                },
              ),
              const Divider(indent: 64),
            ],
          ),
        );
      },
      tail: PagerTail(comments),
    );
  }

  Future<void> _reply(BuildContext anchor, Comment comment) async {
    // A reply to what the list shows: the thread it belongs to is the comment itself, and the
    // comment being answered is the same one — they only differ when a reply is being answered,
    // which is on the thread page. [CommentStore] adds the reply inline, so no full refresh is needed.
    await showCommentSheet(
      context,
      anchor: anchor,
      status: widget.status,
      commentId: comment.id,
      replyToName: comment.author.screenName,
      replyToText: comment.text,
    );
  }
}

/// The two lists share one clock of [InfMotion.tabIn], so one fades out as the other fades in
/// and the gap between them never goes empty.
class _DiscussionCrossfade extends StatefulWidget {
  const _DiscussionCrossfade({required this.showingReposts, required this.page});

  final bool showingReposts;
  final Widget Function(bool reposts, bool primary) page;

  @override
  State<_DiscussionCrossfade> createState() => _DiscussionCrossfadeState();
}

class _DiscussionCrossfadeState extends State<_DiscussionCrossfade> with SingleTickerProviderStateMixin {
  late bool _shown = widget.showingReposts;
  bool? _leaving;
  late final AnimationController _swap = AnimationController(vsync: this, duration: InfMotion.tabIn, value: 1);
  late final Animation<double> _outgoing = ReverseAnimation(_swap);

  /// +1 when the incoming list sits to the right (评论), so it arrives from there and the other
  /// leaves the other way; a tab switch reads as moving sideways instead of a plain fade.
  double _direction = 1;

  /// How far the lists drift: enough to read as a direction, not as a page turn.
  static const double _drift = 18;

  @override
  void initState() {
    super.initState();
    _swap.addStatusListener((status) {
      if (status == AnimationStatus.completed && _leaving != null && mounted) {
        setState(() => _leaving = null);
      }
    });
  }

  @override
  void didUpdateWidget(covariant _DiscussionCrossfade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showingReposts == _shown) return;
    _leaving = _shown;
    _direction = widget.showingReposts ? -1 : 1;
    _shown = widget.showingReposts;
    _swap.value = 0;
    _swap.animateTo(1, curve: InfMotion.enter);
  }

  @override
  void dispose() {
    _swap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = _leaving;
    Widget slide(Animation<double> animation, double from, Widget child) => AnimatedBuilder(
          animation: animation,
          builder: (context, child) =>
              Transform.translate(offset: Offset(_drift * from * (1 - animation.value), 0), child: child),
          child: child,
        );
    return Stack(
      fit: StackFit.expand,
      children: [
        if (leaving != null)
          FadeTransition(
            opacity: _outgoing,
            child: IgnorePointer(
              child: KeyedSubtree(
                key: ValueKey('leave-$leaving'),
                child: slide(_outgoing, -_direction, widget.page(leaving, false)),
              ),
            ),
          ),
        FadeTransition(
          opacity: _swap,
          child: KeyedSubtree(
            key: ValueKey('show-$_shown'),
            child: slide(_swap, _direction, widget.page(_shown, true)),
          ),
        ),
      ],
    );
  }
}
