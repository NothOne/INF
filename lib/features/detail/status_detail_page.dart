import '../../core/motion.dart';
import '../../core/haptics.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/parse.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/rich_text.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/share_sheet.dart';
import '../../core/widgets/status_card.dart';
import '../../core/widgets/transitions.dart';

class StatusDetailPage extends StatefulWidget {
  const StatusDetailPage({
    super.key,
    required this.statusId,
    this.seed,
  });

  final String statusId;
  final Status? seed;

  @override
  State<StatusDetailPage> createState() => _StatusDetailPageState();
}

class _StatusDetailPageState extends State<StatusDetailPage> {
  late Status? _status = widget.seed;
  late bool _loading = widget.seed == null;
  String? _error;
  late final PagingController<Comment> _comments;
  late final PagingController<Status> _reposts;
  bool _showingReposts = false;
  bool _repostsStarted = false;

  @override
  void initState() {
    super.initState();
    if (widget.seed != null) StatusStore.instance.seed(widget.seed!);
    _comments = PagingController<Comment>(
      fetch: (cursor) => WeiboApi.instance.comments(widget.statusId, cursor),
      id: (comment) => comment.id,
    );
    _reposts = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.reposts(widget.statusId, cursor),
      id: (status) => status.id,
    );
    _comments.refresh();
    _load();
  }

  @override
  void dispose() {
    _comments.dispose();
    _reposts.dispose();
    super.dispose();
  }

  void _showReposts(bool value) {
    if (value == _showingReposts) return;
    Haptic.selection.play();
    if (value && !_repostsStarted) {
      _repostsStarted = true;
      _reposts.refresh();
    }
    setState(() => _showingReposts = value);
  }

  Future<void> _load() async {
    try {
      final status = await WeiboApi.instance.status(widget.statusId);
      if (status == null) throw ApiException('这条微博不存在或已被删除');
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
        _error = null;
      });
      StatusStore.instance.seed(status);
      StatusStore.instance.recordViewed(status, enabled: Prefs.instance.recordHistory);
      if (status.isLongText) {
        final long = await WeiboApi.instance.longText(status.id);
        if (long != null && mounted) {
          setState(() => _status = status.copyWith(
                text: long.text,
                links: {...status.links, ...long.links},
                isLongText: false,
              ));
        }
      }
    } catch (error) {
      if (!mounted) return;
      final message = error is ApiException ? error.message : '加载失败';
      if (_status != null) {
        setState(() => _loading = false);
        showMessage(context, message);
      } else {
        setState(() {
          _loading = false;
          _error = message;
        });
      }
    }
  }

  Future<void> _toggleLike() async {
    final status = _status;
    if (status == null) return;
    final message = await StatusStore.instance.toggleLike(status);
    if (mounted) showMessage(context, message);
  }

  Future<void> _comment() async {
    final status = _status;
    final sent = await showCommentSheet(context, statusId: widget.statusId, target: status);
    if (sent == true) {
      _comments.refresh();
      if (status != null && mounted) {
        setState(() => _status = status.copyWith(commentsCount: status.commentsCount + 1));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_comments, _reposts, StatusStore.instance]),
      builder: (context, _) {
        final status = _status;
        final applied = status == null ? null : StatusStore.instance.apply(status);
        final behind = InfChrome.of(context).extendsBehindBars;
        return Scaffold(
          backgroundColor: scheme.surface,
          extendBodyBehindAppBar: behind,
          extendBody: behind,
          appBar: AppBar(
            flexibleSpace: lookBarBackground(context),
            title: const Text('微博正文'),
            actions: [
              if (status != null)
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: '分享',
                  onPressed: () => showStatusShare(
                    context,
                    applied ?? status,
                    onLongImage: () => openLongImage(context, status),
                  ),
                ),
              if (status != null)
                IconButton(
                  icon: const Icon(Icons.more_horiz_rounded),
                  tooltip: '更多',
                  onPressed: () => showStatusActions(
                    context,
                    applied ?? status,
                    onLongImage: () => openLongImage(context, status),
                  ),
                ),
              const SizedBox(width: 4),
            ],
          ),
          bottomNavigationBar: _BottomBar(
            liked: applied?.liked ?? false,
            enabled: status != null,
            onComment: _comment,
            onRepost: () => status == null
                ? null
                : openCompose(context, type: DraftType.repost, statusId: status.id),
            onLike: _toggleLike,
          ),
          body: Stack(
            children: [
              if (applied != null)
                _DetailBody(
                  status: applied,
                  comments: _comments,
                  reposts: _reposts,
                  showingReposts: _showingReposts,
                  onShowReposts: () => _showReposts(true),
                  onShowComments: () => _showReposts(false),
                  onComment: _comment,
                  onLike: _toggleLike,
                ),
              if (status == null && _loading) const StatusDetailSkeleton(),
              if (status == null && !_loading)
                Center(child: ErrorRetry(message: _error, onRetry: _load)),
            ],
          ),
        );
      },
    );
  }
}

