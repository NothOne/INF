import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/paging.dart';
import '../../core/session.dart';
import '../../core/widgets/common.dart';
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
  final Map<String, bool> _following = {};
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

  Future<void> _toggle(User user) async {
    if (_busy.contains(user.id)) return;
    final next = !(_following[user.id] ?? user.following);
    (next ? Haptic.toggleOn : Haptic.toggleOff).play();
    setState(() {
      _busy.add(user.id);
      _following[user.id] = next;
    });
    try {
      await WeiboApi.instance.setFollowing(user.id, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _following[user.id] = !next);
      Haptic.error.play();
      showMessage(context, error is ApiException ? error.message : '操作失败');
    } finally {
      if (mounted) setState(() => _busy.remove(user.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return AnimatedBuilder(
      animation: _pager,
      builder: (context, _) {
        if (_pager.loading && _pager.items.isEmpty) return const LoadingFooter();
        if (_pager.error != null && _pager.items.isEmpty) {
          return Center(child: ErrorRetry(message: _pager.error.toString(), onRetry: _pager.refresh));
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
                  if (_pager.loadingMore) return const LoadingFooter();
                  if (_pager.moreError != null) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: TextButton(onPressed: _pager.loadMore, child: const Text('加载失败，点此重试'))),
                    );
                  }
                  if (!_pager.hasMore) return const LoadingFooter(text: '没有更多了');
                  return const SizedBox(height: 18);
                }
                final user = _pager.items[index];
                final isSelf = user.id == Session.instance.uid;
                return UserListRow(
                  user: user,
                  following: _following[user.id] ?? user.following,
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
