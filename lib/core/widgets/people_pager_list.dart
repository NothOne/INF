import 'package:flutter/material.dart';

import '../error_text.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/relation_store.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pager_tail.dart';
import '../../core/widgets/refresh.dart';
import '../../core/widgets/user_row.dart';

class PeoplePagerList extends StatefulWidget {
  const PeoplePagerList({
    super.key,
    required this.fetch,
    this.emptyText = '这里还没有人',
    this.bottomInset = 24,
  });

  final Future<PageResult<User>> Function(String? cursor) fetch;
  final String emptyText;
  final double bottomInset;

  @override
  State<PeoplePagerList> createState() => _PeoplePagerListState();
}

class _PeoplePagerListState extends State<PeoplePagerList> with AutomaticKeepAliveClientMixin {
  late final PagingController<User> _pager = PagingController<User>(
    fetch: widget.fetch,
    id: (user) => user.id,
  );
  final Set<String> _busy = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _pager.refresh();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  /// [RelationStore] owns the state; this list only keeps a busy mark per row.
  Future<void> _toggle(User user) async {
    if (_busy.contains(user.id)) return;
    setState(() => _busy.add(user.id));
    final failure = await RelationStore.instance.toggleFollowing(user);
    if (!mounted) return;
    setState(() => _busy.remove(user.id));
    showMessage(context, failure);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      // The follow button reads RelationStore, so a tap on the same person elsewhere has to rebuild
      // this row too.
      animation: Listenable.merge([_pager, RelationStore.instance]),
      builder: (context, _) {
        if (_pager.loading && _pager.items.isEmpty) return const LoadingFooter();
        if (_pager.error != null && _pager.items.isEmpty) {
          return Center(child: ErrorView(error: _pager.error, onRetry: _pager.refresh));
        }
        if (_pager.items.isEmpty) return EmptyHint(text: widget.emptyText, icon: Icons.people_outline_rounded);
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            _pager.onScroll(notification);
            return false;
          },
          child: InfRefreshIndicator(
            onRefresh: _pager.refresh,
            child: ListView.builder(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top,
                bottom: widget.bottomInset + MediaQuery.paddingOf(context).bottom,
                left: contentGutter(context),
                right: contentGutter(context),
              ),
              itemCount: _pager.items.length + 1,
              itemBuilder: (context, index) {
                if (index == _pager.items.length) {
                  return PagerTail(_pager, gap: 18);
                }
                final user = _pager.items[index];
                final isSelf = user.id == Session.instance.uid;
                return UserListRow(
                  user: user,
                  following: RelationStore.instance.following(user),
                  busy: _busy.contains(user.id),
                  onToggleFollow: isSelf ? null : () => _toggle(user),
                  onTap: () => openUser(context, user.id),
                );
              },
            ),
          ),
        );
      },
    );
  }
}