class _DetailBody extends StatefulWidget {
  const _DetailBody({
    required this.status,
    required this.comments,
    required this.reposts,
    required this.showingReposts,
    required this.onShowReposts,
    required this.onShowComments,
    required this.onComment,
    required this.onLike,
  });

  final Status status;
  final PagingController<Comment> comments;
  final PagingController<Status> reposts;
  final bool showingReposts;
  final VoidCallback onShowReposts;
  final VoidCallback onShowComments;
  final VoidCallback onComment;
  final VoidCallback onLike;

  @override
  State<_DetailBody> createState() => _DetailBodyState();
}

class _DetailBodyState extends State<_DetailBody> {
  /// Ids from the first page, and the ones that have already played [AppearIn].
  /// A later page is not in the first set, so it is appended in place.
  final Set<String> _commentIntro = {};
  final Set<String> _repostIntro = {};
  final Set<String> _commentPlayed = {};
  final Set<String> _repostPlayed = {};
  bool _commentIntroClosed = false;
  bool _repostIntroClosed = false;

  @override
  void initState() {
    super.initState();
    widget.comments.addListener(_captureCommentIntro);
    widget.reposts.addListener(_captureRepostIntro);
    _captureCommentIntro();
    _captureRepostIntro();
  }

  @override
  void didUpdateWidget(covariant _DetailBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.comments != widget.comments) {
      oldWidget.comments.removeListener(_captureCommentIntro);
      widget.comments.addListener(_captureCommentIntro);
    }
    if (oldWidget.reposts != widget.reposts) {
      oldWidget.reposts.removeListener(_captureRepostIntro);
      widget.reposts.addListener(_captureRepostIntro);
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

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final comments = widget.comments;
    final reposts = widget.reposts;
    final scheme = Theme.of(context).colorScheme;
    final sides = EdgeInsets.symmetric(horizontal: contentGutter(context));
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // The outer header also scrolls. Only the list underneath should turn the page.
        if (notification.depth == 0) return false;
        (widget.showingReposts ? reposts : comments).onScroll(notification);
        return false;
      },
      child: InfRefreshIndicator(
        onRefresh: () async {
          final list = widget.showingReposts ? reposts.refresh() : comments.refresh();
          final results = await Future.wait<Object?>([list, WeiboApi.instance.status(status.id)]);
          return results.first;
        },
        child: NestedScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          headerSliverBuilder: (context, _) => [
            SliverPadding(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top).add(sides),
              sliver: SliverToBoxAdapter(
              child: StatusCard(
                status: status,
                detail: true,
                onOpenStatus: (id) => openStatus(context, statusId: id),
                onOpenUser: (uid) => openUser(context, uid),
                onOpenTopic: (name) => openTopic(context, name),
                onOpenUrl: (url) => openLink(context, url),
                onOpenMedia: (media, index, tag) {
                  if (media[index].kind == MediaKind.video) {
                    openVideo(context, media[index].url, coverUrl: media[index].previewUrl);
                  } else {
                    openImage(context, media: media, index: index, heroTag: tag);
                  }
                },
                onToggleLike: widget.onLike,
                onRepost: () => openCompose(context, type: DraftType.repost, statusId: status.id),
                onComment: widget.onComment,
                onLongImage: () => openLongImage(context, status),
              ),
            ),
            ),
            SliverPadding(
              padding: sides,
              sliver: SliverToBoxAdapter(
                child: Container(height: 8, color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55)),
              ),
            ),
            SliverPadding(
              padding: sides,
              sliver: SliverToBoxAdapter(
                child: _DiscussionSwitch(
                  reposts: status.repostsCount,
                  comments: status.commentsCount,
                  showingReposts: widget.showingReposts,
                  onShowReposts: widget.onShowReposts,
                  onShowComments: widget.onShowComments,
                ),
              ),
            ),
          ],
          body: _DiscussionCrossfade(
            showingReposts: widget.showingReposts,
            page: (reposts, primary) => reposts ? _repostList(primary) : _commentList(primary),
          ),
        ),
      ),
    );
  }

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
          child: Center(child: ErrorRetry(message: reposts.error.toString(), onRetry: reposts.refresh)),
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
              _RepostTile(status: item),
              const Divider(indent: 64),
            ],
          ),
        );
      },
      tail: _PagerTail(
        loadingMore: reposts.loadingMore,
        moreError: reposts.moreError,
        hasMore: reposts.hasMore,
        hasItems: reposts.items.isNotEmpty,
        onRetry: reposts.loadMore,
      ),
    );
  }

  Widget _commentList(bool primary) {
    final comments = widget.comments;
    final status = widget.status;
    if (comments.loading && comments.items.isEmpty) {
      return _pagedList(primary: primary, count: 0, item: (_, _) => const SizedBox.shrink(), tail: const LoadingFooter());
    }
    if (comments.error != null && comments.items.isEmpty) {
      return _pagedList(
        primary: primary,
        count: 0,
        item: (_, _) => const SizedBox.shrink(),
        tail: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(child: ErrorRetry(message: comments.error.toString(), onRetry: comments.refresh)),
        ),
      );
    }
    if (comments.items.isEmpty) {
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
    return _pagedList(
      primary: primary,
      count: comments.items.length,
      item: (context, index) {
        final comment = comments.items[index];
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
                onOpenFloor: () => openCommentFloor(context, statusId: status.id, root: comment),
                onReply: () => _reply(context, comment),
                onTap: () => showCommentActions(context, comment, onReply: () => _reply(context, comment)),
                onOpenImage: (images, imageIndex, tag) {
                  openImage(context, media: images, index: imageIndex, heroTag: tag);
                },
              ),
              const Divider(indent: 64),
            ],
          ),
        );
      },
      tail: _PagerTail(
        loadingMore: comments.loadingMore,
        moreError: comments.moreError,
        hasMore: comments.hasMore,
        hasItems: comments.items.isNotEmpty,
        onRetry: comments.loadMore,
      ),
    );
  }

  Future<void> _reply(BuildContext context, Comment comment) async {
    final sent = await showCommentSheet(
      context,
      statusId: widget.status.id,
      commentId: comment.id,
      replyToName: comment.author.screenName,
      replyToText: comment.text,
    );
    if (sent == true) widget.comments.refresh();
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
    return Stack(
      fit: StackFit.expand,
      children: [
        if (leaving != null)
          FadeTransition(
            opacity: _outgoing,
            child: IgnorePointer(
              child: KeyedSubtree(
                key: ValueKey('leave-$leaving'),
                child: widget.page(leaving, false),
              ),
            ),
          ),
        FadeTransition(
          opacity: _swap,
          child: KeyedSubtree(
            key: ValueKey('show-$_shown'),
            child: widget.page(_shown, true),
          ),
        ),
      ],
    );
  }
}

