import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/error_text.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/group_chat_api.dart';
import '../../core/models.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/session.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';

/// A group chat's own page, opened from the ⋯ in the chat's top bar.
///
/// Everything here comes from weibo.com's webim backend — the phone site has no group description at
/// all. `groupchat/query.json` answers with the name, the size, the owner, the admins and the
/// announcement in one go; `query_group.json` pages the members out; the notification switch has its
/// own pair of endpoints (see `WeiboApi.groupInfo`). The announcement is edited in place by the owner
/// or an admin, and read-only for everyone else.
///
/// Pops with true once the group was left.
class GroupInfoPage extends StatefulWidget {
  const GroupInfoPage({
    super.key,
    required this.gid,
    required this.name,
    this.memberCount = 0,
  });

  final String gid;

  /// The name the chat page knows, shown until the real answer arrives.
  final String name;

  /// Likewise the count from the title, so the header is not blank while it loads.
  final int memberCount;

  @override
  State<GroupInfoPage> createState() => _GroupInfoPageState();
}

class _GroupInfoPageState extends State<GroupInfoPage> {
  GroupInfo? _info;
  List<GroupMember> _members = const [];
  bool _muted = false;
  bool _loading = true;
  bool _busy = false;
  Object? _error;

  String? get _selfId => Session.instance.uid;

