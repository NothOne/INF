import 'package:flutter/material.dart';

import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/navigation.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// The people the chat page has seen speak in a group, with a search box over them.
///
/// m.weibo.cn has no member list for a group (see `WeiboApi.groupSpeakers`), so the entries here are
/// the senders of the messages that have been loaded — not the roster. The header says so, and the
/// page offers to page back through the history for more of them rather than implying the list is
/// complete.
class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({
    super.key,
    required this.gid,
    required this.name,
    required this.speakers,
    this.memberCount = 0,
    this.hasMoreHistory = false,
    this.onLoadOlder,
  });

  final String gid;
  final String name;
  final List<User> speakers;

  /// The group's real size, from the title. Exact, even though its members cannot be listed.
  final int memberCount;
  final bool hasMoreHistory;
  final Future<List<User>> Function()? onLoadOlder;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  final TextEditingController _query = TextEditingController();
  late List<User> _speakers = widget.speakers;
  bool _loadingMore = false;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  List<User> get _shown {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return _speakers;
    return _speakers
        .where((user) => user.screenName.toLowerCase().contains(query) || user.id == query)
        .toList();
  }

  Future<void> _more() async {
    final load = widget.onLoadOlder;
    if (load == null || _loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      final all = await load();
      if (!mounted) return;
      if (all.isNotEmpty) setState(() => _speakers = all);
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final shown = _shown;
    final searching = _query.text.trim().isNotEmpty;
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
                    ? '在已看到的 ${_speakers.length} 位成员里找到 ${shown.length} 位'
                    : _speakers.isEmpty
                        ? '还没有可以列出的成员'
                        : widget.memberCount > 0
                            ? '已看到 ${_speakers.length} 位 · 群共 ${widget.memberCount} 人'
                            : '已看到 ${_speakers.length} 位',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? EmptyHint(text: searching ? '没有匹配的成员' : '群里还没有人发过言')
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
                    itemCount: shown.length + (searching || !widget.hasMoreHistory ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index >= shown.length) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            child: TextButton(
                              onPressed: _loadingMore ? null : _more,
                              child: Text(_loadingMore ? '正在往前翻…' : '往前翻聊天记录，看到更多成员'),
                            ),
                          ),
                        );
                      }
                      final user = shown[index];
                      return ListTile(
                        leading: Avatar(url: user.avatarUrl, size: 40, verified: user.verified),
                        title: Text(user.screenName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: user.description.isEmpty
                            ? null
                            : Text(user.description, maxLines: 1, overflow: TextOverflow.ellipsis),
                        onTap: () => openUser(context, user.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
