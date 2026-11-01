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
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/rich_text.dart';
import '../../core/widgets/transitions.dart';

class MessagePage extends StatefulWidget {
  const MessagePage({super.key});

  @override
  State<MessagePage> createState() => _MessagePageState();
}

class _MessagePageState extends State<MessagePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: InfChrome.of(context).extendsBehindBars,
      appBar: AppBar(
        title: const Text('私信'),
        flexibleSpace: lookBarBackground(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(47),
          child: ContentColumn(
            child: TabBar(
              controller: _tabs,
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: scheme.outlineVariant.withValues(alpha: 0.4),
              tabs: const [
                Tab(height: 46, child: Text('关注的人', style: TextStyle(fontSize: 13.5))),
                Tab(height: 46, child: Text('未关注人', style: TextStyle(fontSize: 13.5))),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _ConversationList(strangers: false, tabs: _tabs),
          _ConversationList(strangers: true, tabs: _tabs),
        ],
      ),
    );
  }
}

class _ConversationList extends StatefulWidget {
  const _ConversationList({required this.strangers, required this.tabs});

  final bool strangers;
  final TabController tabs;

  int get position => strangers ? 1 : 0;

  @override
  State<_ConversationList> createState() => _ConversationListState();
}

class _ConversationListState extends State<_ConversationList> with AutomaticKeepAliveClientMixin, ShellTabAware {
  late final PagingController<Conversation> _pager = PagingController<Conversation>(
    fetch: (cursor) => WeiboApi.instance.conversations(widget.strangers, cursor),
    id: (conversation) => conversation.user.id,
  );
  final ScrollController _scroll = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  int get shellTab => 2;

  @override
  void initState() {
    super.initState();
    _pager.seed(WeiboApi.instance.cachedConversations(widget.strangers));
    widget.tabs.addListener(_innerTabChanged);
  }

  void _innerTabChanged() {
    if (widget.tabs.indexIsChanging || currentShellTab.value != shellTab) return;
    if (widget.tabs.index == widget.position) onTabShown(first: false);
  }

  @override
  void onTabShown({required bool first}) {
    if (!first && widget.tabs.index != widget.position) return;
    final last = _pager.refreshedAt;
    final unread = UnreadMonitor.instance.counts.messages > 0;
    final old = last == null || DateTime.now().difference(last) > const Duration(minutes: 1);
    final atTop = !_scroll.hasClients || _scroll.offset < 40;
    if (first || (atTop && (unread || old))) _refresh();
  }

  Future<bool> _refresh() async {
    final ok = await _pager.refresh(background: _pager.items.isNotEmpty);
    if (mounted) UnreadMonitor.instance.refresh(force: true);
    return ok;
  }

  Future<void> _openConversation(Conversation conversation) async {
    await openChat(
      context,
      uid: conversation.groupId ?? conversation.user.id,
      name: conversation.user.screenName,
      group: conversation.isGroup,
    );
    if (!mounted) return;
    await _refresh();
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
        return const RowListSkeleton(key: ValueKey('skeleton'), avatar: 48);
      }
      return EmptyHint(
        key: const ValueKey('empty'),
        text: widget.strangers ? '没有未关注人的私信' : '没有私信',
        icon: Icons.mail_outline_rounded,
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
              return const SizedBox(height: 18);
            }
            final conversation = _pager.items[index];
            return AppearIn(
              key: ValueKey(conversation.user.id),
              animate: _pager.fresh.contains(conversation.user.id),
              child: PaneSelected(
                ids: ['chat:${conversation.groupId ?? conversation.user.id}'],
                child: _ConversationRow(
                  conversation: conversation,
                  onTap: () => _openConversation(conversation),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation, required this.onTap});

  final Conversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = conversation.user;
    final time = relativeTime(conversation.updatedAt);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
        child: Row(
          children: [
            Badge.count(
              count: conversation.unread,
              isLabelVisible: conversation.unread > 0,
              offset: const Offset(4, -4),
              child: Avatar(url: user.avatarUrl, size: 48, verified: user.verified),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          user.screenName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 15),
                        ),
                      ),
                      if (conversation.isGroup) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: scheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '群',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.onSecondaryContainer,
                                  fontSize: 9.5,
                                ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        time,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  RichStatusText(
                    text: conversation.lastText,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13.5,
                        ),
                    maxLines: 1,
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