class _PagerTail extends StatelessWidget {
  const _PagerTail({
    required this.loadingMore,
    required this.moreError,
    required this.hasMore,
    required this.hasItems,
    required this.onRetry,
  });

  final bool loadingMore;
  final Object? moreError;
  final bool hasMore;
  final bool hasItems;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loadingMore) return const LoadingFooter();
    if (moreError != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(child: TextButton(onPressed: onRetry, child: const Text('加载失败，点此重试'))),
      );
    }
    if (!hasMore && hasItems) return const LoadingFooter(text: '没有更多了');
    return const SizedBox(height: 20);
  }
}

class _DiscussionSwitch extends StatelessWidget {
  const _DiscussionSwitch({
    required this.reposts,
    required this.comments,
    required this.showingReposts,
    required this.onShowReposts,
    required this.onShowComments,
  });

  final int reposts;
  final int comments;
  final bool showingReposts;
  final VoidCallback onShowReposts;
  final VoidCallback onShowComments;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
      child: Row(
        children: [
          _tab(context, '转发', reposts, showingReposts, onShowReposts),
          _tab(context, '评论', comments, !showingReposts, onShowComments),
        ],
      ),
    );
  }

  Widget _tab(BuildContext context, String label, int count, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    final caption = count > 0 ? '$label ${compactCount(count)}' : label;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 6),
          child: Column(
            children: [
              AnimatedDefaultTextStyle(
                duration: InfMotion.feedback,
                style: (Theme.of(context).textTheme.titleSmall ?? const TextStyle()).copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                child: Text(caption),
              ),
              const SizedBox(height: 7),
              AnimatedContainer(
                duration: InfMotion.feedback,
                curve: Curves.easeOutCubic,
                height: 2.5,
                width: selected ? 26 : 0,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RepostTile extends StatelessWidget {
  const _RepostTile({required this.status});

  final Status status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = status.text.trim().isEmpty ? '转发微博' : status.text;
    return InkWell(
      onTap: () => openStatus(context, statusId: status.id, seed: status),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => openUser(context, status.author.id),
              child: Avatar(url: status.author.avatarUrl, size: 40, verified: status.author.verified),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: GestureDetector(
                          onTap: () => openUser(context, status.author.id),
                          child: Text(
                            status.author.screenName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        relativeTime(status.createdAt),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  RichStatusText(
                    text: text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5),
                    onMention: (uid) => openUser(context, uid),
                    onTopic: (name) => openTopic(context, name),
                    onUrl: (url) => openLink(context, url),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum CommentAction { reply, copy }

Future<void> showCommentActions(
  BuildContext context,
  Comment comment, {
  required Future<void> Function() onReply,
}) async {
  final action = await showActionSheet<CommentAction>(
    context: context,
    frosted: false,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.reply_rounded),
            title: const Text('评论'),
            subtitle: Text('回复 @${comment.author.screenName}'),
            onTap: () => Navigator.of(sheetContext).pop(CommentAction.reply),
          ),
          ListTile(
            leading: const Icon(Icons.copy_rounded),
            title: const Text('复制'),
            subtitle: const Text('复制评论正文'),
            onTap: () => Navigator.of(sheetContext).pop(CommentAction.copy),
          ),
          const SizedBox(height: 4),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  switch (action) {
    case CommentAction.reply:
      await onReply();
    case CommentAction.copy:
      await Clipboard.setData(ClipboardData(text: comment.text));
      Haptic.success.play();
      if (context.mounted) showMessage(context, '评论已复制');
    case null:
      return;
  }
}

class CommentTile extends StatelessWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.onOpenUser,
    required this.onOpenTopic,
    required this.onOpenUrl,
    required this.onOpenFloor,
    required this.onReply,
    required this.onOpenImage,
    this.imagesAsLinks = false,
    this.showReplies = true,
    this.onTap,
  });

  final Comment comment;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<String> onOpenTopic;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback onOpenFloor;
  final VoidCallback onReply;
  final void Function(List<Media> images, int index, String? heroTag) onOpenImage;
  final bool imagesAsLinks;

  /// Off where the replies are listed in full right below, as on the floor page.
  final bool showReplies;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = comment.region == null || comment.region!.isEmpty
        ? relativeTime(comment.createdAt)
        : '${relativeTime(comment.createdAt)} · ${comment.region}';
    final body = comment.replyTo == null
        ? comment.text
        : '回复 ${comment.replyTo!.screenName}：${comment.text}';
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => onOpenUser(comment.author.id),
            child: Avatar(url: comment.author.avatarUrl, size: 36, verified: comment.author.verified),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => onOpenUser(comment.author.id),
                  child: Text(
                    comment.author.screenName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14),
                  ),
                ),
                const SizedBox(height: 3),
                RichStatusText(
                  text: body,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5),
                  onMention: onOpenUser,
                  onTopic: onOpenTopic,
                  onUrl: onOpenUrl,
                  inlineImages: !imagesAsLinks && comment.images.isEmpty,
                  onOpenImage: (url, tag) => onOpenImage([Media.image(url)], 0, tag),
                ),
                if (comment.images.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  if (imagesAsLinks)
                    Wrap(
                      spacing: 14,
                      children: [
                        for (var i = 0; i < comment.images.length; i++)
                          Builder(
                            builder: (cellContext) {
                              final tag = 'link-img-comment-' + comment.id + '-' + i.toString();
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => onOpenImage(comment.images, i, tag),
                                child: Hero(
                                  tag: tag,
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: InlineLinkLabel(
                                      icon: Icons.image_outlined,
                                      label: '查看图片',
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 13),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    )
                  else
                    _CommentImages(
                      images: comment.images,
                      commentId: comment.id,
                      onOpen: onOpenImage,
                    ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        meta,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ),
                    TextButton(
                      onPressed: onReply,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(42, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 7),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('回复', style: TextStyle(fontSize: 11.5)),
                    ),
                    if (comment.likesCount > 0) ...[
                      Icon(
                        comment.liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
                        size: 13,
                        color: comment.liked ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        compactCount(comment.likesCount),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: comment.liked ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ],
                ),
                if (showReplies && comment.replies.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _InlineReplies(comment: comment, onTap: onOpenFloor),
                ],
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }
}

class _CommentImages extends StatelessWidget {
  const _CommentImages({required this.images, required this.commentId, required this.onOpen});

  final List<Media> images;
  final String commentId;
  final void Function(List<Media> images, int index, String? heroTag) onOpen;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < images.length && i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onOpen(images, i, 'comment-$commentId-$i'),
            child: Hero(
              tag: 'comment-$commentId-$i',
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 86,
                  height: 86,
                  child: SmartImage(
                    url: images[i].previewUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InlineReplies extends StatelessWidget {
  const _InlineReplies({required this.comment, required this.onTap});

  final Comment comment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shown = comment.replies.take(3).toList();
    return Material(
      color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.58),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final reply in shown)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: RichText(
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodySmall,
                      children: [
                        TextSpan(
                          text: '${reply.author.screenName}：',
                          style: TextStyle(color: scheme.primary),
                        ),
                        TextSpan(text: reply.text),
                      ],
                    ),
                  ),
                ),
              if (comment.repliesCount > shown.length)
                Text(
                  '共${compactCount(comment.repliesCount)}条回复 >',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The same short pop the card's like button uses, so the two controls feel like one.
class _PopLikeButton extends StatefulWidget {
  const _PopLikeButton({required this.liked, required this.enabled, required this.onLike});

  final bool liked;
  final bool enabled;
  final VoidCallback onLike;

  @override
  State<_PopLikeButton> createState() => _PopLikeButtonState();
}

class _PopLikeButtonState extends State<_PopLikeButton> {
  bool _popped = false;

  void _tap() {
    setState(() => _popped = true);
    Future<void>.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _popped = false);
    });
    widget.onLike();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.liked ? scheme.primary : scheme.onSurfaceVariant;
    return IconButton(
      onPressed: widget.enabled ? _tap : null,
      tooltip: '赞',
      icon: AnimatedScale(
        scale: _popped ? 1.28 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutBack,
        child: TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: color),
          duration: const Duration(milliseconds: 160),
          builder: (context, value, _) => Icon(
            widget.liked ? Icons.thumb_up_rounded : Icons.thumb_up_outlined,
            color: value,
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.liked,
    required this.enabled,
    required this.onComment,
    required this.onRepost,
    required this.onLike,
  });

  final bool liked;
  final bool enabled;
  final VoidCallback onComment;
  final VoidCallback onRepost;
  final VoidCallback onLike;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final bar = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: enabled ? onComment : null,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                    color: chrome.fill(scheme, scheme.surfaceContainerHigh, 0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '写评论…',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: enabled ? onRepost : null,
              tooltip: '转发',
              icon: const Icon(Icons.repeat_rounded),
            ),
            _PopLikeButton(liked: liked, enabled: enabled, onLike: onLike),
          ],
        ),
      ),
    );
    return chrome.edgePanel(context, child: ContentColumn(child: bar));
  }
}

