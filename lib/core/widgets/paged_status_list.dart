import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/pane.dart';
import '../../core/prefs.dart';
import '../../core/status_store.dart';
import 'comment_sheet.dart';
import 'common.dart';
import 'refresh.dart';
import 'status_card.dart';
import 'transitions.dart';

/// A paged list of posts, used by search, topics, profiles and the liked feed. The feed itself has
/// a slightly different header so it keeps its own widget, but the card contract is the same.
class PagedStatusList extends StatelessWidget {
  const PagedStatusList({
    super.key,
    required this.pager,
    this.header,
    this.emptyText = '没有微博',
    this.bottomInset = 24,
    this.underAppBar = true,
    this.controller,
    this.nested = false,
    this.refreshable = true,
    this.hideBlocked = true,
  });

  final PagingController<Status> pager;
  final Widget? header;
  final String emptyText;
  final double bottomInset;

  /// Pad by the bar when the list is the page body and the body runs behind the app bar.
  /// Nested lists (under a tab strip that is already in the body) leave this off.
  final bool underAppBar;

  final ScrollController? controller;

  /// The list is the body of a [NestedScrollView] whose pinned header sits in a
  /// [SliverOverlapAbsorber]; it starts below that header instead of under it.
  final bool nested;

  /// Off when an enclosing view already owns pull-to-refresh.
  final bool refreshable;

  /// Leaves out the posts of people blocked on this device; off on their own page.
  final bool hideBlocked;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([pager, StatusStore.instance, Prefs.instance]),
      // Cross-fading two copies of the same header would dim it halfway through.
      builder: (context, _) => header == null ? StateSwitcher(child: _body(context)) : _body(context),
    );
  }

  Widget _refresh({Key? key, required Widget child}) =>
      refreshable ? InfRefreshIndicator(key: key, onRefresh: pager.refresh, child: child) : KeyedSubtree(key: key, child: child);

  Widget _scrollView(BuildContext context, List<Widget> slivers) {
    return CustomScrollView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (nested) SliverOverlapInjector(handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context)),
        ...slivers,
      ],
    );
  }

  Widget _body(BuildContext context) {
    final headerCount = header == null ? 0 : 1;
    final top = underAppBar ? MediaQuery.paddingOf(context).top : 0.0;
    final gutter = contentGutter(context);
    if (pager.items.isEmpty) {
      final Widget state;
      if (pager.error != null) {
        state = Padding(
          padding: const EdgeInsets.only(top: 80),
          child: Center(child: ErrorRetry(message: pager.error.toString(), onRetry: pager.refresh)),
        );
      } else if (pager.loading || pager.refreshedAt == null) {
        state = SizedBox(
          height: 520,
          child: MediaQuery.removePadding(context: context, removeTop: true, child: const StatusListSkeleton()),
        );
      } else {
        state = Padding(
          padding: const EdgeInsets.only(top: 120),
          child: EmptyHint(text: emptyText, icon: Icons.forum_outlined),
        );
      }
      // The header (a profile, say) stays put above whichever state the posts are in.
      return _refresh(
        key: ValueKey(pager.error != null ? 'error' : (pager.loading || pager.refreshedAt == null ? 'loading' : 'empty')),
        child: _scrollView(context, [
          SliverPadding(
            padding: EdgeInsets.only(top: top, left: gutter, right: gutter),
            sliver: SliverList.list(
              children: [
                if (header != null) header!,
                state,
              ],
            ),
          ),
        ]),
      );
    }
    return NotificationListener<ScrollNotification>(
      key: const ValueKey('list'),
      onNotification: (notification) {
        pager.onScroll(notification);
        return false;
      },
      child: _refresh(
        child: _scrollView(context, [
          SliverPadding(
            padding: EdgeInsets.only(
              top: top,
              bottom: bottomInset + MediaQuery.paddingOf(context).bottom,
              left: gutter,
              right: gutter,
            ),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                childCount: pager.items.length + headerCount + 1,
                findChildIndexCallback: (key) => pager.indexOfKey(key, offset: headerCount),
                (context, index) {
                  if (headerCount == 1 && index == 0) return header!;
                  final itemIndex = index - headerCount;
                  if (itemIndex == pager.items.length) {
                    if (pager.loadingMore) return const LoadingFooter();
                    if (pager.moreError != null) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: TextButton(onPressed: pager.loadMore, child: const Text('加载失败，点此重试')),
                        ),
                      );
                    }
                    if (!pager.hasMore) return const LoadingFooter(text: '没有更多了');
                    return const SizedBox(height: 24);
                  }
                  final status = pager.items[itemIndex];
                  if (hideBlocked && Prefs.instance.isBlocked(status.author.id)) {
                    return SizedBox.shrink(key: ValueKey(status.id));
                  }
                  return AppearIn(
                    key: ValueKey(status.id),
                    animate: pager.fresh.contains(status.id),
                    child: Column(
                      children: [
                        PaneSelected(
                          ids: ['status:${status.id}', if (status.repostOf != null) 'status:${status.repostOf!.id}'],
                          child: StatusCard(
                          status: status,
                          heroScope: '${status.id}-$itemIndex',
                          onOpenStatus: (id) => openStatus(
                            context,
                            statusId: id,
                            seed: status,
                          ),
                          onOpenUser: (uid) => openUser(context, uid),
                          onOpenTopic: (name) => openTopic(context, name),
                          onOpenUrl: (url) => openLink(context, url),
                          onOpenMedia: (media, mediaIndex, heroTag) {
                            if (media[mediaIndex].kind == MediaKind.video) {
                              openVideo(context, media[mediaIndex].url, coverUrl: media[mediaIndex].previewUrl);
                            } else {
                              openImage(context, media: media, index: mediaIndex, heroTag: heroTag);
                            }
                          },
                          onRepost: () => openCompose(context, type: DraftType.repost, statusId: status.id),
                          onComment: () => showCommentSheet(context, statusId: status.id, target: status),
                        ),
                        ),
                        const Divider(),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
