import 'package:flutter/material.dart';

import '../error_text.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/paging.dart';
import '../../core/pane.dart';
import '../../core/prefs.dart';
import 'common.dart';
import 'pager_tail.dart';
import 'refresh.dart';
import 'status_card_host.dart';
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
    this.refreshKey,
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
  final GlobalKey<InfRefreshIndicatorState>? refreshKey;

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
      animation: Listenable.merge([pager, Prefs.instance.blockedNotifier]),
      // Cross-fading two copies of the same header would dim it halfway through.
      builder: (context, _) => header == null ? StateSwitcher(child: _body(context)) : _body(context),
    );
  }

  Widget _refresh({Key? key, required Widget child}) =>
      refreshable ? InfRefreshIndicator(key: key, onRefresh: pager.refresh, child: child) : KeyedSubtree(key: key, child: child);

  Widget _scrollView(BuildContext context, List<Widget> slivers, {bool attachController = true}) {
    return CustomScrollView(
      controller: attachController ? controller : null,
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
          child: Center(child: ErrorView(error: pager.error, onRetry: pager.refresh)),
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
      // Do not attach `controller` or `refreshKey` here: during StateSwitcher's cross-fade to the
      // list both views are mounted at once, and a ScrollController / GlobalKey may only belong to one.
      return _refresh(
        key: ValueKey(pager.error != null ? 'error' : (pager.loading || pager.refreshedAt == null ? 'loading' : 'empty')),
        child: _scrollView(
          context,
          [
            SliverPadding(
              padding: EdgeInsets.only(top: top, left: gutter, right: gutter),
              sliver: SliverList.list(
                children: [
                  ?header,
                  state,
                ],
              ),
            ),
          ],
          attachController: false,
        ),
      );
    }
    return NotificationListener<ScrollNotification>(
      key: const ValueKey('list'),
      onNotification: (notification) {
        pager.onScroll(notification);
        return false;
      },
      child: _refresh(
        key: refreshKey,
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
                    return PagerTail(pager, gap: 24);
                  }
                  final status = pager.items[itemIndex];
                  if (hideBlocked && hiddenByBlock(status)) {
                    return SizedBox.shrink(key: ValueKey(status.id));
                  }
                  return AppearIn(
                    key: ValueKey(status.id),
                    animate: pager.fresh.contains(status.id),
                    child: Column(
                      children: [
                        PaneSelected(
                          ids: ['status:${status.id}', if (status.repostOf != null) 'status:${status.repostOf!.id}'],
                          child: buildStatusCard(context, status, heroScope: '${status.id}-$itemIndex'),
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