class StatusDetailSkeleton extends StatelessWidget {
  const StatusDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const SkeletonPulse(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SkeletonBox(width: 40, height: 40, radius: 20),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SkeletonBox(width: 110, height: 13),
                    SizedBox(height: 8),
                    SkeletonBox(width: 80, height: 10),
                  ],
                ),
              ],
            ),
            SizedBox(height: 20),
            SkeletonBox(width: double.infinity, height: 14),
            SizedBox(height: 9),
            SkeletonBox(width: 300, height: 14),
            SizedBox(height: 9),
            SkeletonBox(width: 180, height: 14),
            SizedBox(height: 18),
            SkeletonBox(width: double.infinity, height: 190, radius: 10),
          ],
        ),
      ),
    );
  }
}

/// A comment and every reply under it. The comment heads the page, so a reply that only says
/// 「同意」 still reads against what it agrees with.
class CommentFloorPage extends StatefulWidget {
  const CommentFloorPage({super.key, required this.statusId, required this.commentId, this.root});

  final String statusId;
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
    final (page, root) = await WeiboApi.instance.replyThread(widget.statusId, widget.commentId, cursor);
    if (root != null && mounted) {
      // The thread's copy has no inline replies; keep the count the list knew if it has none.
      final known = _root;
      setState(() => _root = known != null && root.repliesCount == 0 ? root.copyWith(repliesCount: known.repliesCount) : root);
    }
    return page;
  }

  Future<void> _reply(Comment comment) async {
    final sent = await showCommentSheet(
      context,
      statusId: widget.statusId,
      commentId: comment.id,
      replyToName: comment.author.screenName,
      replyToText: comment.text,
    );
    if (sent == true) _replies.refresh();
  }

  Widget _tile(Comment comment, {bool root = false}) {
    return CommentTile(
      comment: comment,
      onOpenUser: (uid) => openUser(context, uid),
      onOpenTopic: (name) => openTopic(context, name),
      onOpenUrl: (url) => openLink(context, url),
      onOpenFloor: () {},
      imagesAsLinks: !root,
      showReplies: false,
      onReply: () => _reply(comment),
      onTap: () => showCommentActions(context, comment, onReply: () => _reply(comment)),
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
        animation: _replies,
        builder: (context, _) {
          final root = _root;
          final items = _replies.items;
          final count = root == null ? items.length : (root.repliesCount > items.length ? root.repliesCount : items.length);
          final Widget? state;
          if (_replies.loading && items.isEmpty) {
            state = const LoadingFooter();
          } else if (_replies.error != null && items.isEmpty) {
            state = Padding(
              padding: const EdgeInsets.all(28),
              child: Center(child: ErrorRetry(message: _replies.error.toString(), onRetry: _replies.refresh)),
            );
          } else if (items.isEmpty) {
            state = const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: EmptyHint(text: '还没有回复'));
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
                itemCount: 1 + (state == null ? items.length + 1 : 1),
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
                  if (itemIndex == items.length) {
                    return _PagerTail(
                      loadingMore: _replies.loadingMore,
                      moreError: _replies.moreError,
                      hasMore: _replies.hasMore,
                      hasItems: items.isNotEmpty,
                      onRetry: _replies.loadMore,
                    );
                  }
                  return Column(
                    children: [
                      if (itemIndex > 0) const Divider(indent: 64),
                      _tile(items[itemIndex]),
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
