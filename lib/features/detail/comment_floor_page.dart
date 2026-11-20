import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/comment_store.dart';
import '../../core/error_text.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/comment_tile.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pager_tail.dart';
import '../../core/widgets/refresh.dart';

/// A comment and every reply under it. The comment heads the page, so a reply that only says
/// 「同意」 still reads against what it agrees with.
///
/// It used to live at the bottom of `status_detail_page.dart`, sharing a file with a page it does
/// not talk to. It is its own page — opened from a comment's reply box — so it is its own file.
class CommentFloorPage extends StatefulWidget {
  const CommentFloorPage({
    super.key,
    required this.status,
    required this.commentId,
    this.root,
  });

  /// The post the thread hangs off. Comments and replies are addressed by it, and a reply sent from
  /// here is a reply on this post.
  final Status status;

  final String commentId;

  /// The comment as the list showed it; the thread's own copy replaces it once loaded.
  final Comment? root;

  @override
  State<CommentFloorPage> createState() => _CommentFloorPageState();
}

class _CommentFloorPageState extends State<CommentFloorPage> {
  late Comment? _root = widget.root;
  late final PagingController<Comment> _replies = PagingController<Comment>(
    fetch: _fetch,
    id: (comment) => comment.id,
  );

  @override
  void initState() {
    super.initState();
    _replies.refresh();
  }

  @override
  void dispose() {
    _replies.dispose();
    super.dispose();
  }

  Future<PageResult<Comment>> _fetch(String? cursor) async {
    final (page, root) = await WeiboApi.instance.replyThread(widget.status.id, widget.commentId, cursor);
    if (cursor == null) CommentStore.instance.settleReplies(widget.commentId, loaded: page.items);
    if (root != null && mounted) {
      // The thread's copy has no inline replies; keep the count the list knew if it has none.
      final known = _root;
      setState(() => _root = known != null && root.repliesCount == 0 ? root.copyWith(repliesCount: known.repliesCount) : root);
    }
    return page;
  }

  Future<void> _reply(BuildContext anchor, Comment comment) async {
    // The thread is [widget.commentId]; what is being answered is [comment]. They are only the same
    // id for a reply to the top-level comment, which is the common case — passing the answered id as
    // both filed a reply to a reply under the wrong comment. [CommentStore] places the sent reply
    // at the top immediately, so reloading the whole thread is unnecessary.
    await showCommentSheet(
      context,
      anchor: anchor,
      status: widget.status,
      commentId: comment.id,
      rootId: widget.commentId,
      replyToName: comment.author.screenName,
      replyToText: comment.text,
    );
  }

  Widget _tile(Comment comment, {bool root = false, bool awaitable = false}) {
    return CommentTile(
      comment: comment,
      awaitable: awaitable,
      onOpenUser: (uid) => openUser(context, uid),
      onOpenTopic: (name) => openTopic(context, name),
      onOpenUrl: (url) => openLink(context, url),
      onOpenFloor: () {},
      imagesAsLinks: !root,
      showReplies: false,
      onReply: awaitable ? (_) {} : (anchor) => _reply(anchor, comment),
      onTap: awaitable
          ? null
          : (anchor) => showCommentActions(context, comment, anchor: anchor, onReply: () => _reply(anchor, comment)),
      onOpenImage: (images, imageIndex, tag) {
        openImage(context, media: images, index: imageIndex, heroTag: tag);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(title: const Text('评论详情'), flexibleSpace: lookBarBackground(context)),
      body: AnimatedBuilder(
        animation: Listenable.merge([_replies, CommentStore.instance]),
        builder: (context, _) {
          final root = _root;
          final pending = CommentStore.instance.pendingRepliesFor(widget.commentId);
          final pendingIds = {for (final reply in pending) reply.id};
          final loaded = [
            for (final reply in _replies.items)
              if (!pendingIds.contains(reply.id)) reply,
          ];
          final totalLoaded = pending.length + loaded.length;
          final baseCount = root == null ? 0 : root.repliesCount + pending.length;
          final count = baseCount > totalLoaded ? baseCount : totalLoaded;
          final Widget? state;
          if (totalLoaded == 0) {
            if (_replies.loading) {
              state = const LoadingFooter();
            } else if (_replies.error != null) {
              state = Padding(
                padding: const EdgeInsets.all(28),
                child: Center(child: ErrorView(error: _replies.error, onRetry: _replies.refresh)),
              );
            } else {
              state = const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyHint(text: '还没有回复'));
            }
          } else {
            state = null;
          }
          return NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _replies.onScroll(notification);
              return false;
            },
            child: InfRefreshIndicator(
              onRefresh: _replies.refresh,
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.only(
                  top: MediaQuery.paddingOf(context).top,
                  bottom: 28 + MediaQuery.paddingOf(context).bottom,
                  left: contentGutter(context),
                  right: contentGutter(context),
                ),
                itemCount: 1 + (state == null ? totalLoaded + 1 : 1),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (root != null) _tile(root, root: true),
                        Container(height: 8, color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55)),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                          child: Text(
                            count > 0 ? '全部回复 · ${compactCount(count)}' : '全部回复',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    );
                  }
                  if (state != null) return state;
                  final itemIndex = index - 1;
                  if (itemIndex == totalLoaded) return PagerTail(_replies);
                  final reply = itemIndex < pending.length
                      ? pending[itemIndex]
                      : loaded[itemIndex - pending.length];
                  return Column(
                    children: [
                      if (itemIndex > 0) const Divider(indent: 64),
                      _tile(reply, awaitable: CommentStore.instance.isPending(reply)),
                    ],
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}
