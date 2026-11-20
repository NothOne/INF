import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/group_chat_api.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// Everyone in a group chat, with a search box over them.
///
/// The members come from weibo.com's `query_group.json`, which hands them out in pages. It has no way
/// to ask for one by name, so the search runs over what has been loaded and says how much of the
/// group that is — the count beside it is the group's real size, so the gap is visible rather than
/// implied.
class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({
    super.key,
    required this.gid,
    required this.name,
    this.info,
  });

  final String gid;
  final String name;

  /// The group's own answer, for the size and to mark the owner and admins.
  final GroupInfo? info;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  /// How many the service returns at a time. Asking for more does not get more.
  static const _pageSize = 50;

  final TextEditingController _query = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<GroupMember> _members = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 400) _load();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (_loadingMore || (!reset && !_hasMore)) return;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _members.clear();
        _hasMore = true;
      });
    } else {
      setState(() => _loadingMore = true);
    }
    try {
      final page = await GroupChatApi.instance.groupMembers(widget.gid, offset: _members.length, count: _pageSize);
      if (!mounted) return;
      setState(() {
        final seen = {for (final member in _members) member.uid};
        _members.addAll(page.where((member) => seen.add(member.uid)));
        // A page shorter than asked for is the last one; the answer carries no cursor.
        _hasMore = page.length >= _pageSize;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (_members.isEmpty) _error = error;
      });
    }
  }

  List<GroupMember> get _shown {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _members;
    return _members
        .where((member) => member.screenName.toLowerCase().contains(query) || member.uid == query)
        .toList();
  }

  String? _role(GroupMember member) {
    final info = widget.info;
    if (info == null) return null;
    if (member.uid == info.ownerId) return '群主';
    if (info.adminIds.contains(member.uid)) return '管理员';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final shown = _shown;
    final searching = _query.text.trim().isNotEmpty;
    final total = widget.info?.memberCount ?? 0;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(widget.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              (chrome.extendsBehindBars ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0) + 8,
              gutter,
              8,
            ),
            child: ContentColumn(
              child: TextField(
                controller: _query,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: '搜索成员',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _query.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18),
                          tooltip: '清除',
                          onPressed: () {
                            _query.clear();
                            setState(() {});
                          },
                        ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(gutter + 4, 0, gutter + 4, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                searching
                    ? '在已加载的 ${_members.length} 位成员里找到 ${shown.length} 位'
                    : total > 0
                        ? '已加载 ${_members.length} / $total 人'
                        : '已加载 ${_members.length} 人',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(child: _body(context, shown, searching)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, List<GroupMember> shown, bool searching) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: ErrorView(error: _error, onRetry: () => _load(reset: true)));
    }
    if (shown.isEmpty) {
      return EmptyHint(text: searching ? '没有匹配的成员' : '这个群还没有成员');
    }
    return ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
      itemCount: shown.length + (!searching && _hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= shown.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          );
        }
        final member = shown[index];
        final role = _role(member);
        return ListTile(
          leading: Avatar(url: member.avatarUrl, size: 40, verified: member.verified),
          title: Row(
            children: [
              Flexible(child: Text(member.screenName, maxLines: 1, overflow: TextOverflow.ellipsis)),
              if (role != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    role,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 10,
                        ),
                  ),
                ),
              ],
            ],
          ),
          trailing: member.level > 0
              ? Text(
                  'Lv.${member.level}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                )
              : null,
          onTap: () => openUser(context, member.uid),
        );
      },
    );
  }
}
