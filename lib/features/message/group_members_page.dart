import 'package:flutter/material.dart';

import '../../core/error_text.dart';
import '../../core/group_chat_api.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';

/// Everyone in a group chat, with instant search over nickname, uid and pinyin.
///
/// Members are fetched in full via `api.weibo.com/webim/query_group.json` with
/// `query_all_member=1&query_member_count=5000` (matching the web client, since the endpoint does
/// not support offset pagination). Owners and admins are pinned to the top.
class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({
    super.key,
    required this.gid,
    required this.name,
    this.info,
    this.initialMembers,
  });

  final String gid;
  final String name;

  /// The group's own metadata, for total size and to mark the owner and admins.
  final GroupInfo? info;

  /// Optional preloaded member list handed over from [GroupInfoPage] so the list paints at once.
  final List<GroupMember>? initialMembers;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  final TextEditingController _query = TextEditingController();
  List<GroupMember> _members = const [];
  GroupInfo? _info;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _info = widget.info;
    final initial = widget.initialMembers;
    if (initial != null && initial.isNotEmpty) {
      _members = _sortMembers(initial, _info);
      _loading = false;
    } else {
      _load();
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_members.isEmpty) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await GroupChatApi.instance.queryGroup(widget.gid, allMembers: true);
      if (!mounted) return;
      final mergedInfo = _info == null ? result.info : _info!.mergeWith(result.info);
      setState(() {
        _info = mergedInfo;
        _members = _sortMembers(result.members, mergedInfo);
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_members.isEmpty) _error = error;
      });
    }
  }

  List<GroupMember> _sortMembers(List<GroupMember> source, GroupInfo? info) {
    if (info == null || source.isEmpty) return List.of(source);
    int rank(GroupMember m) {
      if (m.uid == info.ownerId) return 0;
      if (info.adminIds.contains(m.uid)) return 1;
      return 2;
    }

    final indexed = source.indexed.toList();
    indexed.sort((a, b) {
      final cmp = rank(a.$2).compareTo(rank(b.$2));
      return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
    });
    return [for (final item in indexed) item.$2];
  }

  List<GroupMember> get _shown {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _members;
    return _members
        .where((member) =>
            member.screenName.toLowerCase().contains(query) ||
            member.uid == query ||
            (member.jp.isNotEmpty && member.jp.toLowerCase().contains(query)) ||
            (member.qp.isNotEmpty && member.qp.toLowerCase().contains(query)))
        .toList();
  }

  String? _role(GroupMember member) {
    final info = _info;
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
    final total = _info?.memberCount ?? 0;

    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: Text(
          total > 0 ? '群成员 ($total)' : '群成员',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: Builder(
        builder: (bodyContext) => Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                gutter + 12,
                MediaQuery.paddingOf(bodyContext).top + 8,
                gutter + 12,
                8,
              ),
              child: ContentColumn(
                child: TextField(
                  controller: _query,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '搜索昵称、拼音或 UID',
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
            if (!_loading && _error == null)
              Padding(
                padding: EdgeInsets.fromLTRB(gutter + 16, 0, gutter + 16, 6),
                child: ContentColumn(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      searching
                          ? '在 ${_members.length} 位成员里找到 ${shown.length} 位'
                          : total > _members.length
                              ? '已获取 ${_members.length} / $total 人'
                              : '共 ${_members.length} 位成员',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ),
                ),
              ),
            Expanded(child: _body(context, shown, searching, gutter)),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<GroupMember> shown, bool searching, double gutter) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: ErrorView(error: _error, onRetry: _load));
    }
    if (shown.isEmpty) {
      return EmptyHint(text: searching ? '没有匹配的成员' : '这个群还没有成员');
    }
    final scheme = Theme.of(context).colorScheme;
    return InfRefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, 24 + MediaQuery.paddingOf(context).bottom),
        itemCount: shown.length,
        itemBuilder: (context, index) {
          final member = shown[index];
          final role = _role(member);
          final isOwner = role == '群主';
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
                      color: (isOwner ? scheme.tertiary : scheme.primary).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      role,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isOwner ? scheme.tertiary : scheme.primary,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                ],
              ],
            ),
            trailing: member.level > 0
                ? Text(
                    'Lv.${member.level}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  )
                : null,
            onTap: () => openUser(context, member.uid),
          );
        },
      ),
    );
  }
}
