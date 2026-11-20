import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/comment_store.dart';
import '../../core/error_text.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/detail_bottom_bar.dart';
import '../../core/widgets/share_sheet.dart';
import '../../core/widgets/status_card_host.dart';
import '../../core/widgets/status_menu_route.dart';
import 'discussion_lists.dart';

/// 按热度 is what the hot flow returns; 按时间 asks the same list newest first.
enum CommentSort { hot, time }

/// A post and the discussion under it.
///
/// The page itself is the shell: it loads the post, owns the two pagers, and decides what the bar
/// does. The lists are [DiscussionLists], the bar is [DetailBottomBar], a comment row is
/// [CommentTile] and a reply thread is [CommentFloorPage] — all in their own files, so adding to the
/// discussion does not mean scrolling past the page's own plumbing.
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
  Object? _error;

  /// A long post's whole text once it has arrived, to put on whatever the requests return.
  ({String text, Map<String, WeiboLink> links})? _long;

  /// The route animations this page is waiting on before changing how tall it is.
  final List<(Animation<double>, AnimationStatusListener)> _waiting = [];

  /// The transition this page is drawn by, read where a lookup is allowed.
  Animation<double>? _routeAnimation;

  late PagingController<Comment> _comments;
  late final PagingController<Status> _reposts;
  CommentSort _sort = CommentSort.hot;
  bool _showingReposts = false;
  bool _repostsStarted = false;

  PagingController<Comment> _commentsPager(CommentSort sort) => PagingController<Comment>(
    fetch: (cursor) async {
      final page = await WeiboApi.instance.comments(
        widget.statusId,
        cursor,
        byTime: sort == CommentSort.time,
      );
      // A pending comment that this page contains is now the server's copy; one it does not
      // contain (a hot-ordered first page often omits what was just written) stays on screen.
      if (cursor == null) CommentStore.instance.settle(widget.statusId, loaded: page.items);
      return page;
    },
    id: (comment) => comment.id,
    // The first page from last time, so the page opens on the discussion instead of a skeleton.
  )..seed(WeiboApi.instance.cachedComments(widget.statusId, byTime: sort == CommentSort.time));

  @override
  void initState() {
    super.initState();
    final seed = widget.seed;
    if (seed != null) {
      StatusStore.instance.seed(seed);
      // The tap that opened this page asked for the rest of a long post, and by now it may be
      // here: the page then opens already showing what it will show, instead of growing taller
      // while it is still growing out of the card.
      if (seed.isLongText) {
        _long = StatusStore.instance.longTextNow(seed.id);
        if (_long != null) _status = _withLongText(seed);
      }
    }
    _comments = _commentsPager(_sort);
    _reposts = PagingController<Status>(
      fetch: (cursor) => WeiboApi.instance.reposts(widget.statusId, cursor),
      id: (status) => status.id,
      remember: StatusStore.instance.remember,
    );
    _comments.refresh();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeAnimation = ModalRoute.of(context)?.animation;
  }

  @override
  void dispose() {
    for (final (animation, listener) in _waiting) {
      animation.removeStatusListener(listener);
    }
    _waiting.clear();
    _comments.dispose();
    _reposts.dispose();
    super.dispose();
  }

  /// The post with its whole text on it, filed back into [Entities] so the truncated card in the
  /// list behind this page shows the same text on the way back rather than the six-line cut it was
  /// parsed with.
  Status _withLongText(Status status, {bool notify = false}) {
    if (_long == null) return notify ? StatusStore.instance.remember(status, notify: true) : status;
    final mergedLinks = Map<String, WeiboLink>.from(status.links);
    for (final entry in _long!.links.entries) {
      final prev = mergedLinks[entry.key];
      if (prev != null && prev.images.length > entry.value.images.length) {
        mergedLinks[entry.key] = WeiboLink(
          url: entry.key,
          label: prev.label.isNotEmpty ? prev.label : entry.value.label,
          kind: entry.value.kind,
          images: prev.images,
        );
      } else {
        mergedLinks[entry.key] = entry.value;
      }
    }
    final whole = status.copyWith(
      text: _long!.text,
      links: mergedLinks,
      isLongText: false,
    );
    return StatusStore.instance.remember(whole, notify: notify);
  }

  /// Runs [apply] now, or once the page has finished opening. While it is still growing out of
  /// the card its content is copied and scaled, so more text arriving then is seen as the page
  /// jumping, and the copy that later shrinks back is not the one the card grew from. [immediately]
  /// is for a change that does not alter the shape, such as a skeleton giving way to the post.
  void _whenSettled(VoidCallback apply, {bool immediately = false}) {
    if (!mounted) return;
    final animation = immediately ? null : _routeAnimation;
    if (animation == null || animation.isCompleted) {
      apply();
      return;
    }
    late final AnimationStatusListener listener;
    listener = (status) {
      if (status != AnimationStatus.completed && status != AnimationStatus.dismissed) return;
      animation.removeStatusListener(listener);
      _waiting.removeWhere((entry) => entry.$2 == listener);
      if (mounted && status == AnimationStatus.completed) apply();
    };
    animation.addStatusListener(listener);
    _waiting.add((animation, listener));
  }

  /// Another order is another list: the cursor of one means nothing to the other.
  void _setSort(CommentSort sort) {
    if (sort == _sort) return;
    Haptic.selection.play();
    final previous = _comments;
    final next = _commentsPager(sort);
    setState(() {
      _sort = sort;
      _comments = next;
    });
    next.refresh();
    previous.disposeDeferred();
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
    // A long post's whole text is asked for beside the post itself, not after it: one request
    // after another would still be running when the page has finished opening. The tap usually
    // started it already, and the store shares that request rather than sending another. Without
    // a seed there is nothing to tell it is long until the post arrives.
    final seed = _status;
    final needsLong = seed != null && seed.isLongText && _long == null;
    final pendingLong = needsLong ? _pullLongText(seed.id) : null;
    pendingLong?.ignore();
    try {
      final status = await WeiboApi.instance.status(widget.statusId);
      if (status == null) throw ApiException('这条微博不存在或已被删除');
      if (!mounted) return;
      StatusStore.instance.seed(status);
      StatusStore.instance.recordViewed(status, enabled: Prefs.instance.recordHistory);
      // A skeleton has to be replaced at once; only text changing on a page that already has some
      // waits, as that is what makes the copy jump while it is still growing out of the card.
      _whenSettled(() {
        setState(() {
          _status = _withLongText(status, notify: true);
          _loading = false;
          _error = null;
        });
      }, immediately: seed == null);
      if (status.isLongText && _long == null) await (pendingLong ?? _pullLongText(status.id));
    } catch (error) {
      if (!mounted) return;
      if (_status != null) {
        setState(() => _loading = false);
        showMessage(context, friendlyError(error));
      } else {
        setState(() {
          _loading = false;
          _error = error;
        });
      }
    }
  }

  /// Holds on to the whole text and puts it on whatever the page shows, once the page has stopped
  /// growing. Throws like the request did, so a failure is reported as before.
  Future<void> _pullLongText(String id) async {
    final long = await StatusStore.instance.longText(id);
    if (long == null || !mounted) return;
    _long = long;
    _whenSettled(() {
      final status = _status;
      if (status != null) setState(() => _status = _withLongText(status, notify: true));
    });
  }

  Future<void> _toggleLike() async {
    final status = _status;
    if (status == null) return;
    final message = await StatusStore.instance.toggleLike(status);
    if (mounted) showMessage(context, message);
  }

  Future<void> _comment(BuildContext anchor) async {
    final status = _status;
    if (status == null) return;
    // Nothing is refreshed here. The comment the reader just sent is drawn from [CommentStore] at
    // the top of the list straight away, and the count went up in [StatusStore]; reloading the
    // whole thread was only ever a way to make the new comment appear, and it cost the reader
    // their place in a long one.
    await showCommentSheet(context, anchor: anchor, status: status);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      // This post's own state, not the whole store: the page draws one post and the bar under it.
      animation: Listenable.merge([
        _comments,
        _reposts,
        CommentStore.instance,
        StatusStore.instance.of([
          widget.statusId,
          if (widget.seed?.repostOf != null) widget.seed!.repostOf!.id,
        ]),
      ]),
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
            actions: InfChrome.of(context).barActions(context, [
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
                Builder(
                  // The menu grows out of this button's own rectangle, so the button's context is
                  // the anchor rather than the page's.
                  builder: (buttonContext) => IconButton(
                    icon: const Icon(Icons.more_horiz_rounded),
                    tooltip: '更多',
                    onPressed: () => showStatusMenu(
                      context,
                      applied ?? status,
                      anchor: buttonContext,
                      onLongImage: () => openLongImage(context, status),
                      originRadius: 20,
                      // A bar's `⋯` opens its menu against its own corner, not in the middle of
                      // the page: the button is where the finger is.
                      placement: StatusMenuPlacement.anchored,
                    ),
                  ),
                ),
            ]),
          ),
          bottomNavigationBar: DetailBottomBar(
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
              if (applied != null) _post(context, applied),
              if (status == null && _loading) const StatusDetailSkeleton(),
              if (status == null && !_loading) Center(child: ErrorView(error: _error, onRetry: _load)),
            ],
          ),
        );
      },
    );
  }

  /// The post, then the two tabs, then whichever list is showing.
  ///
  /// One NestedScrollView: the post and the tabs are the header, so they scroll away and the list
  /// underneath is the only thing that pages.
  Widget _post(BuildContext context, Status status) {
    final scheme = Theme.of(context).colorScheme;
    final sides = EdgeInsets.symmetric(horizontal: contentGutter(context));
    final divider = InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.55);
    return NestedScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      headerSliverBuilder: (context, _) => [
        SliverPadding(
          padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top).add(sides),
          sliver: SliverToBoxAdapter(
            child: buildStatusCard(
              context,
              status,
              heroScope: status.id,
              detail: true,
              saveAllButton: true,
              detailStatusId: status.id,
              onToggleLike: _toggleLike,
              onLongImage: () => openLongImage(context, status),
            ),
          ),
        ),
        SliverPadding(
          padding: sides,
          sliver: SliverToBoxAdapter(child: Container(height: 8, color: divider)),
        ),
        SliverPadding(
          padding: sides,
          sliver: SliverToBoxAdapter(
            child: DiscussionSwitch(
              reposts: status.repostsCount,
              comments: status.commentsCount,
              showingReposts: _showingReposts,
              onShowReposts: () => _showReposts(true),
              onShowComments: () => _showReposts(false),
            ),
          ),
        ),
        SliverPadding(
          padding: sides,
          sliver: SliverToBoxAdapter(
            // Kept in the header while hidden, so the sliver count does not change under a
            // NestedScrollView that is already scrolled into it.
            child: _showingReposts
                ? const SizedBox.shrink()
                : CommentSortBar(
                    byTime: _sort == CommentSort.time,
                    onSort: (byTime) => _setSort(byTime ? CommentSort.time : CommentSort.hot),
                  ),
          ),
        ),
      ],
      body: DiscussionLists(
        status: status,
        comments: _comments,
        reposts: _reposts,
        byTime: _sort == CommentSort.time,
        onSort: (byTime) => _setSort(byTime ? CommentSort.time : CommentSort.hot),
        showingReposts: _showingReposts,
        onShowReposts: () => _showReposts(true),
        onShowComments: () => _showReposts(false),
        onComment: _comment,
        onStatusRefreshed: (fresh) => setState(() => _status = _withLongText(fresh, notify: true)),
      ),
    );
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