  String get _link => 'https://m.weibo.cn/message/chat?gid=${widget.gid}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Independent requests, so they go out together: the group's own answer is what the page is
      // built around, and the members are the strip under it.
      final info = await GroupChatApi.instance.groupInfo(widget.gid);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
      });
      final (members, muted) = await (
        GroupChatApi.instance.groupMembers(widget.gid, count: 12),
        GroupChatApi.instance.groupMuted(widget.gid),
      ).wait;
      if (!mounted) return;
      setState(() {
        _members = members;
        _muted = muted;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  String get _name => (_info?.name.isNotEmpty ?? false) ? _info!.name : widget.name;

  int get _count => _info?.memberCount ?? widget.memberCount;

  Future<void> _openMembers() => openGroupMembers(
        context,
        gid: widget.gid,
        name: _name,
        info: _info,
      );

  Future<void> _toggleMuted(bool value) async {
    final previous = _muted;
    setState(() => _muted = value);
    (value ? Haptic.toggleOn : Haptic.toggleOff).play();
    try {
      await GroupChatApi.instance.setGroupMuted(widget.gid, value);
      if (mounted) showMessage(context, value ? '这个群的消息不再提醒' : '已恢复提醒');
    } catch (error) {
      Haptic.error.play();
      if (!mounted) return;
      setState(() => _muted = previous);
      showMessage(context, friendlyError(error));
    }
  }

  Future<void> _editNotice() async {
    final current = _info?.notice ?? '';
    final controller = TextEditingController(text: current);
    final next = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('编辑群公告'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 4,
          maxLines: 10,
          decoration: const InputDecoration(hintText: '写点什么让大家都知道'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || next == current) return;
    try {
      await GroupChatApi.instance.setGroupNotice(widget.gid, next);
      Haptic.success.play();
      if (!mounted) return;
      setState(() => _info = GroupInfo(
            gid: widget.gid,
            name: _name,
            memberCount: _count,
            maxMembers: _info?.maxMembers ?? 0,
            ownerId: _info?.ownerId ?? '',
            adminIds: _info?.adminIds ?? const {},
            notice: next.isEmpty ? null : next,
            createdAt: _info?.createdAt,
            place: _info?.place,
          ));
      showMessage(context, '群公告已更新');
    } catch (error) {
      Haptic.error.play();
      if (mounted) showMessage(context, friendlyError(error));
    }
  }

  Future<void> _share() async {
    try {
      await SharePlus.instance.share(ShareParams(text: '微博群聊：$_name\n$_link', subject: _name));
    } catch (_) {
      await _copy(_link);
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    Haptic.success.play();
    if (mounted) showMessage(context, '已复制');
  }

  Future<void> _openInBrowser() async {
    if (await Native.openUrl(_link)) return;
    if (mounted) showMessage(context, '没有可以打开链接的浏览器');
  }

  Future<void> _leave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('退出群聊'),
        content: const Text('退出后不再接收这个群的消息，确定退出？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('退出')),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      await WeiboApi.instance.leaveGroup(widget.gid);
      Haptic.success.play();
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      Haptic.error.play();
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, friendlyError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chrome = InfChrome.of(context);
    final gutter = contentGutter(context);
    final info = _info;
    final notice = info?.notice;
    final canEdit = info?.isAdmin(_selfId) ?? false;
    return Scaffold(
      backgroundColor: scheme.surface,
      extendBodyBehindAppBar: chrome.extendsBehindBars,
      appBar: AppBar(
        flexibleSpace: lookBarBackground(context),
        title: const Text('群聊信息'),
        actions: [
          IconButton(onPressed: _share, tooltip: '分享群', icon: const Icon(Icons.ios_share_rounded)),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              gutter,
              (chrome.extendsBehindBars ? MediaQuery.paddingOf(context).top + kToolbarHeight : 0) + 16,
              gutter,
              28 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              _Header(
                name: _name,
                gid: widget.gid,
                count: _count,
                max: info?.maxMembers ?? 0,
                place: info?.place,
                createdAt: info?.createdAt,
              ),
              if (_loading)
                const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Center(child: CircularProgressIndicator()))
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: ErrorView(error: _error, onRetry: _load),
                )
              else ...[
                const SizedBox(height: 18),
                _MembersStrip(members: _members, count: _count, onTap: _openMembers),
                const SizedBox(height: 10),
                const Divider(height: 24),
                _SectionCard(
                  children: [
                    _Row(
                      icon: Icons.campaign_outlined,
                      label: '群公告',
                      value: notice == null ? '暂无公告' : null,
                      onTap: canEdit
                          ? _editNotice
                          : (notice == null ? null : () => _showNotice(notice)),
                      badge: canEdit ? '编辑' : null,
                    ),
                    _Row(
                      icon: Icons.notifications_off_outlined,
                      label: '消息免打扰',
                      trailing: Switch(value: _muted, onChanged: _toggleMuted),
                      onTap: () => _toggleMuted(!_muted),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  children: [
                    _Row(icon: Icons.ios_share_rounded, label: '分享群', onTap: _share),
                    _Row(icon: Icons.tag_rounded, label: '复制群号', onTap: () => _copy(widget.gid)),
                    _Row(icon: Icons.open_in_browser_rounded, label: '在浏览器中打开', onTap: _openInBrowser),
                  ],
                ),
                const SizedBox(height: 10),
                _SectionCard(
                  children: [
                    _Row(icon: Icons.logout_rounded, label: '退出群聊', danger: true, onTap: _busy ? null : _leave),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNotice(String notice) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('群公告'),
        content: SingleChildScrollView(child: Text(notice)),
        actions: [
          TextButton(
            onPressed: () => _copy(notice).then((_) {
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            }),
            child: const Text('复制'),
          ),
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('关闭')),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.gid,
    required this.count,
    required this.max,
    this.place,
    this.createdAt,
  });

  final String name;
  final String gid;
  final int count;
  final int max;
  final String? place;
  final int? createdAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final details = <String>[
      '群号 $gid',
      if (count > 0) max > 0 ? '$count / $max 人' : '$count 人',
      if (place != null && place!.isNotEmpty) place!,
      if (createdAt != null) '${DateTime.fromMillisecondsSinceEpoch(createdAt! * 1000).year} 年创建',
    ];
    return Column(
      children: [
        Center(
          child: CircleAvatar(
            radius: 32,
            backgroundColor: scheme.secondaryContainer,
            child: Icon(Icons.groups_rounded, size: 34, color: scheme.onSecondaryContainer),
          ),
        ),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          details.join(' · '),
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

/// The strip of faces at the top, and the way into the full list.
class _MembersStrip extends StatelessWidget {
  const _MembersStrip({required this.members, required this.count, required this.onTap});

  final List<GroupMember> members;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: members.isEmpty
                  ? Text('查看成员', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
                  : Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final member in members.take(9))
                          Avatar(url: member.avatarUrl, size: 38, verified: member.verified),
                      ],
                    ),
            ),
            const SizedBox(width: 8),
            Text(
              count > 0 ? '$count 人' : '全部成员',
              style: textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

/// A rounded block of rows, the shape a settings screen uses.
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(color: scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.onTap,
    this.badge,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final String? value;
  final Widget? trailing;

  /// A short right-hand word, such as 编辑, for a row that opens an editor rather than a detail.
  final String? badge;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: danger ? scheme.error : scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(color: danger ? scheme.error : scheme.onSurface),
              ),
            ),
            if (value != null)
              Flexible(
                child: Text(
                  value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ?trailing,
            if (badge != null)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Text(
                  badge!,
                  style: textTheme.labelSmall?.copyWith(color: scheme.primary),
                ),
              ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
