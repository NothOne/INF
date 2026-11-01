import 'package:flutter/material.dart';

import '../../core/look.dart';
import '../../core/api.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/pane.dart';
import '../../core/parse.dart';
import '../../core/shell_tabs.dart';
import '../../core/unread_monitor.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/comment_sheet.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/rich_text.dart';
import '../../core/widgets/smart_image.dart';
import '../../core/widgets/transitions.dart';

class NotifyPage extends StatefulWidget {
  const NotifyPage({super.key});

  @override
  State<NotifyPage> createState() => _NotifyPageState();
}

class _NotifyPageState extends State<NotifyPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: NotificationKind.values.length, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: UnreadMonitor.instance,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final counts = UnreadMonitor.instance.counts;
        return Scaffold(
          backgroundColor: Colors.transparent,
          extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
          appBar: AppBar(
            title: const Text('通知'),
            flexibleSpace: lookBarBackground(context),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(47),
              child: Material(
                color: Colors.transparent,
                child: ContentColumn(child: TabBar(
                  controller: _tabs,
                  indicatorSize: TabBarIndicatorSize.label,
                  dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                  tabs: [
                    for (final kind in NotificationKind.values)
                      Tab(
                        height: 46,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(kind.label, style: const TextStyle(fontSize: 13.5)),
                            if (counts.of(kind) > 0) ...[
                              const SizedBox(width: 4),
                              CountBadge(count: counts.of(kind)),
                            ],
                          ],
                        ),
                      ),
                  ],
                )),
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              for (final (position, kind) in NotificationKind.values.indexed)
                _NotifyList(kind: kind, tabs: _tabs, position: position, key: ValueKey(kind)),
            ],
          ),
        );
      },
    );
  }
}

class _NotifyList extends StatefulWidget {
  const _NotifyList({super.key, required this.kind, required this.tabs, required this.position});

  final NotificationKind kind;
  final TabController tabs;
  final int position;

  @override
  State<_NotifyList> createState() => _NotifyListState();
}

class _NotifyListState extends State<_NotifyList> with AutomaticKeepAliveClientMixin, ShellTabAware {
  late final PagingController<NotificationItem> _pager = PagingController<NotificationItem>(
    fetch: (cursor) => WeiboApi.instance.notifications(widget.kind, cursor),
    id: (item) => item.id,
  );
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  int get shellTab => 1;

  @override
  void initState() {
    super.initState();
    _pager.seed(WeiboApi.instance.cachedNotifications(widget.kind));
    widget.tabs.addListener(_innerTabChanged);
  }

  void _innerTabChanged() {
    if (widget.tabs.indexIsChanging || currentShellTab.value != shellTab) return;
    if (widget.tabs.index == widget.position) onTabShown(first: false);
  }

  /// Loading a list can mark it read on Weibo's side, so only the sub-tab in view refreshes.
  @override
  void onTabShown({required bool first}) {
    if (!first && widget.tabs.index != widget.position) return;
    final last = _pager.refreshedAt;
    final unread = UnreadMonitor.instance.counts.of(widget.kind) > 0;
    final old = last == null || DateTime.now().difference(last) > const Duration(minutes: 1);
    final atTop = !_scroll.hasClients || _scroll.offset < 40;
    if (first || (atTop && (unread || old))) _refresh();
  }

  Future<bool> _refresh() async {
    final ok = await _pager.refresh(background: _pager.items.isNotEmpty);
    if (mounted) UnreadMonitor.instance.refresh(force: true);
    return ok;
  }

  @override
  void dispose() {
    widget.tabs.removeListener(_innerTabChanged);
    _pager.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _pager,
      builder: (context, _) => RefreshingBar(
        active: _pager.backgroundRefreshing,
        child: StateSwitcher(child: _body(context)),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_pager.items.isEmpty) {
      if (_pager.error != null) {
        return Center(
          key: const ValueKey('error'),
          child: ErrorRetry(message: _pager.error.toString(), onRetry: _refresh),
        );
      }
      if (_pager.loading || _pager.refreshedAt == null) {
        return const RowListSkeleton(key: ValueKey('skeleton'));
      }
      return EmptyHint(
        key: const ValueKey('empty'),
        text: widget.kind.emptyText,
        icon: Icons.notifications_none_rounded,
      );
    }
    return NotificationListener<ScrollNotification>(
      key: const ValueKey('list'),
      onNotification: (notification) {
        _pager.onScroll(notification);
        return false;
      },
      child: InfRefreshIndicator(
        onRefresh: _refresh,
        child: ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.only(
            top: MediaQuery.paddingOf(context).top,
            bottom: ShellLayout.clearance(context, 92) + MediaQuery.paddingOf(context).bottom,
            left: contentGutter(context),
            right: contentGutter(context),
          ),
          itemCount: _pager.items.length + 1,
          findChildIndexCallback: _pager.indexOfKey,
          itemBuilder: (context, index) {
            if (index == _pager.items.length) {
              if (_pager.loadingMore) return const LoadingFooter();
              if (!_pager.hasMore) return const LoadingFooter(text: '没有更多了');
              return const SizedBox(height: 20);
            }
            final item = _pager.items[index];
            return AppearIn(
              key: ValueKey(item.id),
              animate: _pager.fresh.contains(item.id),
              child: PaneSelected(
                ids: [if (item.statusId != null) 'status:${item.statusId}'],
                child: _NotifyItem(
                item: item,
                onOpenStatus: (statusId) => openStatus(context, statusId: statusId),
                onOpenUser: (uid) => openUser(context, uid),
                onOpenTopic: (name) => openTopic(context, name),
                onOpenUrl: (url) => openLink(context, url),
                onReply: item.commentId == null || item.statusId == null
                    ? null
                    : () => showCommentSheet(
                          context,
                          statusId: item.statusId!,
                          commentId: item.commentId,
                          replyToName: item.user.screenName,
                          replyToText: item.text,
                        ),
              ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NotifyItem extends StatelessWidget {
  const _NotifyItem({
    required this.item,
    required this.onOpenStatus,
    required this.onOpenUser,
    required this.onOpenTopic,
    required this.onOpenUrl,
    this.onReply,
  });

  final NotificationItem item;
  final ValueChanged<String> onOpenStatus;
  final ValueChanged<String> onOpenUser;
  final ValueChanged<String> onOpenTopic;
  final ValueChanged<String> onOpenUrl;
  final VoidCallback? onReply;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = relativeTime(item.createdAt);
    return InkWell(
      onTap: item.statusId == null ? null : () => onOpenStatus(item.statusId!),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => onOpenUser(item.user.id),
              child: Avatar(url: item.user.avatarUrl, size: 40, verified: item.user.verified),
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
                          onTap: () => onOpenUser(item.user.id),
                          child: Text(
                            item.user.screenName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 14.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                      const Spacer(),
                      if (onReply != null)
                        TextButton(
                          onPressed: onReply,
                          style: TextButton.styleFrom(
                            minimumSize: const Size(38, 26),
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text('回复', style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  RichStatusText(
                    text: item.text,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 14.5),
                    onMention: onOpenUser,
                    onTopic: onOpenTopic,
                    onUrl: onOpenUrl,
                  ),
                  if (item.targetText != null || item.targetImage != null) ...[
                    const SizedBox(height: 7),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: InfChrome.of(context).fill(scheme, scheme.surfaceContainerHigh, 0.62),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Row(
                        children: [
                          if (item.targetImage != null) ...[
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: SmartImage(url: item.targetImage, width: 48, height: 48),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: RichStatusText(
                              text: item.targetText ?? '',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
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
