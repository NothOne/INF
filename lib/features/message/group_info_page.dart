import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/api.dart';
import '../../core/error_text.dart';
import '../../core/group_chat_api.dart';
import '../../core/haptics.dart';
import '../../core/layout.dart';
import '../../core/look.dart';
import '../../core/models.dart';
import '../../core/native.dart';
import '../../core/navigation.dart';
import '../../core/session.dart';
import '../../core/widgets/avatar.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/refresh.dart';

/// A group chat's own page, opened from the ⋯ in the chat's top bar.
///
/// Everything here comes from weibo.com's webim backend (`api.weibo.com/webim/*`) — the phone site
/// has no group description at all. `groupchat/query.json` and `query_group.json`
/// (`query_all_member=1&query_member_count=5000`) are queried together and merged so all members
/// and the announcement (`bulletin`) are complete. The announcement shows a multi-line preview in
/// place and opens [GroupNoticePage] for full reading and admin editing.
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
      _loading = _info == null;
      _error = null;
    });
    try {
      // Query query_group.json (matching pcweibochat's primary group+bulletin query),
      // query_group.json?query_all_member=1 (complete member roster), groupchat/query.json, and
      // push_settings in parallel, merging so the fullest announcement and member list always win.
      GroupInfo? baseInfo;
      ({GroupInfo info, List<GroupMember> members})? primaryGroup;
      ({GroupInfo info, List<GroupMember> members})? allMembersGroup;
      bool? muted;
      Object? firstError;

      await Future.wait<void>([
        GroupChatApi.instance
            .queryGroup(widget.gid, allMembers: false)
            .then<void>((v) => primaryGroup = v)
            .catchError((Object e) {
          firstError ??= e;
        }),
        GroupChatApi.instance.groupInfo(widget.gid).then<void>((v) => baseInfo = v).catchError((Object e) {
          firstError ??= e;
        }),
        GroupChatApi.instance
            .queryGroup(widget.gid, allMembers: true)
            .then<void>((v) => allMembersGroup = v)
            .catchError((Object e) {
          firstError ??= e;
        }),
        GroupChatApi.instance.groupMuted(widget.gid).then<void>((v) => muted = v).catchError((Object _) {}),
      ]);
      if (!mounted) return;
      final candidates = [
        if (primaryGroup != null) primaryGroup!.info,
        if (allMembersGroup != null) allMembersGroup!.info,
        ?baseInfo,
      ];
      if (candidates.isEmpty) {
        setState(() {
          _loading = false;
          _error = firstError ?? ApiException('获取群聊信息失败');
        });
        return;
      }
      var merged = candidates.first;
      for (final extra in candidates.skip(1)) {
        merged = merged.mergeWith(extra);
      }
      final rawMembers = (allMembersGroup?.members.length ?? 0) >= (primaryGroup?.members.length ?? 0)
          ? (allMembersGroup?.members ?? primaryGroup?.members ?? _members)
          : primaryGroup!.members;
      final sortedMembers = _sortMembers(rawMembers, merged);
      setState(() {
        _info = merged;
        _members = sortedMembers;
        if (muted != null) _muted = muted!;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_info == null) _error = error;
      });
    }
  }

  List<GroupMember> _sortMembers(List<GroupMember> source, GroupInfo info) {
    if (source.isEmpty) return source;
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

  String get _name => (_info?.name.isNotEmpty ?? false) ? _info!.name : widget.name;

  int get _count {
    final reported = _info?.memberCount ?? widget.memberCount;
    return reported > 0 ? reported : _members.length;
  }

  Future<void> _openMembers() => openGroupMembers(
        context,
        gid: widget.gid,
        name: _name,
        info: _info,
        initialMembers: _members.isEmpty ? null : _members,
      );

  Future<void> _openNotice() async {
    final info = _info;
    if (info == null) return;
    final canEdit = info.isAdmin(_selfId);
    if ((info.notice?.isEmpty ?? true) && !canEdit) return;
    final updated = await openGroupNotice(context, info: info, canEdit: canEdit);
    if (!mounted || updated == null) return;
    setState(() => _info = updated);
  }

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
      body: InfRefreshIndicator(
        onRefresh: _load,
        child: ContentColumn(
          child: Builder(
            builder: (bodyContext) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                gutter + 12,
                MediaQuery.paddingOf(bodyContext).top + 16,
                gutter + 12,
                28 + MediaQuery.paddingOf(bodyContext).bottom,
              ),
              children: [
                _Header(
                  name: _name,
                  gid: widget.gid,
                  avatarUrl: info?.avatarUrl,
                  summary: info?.summary,
                  count: _count,
                  max: info?.maxMembers ?? 0,
                  place: info?.place,
                  createdAt: info?.createdAt,
                ),
                if (_loading)
                  const Padding(padding: EdgeInsets.symmetric(vertical: 28), child: Center(child: CircularProgressIndicator()))
                else if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: ErrorView(error: _error, onRetry: _load),
                  )
                else ...[
                  const SizedBox(height: 18),
                  _MembersCard(
                    members: _members,
                    totalCount: _count,
                    ownerId: info?.ownerId ?? '',
                    adminIds: info?.adminIds ?? const {},
                    onTapAll: _openMembers,
                    onTapMember: (uid) => openUser(context, uid),
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    children: [
                      _NoticeRow(
                        notice: notice,
                        hasLink: info?.noticeScheme?.isNotEmpty ?? false,
                        canEdit: canEdit,
                        onTap: (notice != null || canEdit) ? _openNotice : null,
                      ),
                      Divider(height: 1, indent: 46, color: scheme.outlineVariant.withValues(alpha: 0.4)),
                      _Row(
                        icon: Icons.notifications_off_outlined,
                        label: '消息免打扰',
                        trailing: Switch(value: _muted, onChanged: _toggleMuted),
                        onTap: () => _toggleMuted(!_muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _SectionCard(
                    children: [
                      _Row(icon: Icons.ios_share_rounded, label: '分享群', onTap: _share),
                      _Row(icon: Icons.tag_rounded, label: '复制群号', onTap: () => _copy(widget.gid)),
                      _Row(icon: Icons.open_in_browser_rounded, label: '在浏览器中打开', onTap: _openInBrowser),
                    ],
                  ),
                  const SizedBox(height: 12),
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
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.name,
    required this.gid,
    this.avatarUrl,
    this.summary,
    required this.count,
    required this.max,
    this.place,
    this.createdAt,
  });

  final String name;
  final String gid;
  final String? avatarUrl;
  final String? summary;
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
      if (createdAt != null && createdAt! > 0) '${DateTime.fromMillisecondsSinceEpoch(createdAt! * 1000).year} 年创建',
    ];
    return Column(
      children: [
        Center(
          child: (avatarUrl != null && avatarUrl!.isNotEmpty)
              ? Avatar(url: avatarUrl, size: 64)
              : CircleAvatar(
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
        if (summary != null && summary!.isNotEmpty) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              summary!,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

/// Group members preview card: shows a 5-column avatar + name grid and opens the full list.
class _MembersCard extends StatelessWidget {
  const _MembersCard({
    required this.members,
    required this.totalCount,
    required this.ownerId,
    required this.adminIds,
    required this.onTapAll,
    required this.onTapMember,
  });

  final List<GroupMember> members;
  final int totalCount;
  final String ownerId;
  final Set<String> adminIds;
  final VoidCallback onTapAll;
  final ValueChanged<String> onTapMember;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preview = members.take(10).toList(growable: false);
    final shownTotal = totalCount > 0 ? totalCount : members.length;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onTapAll,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 8),
              child: Row(
                children: [
                  Icon(Icons.group_outlined, size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('群成员', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
                  ),
                  Text(
                    shownTotal > 0 ? '共 $shownTotal 人' : '查看全部',
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
                ],
              ),
            ),
          ),
          if (preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const columns = 5;
                  final itemWidth = (constraints.maxWidth / columns).floorToDouble();
                  return Wrap(
                    runSpacing: 10,
                    children: [
                      for (final member in preview)
                        SizedBox(
                          width: itemWidth,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onTapMember(member.uid),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      Avatar(url: member.avatarUrl, size: 42, verified: member.verified),
                                      if (member.uid == ownerId || adminIds.contains(member.uid))
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 3.5, vertical: 0.5),
                                            decoration: BoxDecoration(
                                              color: member.uid == ownerId ? scheme.tertiary : scheme.primary,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              member.uid == ownerId ? '主' : '管',
                                              style: TextStyle(
                                                color: member.uid == ownerId ? scheme.onTertiary : scheme.onPrimary,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w700,
                                                height: 1.2,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    member.screenName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: textTheme.labelSmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          if (members.length > preview.length || shownTotal > preview.length) ...[
            Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
            InkWell(
              onTap: onTapAll,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '查看全部 $shownTotal 位群成员',
                      style: textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.chevron_right_rounded, size: 17, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Group announcement row with multi-line preview right on [GroupInfoPage]; taps open [GroupNoticePage].
class _NoticeRow extends StatelessWidget {
  const _NoticeRow({
    required this.notice,
    required this.hasLink,
    required this.canEdit,
    required this.onTap,
  });

  final String? notice;
  final bool hasLink;
  final bool canEdit;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final hasNotice = notice != null && notice!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.campaign_outlined, size: 20, color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('群公告', style: textTheme.bodyMedium?.copyWith(color: scheme.onSurface)),
                ),
                if (!hasNotice)
                  Text(
                    canEdit ? '去发布' : '暂无公告',
                    style: textTheme.bodySmall?.copyWith(
                      color: canEdit ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  )
                else if (hasLink)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(Icons.link_rounded, size: 16, color: scheme.primary),
                  ),
                if (onTap != null)
                  Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
              ],
            ),
            if (hasNotice) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 32, right: 6),
                child: Text(
                  notice!,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
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
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    this.trailing,
    this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final Widget? trailing;
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
            ?trailing,
            if (onTap != null && trailing == null)
              Icon(Icons.chevron_right_rounded, size: 20, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
